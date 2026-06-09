# Markdown Features Showcase

This document demonstrates the various Markdown features supported by MarkView, based on GitHub Flavored Markdown (GFM) with additional extensions like math via KaTeX.

## Headings

### Example 1: Standard Heading Levels

# Heading Level 1

## Heading Level 2

### Heading Level 3

#### Heading Level 4

##### Heading Level 5

###### Heading Level 6

### Example 2: Additional Headings with Emphasis

# Main Document Title

## Section with **Bold**

### Subsection with *Italic*

## Paragraphs

### Example 1: Basic Paragraphs

This is a standard paragraph. It contains multiple sentences to show natural text flow and wrapping.

Paragraphs in Markdown are created by separating blocks of text with one or more blank lines. Inline formatting like **bold** can be included.

### Example 2: Paragraphs with Mixed Content

Here is another paragraph. It demonstrates how text can include links, code, and other inline elements seamlessly within the flow of the paragraph itself.

This second paragraph follows after a blank line, ensuring proper separation from the previous one.

## Emphasis and Strong Text

### Example 1: Basic Emphasis

You can emphasize text using *italic* or _italic_ syntax.

For strong emphasis, use **bold** or __bold__.

Combined emphasis works as ***bold and italic*** or ___bold and italic___.

### Example 2: Nested and Mixed Emphasis

This sentence has *italic containing **bold** text* inside it.

You can also have **bold with *italic* inside** for mixed styles.

## Strikethrough

### Example 1: Simple Strikethrough

This text has been ~~struck through~~ to show deletion or correction.

### Example 2: Strikethrough in Context

The old method was ~~inefficient and slow~~, while the new approach is much better.

## Inline Code

### Example 1: Basic Inline Code

Use backticks for `inline code` snippets, such as variable names like `userName` or commands like `ls -la`.

### Example 2: Inline Code with Special Characters

Functions like `calculateTotal(price, tax)` or constants such as `MAX_VALUE = 100` are common in code discussions.

## Fenced Code Blocks

### Example 1: Python Code Block

```python
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)

print(fibonacci(10))
```

### Example 2: Swift Code Block with Comments

```swift
// A simple function to greet users
func greet(name: String) -> String {
    return "Hello, \(name)!"
}

let message = greet(name: "World")
print(message)
```

## Unordered Lists

### Example 1: Basic Unordered List

- First item in the list
- Second item
  - Nested sub-item under second
  - Another nested item
- Third item

### Example 2: Alternative Unordered List Markers

* Item using asterisk
* Another asterisk item
  * Nested with asterisk
+ Item using plus sign
+ Another plus item

## Ordered Lists

### Example 1: Basic Ordered List

1. First step in the process
2. Second step
   1. Sub-step under second
   2. Another sub-step
3. Final step

### Example 2: Ordered List with Custom Start

5. Starting from five
6. Continues sequentially
   1. Nested ordered item
7. Back to main list

## Task Lists

### Example 1: Simple Task List

- [x] Completed task one
- [ ] Pending task two
- [x] Another completed task
- [ ] Final pending item

### Example 2: Task List with Nesting

- [x] Main task completed
  - [x] Subtask one done
  - [ ] Subtask two pending
- [ ] Another main task

## Blockquotes

### Example 1: Simple Blockquote

> This is a simple blockquote.
> It can contain multiple lines of quoted text.

### Example 2: Nested Blockquotes

> This is the outer quote.
>
> > This is a nested inner quote.
> > It demonstrates deeper quoting levels.

## Links

### Example 1: Inline and Reference Links

This is an [inline link](https://example.com "Example Site").

See the [reference link][ref1] for more info.

[ref1]: https://example.org "Reference Title"

### Example 2: Autolinks and Email

Visit https://github.com for the project.

Contact us at <support@example.com> for help.

## Images

### Example 1: Basic Image

![Placeholder Image 1](https://via.placeholder.com/300x150/0066cc/ffffff?text=Image+One "Image One Title")

### Example 2: Another Image Example

![Placeholder Image 2](https://via.placeholder.com/200x100/ff6600/ffffff?text=Image+Two "Image Two Title")

## Horizontal Rules

### Example 1: Standard Horizontal Rule

Text before the rule.

---

Text after the rule.

### Example 2: Alternative Horizontal Rule

Content above.

***

More content below.

## Tables

### Example 1: Simple Table

| Feature     | Description          | Status  |
|-------------|----------------------|---------|
| Headings    | Various levels       | Done    |
| Lists       | Ordered and unordered| Done    |
| Emphasis    | Bold and italic      | Done    |

### Example 2: Table with Alignment

| Left Align | Center Align | Right Align |
|:-----------|:------------:|------------:|
| Text one   |    Text two   |    Text three |
| More left  |   More center |    More right |

## Math Equations

### Example 1: Inline Math

The famous equation is $E = mc^2$, and the quadratic formula is $x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$.

### Example 2: Display Math

Here is a summation:

$$

\sum_{i=1}^{n} i = \frac{n(n+1)}{2}

$$

And a matrix example:

$$

\begin{pmatrix}
a & b \\
c & d
\end{pmatrix}

$$

## Footnotes

### Example 1: Basic Footnote

This sentence has a footnote reference.[^footnote1]

[^footnote1]: This is the content of the first footnote. It can be quite detailed.

### Example 2: Multiple Footnotes

Another reference here[^footnote2] and also here[^footnote3].

[^footnote2]: Second footnote with some explanation.

[^footnote3]: Third footnote for additional information.


## Word-by-Word Diff Test Cases

The sections below contain paired "before" and "after" examples for each major Markdown feature. The paragraph above each "after" block describes the artificial change made to the Markdown source. These are designed so that when viewing the diff of this file (original commit on left, this version on right), the red/green word-by-word highlighting can be visually verified inside headings, paragraphs, formatting, tables, math, lists, code, etc.

One instance per feature remains completely unchanged from the examples above. The modified instances below have targeted partial changes (single word changes, formatting changes, table row/column/cell edits, math variable + operator changes, etc.).

### Headings - Test

Changed version: level changed from H1 to H2 and one word in the heading text was altered.

## Revised Document Title with Word Change

### Paragraph / Sentence - Test

Changed version: single word "demonstrates" changed to "shows" and "include" to "contain" in the middle of the sentence.

Here is another paragraph. It shows how text may contain links, code, and other inline elements seamlessly within the flow of the paragraph itself.

### Emphasis and Formatting Change - Test

Changed version: the word "bold" was changed from **bold** to *italic*, and "italic" from *italic* to **bold** to test formatting type change.

This sentence has *italic containing **bold** text* inside it.

You can also have **bold with *italic* inside** for mixed styles.

Changed version: emphasis type swapped on specific words.

This sentence has *italic containing *bold* text* inside it.

You can also have *italic with **bold** inside* for mixed styles.

### Strikethrough - Test

Changed version: the struck phrase was re-ordered and one word synonym changed from "inefficient and slow" to "slow and inefficient", plus one extra struck word added.

The old method was ~~slow and inefficient~~, while the new approach is much better. Additional ~~struck~~ text.

### Inline Code - Test

Changed version: function name changed from calculateTotal to calculateSum and parameter from tax to taxRate.

Functions like `calculateSum(price, taxRate)` or constants such as `MAX_VALUE = 100` are common in code discussions.

### Fenced Code Block - Test

Changed version: function renamed, string literal changed from "Hello" to "Hi", and one extra line added inside the block.

```swift
// A simple function to greet users
func greetUser(name: String) -> String {
    return "Hi, \(name)!"
}

let message = greetUser(name: "World")
print(message)
print("Extra line added for test")
```

### Unordered List - Test

Changed version: one item's text changed, one new top-level item added, one nested item removed.

* Item using asterisk
* Another asterisk item with update
+ Item using plus sign
+ Another plus item

### Ordered List - Test

Changed version: one item's text changed, starting number context, one nested removed, one new item added.

5. Starting from five
6. Continues sequentially with modification
7. Back to main list with tweak
8. Newly added item for diff test

### Task List - Test

Changed version: one task text and checked state changed, one subtask removed, one new task added.

- [ ] Main task completed - text and state changed
  - [x] Subtask one done
- [ ] Another main task
- [ ] Newly added unchecked task

### Blockquote - Test

Changed version: outer quote text changed, inner quote text and added sentence.

> This is the outer quote with revisions.
>
> > This is a nested inner quote.
> > It demonstrates deeper quote levels. Extra sentence added here for testing.

### Links - Test

Changed version: main URL changed, email domain changed, reference title altered.

Visit https://example.com for the project.

Contact us at <support@altered.example.com> for help.

See the [reference link][ref1] for more info.

[ref1]: https://example.org "Altered Title"

### Images - Test

Changed version: image URL dimensions and text changed, title changed.

![Placeholder Image 2](https://via.placeholder.com/250x75/ff6600/ffffff?text=Image+Two+Altered "Altered Image Title")

### Horizontal Rule - Test

Changed version: rule marker changed from *** to --- and surrounding text slightly modified.

Content above - wording changed.

---

More content below - wording changed for diff test.

### Tables - Test

Changed version: one cell wording changed ("Text two" to "Text two - modified"), one row removed, one new row added, and structure for column add/delete simulated by changing a column's content and adding a column.

| Left Align | Center Align | Right Align | Extra Col |
|:-----------|:------------:|------------:|-----------|
| Text one   |    Text two - modified   |    Text three | New col   |
| New row appended | Center | Right | Another |

### Math Equations - Test

Changed version: summation variable renamed from i to k, upper limit changed from n to m, and matrix had b changed to x (partial formula change).

Here is a summation:

$$

\sum_{k=1}^{m} k = \frac{m(m+1)}{2}

$$

And a matrix example:

$$

\begin{pmatrix}
a & x \\
c & d
\end{pmatrix}

$$

### Footnotes - Test

Changed version: footnote2 content had "some explanation" changed to "some explanation and more", footnote3 altered, and a new footnote4 added.

Another reference here[^footnote2] and also here[^footnote3].

[^footnote2]: Second footnote with some explanation and more.
[^footnote3]: Third footnote for altered information.
[^footnote4]: Added footnote four.

