# Markdown *Diff* Showcase

This document demonstrates the various Markdown features supported by MarkView and how diffs are shown, based on GitHub Flavored Markdown (GFM) with some extensions like math via KaTeX.

## Headings

### Example 1: Standard Heading Levels

# Heading Level 1

## Heading Level 2

### Heading Level 3

#### Heading **Level** 4

##### Heading ~~Level~~ 5

###### Heading *Level 6*

### Example 2: Additional Headings with Emphasis

# Main Document Title

## Section with *Italic*

### **Subsection** with *Italic*

## Paragraphs

### Example 1: Basic Paragraphs

This is a standard paragraph. It contains multiple sentences to show natural text flow and wrapping.

Paragraphs in Markdown are created by having blocks of text separated with one or more blank lines. Inline formatting like **bold** can be included.

### Example 2: Paragraphs with Mixed Content

Here is another paragraph. It demonstrates how text can include links, code, and other inline elements seamlessly within the flow of the paragraph itself.

This second paragraph follows after a blank line, ensuring proper separation from the previous one.

## Emphasis and Strong Text

### Example 1: Basic Emphasis

You always emphasize text using *italic* or _italic_ syntax.

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
    // the end
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)

print(fibonacci(10))
```

### Example 2: Swift Code Block with Comments

```swift
// A simple function to greet users
func greet(world: String) -> String {
    return "Hello, \(world)!"
}

let message = greet(world: "World")
print(message)
```

## Unordered Lists

### Example 1: Basic Unordered List

- First entry in the list
  - Nested in the first item
- Second item
  - Nested sub-item under second
  - Another nested item
- Third item
- Fourth item

### Example 2: Alternative Unordered List Markers

+ Item using asterisk
+ Another asterisk item
  + Nested with asterisk
* Item using plus sign
* Another plus item

## Ordered Lists

### Example 1: Basic Ordered List

1. First step in the process
2. Second step
   1. Another sub-step
   2. Sub-step under second
3. Final step

### Example 2: Ordered List with Custom Start

5. Starting from five
6. Continues sequentially
   1. Nested ordered item
7. Back to main list

## Task Lists

### Example 1: Simple Task List

- [ ] Completed task one
- [x] Pending task two
- [ ] Another completed task
- [ ] Final pending item

### Example 2: Task List with Nesting

- [x] Main task completed
  - [ ] Subtask one done
  - [x] Subtask two pending
- [x] Another main task

## Blockquotes

### Example 1: Simple Blockquote

> This is a blockquote.
> It can contain multiple lines of quoted text.

### Example 2: Nested Blockquotes

> This is an outer quote.
>
> > This is a nested quote.
> > It demonstrates deeper quoting levels.

## Links

### Example 1: Inline and Reference Links

This is an [a link](https://example.com "Example Site").

See the [reference link][ref2] for more info.

[ref2]: https://example.org "Reference Title"

### Example 2: Autolinks and Email

Visit https://www.github.com for the project.

Contact us at <support@erewhon.com> for help.

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
| Lists       | Ordered / unordered  | Done    |
| Underline   | Underlining          | Done    |
| Emphasis    | Bold and italic      | Done    |

### Example 2: Table with Alignment

| Left Align | Center Align | Right Align | No Align |
|:-----------|:------------:|------------:|----------|
| Text one   |    Text two   |    Text three | four  |
| More left  |   More center |    More right | more  |

## Math Equations

### Example 1: Inline Math

The famous equation is $E = mc^2$, and the quadratic formula is $x = \frac{-B \pm \sqrt{B^2 - 4AC}}{2a}$.

### Example 2: Display Math

Here is a summation:

$$
\sum_{i=1}^{n} i = \sum_{n(n+1)}{2}
$$

And a matrix example:

$$
\begin{pmatrix}
A & b \\
c & d
\end{pmatrix}
$$

## Footnotes

### Example 1: Basic Footnote

This phrase has a footnote reference.[^footnote1]

[^footnote1]: This is the first footnote. It can be quite detailed.

### Example 2: Multiple Footnotes

Another reference here[^footnote2] and also here[^footnote3].

[^footnote2]: Second footnote with some explanation.

[^footnote3]: Third footnote for additional information.
