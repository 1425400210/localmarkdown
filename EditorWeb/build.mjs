import { build } from 'esbuild';
import { mkdir, writeFile, readFile, readdir } from 'node:fs/promises';
const out = '../Sources/LocalMarkdown/Resources/Editor';
await mkdir(out, { recursive: true });
await build({ entryPoints: ['src/editor.js'], bundle: true, outfile: `${out}/editor.js`,
  format: 'iife', target: 'safari17', minify: true, legalComments: 'external',
  loader: { '.woff2': 'file', '.woff': 'file', '.ttf': 'file' }, assetNames: 'fonts/[name]-[hash]' });
await writeFile(`${out}/index.html`, `<!doctype html>
<html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' local-md: https: http: data:; font-src 'self' data:; connect-src 'none'; object-src 'none'; base-uri 'none'">
<link rel="stylesheet" href="editor.css"></head><body><main id="editor"></main><script src="editor.js"></script></body></html>`);
// Keep license notices with the shipped offline dependencies.
const lock = JSON.parse(await readFile('package-lock.json', 'utf8'));
let notices = '# Bundled dependency notices\n';
for (const [path, info] of Object.entries(lock.packages)) {
  if (!path || info.dev) continue;
  notices += `\n## ${path.replace('node_modules/', '')} ${info.version} (${info.license || 'see package'})\n`;
  const files = await readdir(path).catch(() => []);
  for (const file of files.filter(f => /^(licen[cs]e|copying)(\.|$)/i.test(f))) {
    notices += '\n' + await readFile(`${path}/${file}`, 'utf8').catch(() => '') + '\n';
  }
}
notices += '\n## Open Sans fonts\nDigitized data copyright © 2010-2011, Google Corporation.\n' + await readFile('src/fonts/LICENSE.txt', 'utf8');
await writeFile(`${out}/THIRD-PARTY-NOTICES.txt`, notices);
