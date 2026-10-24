// RichSourceImporter 코드 복사 픽스처용 페이지. impeccable 문서의 명령 위젯, GitHub README, MDN, Docusaurus 탭,
// Sphinx 줄 번호 표를 DOM 구조와 숨김·선택 불가 스타일만 따라 직접 쓴 재현본이다. 글과 아이콘도 직접 쓴 것이다.
// capture.mjs가 불러 쓴다.

const icon = (className = '') =>
  `<svg aria-hidden="true" width="16" height="16" viewBox="0 0 16 16"${className ? ` class="${className}"` : ''}><path d="M3 3h7v7H3z M6 6h7v7H6z"></path></svg>`;

const impeccable = String.raw`<article id="all">
<p id="p-intro">Before you ask for new screens, tell Impeccable about the design you already ship. The running app, its components and its stylesheets all count as evidence of the current system.</p>
<h2 id="h-start">Start from what exists</h2>
<p id="p-ask">Ask Impeccable to write down the design you have:</p>
<div id="widget" class="site-code-block code-block-wrap is-command has-tool-selector docs-command-block" data-code-variant="standard"><div class="site-code-header"><div class="site-code-tools" role="group" aria-label="Coding tool" data-command-syntax-controls=""><button class="site-code-tab is-active" type="button" data-syntax="slash" aria-pressed="true" title="Claude Code, Cursor, Gemini CLI, and other agents">Most Agents</button><button class="site-code-tab" type="button" data-syntax="codex" aria-pressed="false" title="Codex">Codex</button></div><button class="site-code-copy" type="button" aria-label="Copy command">${icon('site-code-copy-icon')}${icon('site-code-check-icon')}<span class="site-code-copy-label" aria-hidden="true">Copy</span></button></div><span class="site-code-prompt" aria-hidden="true">›</span><pre class="astro-code impeccable-paper site-code-content" data-site-code-ready="true" tabindex="0" data-language="text"><code><span class="line"><span><span class="site-code-invocation">/impeccable</span> document</span></span></code></pre></div><span class="site-code-status" role="status" aria-live="polite"></span>
<p id="p-scan">It scans the code and writes the colors, type scale, spacing rules and components it finds to <code>DESIGN.md</code>, and keeps extra generated details in <code>.impeccable/design.json</code>. Read the record and fix anything that captures an accident instead of a decision.</p>
<p id="p-refresh">When <code>DESIGN.md</code> is already there, ask for a refresh after the code changes. Product goals, audience and constraints live in <code>PRODUCT.md</code>, which <a href="https://impeccable.style/docs/init">init</a> creates. <a href="https://impeccable.style/docs/context">Context files</a> describes what each record holds.</p>
</article>`;

const impeccableStyle = `
.site-code-block { display: grid; grid-template-columns: min-content minmax(0, 1fr); align-items: center; gap: 0 14px; margin: 24px 0; border: 1px solid #e2ded6; border-radius: 10px; }
.site-code-header { grid-column: 1 / -1; display: flex; align-items: center; justify-content: space-between; padding: 6px 8px; }
.site-code-tools { display: flex; gap: 4px; }
.site-code-tab { font-size: 12px; padding: 4px 10px; border: 0; border-radius: 6px; background: none; }
.site-code-copy { display: inline-grid; position: relative; place-items: center; padding: 4px; border: 0; background: none; }
.site-code-copy-label, .site-code-status { position: absolute; width: 1px; height: 1px; overflow: hidden; white-space: nowrap; clip-path: inset(50%); }
.site-code-prompt { user-select: none; color: #8c8578; font-family: "JetBrains Mono", monospace; margin-left: 16px; }
.site-code-content { grid-column: 2; margin: 14px 16px 16px 0; white-space: pre-wrap; background: #eee; font-family: "JetBrains Mono", ui-monospace, SFMono-Regular, monospace; }
.site-code-invocation { color: #a67c2a; }
p code { font-family: "JetBrains Mono", ui-monospace, SFMono-Regular, monospace; font-size: 0.92em; background: #f0eee9; border-radius: 4px; padding: 1px 5px; }`;

const github = String.raw`<article id="all">
<h2 class="heading-element" dir="auto">Install</h2>
<p dir="auto">Add the package with <code class="notranslate">npm</code>, then import it:</p>
<div class="highlight highlight-source-shell notranslate position-relative overflow-auto" dir="auto"><pre><span class="pl-c1">npm</span> install left-pad</pre><div class="zeroclipboard-container"><clipboard-copy aria-label="Copy" class="ClipboardButton btn btn-invisible js-clipboard-copy m-2 p-0 d-flex" data-copy-feedback="Copied!" value="npm install left-pad" tabindex="0" role="button">${icon()}${icon('d-none')}</clipboard-copy></div></div><div class="highlight highlight-source-js notranslate position-relative overflow-auto" dir="auto"><pre><span class="pl-k">import</span> <span class="pl-s1">leftPad</span> <span class="pl-k">from</span> <span class="pl-s">'left-pad'</span><span class="pl-kos">;</span>
<span class="pl-en">leftPad</span><span class="pl-kos">(</span><span class="pl-s">'7'</span><span class="pl-kos">,</span> <span class="pl-c1">3</span><span class="pl-kos">,</span> <span class="pl-s">'0'</span><span class="pl-kos">)</span><span class="pl-kos">;</span> <span class="pl-c">// =&gt; '007'</span></pre><div class="zeroclipboard-container"><clipboard-copy aria-label="Copy" class="ClipboardButton btn btn-invisible js-clipboard-copy m-2 p-0 d-flex" data-copy-feedback="Copied!" value="import leftPad from 'left-pad';" tabindex="0" role="button">${icon()}${icon('d-none')}</clipboard-copy></div></div>
<p dir="auto">See the <a href="https://github.com/left-pad/left-pad/blob/main/API.md">API reference</a> for every option.</p>
</article>`;

const githubStyle = `
.highlight { position: relative; margin-bottom: 16px; }
.highlight pre { margin: 0; padding: 16px; background: #f6f8fa; white-space: pre; font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace; font-size: 13.6px; }
.zeroclipboard-container { position: absolute; top: 0; right: 0; display: flex; }
.d-flex { display: flex; }
.d-none { display: none; }
p code { font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace; font-size: 13.6px; }`;

const mdn = String.raw`<article id="all">
<p>Use <a href="https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/map"><code>Array.prototype.map()</code></a> to build a new array:</p>
<div class="code-example"><div class="example-header"><span class="language-name">js</span><button type="button" class="icon copy-icon"><span class="visually-hidden">Copy to Clipboard</span></button></div><pre class="brush: js notranslate"><code><span class="token keyword">const</span> doubled <span class="token operator">=</span> numbers<span class="token punctuation">.</span><span class="token function">map</span><span class="token punctuation">(</span><span class="token parameter">n</span> <span class="token operator">=&gt;</span> n <span class="token operator">*</span> <span class="token number">2</span><span class="token punctuation">)</span><span class="token punctuation">;</span></code></pre></div>
<p>The callback runs once for each element. Use <code>forEach()</code> when you need no new array.</p>
</article>`;

const mdnStyle = `
.example-header { display: flex; justify-content: space-between; }
.language-name { font-size: 13px; }
.copy-icon { display: inline-flex; border: 0; background: none; }
.visually-hidden { border: 0; clip: rect(0 0 0 0); height: 1px; margin: -1px; overflow: hidden; padding: 0; position: absolute; white-space: nowrap; width: 1px; }
pre, code { font-family: Menlo, Consolas, monospace; }
pre { white-space: pre; }`;

const panel = (command, hidden) => `<div role="tabpanel" class="tabItem_Ymn6"${hidden ? ' hidden=""' : ''}><div class="language-bash codeBlockContainer_Ckt0 theme-code-block"><div class="codeBlockContent_biex"><pre tabindex="0" class="prism-code language-bash codeBlock_bY9V thin-scrollbar"><code class="codeBlockLines_e6Vv"><span class="token-line"><span class="token plain">${command}</span><br></span></code></pre><div class="buttonGroup__atx"><button type="button" aria-label="Copy code to clipboard" title="Copy" class="clean-btn"><span class="copyButtonIcons_eSgA" aria-hidden="true">${icon()}</span></button></div></div></div></div>`;

const docusaurus = String.raw`<article id="all">
<p>Install the package:</p>
<div class="tabs-container tabList__CuJ"><ul role="tablist" aria-orientation="horizontal" class="tabs"><li role="tab" tabindex="0" aria-selected="true" class="tabs__item tabItem_LNqP tabs__item--active">npm</li><li role="tab" tabindex="-1" aria-selected="false" class="tabs__item tabItem_LNqP">Yarn</li><li role="tab" tabindex="-1" aria-selected="false" class="tabs__item tabItem_LNqP">pnpm</li></ul><div class="margin-top--md">${panel('npm install @docusaurus/core', false)}${panel('yarn add @docusaurus/core', true)}${panel('pnpm add @docusaurus/core', true)}</div></div>
<p>Then restart the dev server with <code>npm run start</code>.</p>
</article>`;

const docusaurusStyle = `
.tabs { display: flex; list-style: none; padding: 0; margin: 0; }
.tabs__item { padding: 4px 12px; }
.codeBlockContent_biex { position: relative; }
.prism-code { margin: 0; padding: 16px; white-space: pre; background: #f6f8fa; font-family: SFMono-Regular, Menlo, monospace; }
.token-line { display: block; }
.buttonGroup__atx { position: absolute; top: 8px; right: 8px; display: flex; }
.clean-btn { border: 0; background: none; }`;

const sphinx = String.raw`<article id="all">
<p>The script prints where it runs:</p>
<div class="highlight-python notranslate"><table class="highlighttable"><tbody><tr><td class="linenos"><div class="linenodiv"><pre><span class="normal">1</span>
<span class="normal">2</span>
<span class="normal">3</span></pre></div></td><td class="code"><div class="highlight"><pre><span></span><span class="kn">import</span> <span class="nn">os</span>
<span class="c1"># Print the working directory</span>
<span class="nb">print</span><span class="p">(</span><span class="n">os</span><span class="o">.</span><span class="n">getcwd</span><span class="p">())</span>
</pre></div></td></tr></tbody></table></div>
<p>See <a class="reference external" href="https://docs.python.org/3/library/os.html#os.getcwd"><code class="xref py py-func docutils literal notranslate"><span class="pre">os.getcwd()</span></code></a> in the library reference.</p>
</article>`;

const sphinxStyle = `
.highlighttable { border-collapse: collapse; }
.highlighttable td { padding: 0 8px 0 0; vertical-align: top; }
.highlighttable pre { margin: 0; font-family: SFMono-Regular, Menlo, monospace; }
.linenos { color: #999; }`;

function page(title, style, content) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>${title}</title>
<style>body{font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:760px;margin:24px auto;line-height:1.6;font-size:16px;color:#1a1a1a}${style}</style>
</head><body>
${content}
</body></html>
`;
}

/** Returns { name: html } for every fixture page. */
export function pages() {
  return {
    impeccable: page('Impeccable replica', impeccableStyle, impeccable),
    github: page('GitHub README replica', githubStyle, github),
    mdn: page('MDN replica', mdnStyle, mdn),
    docusaurus: page('Docusaurus tabs replica', docusaurusStyle, docusaurus),
    sphinx: page('Sphinx line numbers replica', sphinxStyle, sphinx),
  };
}
