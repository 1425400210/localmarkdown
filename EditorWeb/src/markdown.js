import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import mark from 'markdown-it-mark';
import texmath from 'markdown-it-texmath';
import katex from 'katex';
import hljs from 'highlight.js';

export const md = new MarkdownIt({
  html: true, linkify: true, typographer: false, breaks: false,
  highlight(code, language) {
    return language && hljs.getLanguage(language)
      ? hljs.highlight(code, { language, ignoreIllegals: true }).value : '';
  }
}).use(footnote).use(mark).use(texmath, {
  engine: katex, delimiters: 'dollars',
  katexOptions: { throwOnError: false, trust: false, strict: false, maxExpand: 1000 }
});
const escape = md.utils.escapeHtml;

// Metadata is a document block, not a horizontal rule followed by a Setext heading.
md.block.ruler.before('hr', 'frontmatter', (state, start, end, silent) => {
  if (start !== 0 || state.src.slice(state.bMarks[0], state.eMarks[0]).trim() !== '---') return false;
  let close = 1;
  while (close < end && !/^(---|\.\.\.)\s*$/.test(state.src.slice(state.bMarks[close], state.eMarks[close]))) close++;
  if (close === end) return false;
  if (!silent) {
    const token = state.push('frontmatter', '', 0);
    token.map = [start, close + 1];
    token.content = state.getLines(start + 1, close, 0, false);
    state.line = close + 1;
  }
  return true;
});
md.renderer.rules.frontmatter = (tokens, i) => `<section class="metadata"><div class="block-label">文档属性 · YAML</div><pre>${escape(tokens[i].content)}</pre></section>`;

const fence = md.renderer.rules.fence;
md.renderer.rules.fence = (tokens, i, options, env, self) => {
  const token = tokens[i];
  if (token.info.trim() === 'mermaid') {
    return `<div class="diagram" data-mermaid=""><pre>${escape(token.content)}</pre></div>`;
  }
  return `<div class="code-block"><div class="code-toolbar"><span>${escape(token.info.trim().split(/\s/)[0] || '代码')}</span><button type="button" data-copy-code>复制</button></div>${fence(tokens, i, options, env, self)}</div>`;
};

function plainInline(tokens = []) {
  return tokens.map(t => t.type === 'image' ? t.content : t.children ? plainInline(t.children)
    : ['text', 'code_inline', 'math_inline'].includes(t.type) ? t.content
    : t.type === 'softbreak' || t.type === 'hardbreak' ? ' ' : '').join('');
}

// Preserve the parser's source maps. Widget actions always modify source, never rendered HTML.
md.core.ruler.after('inline', 'local_blocks', state => {
  const ids = new Map();
  const tokens = state.tokens;
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t.type === 'heading_open') {
      const title = plainInline(tokens[i + 1]?.children);
      const base = title.toLowerCase().replace(/[^\p{L}\p{N}_\s-]/gu, '').replace(/\s/g, '-');
      const n = ids.get(base) || 0;
      ids.set(base, n + 1);
      t.attrSet('id', n ? `${base}-${n}` : base);
      t.meta = { title };
    }
    if (t.type === 'list_item_open') {
      const inline = tokens[i + 2];
      if (tokens[i + 1]?.type !== 'paragraph_open' || inline?.type !== 'inline') continue;
      const first = inline.children?.[0];
      const match = first?.type === 'text' && inline.content.match(/^\[([ xX])\]\s+/);
      if (!match) continue;
      first.content = first.content.slice(match[0].length);
      const checkbox = new state.Token('html_inline', '', 0);
      checkbox.content = `<input type="checkbox" data-task-line="${t.map[0]}" aria-label="切换任务" ${match[1] !== ' ' ? 'checked' : ''}>`;
      inline.children.unshift(checkbox);
      t.attrJoin('class', 'task-item');
    }
    if (t.type === 'blockquote_open' && tokens[i + 1]?.type === 'paragraph_open') {
      const inline = tokens[i + 2];
      const first = inline?.children?.[0];
      const match = first?.type === 'text' && first.content.match(/^\[!([A-Za-z]+)\]([+-])?(?:[ \t]+([^\n]*))?/);
      if (!match) continue;
      const kind = match[1].toLowerCase();
      const labels = { note: '笔记', tip: '提示', important: '重要', warning: '警告', caution: '注意', info: '信息' };
      t.attrJoin('class', `callout callout-${kind}`);
      first.content = first.content.slice(match[0].length);
      const title = new state.Token('html_inline', '', 0);
      title.content = `<strong class="callout-title">${escape(match[3] || labels[kind] || kind)}</strong>`;
      inline.children.unshift(title);
    }
  }
});

export function parseDocument(source) {
  const env = {};
  const tokens = md.parse(source, env);
  const starts = [0];
  for (let i = 0; i < source.length; i++) if (source[i] === '\n') starts.push(i + 1);
  const offset = line => starts[line] ?? source.length;
  const blocks = [];
  const headings = [];
  const html = ts => md.renderer.render(ts, md.options, env);
  for (let i = 0; i < tokens.length;) {
    const token = tokens[i];
    if (token.type === 'heading_open' && token.map) {
      headings.push({ title: token.meta?.title || '', level: Number(token.tag.slice(1)),
        from: offset(token.map[0]), to: offset(token.map[1]), id: token.attrGet('id') });
    }
    // Root blocks are replaced together, retaining nested lists, quotes and tables.
    if (token.level !== 0 || !token.map) { i++; continue; }
    let end = i + 1;
    if (token.nesting === 1) {
      let depth = 1;
      while (end < tokens.length && depth) { depth += tokens[end].nesting; end++; }
    }
    const from = offset(token.map[0]);
    let to = offset(token.map[1]);
    if (source[to - 1] === '\n') to--;
    if (source[to - 1] === '\r') to--;
    if (to > from) blocks.push({ from, to, html: html(tokens.slice(i, end)), type: token.type });
    // Also expose headings nested inside a quote or list in the outline.
    for (let j = i + 1; j < end; j++) {
      const h = tokens[j];
      if (h.type === 'heading_open' && h.map) headings.push({ title: h.meta?.title || '',
        level: Number(h.tag.slice(1)), from: offset(h.map[0]), to: offset(h.map[1]), id: h.attrGet('id') });
    }
    i = end;
  }
  // Footnote definitions are removed from the token stream and rendered as a footer.
  // Show them at their original source position, so clicking the footer edits the definitions.
  const footStart = tokens.findIndex(t => t.type === 'footnote_block_open');
  if (footStart >= 0) {
    const definitions = [...source.matchAll(/^ {0,3}\[\^[^\]\n]+\]:.*(?:\n(?:[ \t]+[^\n]*|(?=\n)))*/gm)]
      .filter(m => !blocks.some(b => m.index >= b.from && m.index < b.to));
    for (let i = 0; i < definitions.length; i++) {
      const m = definitions[i];
      blocks.push({ from: m.index, to: m.index + m[0].replace(/[\r\n]+$/, '').length,
        html: i === 0 ? html(tokens.slice(footStart)) : '<div class="definition-label">脚注定义</div>', type: 'footnotes' });
    }
  }
  // Reference definitions have no visible tokens but remain editable and discoverable.
  for (const m of source.matchAll(/^ {0,3}\[(?!\^)[^\]\n]+\]:[^\n]+/gm)) {
    if (!blocks.some(b => m.index >= b.from && m.index < b.to)) blocks.push({
      from: m.index, to: m.index + m[0].length, type: 'reference',
      html: `<div class="definition-label">链接定义 <code>${escape(m[0])}</code></div>`
    });
  }
  blocks.sort((a, b) => a.from - b.from);
  return { blocks, headings, html: html(tokens) };
}

export function taskEdit(source, lineNumber) {
  const lines = source.split('\n');
  const line = lines[lineNumber];
  if (line == null) return null;
  const match = line.match(/^(?:[ \t]*>[ \t]?)*[ \t]*(?:[-+*]|\d+[.)])[ \t]+\[([ xX])\]/);
  if (!match) return null;
  const from = lines.slice(0, lineNumber).reduce((n, s) => n + s.length + 1, 0) + match[0].length - 2;
  return { from, to: from + 1, insert: match[1] === ' ' ? 'x' : ' ' };
}
