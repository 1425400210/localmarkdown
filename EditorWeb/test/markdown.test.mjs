import test from 'node:test';
import assert from 'node:assert/strict';
import { parseDocument, taskEdit } from '../src/markdown.js';

const render = source => parseDocument(source).html;
test('CommonMark blocks, nesting, Setext headings, escapes and entities', () => {
  const source = '# Heading\n\nSetext\n======\n\n> quote\n>\n> > inner\n\n1. first\n   - nested\n\n       code\n\n---\n\n\\*literal\\* &amp;  \nbreak\n';
  const result = parseDocument(source);
  assert.deepEqual(result.headings.map(h => h.title), ['Heading', 'Setext']);
  for (const tag of ['<h1', '<blockquote>', '<ol>', '<ul>', '<hr>', '<br>']) assert.ok(result.html.includes(tag), tag);
  assert.match(result.html, /\*literal\* &amp;/);
  for (const b of result.blocks) assert.ok(b.from >= 0 && b.to <= source.length && b.to > b.from);
});
test('nested emphasis protects only literal code, not its enclosing bold', () => {
  assert.match(render('**L2 (`reg_lambda`)** and ***strong italic***'), /<strong>L2 \(<code>reg_lambda<\/code>\)<\/strong>/);
  assert.match(render('`**literal**` and **[link](https://example.com)**'), /<code>\*\*literal\*\*<\/code>/);
  assert.match(render('**[link](https://example.com)**'), /<strong><a /);
});
test('fences, indented code, literal markers and language highlighting', () => {
  const html = render('````python\nprint("hi")\n```\n# literal\n````\n\n    indented code\n');
  assert.match(html, /hljs-/);
  assert.match(html, /# literal/);
  assert.match(html, /<pre><code>indented code/);
  assert.equal(parseDocument('```\n# not heading\n```').headings.length, 0);
});
test('tables support alignment, escaped pipes and nested inline formatting', () => {
  const html = render('| left | right |\n| :--- | ---: |\n| **a `b`** | c\\|d |');
  assert.match(html, /<table>/);
  assert.match(html, /text-align:right/);
  assert.match(html, /<strong>a <code>b<\/code><\/strong>/);
  assert.match(html, /c\|d/);
});
test('links, references, anchors, autolinks and images', () => {
  const html = render('# Title\n\n[go](#title) [ref][id] https://example.com <a@example.com>\n\n![图片](images/a.png)\n\n[id]: https://example.org "title"');
  assert.match(html, /href="#title"/);
  assert.match(html, /href="https:\/\/example.org" title="title"/);
  assert.match(html, /href="mailto:a@example.com"/);
  assert.match(html, /src="images\/a.png"/);
});
test('tasks map to exact source character including quote, nesting and unicode', () => {
  const source = '😀\n\n- [ ] first\n  - [x] child\n\n> - [ ] quoted';
  const html = render(source);
  assert.match(html, /data-task-line="2"/);
  assert.match(html, /data-task-line="3"/);
  for (const line of [2, 3, 5]) {
    const edit = taskEdit(source, line);
    assert.ok(edit);
    assert.equal(edit.to - edit.from, 1);
    assert.ok(source.slice(edit.from - 1, edit.to + 1).match(/^\[[ x]\]$/));
  }
  assert.equal(taskEdit(source, 0), null);
});
test('extensions render math, highlight, strike, footnotes, YAML, callouts and mermaid', () => {
  const source = '---\ntitle: 测试\n---\n\n# 标题 $X$\n\n$x^2$ and ==mark== ~~strike~~ text[^1]\n\n$$\\frac{a}{b}$$\n\n> [!NOTE]\n> Notice\n\n```mermaid\ngraph TD\nA --> B\n```\n\n[^1]: **footnote**\n';
  const result = parseDocument(source);
  for (const pattern of [/class="metadata"/, /class="katex"/, /<mark>mark<\/mark>/, /<s>strike<\/s>/, /class="footnotes"/, /callout-note/, /data-mermaid=/]) assert.match(result.html, pattern);
  assert.equal(result.headings[0].title, '标题 X');
  assert.ok(result.blocks.some(b => b.type === 'footnotes'));
  assert.ok(result.blocks.some(b => b.type === 'math_block'));
});
test('broken math stays editable and source is never transformed', () => {
  const source = '# 中文😀\r\n\r\n$\\invalid{ $\r\n\r\n**unclosed\r\n';
  const copy = source;
  assert.doesNotThrow(() => parseDocument(source));
  assert.equal(source, copy);
});
test('code and escaped math/highlight are literal', () => {
  const html = render('`$x$ ==literal==` \\*not italic\\*');
  assert.ok(!html.includes('class="katex"'));
  assert.ok(!html.includes('<mark>'));
});
test('block ranges do not overlap including footnote definitions in code', () => {
  const source = '# A\n\n```md\n[^1]: code only\n```\n\ntext[^2]\n\n[^2]: real\n\nEnd\n';
  const { blocks } = parseDocument(source);
  for (let i = 1; i < blocks.length; i++) assert.ok(blocks[i].from >= blocks[i - 1].to);
  assert.equal(blocks.filter(b => b.type === 'footnotes').length, 1);
});
test('escaped task markers remain literal', () => {
  assert.ok(!render('- \\[ \\] literal').includes('type="checkbox"'));
});
