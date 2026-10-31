// playwright-cli invokes this standalone callback outside the Astro application.
async function browser_layout(page) {
  const origin = 'http://127.0.0.1:4433';
  await page.goto(origin + '/designs/');
  const paths = await page
    .locator('[data-example-card] > a')
    .evaluateAll((links) => links.map((link) => new URL(link.href).pathname));
  const results = [];
  for (const width of [1440, 768, 390]) {
    await page.setViewportSize({ width, height: 900 });
    for (const path of [
      '/',
      '/en/',
      '/designs/',
      '/guide/',
      '/en/guide/',
      '/privacy/',
      '/en/privacy/',
      ...paths,
    ]) {
      const response = await page.goto(origin + path);
      if (response.status() !== 200) throw new Error(path + ': HTTP ' + response.status());
      const result = await page.evaluate(() => ({
        width: innerWidth,
        scrollWidth: document.documentElement.scrollWidth,
        h1: document.querySelectorAll('h1').length,
        title: document.title,
        images: [...document.images]
          .filter((image) => image.getAttribute('src') && image.loading !== 'lazy')
          .every((image) => image.complete && image.naturalWidth > 0),
      }));
      if (result.scrollWidth > width + 1)
        throw new Error(path + ' overflows at ' + width + ': ' + result.scrollWidth);
      if (result.h1 !== 1) throw new Error(path + ': expected one main heading');
      if (!result.images) {
        await page.waitForFunction(() =>
          [...document.images]
            .filter((image) => image.getAttribute('src') && image.loading !== 'lazy')
            .every((image) => image.complete && image.naturalWidth > 0),
        );
      }
      results.push({ path, width, scrollWidth: result.scrollWidth });
    }
  }
  const missing = await page.goto(origin + '/not-a-landing-example/');
  if (missing.status() !== 404) throw new Error('Unknown path did not return 404');
  if (!(await page.getByRole('heading', { level: 1 }).textContent()).includes('찾을 수'))
    throw new Error('Custom 404 page did not render');
  return {
    checked: results.length,
    widths: [1440, 768, 390],
    routes: 1 + paths.length,
    notFoundStatus: missing.status(),
    results,
  };
}
