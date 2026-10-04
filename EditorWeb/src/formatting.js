// All positions use JavaScript/CodeMirror UTF-16 offsets. The editor owns undo history.
export function formatEdit(text, from, to, action) {
  const selected = text.slice(from, to);
  const inline = { underline: ['<u>','</u>'], bold: ['**','**'], italic: ['*','*'], strike: ['~~','~~'], highlight: ['==','=='], inlineCode: ['`','`'] };
  if (inline[action]) {
    let [left, right] = inline[action];
    if (action === 'inlineCode' && selected.includes('`')) {
      left = right = '`'.repeat(Math.max(...(selected.match(/`+/g) || []).map(s => s.length)) + 1);
    }
    if (selected.startsWith(left) && selected.endsWith(right) && selected.length >= left.length + right.length) {
      const insert = selected.slice(left.length, -right.length);
      return { from, to, insert, anchor: from, head: from + insert.length };
    }
    if (text.slice(Math.max(0, from-left.length), from) === left && text.slice(to,to+right.length) === right) {
      return { from: from-left.length, to: to+right.length, insert: selected, anchor: from-left.length, head: to-left.length };
    }
    return { from, to, insert: left+selected+right, anchor: from+left.length, head: to+left.length };
  }
  if (/^heading[0-6]$/.test(action) || ['quote','unordered','ordered','task'].includes(action)) {
    const start = from === 0 ? 0 : text.lastIndexOf('\n', from-1)+1;
    let end = text.indexOf('\n', to > from && text[to-1] === '\n' ? to-1 : to);
    if (end < 0) end = text.length;
    const lines = text.slice(start,end).split('\n');
    const level = action.startsWith('heading') ? Number(action.slice(-1)) : null;
    const prefix = level !== null ? '#'.repeat(level)+(level ? ' ' : '') : {quote:'> ',unordered:'- ',ordered:'1. ',task:'- [ ] '}[action];
    const pattern = level !== null ? /^( {0,3})#{1,6}\s+/ : /^(\s*)(?:>\s?|[-+*]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)/;
    const insert = lines.map((line,index) => {
      const clean = line.replace(pattern,'$1');
      return (action === 'ordered' ? `${index+1}. ` : prefix)+clean;
    }).join('\n');
    const delta = insert.length-(end-start);
    return { from:start,to:end,insert,anchor:from===to ? Math.max(start,from+delta) : start,head:from===to ? Math.max(start,to+delta) : start+insert.length };
  }
  if (action === 'link' || action === 'image') {
    const label = selected || (action === 'link' ? '链接文字' : '图片说明');
    const left = action === 'image' ? '![' : '[';
    const insert = `${left}${label}](https://)`;
    const anchor = from+left.length+label.length+2;
    return {from,to,insert,anchor,head:anchor+8};
  }
  const blocks = {mathBlock:'$$\n'+selected+'\n$$',rule:'---',table:'| 列 1 | 列 2 |\n| --- | --- |\n| 内容 | 内容 |'};
  if (action === 'codeBlock') {
    const fence = '`'.repeat(Math.max(3,...(selected.match(/`+/g)||[]).map(s=>s.length+1)));
    blocks.codeBlock = fence+'\n'+selected+'\n'+fence;
  }
  if (blocks[action]) {
    const before = from && text[from-1] !== '\n' ? '\n\n' : from && text[from-2] !== '\n' ? '\n' : '';
    const after = to < text.length && text[to] !== '\n' ? '\n\n' : '\n';
    const insert = before+blocks[action]+after;
    const anchor = from+before.length+(action === 'codeBlock' ? blocks[action].indexOf('\n')+1 : 0);
    return {from,to,insert,anchor,head:action==='codeBlock' ? anchor+selected.length : anchor+blocks[action].length};
  }
  return null;
}
