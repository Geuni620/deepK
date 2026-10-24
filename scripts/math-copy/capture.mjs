// page.mjs의 페이지를 헤드리스 Chrome에서 ⌘C로 복사해 text/plain과 원본 text/html을
// DeepKTests/Fixtures/MathCopy/<name>.txt, .html로 저장한다. 헤드리스 Chrome은 메모리 클립보드를 쓰므로
// 일반 클립보드에 쓰지 않는다. macOS Chrome처럼 HTML 앞에 <meta charset='utf-8'>를 붙인다.
//
// 준비: npm install --prefix /private/tmp/deepk-math-copy katex@0.16.25 mathjax-full@3.2.1 playwright-core@1.64.0
// 실행: node scripts/math-copy/capture.mjs [node_modules 경로] [출력 폴더]
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pages } from './page.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const modules = path.resolve(process.argv[2] ?? '/private/tmp/deepk-math-copy/node_modules');
const output = path.resolve(process.argv[3] ?? `${root}/DeepKTests/Fixtures/MathCopy`);
const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const { chromium } = await import(`${modules}/playwright-core/index.mjs`);

const html = await pages(modules);
const types = { '.css': 'text/css', '.js': 'text/javascript', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf' };
const server = http.createServer((request, response) => {
  const url = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  const name = url.slice(1).replace(/\.html$/, '');
  if (html[name]) {
    response.setHeader('content-type', 'text/html; charset=utf-8');
    return response.end(html[name]);
  }
  const file = path.join(modules, url.replace(/^\/modules\//, ''));
  if (!url.startsWith('/modules/') || !file.startsWith(modules) || !fs.existsSync(file)) {
    response.statusCode = 404;
    return response.end();
  }
  response.setHeader('content-type', types[path.extname(file)] ?? 'application/octet-stream');
  fs.createReadStream(file).pipe(response);
}).listen(0);
await new Promise((resolve) => server.on('listening', resolve));
const origin = `http://localhost:${server.address().port}`;

const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'deepk-math-copy-'));
const context = await chromium.launchPersistentContext(profile, { executablePath: chrome, headless: true, viewport: { width: 1000, height: 900 } });
await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin });
console.log('Chrome', context.browser()?.version() ?? '(persistent context)');

// [파일 이름, 페이지, 선택 범위]. partial은 첫 수식의 화면 글자 중간에서 시작해 문단 끝까지 고른다.
// cut은 숨은 MathML의 "+" 토큰에서 시작해 문단 끝까지 고른다(Shift+←로 수식 안까지 넓힌 선택).
const cases = [
  ['katex-article', 'katex', 'all'],
  ['katex-partial', 'katex', 'partial'],
  ['katex-code', 'edges', 'e-code'],
  ['katex-breaks', 'edges', 'e-breaks'],
  ['katex-accents', 'edges', 'e-accents'],
  ['katex-cut', 'edges', 'cut'],
  ['katex-linear', 'edges', 'e-linear'],
  ['copytex-article', 'copytex', 'all'],
  ['mathml-article', 'mathml', 'all'],
  ['mathjax3-article', 'mathjax3', 'all'],
  ['control', 'control', 'all'],
];
fs.mkdirSync(output, { recursive: true });
for (const [file, name, selection] of cases) {
  const tab = await context.newPage();
  await tab.goto(`${origin}/${name}.html`);
  if (name === 'mathjax3') await tab.waitForFunction(() => window.MathJax?.startup?.promise).then(() => tab.evaluate(() => MathJax.startup.promise));
  await tab.evaluate(() => document.fonts.ready);
  await tab.evaluate(async () => navigator.clipboard.writeText(''));
  await tab.evaluate((selection) => {
    const range = document.createRange();
    if (selection === 'partial') {
      const paragraph = document.getElementById('p-units');
      const glyphs = paragraph.querySelector('.katex-html');
      const walker = document.createTreeWalker(glyphs, NodeFilter.SHOW_TEXT);
      walker.nextNode();
      walker.nextNode();
      range.setStart(walker.currentNode, 0);
      range.setEndAfter(paragraph.lastChild);
    } else if (selection === 'cut') {
      const paragraph = document.getElementById('e-cut');
      const walker = document.createTreeWalker(paragraph.querySelector('.katex-mathml'), NodeFilter.SHOW_TEXT);
      walker.nextNode();
      walker.nextNode();
      range.setStart(walker.currentNode, 0);
      range.setEndAfter(paragraph.lastChild);
    } else {
      range.selectNodeContents(document.getElementById(selection));
    }
    getSelection().removeAllRanges();
    getSelection().addRange(range);
  }, selection);
  await tab.keyboard.press('Meta+KeyC');
  const copied = await tab.evaluate(async () => {
    const out = { plain: null, html: null };
    for (const item of await navigator.clipboard.read({ unsanitized: ['text/html'] })) {
      if (item.types.includes('text/plain')) out.plain = await (await item.getType('text/plain')).text();
      if (item.types.includes('text/html')) out.html = await (await item.getType('text/html')).text();
    }
    return out;
  });
  if (copied.plain == null || copied.html == null) throw new Error(`${file}: clipboard is missing text/plain or text/html`);
  fs.writeFileSync(`${output}/${file}.txt`, copied.plain);
  fs.writeFileSync(`${output}/${file}.html`, `<meta charset='utf-8'>${copied.html}`);
  console.log(file, copied.plain.length, 'characters,', copied.html.length, 'HTML characters');
  await tab.close();
}
await context.close();
server.close();
fs.rmSync(profile, { recursive: true, force: true });
