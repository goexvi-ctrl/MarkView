/* MarkView find.js - in-page find (Cmd-F).
 *
 * Loaded by BOTH the normal document template and the side-by-side comparison
 * (diff) page, so find works in either. The find bar UI is a native AppKit view
 * (see FindBar.swift); these functions do the DOM searching, highlight every
 * match, track a "current" match, and return {count, current} to Swift via the
 * evaluateJavaScript completion handler.
 *
 * Search root: the normal view searches #content; the comparison page has no
 * #content, so it falls back to document.body and searches both panes.
 *
 * Matches are case-insensitive and confined to a single text node (matches that
 * straddle inline element boundaries are not found - the same limitation as most
 * in-page find implementations). Text inside scripts, styles, SVG and Mermaid is
 * skipped so highlighting never corrupts those.
 *
 * KaTeX-rendered math can't be highlighted character-by-character without breaking
 * its layout, so a formula is matched as a whole unit against its LaTeX source
 * (stored by KaTeX in a hidden <annotation>). A matching formula gets a translucent
 * box highlight on its .katex container - e.g. searching "4ac" lands on b^2-4ac.
 */
'use strict';

(function() {
  const MARK_CLASS = 'mv-find';
  const CURRENT_CLASS = 'mv-find-current';
  const FORMULA_CLASS = 'mv-find-formula';

  let matches = [];       // document-ordered array of match elements (text <mark>s + matched .katex spans)
  let currentIndex = -1;  // index into matches, or -1 when there is no current match
  let lastQuery = '';

  function result() {
    return { count: matches.length, current: currentIndex + 1 };
  }

  // Remove all highlighting. Whole-formula matches just lose their classes (the
  // .katex element is left untouched); text matches are unwrapped and the split
  // text is coalesced back together so repeated searches stay clean.
  function clearHighlights() {
    document.querySelectorAll('.' + FORMULA_CLASS).forEach(function(el) {
      el.classList.remove(FORMULA_CLASS);
      el.classList.remove(CURRENT_CLASS);
    });

    const marks = document.querySelectorAll('mark.' + MARK_CLASS);
    const parents = new Set();
    marks.forEach(function(m) {
      const parent = m.parentNode;
      if (!parent) return;
      while (m.firstChild) parent.insertBefore(m.firstChild, m);
      parent.removeChild(m);
      parents.add(parent);
    });
    parents.forEach(function(p) { try { p.normalize(); } catch (e) {} });
    matches = [];
    currentIndex = -1;
  }

  // True if this text node lives somewhere we must not touch.
  function shouldSkip(node) {
    let el = node.parentNode;
    while (el && el.nodeType === 1) {
      const tag = el.tagName;
      if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT' ||
          tag === 'TEXTAREA' || tag === 'SVG' || tag === 'svg') {
        return true;
      }
      const cls = el.classList;
      if (cls && (cls.contains('katex') || cls.contains('mermaid'))) return true;
      el = el.parentNode;
    }
    return false;
  }

  function highlightAll(query) {
    clearHighlights();
    if (!query) return 0;

    const root = document.getElementById('content') || document.body;
    if (!root) return 0;

    const lcQuery = query.toLowerCase();
    const qLen = query.length;

    // Collect matching text nodes first; we must not mutate the tree while the
    // TreeWalker is live.
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function(node) {
        const v = node.nodeValue;
        if (!v || v.length < qLen) return NodeFilter.FILTER_REJECT;
        if (v.toLowerCase().indexOf(lcQuery) === -1) return NodeFilter.FILTER_REJECT;
        if (shouldSkip(node)) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    const textNodes = [];
    let n;
    while ((n = walker.nextNode())) textNodes.push(n);

    textNodes.forEach(function(textNode) {
      const text = textNode.nodeValue;
      const lcText = text.toLowerCase();
      let idx = lcText.indexOf(lcQuery);
      if (idx === -1) return;

      const frag = document.createDocumentFragment();
      let pos = 0;
      while (idx !== -1) {
        if (idx > pos) frag.appendChild(document.createTextNode(text.slice(pos, idx)));
        const mark = document.createElement('mark');
        mark.className = MARK_CLASS;
        mark.textContent = text.slice(idx, idx + qLen);
        frag.appendChild(mark);
        matches.push(mark);
        pos = idx + qLen;
        idx = lcText.indexOf(lcQuery, pos);
      }
      if (pos < text.length) frag.appendChild(document.createTextNode(text.slice(pos)));
      textNode.parentNode.replaceChild(frag, textNode);
    });

    // Whole-formula pass: a KaTeX formula matches when its LaTeX source contains
    // the query. We highlight the whole .katex box rather than a sub-range.
    const formulas = root.querySelectorAll ? root.querySelectorAll('.katex') : [];
    Array.prototype.forEach.call(formulas, function(kx) {
      const ann = kx.querySelector ? kx.querySelector('annotation') : null;
      const src = (ann ? ann.textContent : kx.textContent) || '';
      if (src.toLowerCase().indexOf(lcQuery) === -1) return;
      kx.classList.add(FORMULA_CLASS);
      matches.push(kx);
    });

    // Order all matches (text marks + formulas) by document position so Next/Prev
    // and the "X of Y" index follow reading order.
    if (matches.length > 1 && typeof matches[0].compareDocumentPosition === 'function') {
      matches.sort(function(a, b) {
        if (a === b) return 0;
        const rel = a.compareDocumentPosition(b);
        if (rel & Node.DOCUMENT_POSITION_FOLLOWING) return -1;
        if (rel & Node.DOCUMENT_POSITION_PRECEDING) return 1;
        return 0;
      });
    }

    return matches.length;
  }

  // The comparison/diff page (HTMLTemplate.buildComparison) is a fixed, viewport-
  // sized two-pane layout; each pane (.compare-pane) scrolls internally. The nearest
  // enclosing diff pane for `el`, or null when we're in the normal document view.
  function comparePaneAncestor(el) {
    let node = el.parentElement;
    while (node && node !== document.body) {
      if (node.classList && node.classList.contains('compare-pane')) return node;
      node = node.parentElement;
    }
    return null;
  }

  // Bring a match into view. For diff panes we scroll ONLY the pane, clamped to its
  // own range: scrollIntoView() bubbles to the top-level document when the inner
  // container can't satisfy the request (e.g. a formula near the end of a pane),
  // which would shift the fixed two-pane layout off-screen and blank the view.
  function scrollMatchIntoView(el) {
    const pane = comparePaneAncestor(el);
    if (pane) {
      const er = el.getBoundingClientRect();
      const pr = pane.getBoundingClientRect();
      pane.scrollTop = Math.max(0, pane.scrollTop + (er.top - pr.top) - (pane.clientHeight - er.height) / 2);
      if (er.left < pr.left || er.right > pr.right) {
        pane.scrollLeft = Math.max(0, pane.scrollLeft + (er.left - pr.left) - 16);
      }
      return;
    }
    try { el.scrollIntoView({ block: 'center', inline: 'nearest' }); }
    catch (e) { el.scrollIntoView(); }
  }

  function setCurrent(index, scroll) {
    if (currentIndex >= 0 && currentIndex < matches.length) {
      matches[currentIndex].classList.remove(CURRENT_CLASS);
    }
    currentIndex = index;
    if (currentIndex >= 0 && currentIndex < matches.length) {
      const el = matches[currentIndex];
      el.classList.add(CURRENT_CLASS);
      if (scroll) scrollMatchIntoView(el);
    }
  }

  // First match at or below the current viewport top, so a fresh search jumps to
  // the nearest match rather than always snapping back to the top of the document.
  function firstMatchFromViewport() {
    for (let i = 0; i < matches.length; i++) {
      if (matches[i].getBoundingClientRect().top >= 0) return i;
    }
    return matches.length ? 0 : -1;
  }

  // Run a fresh search for `query`, highlight everything, and select the first
  // match near the viewport. Returns {count, current}.
  window.markviewFind = function(query) {
    lastQuery = query || '';
    const count = highlightAll(lastQuery);
    if (count === 0) return result();
    const start = firstMatchFromViewport();
    setCurrent(start < 0 ? 0 : start, true);
    return result();
  };

  // Advance to the next (forward = true) or previous match, wrapping around.
  window.markviewFindStep = function(forward) {
    if (matches.length === 0) return result();
    let next = currentIndex + (forward ? 1 : -1);
    if (next >= matches.length) next = 0;
    if (next < 0) next = matches.length - 1;
    setCurrent(next, true);
    return result();
  };

  // Remove all highlights and reset state (find bar closed).
  window.markviewClearFind = function() {
    clearHighlights();
    lastQuery = '';
    return result();
  };
})();
