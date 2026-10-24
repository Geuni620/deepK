// page.mjs의 재현 페이지를 헤드리스 Chrome에서 ⌘C로 복사해 text/plain과 원본 text/html을
// DeepKTests/Fixtures/CodeCopy/<name>.txt, .html로 저장한다. 헤드리스 Chrome은 메모리 클립보드를 쓰므로
// 일반 클립보드에 쓰지 않는다. macOS Chrome처럼 HTML 앞에 <meta charset='utf-8'>를 붙인다.
// 실제 사이트 복사는 scripts/dump-pasteboard.swift로 따로 받아 scripts/inspect-copied-source.sh로 보고, 커밋하지 않는다.
//
// 준비: npm install --prefix /private/tmp/deepk-code-copy playwright-core@1.64.0
// 실행: node scripts/code-copy/capture.mjs [node_modules 경로] [출력 폴더]
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pages } from './page.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const modules = path.resolve(process.argv[2] ?? '/private/tmp/deepk-code-copy/node_modules');
const output = path.resolve(process.argv[3] ?? `${root}/DeepKTests/Fixtures/CodeCopy`);
const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const { chromium } = await import(`${modules}/playwright-core/index.mjs`);

const html = pages();
const server = http.createServer((request, response) => {
  const name = decodeURIComponent(new URL(request.url, 'http://localhost').pathname).slice(1).replace(/\.html$/, '');
  if (!html[name]) {
    response.statusCode = 404;
    return response.end();
  }
  response.setHeader('content-type', 'text/html; charset=utf-8');
  response.end(html[name]);
}).listen(0);
await new Promise((resolve) => server.on('listening', resolve));
const origin = `http://localhost:${server.address().port}`;

const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'deepk-code-copy-'));
const context = await chromium.launchPersistentContext(profile, { executablePath: chrome, headless: true, viewport: { width: 1000, height: 900 } });
await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin });
console.log('Chrome', context.browser()?.version() ?? '(persistent context)');

// [파일 이름, 페이지, 선택 시작 요소, 선택 끝 요소, 복사 버튼을 누른 뒤인지]. 시작 요소 앞부터 끝 요소의 글 끝까지
// 고른다(끌어서 고를 때처럼 마지막 문단 뒤 줄바꿈은 들어가지 않는다).
// impeccable 세 선택은 위젯의 버튼 글자가 정렬 허용치를 넘기던 크기다(전체, 위젯과 문단 둘, 위젯과 문단 하나).
const cases = [
  ['impeccable-full', 'impeccable', 'p-intro', 'p-refresh', false],
  ['impeccable-two', 'impeccable', 'p-ask', 'p-refresh', false],
  ['impeccable-one', 'impeccable', 'widget', 'p-scan', false],
  ['impeccable-copied', 'impeccable', 'p-ask', 'p-refresh', true],
  ['github-readme', 'github', null, null, false],
  ['mdn', 'mdn', null, null, false],
  ['docusaurus-tabs', 'docusaurus', null, null, false],
  ['sphinx-linenos', 'sphinx', null, null, false],
];
fs.mkdirSync(output, { recursive: true });
for (const [file, name, first, last, copied] of cases) {
  const tab = await context.newPage();
  await tab.goto(`${origin}/${name}.html`);
  await tab.evaluate(() => document.fonts.ready);
  await tab.evaluate(async () => navigator.clipboard.writeText(''));
  await tab.evaluate(([first, last, copied]) => {
    if (copied) {
      // 위젯의 복사 버튼을 누른 뒤: 숨은 라벨과 상태 글이 바뀐다.
      document.querySelector('.site-code-copy').classList.add('is-copied');
      document.querySelector('.site-code-copy-label').textContent = 'Copied';
      document.querySelector('.site-code-status').textContent = 'Copied to clipboard.';
    }
    const range = document.createRange();
    if (first) {
      range.setStartBefore(document.getElementById(first));
      const end = document.getElementById(last);
      range.setEnd(end, end.childNodes.length);
    } else {
      range.selectNodeContents(document.getElementById('all'));
    }
    getSelection().removeAllRanges();
    getSelection().addRange(range);
  }, [first, last, copied]);
  await tab.keyboard.press('Meta+KeyC');
  const result = await tab.evaluate(async () => {
    const out = { plain: null, html: null };
    for (const item of await navigator.clipboard.read({ unsanitized: ['text/html'] })) {
      if (item.types.includes('text/plain')) out.plain = await (await item.getType('text/plain')).text();
      if (item.types.includes('text/html')) out.html = await (await item.getType('text/html')).text();
    }
    return out;
  });
  if (result.plain == null || result.html == null) throw new Error(`${file}: clipboard is missing text/plain or text/html`);
  fs.writeFileSync(`${output}/${file}.txt`, result.plain);
  fs.writeFileSync(`${output}/${file}.html`, `<meta charset='utf-8'>${result.html}`);
  console.log(file, result.plain.length, 'characters,', result.html.length, 'HTML characters');
  await tab.close();
}
await context.close();
server.close();
fs.rmSync(profile, { recursive: true, force: true });
