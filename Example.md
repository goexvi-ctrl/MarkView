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

This paragraph describes the change to the headings feature: the top-level heading text was updated with new wording, and the level was changed from H1 to H2 to demonstrate partial structural and text changes in headings while keeping surrounding content intact.

## This is a **revised** Main Document Title (changed from original H1)

## Section with **Bold**

### Subsection with *Italic*

## Paragraphs

### Example 1: Basic Paragraphs

This is a standard paragraph. It contains multiple sentences to show natural text flow and wrapping.

Paragraphs in Markdown are created by separating blocks of text with one or more blank lines. Inline formatting like **bold** can be included.

### Example 2: Paragraphs with Mixed Content

Here is another paragraph. It demonstrates how text can include links, code, and other inline elements seamlessly within the flow of the paragraph itself.

This second paragraph follows after a blank line, ensuring proper separation from the previous one.

This paragraph describes the change to the paragraphs feature: wording in the first paragraph was partially updated with new descriptive text, and an additional sentence was added to the second paragraph to show inline text modifications.

Here is another paragraph. It demonstrates how text can include links, code, and other inline elements seamlessly within the flow of the paragraph itself. Additional sentence added here for the test case.

This second paragraph follows after a blank line, ensuring proper separation from the previous one. An extra sentence was appended to demonstrate partial paragraph changes.

## Emphasis and Strong Text

### Example 1: Basic Emphasis

You can emphasize text using *italic* or _italic_ syntax.

For strong emphasis, use **bold** or __bold__.

Combined emphasis works as ***bold and italic*** or ___bold and italic___.

### Example 2: Nested and Mixed Emphasis

This sentence has *italic containing **bold** text* inside it.

You can also have **bold with *italic* inside** for mixed styles.

This paragraph describes the change to the emphasis feature: the italic text was reworded slightly, and the bold portion had its inner text updated to show word-level partial changes within emphasis syntax.

This sentence has *italic containing **revised bold** text* inside it with updated wording.

You can also have **bold with *modified italic* inside** for mixed styles demonstrating the diff.

## Strikethrough

### Example 1: Simple Strikethrough

This text has been ~~struck through~~ to show deletion or correction.

### Example 2: Strikethrough in Context

The old method was ~~inefficient and slow~~, while the new approach is much better.

This paragraph describes the change to the strikethrough feature: the struck-through phrase was updated to new wording, and an additional struck-through segment was inserted to demonstrate partial changes within strikethrough syntax.

The old method was ~~inefficient and slow~~, while the new approach is much better and **revised**. Additional ~~struck text added here~~ for testing word diffs.

## Inline Code

### Example 1: Basic Inline Code

Use backticks for `inline code` snippets, such as variable names like `userName` or commands like `ls -la`.

### Example 2: Inline Code with Special Characters

Functions like `calculateTotal(price, tax)` or constants such as `MAX_VALUE = 100` are common in code discussions.

This paragraph describes the change to the inline code feature: the function name in the code was updated, and a parameter was changed along with surrounding sentence wording to show word-level diffs inside inline code spans.

Functions like `calculateSum(price, taxRate)` or constants such as `MAX_VALUE = 100` are common in code discussions with revised text.

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

This paragraph describes the change to the fenced code block feature: the function name and a string literal inside the code were changed, and a comment was updated with new wording, plus an extra print statement added to demonstrate partial code changes.

```swift
// A simple function to greet users - revised comment
func greetUser(name: String) -> String {
    return "Hello, \(name)!"
}

let message = greetUser(name: "World")
print(message)
print("Additional line for diff test")
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

This paragraph describes the change to the unordered lists feature: one list item's text was reworded, a new item was inserted, and a nested item was deleted (via diff) to show added, removed, and modified list items with word changes.

* Item using asterisk - revised wording
* Another asterisk item with update
  * Nested with asterisk
+ Item using plus sign
+ New added item for testing
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

This paragraph describes the change to the ordered lists feature: the starting number and one item's text were changed, a new numbered item was added, and a nested sub-item was removed to test partial list modifications.

5. Starting from five - revised start
6. Continues sequentially with update
   1. Nested ordered item
7. Back to main list
8. Newly added item for diff test

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

This paragraph describes the change to the task lists feature: one task's text and checked state were updated, a new task item was added, and a subtask was removed to demonstrate changes to task list syntax and states.

- [x] Main task completed - revised text
  - [x] Subtask one done
  - [ ] Subtask two pending
- [ ] Another main task with update
- [ ] Newly added pending task

## Blockquotes

### Example 1: Simple Blockquote

> This is a simple blockquote.
> It can contain multiple lines of quoted text.

### Example 2: Nested Blockquotes

> This is the outer quote.
>
> > This is a nested inner quote.
> > It demonstrates deeper quoting levels.

This paragraph describes the change to the blockquotes feature: the text in the outer and inner quotes was partially reworded, and an additional sentence was added inside the nested quote to show inline text changes within blockquotes.

> This is the outer quote with updated wording.
>
> > This is a nested inner quote with revisions.
> > It demonstrates deeper quoting levels. Additional changed sentence here.

## Links

### Example 1: Inline and Reference Links

This is an [inline link](https://example.com "Example Site").

See the [reference link][ref1] for more info.

[ref1]: https://example.org "Reference Title"

### Example 2: Autolinks and Email

Visit https://github.com for the project.

Contact us at <support@example.com> for help.

This paragraph describes the change to the links feature: the URL in the inline link was changed to a different domain, the link text was updated, and the reference link target and title were modified with partial word changes. An additional autolink was inserted.

Visit https://example.com for the updated project site.

See the [reference link][ref1] for more info with revised title.

[ref1]: https://example.org "Updated Reference Title"

Contact us at <support@example.com> for help. New autolink added: https://new.example.com

## Images

### Example 1: Basic Image

![Placeholder Image 1](https://via.placeholder.com/300x150/0066cc/ffffff?text=Image+One "Image One Title")

### Example 2: Another Image Example

![Placeholder Image 2](https://via.placeholder.com/200x100/ff6600/ffffff?text=Image+Two "Image Two Title")

This paragraph describes the change to the images feature: the image URL was updated to a different placeholder size and text, and the title/alt attributes were changed with new wording to demonstrate partial changes to image syntax.

![Revised Image](https://via.placeholder.com/150x50/ff0000/ffffff?text=Changed+Image "Updated Image Title")

## Horizontal Rules

### Example 1: Standard Horizontal Rule

Text before the rule.

---

Text after the rule.

### Example 2: Alternative Horizontal Rule

Content above.

***

More content below.

This paragraph describes the change to the horizontal rules feature: the rule style was changed from *** to ---, and descriptive text around it was updated with new wording to show changes involving HR syntax and adjacent paragraphs.

Content above with revised text.

---

More content below with added sentence for the test.

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

This paragraph describes the change to the tables feature: the text in one cell was updated with new wording, a new row was added, and one existing row was removed to demonstrate added, deleted, and modified table content at the cell and row level.

| Left Align | Center Align | Right Align |
|:-----------|:------------:|------------:|
| Text one   |    Text two   |    Text three - revised wording here |
| More left  |   More center |    More right |
| New row added | Center new | Right new |

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

This paragraph describes the change to the math equations feature: the variable in the summation was renamed from i to k, the upper limit was changed, and part of the matrix was updated with different letters to show word/symbol changes in formulas.

Here is a summation:

$$

\sum_{k=1}^{m} k = \frac{m(m+1)}{2}

$$

And a matrix example with updates:

$$

\begin{pmatrix}
a & x \\
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

This paragraph describes the change to the footnotes feature: the text of one footnote was updated with new wording, and an additional footnote reference and definition were inserted to demonstrate partial changes to footnote syntax and content.

Another reference here[^footnote2] and also here[^footnote3] with new reference[^footnote4] added.

[^footnote2]: Second footnote with some explanation and revised text here.
[^footnote3]: Third footnote for additional information.
[^footnote4]: Newly added fourth footnote for the diff test case.

