import { EditorState, StateField, StateEffect, Compartment } from '@codemirror/state';
import { EditorView, Decoration, WidgetType, keymap, drawSelection, placeholder } from '@codemirror/view';
import { history, historyKeymap, defaultKeymap, indentWithTab, undo, redo } from '@codemirror/commands';
import { markdown, markdownKeymap } from '@codemirror/lang-markdown';
import { languages } from '@codemirror/language-data';
import { syntaxHighlighting, defaultHighlightStyle } from '@codemirror/language';
import { search, searchKeymap, openSearchPanel } from '@codemirror/search';
import DOMPurify from 'dompurify';
import mermaid from 'mermaid';
import { parseDocument, taskEdit } from './markdown.js';
import { blockSpacing } from './typography.js';
import { formatEdit } from './formatting.js';
import 'katex/dist/katex.min.css';
import './style.css';

const send = (type, payload = {}) => window.webkit?.messageHandlers.editor.postMessage({ type, ...payload });
let settings = { sourceMode: false, fontSize: 16, editorWidth: 800, dark: false };
let parsedSource = null, parsed = null, view, diagramID = 0;
let initialized = false;
let editorExtensions;
const refresh = StateEffect.define();
const externalChange = StateEffect.define();
const theme = new Compartment();
const formattingKeys = new Compartment();
const diagramCache = new Map();
mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'default', suppressErrorRendering: true, flowchart: { htmlLabels: false } });

export function sanitizedHTML(html) {
  const clean = DOMPurify.sanitize(html, {
    FORBID_TAGS: ['script', 'iframe', 'object', 'embed', 'form', 'style', 'link', 'base', 'meta'],
    FORBID_ATTR: ['srcset', 'autofocus', 'contenteditable'],
    ADD_ATTR: ['target'],
  });
  const template = document.createElement('template');
  template.innerHTML = clean;
  for (const image of template.content.querySelectorAll('img')) {
    const src = image.getAttribute('src') || '';
    if (!/^(https?:|data:image\/|local-md:)/i.test(src)) {
      image.setAttribute('src', `local-md://asset?path=${encodeURIComponent(src)}&document=${encodeURIComponent(settings.documentURL || "")}`);
    }
    image.loading = 'lazy';
    image.addEventListener('error', () => image.classList.add('missing-image'));
  }
  return template.content;
}

function sourceModel(state) {
  const source = state.doc.toString();
  if (source !== parsedSource) { parsedSource = source; parsed = parseDocument(source); parsed.blocks = blockSpacing(parsed.blocks); }
  return parsed;
}

class RenderedBlock extends WidgetType {
  constructor(block) { super(); this.block = block; this.dark = settings.dark; this.documentURL = settings.documentURL; }
  eq(other) { return this.block.gap === other.block.gap && this.dark === other.dark && this.documentURL === other.documentURL && this.block.html === other.block.html && this.block.from === other.block.from && this.block.to === other.block.to; }
  toDOM(editor) {
    const wrapper = document.createElement('div');
    wrapper.className = 'rendered-block';
    wrapper.style.setProperty('--block-gap', this.block.gap);
    wrapper.dataset.from = this.block.from;
    wrapper.dataset.to = this.block.to;
    wrapper.append(sanitizedHTML(this.block.html));
    wrapper.addEventListener('mousedown', event => {
      if (event.target.closest('a, input, button')) return;
      event.preventDefault();
      // Reveal the source block in place, with a real CodeMirror selection and history.
      editor.dispatch({ selection: { anchor: this.block.from } });
      editor.focus();
    });
    wrapper.addEventListener('click', event => {
      const checkbox = event.target.closest('input[data-task-line]');
      if (checkbox) {
        const edit = taskEdit(editor.state.doc.toString(), Number(checkbox.dataset.taskLine));
        if (edit) editor.dispatch({ changes: edit, userEvent: 'input' });
        return;
      }
      const copy = event.target.closest('[data-copy-code]');
      if (copy) {
        send('copy', { text: copy.closest('.code-block').querySelector('code').textContent });
        copy.textContent = '已复制';
        setTimeout(() => { if (copy.isConnected) copy.textContent = '复制'; }, 1500);
        return;
      }
      const link = event.target.closest('a');
      if (link) {
        event.preventDefault();
        const href = link.getAttribute('href');
        if (href?.startsWith('#')) {
          const id = decodeURIComponent(href.slice(1));
          const heading = parsed.headings.find(h => h.id === id || h.title === id);
          if (heading) jump(heading.from);
          else document.getElementById(id)?.scrollIntoView({ block: 'center' });
        } else if (href) send('link', { href });
      }
    });
    for (const diagram of wrapper.querySelectorAll('[data-mermaid]')) renderDiagram(diagram, editor);
    wrapper.querySelectorAll('img').forEach(img => {
      img.addEventListener('load', () => editor.requestMeasure());
      img.addEventListener('error', () => { img.alt = `图片无法加载：${img.alt || ''}`; editor.requestMeasure(); });
    });
    return wrapper;
  }
  ignoreEvent() { return true; }
}

async function renderDiagram(element, editor) {
  const code = element.querySelector('pre').textContent;
  const cacheKey = `${settings.dark}:${code}`;
  try {
    let svg = diagramCache.get(cacheKey);
    if (!svg) {
      const result = await mermaid.render(`diagram-${++diagramID}`, code);
      svg = result.svg;
      if (diagramCache.size > 40) diagramCache.delete(diagramCache.keys().next().value);
      diagramCache.set(cacheKey, svg);
    }
    if (element.isConnected) {
      element.innerHTML = DOMPurify.sanitize(svg, { USE_PROFILES: { svg: true, svgFilters: true } });
      editor.requestMeasure();
    }
  } catch (error) {
    element.dataset.error = String(error);
    if (element.isConnected) {
      const hint = document.createElement('div');
      hint.className = 'render-error';
      hint.textContent = '图表语法有误，点击此块修改源码';
      element.prepend(hint);
      editor.requestMeasure();
    }
  }
}

function decorations(state) {
  if (settings.sourceMode) return Decoration.none;
  const ranges = [];
  const blocks = sourceModel(state).blocks;
  for (const block of blocks) {
    const active = state.selection.ranges.some(r => r.from <= block.to && r.to >= block.from);
    if (!active) {
      ranges.push(Decoration.replace({ widget: new RenderedBlock(block), block: true }).range(block.from, block.to));
    } else {
      const level = block.type === 'heading_open' ? block.html.match(/<h([1-6])/)?.[1] : null;
      const code = ['fence', 'code_block'].includes(block.type);
      const first = state.doc.lineAt(block.from), last = state.doc.lineAt(block.to);
      ranges.push(Decoration.line({ attributes: {
        class: level ? `cm-live-heading cm-live-h${level}` : code ? 'cm-live-code' : 'cm-live-block',
        style: `padding-top:${block.gap}`
      } }).range(first.from));
      if (code) for (let line = first.number + 1; line <= last.number; line++) {
        ranges.push(Decoration.line({ class: 'cm-live-code' }).range(state.doc.line(line).from));
      }
    }
  }
  let blockIndex = 0;
  for (let number = 1; number <= state.doc.lines; number++) {
    const line = state.doc.line(number);
    while (blockIndex < blocks.length && blocks[blockIndex].to < line.from) blockIndex++;
    const insideBlock = blocks[blockIndex]?.from <= line.from;
    const selected = state.selection.ranges.some(r => r.from <= line.to && r.to >= line.from);
    if (!insideBlock && !selected && !line.text.trim()) {
      ranges.push(Decoration.line({ class: 'cm-collapsed-blank' }).range(line.from));
    }
  }
  return Decoration.set(ranges, true);
}
const livePreview = StateField.define({
  create: decorations,
  update(value, transaction) {
    return transaction.docChanged || transaction.selection || transaction.effects.some(e => e.is(refresh))
      ? decorations(transaction.state) : value;
  },
  provide: field => EditorView.decorations.from(field)
});

function jump(position) {
  const anchor = Math.min(Math.max(0, position), view.state.doc.length);
  view.dispatch({ selection: { anchor }, effects: EditorView.scrollIntoView(anchor, { y: 'center' }) });
  view.focus();
}
function wrap(marker) {
  const { from, to } = view.state.selection.main;
  view.dispatch({ changes: { from, to, insert: marker + view.state.sliceDoc(from, to) + marker },
    selection: { anchor: from + marker.length, head: to + marker.length }, userEvent: 'input' });
  view.focus();
}

function format(action) {
  const { from, to } = view.state.selection.main;
  const edit = formatEdit(view.state.doc.toString(), from, to, action);
  if (!edit) return false;
  const { anchor, head, ...changes } = edit;
  view.dispatch({ changes, selection: { anchor, head }, userEvent: 'input' });
  view.focus();
  return true;
}
function shortcutBindings() {
  return keymap.of(Object.entries(settings.shortcuts || {}).map(([action, key]) => ({key, run: () => format(action)})).concat(
    settings.controlHeadings === false ? [] : Array.from({length:7}, (_,i) => ({key:`Ctrl-${i}`, run:()=>format(`heading${i}`)}))));
}

window.localMarkdown = {
  update(payload) {
    const previous = settings;
    settings = { ...settings, ...payload };
    document.documentElement.classList.toggle('dark', settings.dark);
    document.documentElement.classList.toggle('source-mode', settings.sourceMode);
    document.documentElement.classList.toggle('standard-width', settings.editorWidth === 800);
    document.documentElement.style.setProperty('--editor-size', `${settings.fontSize}px`);
    document.documentElement.style.setProperty('--editor-width', `${settings.editorWidth}px`);
    if (previous.dark !== settings.dark) {
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: settings.dark ? 'dark' : 'default', suppressErrorRendering: true, flowchart: { htmlLabels: false } });
    }
    if (!initialized) {
      initialized = true;
      view = new EditorView({
        parent: document.getElementById('editor'),
        state: EditorState.create({ doc: payload.text || '', extensions: (editorExtensions = [
          EditorState.lineSeparator.of((payload.text || '').includes('\r\n') ? '\r\n' : '\n'), history(), drawSelection(), EditorView.lineWrapping,
          markdown({ codeLanguages: languages }), syntaxHighlighting(defaultHighlightStyle),
          formattingKeys.of(shortcutBindings()),
          keymap.of([
            ...markdownKeymap, ...historyKeymap, ...searchKeymap, ...defaultKeymap, indentWithTab
          ]),
          search({ top: true }), placeholder('从一个想法开始…'),
          EditorView.exceptionSink.of(error => send('error', { message: String(error?.stack || error) })),
          EditorView.contentAttributes.of({ 'aria-label': 'Markdown 正文', spellcheck: 'false' }),
          theme.of(EditorView.theme({}, { dark: settings.dark })),
          livePreview,
          EditorView.updateListener.of(update => {
            if (update.docChanged) {
              const external = update.transactions.some(t => t.effects.some(e => e.is(externalChange)));
              if (!external) send('change', { text: update.state.sliceDoc() });
              send('outline', { headings: sourceModel(update.state).headings });
            }
          })
        ]) })
      });
      send('outline', { headings: sourceModel(view.state).headings });
    } else {
      const effects = [refresh.of(null), formattingKeys.reconfigure(shortcutBindings())];
      if (previous.dark !== settings.dark) effects.push(theme.reconfigure(EditorView.theme({}, { dark: settings.dark })));
      if (typeof payload.text === 'string' && payload.text !== view.state.sliceDoc()) {
        effects.push(externalChange.of(null));
        // External replacements (revert/open) must not undo into a different document version.
        editorExtensions[0] = EditorState.lineSeparator.of(payload.text.includes('\r\n') ? '\r\n' : '\n');
        view.setState(EditorState.create({ doc: payload.text, extensions: editorExtensions }));
        send('outline', { headings: sourceModel(view.state).headings });
      }
      view.dispatch({ effects });
    }
  },
  command(name, argument) {
    if (!view) return;
    if (name === 'format') format(argument);
    if (name === 'find') openSearchPanel(view);
    if (name === 'wrap') wrap(argument);
    if (name === 'jump') jump(argument);
    if (name === 'undo') undo(view);
    if (name === 'redo') redo(view);
    if (name === 'focus') view.focus();
  },
  // Read-only diagnostics for integration checks; document edits still use editor transactions.
  inspect() { return { text: view?.state.sliceDoc(), selection: view?.state.selection.main,
    blocks: parsed?.blocks.length, headings: parsed?.headings,
    rendered: document.querySelectorAll('.rendered-block').length,
    tables: document.querySelectorAll('table').length, math: document.querySelectorAll('.katex').length,
    diagrams: document.querySelectorAll('.diagram svg').length }; }
};
window.addEventListener('error', event => send('error', { message: event.message }));
window.addEventListener('unhandledrejection', event => send('error', { message: String(event.reason) }));
send('ready');
