import test from 'node:test';
import assert from 'node:assert/strict';
import {formatEdit} from '../src/formatting.js';
const apply = (text,from,to,action) => { const e=formatEdit(text,from,to,action); assert.ok(e); const value=text.slice(0,e.from)+e.insert+text.slice(e.to); assert.ok(e.anchor>=0 && e.head<=value.length); return value; };
test('headings replace levels, support empty lines and return to body',()=>{
 assert.equal(apply('文字😀',4,4,'heading1'),'# 文字😀');
 assert.equal(apply('## 标题',5,5,'heading3'),'### 标题');
 assert.equal(apply('### 标题',6,6,'heading0'),'标题');
 assert.equal(apply('',0,0,'heading2'),'## ');
 assert.equal(apply('\ntext',0,0,'heading1'),'# \ntext');
});
test('selected lines transform without touching next line',()=>{
 assert.equal(apply('甲\n乙\n丙',0,4,'heading2'),'## 甲\n## 乙\n丙');
 assert.equal(apply('- 甲\n- 乙',0,7,'ordered'),'1. 甲\n2. 乙');
 assert.equal(apply('甲\n乙',0,3,'task'),'- [ ] 甲\n- [ ] 乙');
});
test('inline styles toggle both selected and surrounding delimiters',()=>{
 assert.equal(apply('文字',0,2,'bold'),'**文字**');
 assert.equal(apply('**文字**',2,4,'bold'),'文字');
 assert.equal(apply('**文字**',0,6,'bold'),'文字');
 for(const [action,mark] of [['italic','*'],['strike','~~'],['highlight','==']]) assert.equal(apply('甲',0,1,action),mark+'甲'+mark);
});
test('code fences safely contain existing backticks',()=>{
 assert.equal(apply('a`b',0,3,'inlineCode'),'``a`b``');
 assert.equal(apply('```',0,3,'codeBlock'),'````\n```\n````\n');
});
test('links and images select the URL placeholder',()=>{
 for(const action of ['link','image']) {
  const e=formatEdit('名称',0,2,action);
  assert.equal(e.insert.slice(e.anchor,e.head),'https://');
  assert.equal(e.insert,`${action==='image'?'!':''}[名称](https://)`);
 }
});
test('block insertion adds separating newlines',()=>{
 assert.equal(apply('前后',1,1,'rule'),'前\n\n---\n\n后');
 assert.match(apply('',0,0,'table'),/\| --- \| --- \|/);
 assert.equal(apply('引用',0,2,'quote'),'> 引用');
 assert.equal(apply('x^2',0,3,'mathBlock'),'$$\nx^2\n$$\n');
 assert.equal(apply('字',0,1,'underline'),'<u>字</u>');
});
