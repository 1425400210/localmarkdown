// Typora's public GitHub theme: https://github.com/typora/typora-default-themes
// Adjacent block margins collapse to their maximum in a normal document. CodeMirror
// widgets isolate blocks, so we apply that gap once and collapse source-only blank lines.
export function blockSpacing(blocks) {
  let previousBottom = '0px';
  return blocks.map((block, index) => {
    let before = '.8rem', after = '.8rem';
    if (block.type === 'heading_open') before = after = '1rem';
    if (block.type === 'fence' || block.type === 'code_block') before = after = '15px';
    if (block.type === 'hr') before = after = '16px';
    if (block.type === 'frontmatter') before = '0px';
    if (index === 0 && ['bullet_list_open', 'ordered_list_open'].includes(block.type)) before = '30px';
    const gap = `max(${previousBottom}, ${before})`;
    previousBottom = after;
    return { ...block, gap };
  });
}
