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

Changed version: the top-level heading was changed from level 1 to level 2 and the text was updated from "Main Document Title" to "Revised Document Title" to expose heading diff behavior.

## Revised Document Title

## Section with **Bold**

### Subsection with *Italic*

## Paragraphs

### Example 1: Basic Paragraphs

This is a standard paragraph. It contains multiple sentences to show natural text flow and wrapping.

Paragraphs in Markdown are created by separating blocks of text with one or more blank lines. Inline formatting like **bold** can be included.

### Example 2: Paragraphs with Mixed Content

Here is another paragraph. It demonstrates how text can include links, code, and other inline elements seamlessly within the flow of the paragraph itself.

This second paragraph follows after a blank line, ensuring proper separation from the previous one.

Changed version: the first paragraph had "demonstrates how text can include" changed to "shows how text may contain", and the second paragraph had an extra sentence appended.

Here is another paragraph. It shows how text may contain links, code, and other inline elements seamlessly within the flow of the paragraph itself.

This second paragraph follows after a blank line, ensuring proper separation from the previous one. An extra sentence was appended here for the diff test.

## Emphasis and Strong Text

### Example 1: Basic Emphasis

You can emphasize text using *italic* or _italic_ syntax.

For strong emphasis, use **bold** or __bold__.

Combined emphasis works as ***bold and italic*** or ___bold and italic___.

### Example 2: Nested and Mixed Emphasis

This sentence has *italic containing **bold** text* inside it.

You can also have **bold with *italic* inside** for mixed styles.

Changed version: inside the italic the word "bold" was changed to "strong", and inside the bold the word "italic" was changed to "emphasized".

This sentence has *italic containing **strong** text* inside it.

You can also have **bold with *emphasized* inside** for mixed styles.

## Strikethrough

### Example 1: Simple Strikethrough

This text has been ~~struck through~~ to show deletion or correction.

### Example 2: Strikethrough in Context

The old method was ~~inefficient and slow~~, while the new approach is much better.

Changed version: the struck-through phrase was altered from "inefficient and slow" to "slow and inefficient" (word order and synonym change) and an extra struck word was added after it.

The old method was ~~slow and inefficient~~, while the new approach is much better. Additional ~~struck~~ text.

## Inline Code

### Example 1: Basic Inline Code

Use backticks for `inline code` snippets, such as variable names like `userName` or commands like `ls -la`.

### Example 2: Inline Code with Special Characters

Functions like `calculateTotal(price, tax)` or constants such as `MAX_VALUE = 100` are common in code discussions.

Changed version: the function name was changed from calculateTotal to calculateSum and the parameter tax was changed to taxRate, plus minor wording tweak in the sentence.

Functions like `calculateSum(price, taxRate)` or constants such as `MAX_VALUE = 100` are common in code discussions.

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

Changed version: the function was renamed from greet to greetUser, the string "Hello" was changed to "Hi", the comment was slightly altered, and an extra print line was added.

```swift
// A simple function to greet users - updated
func greetUser(name: String) -> String {
    return "Hi, \(name)!"
}

let message = greetUser(name: "World")
print(message)
print("Extra line added for test")
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

Changed version: the second asterisk item had its text changed from "Another asterisk item" to "Another asterisk item with update", a new list item was added, and the nested item under the plus was removed in the source.

* Item using asterisk
* Another asterisk item with update
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

Changed version: the starting number was left but item 6 text was changed, item 7 text tweaked, the nested sub-item removed, and a new item 8 added.

5. Starting from five
6. Continues sequentially with modification
7. Back to main list with tweak
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

Changed version: the first task's text was changed and its state flipped, the subtask "Subtask two pending" was removed, and a new unchecked task was appended.

- [ ] Main task completed - text and state changed
  - [x] Subtask one done
- [ ] Another main task
- [ ] Newly added unchecked task

## Blockquotes

### Example 1: Simple Blockquote

> This is a simple blockquote.
> It can contain multiple lines of quoted text.

### Example 2: Nested Blockquotes

> This is the outer quote.
>
> > This is a nested inner quote.
> > It demonstrates deeper quoting levels.

Changed version: the outer quote text was changed from "This is the outer quote." to "This is the outer quote with revisions.", and inside the nested quote "deeper quoting levels" was changed to "deeper quote levels" with an extra sentence appended.

> This is the outer quote with revisions.
>
> > This is a nested inner quote.
> > It demonstrates deeper quote levels. Extra sentence added here for testing.

## Links

### Example 1: Inline and Reference Links

This is an [inline link](https://example.com "Example Site").

See the [reference link][ref1] for more info.

[ref1]: https://example.org "Reference Title"

### Example 2: Autolinks and Email

Visit https://github.com for the project.

Contact us at <support@example.com> for help.

Changed version: the main URL was changed from github.com to example.com, the autolink email domain was changed, and a reference-style link with altered title was added.

Visit https://example.com for the project.

Contact us at <support@altered.example.com> for help.

See the [reference link][ref1] for more info.

[ref1]: https://example.org "Altered Title"

## Images

### Example 1: Basic Image

![Placeholder Image 1](https://via.placeholder.com/300x150/0066cc/ffffff?text=Image+One "Image One Title")

### Example 2: Another Image Example

![Placeholder Image 2](https://via.placeholder.com/200x100/ff6600/ffffff?text=Image+Two "Image Two Title")

Changed version: the image dimensions in the URL were changed from 200x100 to 250x75, the text inside the URL was changed from "Image+Two" to "Image+Two+Altered", and the title was changed from "Image Two Title" to "Altered Image Title".

![Placeholder Image 2](https://via.placeholder.com/250x75/ff6600/ffffff?text=Image+Two+Altered "Altered Image Title")

## Horizontal Rules

### Example 1: Standard Horizontal Rule

Text before the rule.

---

Text after the rule.

### Example 2: Alternative Horizontal Rule

Content above.

***

More content below.

Changed version: the rule was changed from *** to --- and the text above/below was slightly reworded.

Content above - wording changed.

---

More content below - wording changed for diff test.

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

Changed version: the cell "Text two" was changed to "Text two - modified", the row "More left..." was removed, and a new row was appended.

| Left Align | Center Align | Right Align |
|:-----------|:------------:|------------:|
| Text one   |    Text two - modified   |    Text three |
| New row appended | Center | Right |

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

Changed version: in the summation the index variable was changed from i to k and the upper limit from n to m; in the matrix b was changed to x.

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

## Footnotes

### Example 1: Basic Footnote

This sentence has a footnote reference.[^footnote1]

[^footnote1]: This is the content of the first footnote. It can be quite detailed.

### Example 2: Multiple Footnotes

Another reference here[^footnote2] and also here[^footnote3].

[^footnote2]: Second footnote with some explanation.

[^footnote3]: Third footnote for additional information.

Changed version: the content of footnote2 was changed from "some explanation" to "some explanation and more", footnote3 text was altered, and a new footnote4 was added.

Another reference here[^footnote2] and also here[^footnote3].

[^footnote2]: Second footnote with some explanation and more.
[^footnote3]: Third footnote for altered information.
[^footnote4]: Added footnote four.

