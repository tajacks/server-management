---
layout: layouts/chapter.njk
title: Typography Reference
description: Visual examples and implementation guide for typographical elements
permalink: /typography-reference/
eleventyExcludeFromCollections: true
---

<div style="max-width: 900px; margin: 0 auto; padding: 2rem;">

# Typography Reference

This page demonstrates the typographical flourishes available for structuring and emphasizing content throughout the book.

---

## Callouts & Admonitions

### Information Callout

<div class="callout callout-info">
<strong>Information</strong>: Use this for helpful context or background information that supplements the main text.
</div>

```html
<div class="callout callout-info">
<strong>Information</strong>: Your message here.
</div>
```

### Warning Callout

<div class="callout callout-warning">
<strong>Warning</strong>: Use this to highlight potential pitfalls or important cautions.
</div>

```html
<div class="callout callout-warning">
<strong>Warning</strong>: Your message here.
</div>
```

### Tip Callout

<div class="callout callout-tip">
<strong>Tip</strong>: Use this for helpful suggestions or best practices.
</div>

```html
<div class="callout callout-tip">
<strong>Tip</strong>: Your message here.
</div>
```

---

## Pull Quotes

Use pull quotes to highlight important statements or key takeaways.

<div class="pullquote">
The most important configuration is the one that prevents problems before they occur.
</div>

```html
<div class="pullquote">
Your highlighted quote here.
</div>
```

---

## Block Quotes

Traditional quotations from external sources:

> This is a standard block quote. It uses the default markdown syntax and is styled to fit our academic theme with a subtle left border and italic text.

```markdown
> Your quote text here.
```

---

## Side Notes

<div class="sidenote">
<strong>Note:</strong> Side notes provide supplementary information without interrupting the main text flow. They're perfect for tangential details.
</div>

Use side notes for parenthetical information that readers might want to skip.

```html
<div class="sidenote">
<strong>Note:</strong> Your side note here.
</div>
```

---

## Definition Lists

<dl class="definition-list">
  <dt>Server</dt>
  <dd>A computer system that provides services to other computers over a network.</dd>

  <dt>SSH</dt>
  <dd>Secure Shell, a cryptographic network protocol for secure remote login and command execution.</dd>

  <dt>Daemon</dt>
  <dd>A background process that runs continuously, typically started at boot time.</dd>
</dl>

```html
<dl class="definition-list">
  <dt>Term</dt>
  <dd>Definition of the term.</dd>
</dl>
```

---

## Keyboard Shortcuts

Use keyboard shortcut styling for key combinations and commands:

Press <kbd>Ctrl</kbd>+<kbd>C</kbd> to copy, <kbd>Ctrl</kbd>+<kbd>V</kbd> to paste.

Use <kbd>Shift</kbd>+<kbd>Enter</kbd> to create a new line without submitting.

Exit the editor with <kbd>Esc</kbd> followed by <kbd>:wq</kbd>.

```html
<kbd>Ctrl</kbd>+<kbd>C</kbd>
<kbd>Shift</kbd>+<kbd>Enter</kbd>
<kbd>Esc</kbd>
```

---

## Emphasis Styles

Use **bold text** for strong emphasis and *italic text* for softer emphasis or titles.

Use <span class="small-caps">small caps</span> for acronyms like <span class="small-caps">ssh</span> or <span class="small-caps">http</span>.

```markdown
**bold text**
*italic text*
<span class="small-caps">acronym</span>
```

---

## Code Examples

Inline code looks like this: `apt update && apt upgrade`

Code blocks with language specification:

```bash
#!/bin/bash
systemctl status sshd
journalctl -u sshd -f
```

---

## Highlighted Text

Use <mark>highlighting</mark> to draw attention to specific terms or important text.

```html
<mark>highlighted text</mark>
```

---

## Key Takeaway Box

<div class="key-takeaway">
<strong>Key Takeaway</strong><br>
This box highlights the main points or conclusions of a section. Use it sparingly to emphasize critical concepts readers should remember.
</div>

```html
<div class="key-takeaway">
<strong>Key Takeaway</strong><br>
Your main point here.
</div>
```

---

## Command Examples

<div class="command-example">
<div class="command-label">Run this command:</div>
<code>sudo systemctl restart nginx</code>
</div>

```html
<div class="command-example">
<div class="command-label">Run this command:</div>
<code>your-command-here</code>
</div>
```

---

## Code Files

Display code with a filename header to show which file is being edited:

<div class="code-file">
<div class="code-file-name">/etc/ssh/sshd_config</div>

```bash
Port 22
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```
</div>

<div class="code-file">
<div class="code-file-name">nginx.conf</div>

```nginx
server {
    listen 80;
    server_name example.com;
    root /var/www/html;
}
```
</div>

**Usage:**

```html
<div class="code-file">
  <div class="code-file-name">filename.ext</div>
  <!-- Insert your code block here using triple backticks -->
</div>
```

Wrap the filename div and your code block (with triple backticks) inside the `code-file` div.

</div>
