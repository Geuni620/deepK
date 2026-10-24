// CopiedMathNormalizer 픽스처용 페이지. 같은 글을 렌더러별로 만든다. 글은 직접 쓴 것이다.
// $…$는 인라인, $$…$$는 디스플레이 수식이다. capture.mjs가 불러 쓴다.

const article = [
  ['h2', 'h-scale', String.raw`1. Recipes Scale by $\times k$, Pans by $k^2$`],
  ['p', 'p-units', String.raw`A loaf needs $500\,\mathrm{g}$ of flour and $10\,\mathrm{g}$ of salt. To bake for a crowd you multiply every line by the same factor ($k$), so $k = 3$ gives $1500\,\mathrm{g}$ and $30\,\mathrm{g}$.`],
  ['p', 'p-ratio', String.raw`Bakers keep the dough ratio $\frac{w}{f}$ fixed, where $w$ is water and $f$ is flour. A ratio of $\frac{13}{20}$ is a soft dough; anything above $\frac{4}{5}$ is closer to batter.`],
  ['p', 'p-area', String.raw`A round pan of radius $r$ holds $\pi r^2$ of batter per centimetre of depth, so a pan twice as wide needs four times the dough. Its diameter is $d = 2\sqrt{A/\pi}$, and going the other way, the radius for a target area $A$ is`],
  ['div', 'd-root', String.raw`$$r = \sqrt{\frac{A}{\pi}}$$`],
  ['p', 'p-sum', String.raw`With several pans $p_1, \dots, p_n$ the total area is $\sum_{i=1}^{n} \pi r_i^2$, and the scale factor is that sum divided by the area of the original pan:`],
  ['div', 'd-sum', String.raw`$$k = \frac{1}{A_0} \sum_{i=1}^{n} \pi r_i^2$$`],
  ['p', 'p-count', String.raw`If batch $i$ uses $i$ cups, the first $n$ batches use $\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$ cups in total.`],
  ['p', 'p-matrix', String.raw`Two flours can be tracked per batch as a grid $\begin{pmatrix} 300 & 200 \\ 450 & 300 \end{pmatrix}$ with one row per batch, and scaling only the second batch is the matrix`],
  ['div', 'd-matrix', String.raw`$$S = \begin{pmatrix} 1 & 0 \\ 0 & k \end{pmatrix}$$`],
  ['p', 'p-start', String.raw`$x$ marks the starting weight in this paragraph, and $t \text{ in minutes}$ keeps its label as text, and a pan tilted by $\theta$ fills to a depth of $h \cos\theta$ along its wall.`],
  ['p', 'p-plain', String.raw`Proofing time does not scale with the batch size, which is the one rule that surprises most home bakers.`],
];

const controls = String.raw`<article id="all">
<h2>Release checklist</h2>
<p>Before tagging, run the suite twice and read every warning.<br>Then update the notes:<br>x<br>I<br>I wrote them last week.</p>
<ul><li>n</li><li>x</li><li>+</li><li>2</li><li>Apples</li><li>Pears</li></ul>
<table><tr><th>k</th><th>v</th></tr><tr><td>1</td><td>2</td></tr><tr><td>a</td><td>b</td></tr></table>
<pre><code>let x = 1
x
+
2
}</code></pre>
<p>Click the <span style="display:block">X</span> button to close, then read <a href="https://example.com">the guide</a>.</p>
<p>HTML sup/sub: E = mc<sup>2</sup>, H<sub>2</sub>O, and typed math T ∝ √(L/g), n × n.</p>
<p>Inline-block chips: <span style="display:inline-block">n</span> <span style="display:inline-block">×</span> <span style="display:inline-block">n</span> done.</p>
</article>`;

// 정리기가 원문을 바꾸면 안 되는 자리와 선형식 경계 사례. capture.mjs가 절(id)마다 따로 복사한다.
// 코드 블록·목록·제목의 짧은 줄, 원래 글의 줄바꿈, SVG로 그리는 악센트, 숨은 MathML 안에서 시작한 선택,
// 첨자와 함수 이름의 선형식.
const edges = [
  ['div', 'e-code', String.raw`<p>The program prints the first Fibonacci numbers:</p><pre><code>1
1
2
3
5
8</code></pre><p>Each term after $1$ is the sum of the two before it, so the sixth is $8$.</p><h3>A</h3><p>A short section about sets: the set $S = \{1, 2\}$ has size $2$, and $A$ is any subset.</p><ul><li>x</li><li>x-axis label shown below the chart</li></ul><p>The speed is $v = d/t$ and the kinetic energy is $\frac{1}{2} m v^2$, where $x$ is the position.</p>`],
  ['div', 'e-breaks', '<ul><li>Compute the ratio $\\frac{a}{b}$<pre><code>    ratio = a / b</code></pre></li></ul>'
    + '<div style="white-space:pre-wrap">Step one is done. \n$p$ is the next value.\nThen (\n$q$) follows, and the value is $w$\n  indented second line</div>'
    + '<p>Line one<br>$u$ is next<br>and (<br>$y$) end.</p>'
    + '<p>Press $x^2$ <kbd>Enter</kbd> to square, the value $\\frac{c}{d}$ <img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" width="8" height="8"> is shown, and $v^2$<wbr>is the square.</p>'],
  ['p', 'e-accents', String.raw`The estimate $\widehat{xy}$ ^ is the bitwise XOR, the count $\widetilde{n}$ ~ 100 in practice, and the walk $\overrightarrow{AB}$ → $\overrightarrow{BC}$ goes around, then $z$ follows.`],
  ['p', 'e-cut', String.raw`Let $x + x$ be it.`],
  ['div', 'e-linear', [
    String.raw`e^{i\pi} + 1 = 0`, String.raw`A^T A`, String.raw`\log_2 n`, String.raw`x^{ab}`, String.raw`\sin^2 x`,
    String.raw`\cos^2\theta + \sin^2\theta = 1`, String.raw`\max_i x_i`, String.raw`u_n v_n`, String.raw`\sum_i a_i b_i`,
    String.raw`(x - x_0)^2 + (y - y_0)^2 = r^2`, String.raw`(1 + r_t)^n`, String.raw`\|w - w^*\|^2`,
  ].map((tex) => `<p>Item $${tex}$ end.</p>`).join('')
    + String.raw`<p>The largest is</p>$$\max_i x_i$$<p>The limit is</p>$$\lim_{x \to 0} \frac{\sin x}{x} = 1$$`],
];

function body(math, blocks = article) {
  const html = blocks.map(([tag, id, source]) => {
    const content = source.replace(/\$\$([\s\S]+?)\$\$|\$([^$]+?)\$/g, (_, display, inline) =>
      display != null ? math(display, true) : math(inline, false));
    return `<${tag} id="${id}"${tag === 'div' && blocks === article ? ' class="math-display"' : ''}>${content}</${tag}>`;
  });
  return `<article id="all">\n${html.join('\n')}\n</article>`;
}

function page(title, head, content) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>${title}</title>
<style>body{font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:760px;margin:24px auto;line-height:1.7;font-size:18px;color:#333} .math-display{text-align:center;margin:1em 0}</style>
${head}</head><body>
${content}
</body></html>
`;
}

/** Returns { name: html } for every fixture page. `modules` is the node_modules path the server also exposes at /modules. */
export async function pages(modules) {
  const { default: katex } = await import(`${modules}/katex/dist/katex.mjs`);
  const render = (tex, display, output = 'htmlAndMathml') =>
    katex.renderToString(tex, { displayMode: display, output, throwOnError: true });
  const css = '<link rel="stylesheet" href="/modules/katex/dist/katex.min.css">';
  const escape = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const native = (tex, display) => render(tex, display, 'mathml').replace(/^<span class="katex">/, '').replace(/<\/span>$/, '');
  return {
    katex: page('KaTeX', css, body(render)),
    edges: page('KaTeX edge cases', css, body(render, edges)),
    copytex: page('KaTeX copy-tex', `${css}\n<script src="/modules/katex/dist/contrib/copy-tex.min.js"></script>`, body(render)),
    mathml: page('Native MathML', '', body(native)),
    mathjax3: page('MathJax 3 CHTML',
      `<script>window.MathJax={tex:{inlineMath:[['\\\\(','\\\\)']]}};</script>\n<script src="/modules/mathjax-full/es5/tex-chtml.js"></script>`,
      body((tex, display) => display ? `\\[${escape(tex)}\\]` : `\\(${escape(tex)}\\)`)),
    control: page('Control', '', controls),
  };
}
