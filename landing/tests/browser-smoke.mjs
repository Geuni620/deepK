async function browser_smoke(page) {
  const origin = 'http://127.0.0.1:4433';
  const passed = [];
  const pageErrors = [];
  const unexpectedRequests = [];
  const marker = 'PR_CHECK_DO_NOT_SEND_20261026';
  page.on('pageerror', (error) => pageErrors.push(error.message));
  page.on('request', (request) => {
    if (request.method() !== 'GET' || request.url().includes(marker))
      unexpectedRequests.push({ method: request.method(), url: request.url() });
  });
  const check = (condition, message) => {
    if (!condition) throw new Error(message);
  };
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto(origin + '/');
  check(
    (await page.locator('[data-example-card]').count()) === 18,
    'Catalog should have 18 examples',
  );
  for (const [kind, count] of [
    ['design', 10],
    ['responsive', 3],
    ['flow', 4],
    ['guide', 1],
  ]) {
    await page.locator('[data-filter="' + kind + '"]').click();
    check(
      (await page.locator('[data-example-card]:visible').count()) === count,
      'Wrong category count: ' + kind,
    );
  }
  await page.locator('[data-filter="all"]').click();
  passed.push('catalog and category filters');
  await page.getByRole('checkbox', { name: 'Warm Sand 후보 선택', exact: true }).check();
  await page.reload();
  check(
    await page.getByRole('checkbox', { name: 'Warm Sand 후보 선택', exact: true }).isChecked(),
    'Candidate was not restored',
  );
  await page.getByRole('button', { name: '후보만 보기', exact: true }).click();
  check(
    (await page.locator('[data-example-card]:visible').count()) === 1,
    'Selected-only filter failed',
  );
  await page.locator('[data-filter="all"]').click();
  passed.push('candidate persistence and selected-only filter');
  await page.getByRole('link', { name: 'Warm Sand 구현 화면 열기', exact: true }).click();
  check(
    await page.locator('#preview-dialog').evaluate((dialog) => dialog.open),
    'Preview did not open',
  );
  await page.getByRole('button', { name: '원본 시안', exact: true }).click();
  await page.waitForFunction(() => {
    const image = document.querySelector('#reference-frame');
    return image && !image.hidden && image.complete && image.naturalWidth > 0;
  });
  await page.getByRole('button', { name: '다음 예시', exact: true }).click();
  check(
    (await page.locator('#live-frame').getAttribute('src')).includes('/keystroke/'),
    'Preview next failed',
  );
  await page.getByRole('button', { name: '이전 예시', exact: true }).click();
  check(
    (await page.locator('#live-frame').getAttribute('src')).includes('/warm-sand/'),
    'Preview previous failed',
  );
  await page.keyboard.press('Escape');
  check(
    !(await page.locator('#preview-dialog').evaluate((dialog) => dialog.open)),
    'Escape did not close preview',
  );
  await page.waitForURL((url) => !url.searchParams.has('case'));
  check(!new URL(page.url()).searchParams.has('case'), 'Closing preview did not clear case');
  passed.push('preview, reference image, navigation, and Escape');
  await page.evaluate(() => localStorage.setItem('deepk:landing:candidates:v1', '{broken'));
  await page.reload();
  check(
    (await page.locator('[data-candidate]:checked').count()) === 0,
    'Malformed storage was not rejected',
  );
  await page.goto(origin + '/?case=../../outside');
  check(
    !(await page.locator('#preview-dialog').evaluate((dialog) => dialog.open)),
    'Unknown case opened preview',
  );
  passed.push('malformed local storage and unknown case');
  await page.goto(origin + '/examples/demo-input/');
  const input = page.getByRole('textbox', { name: '내 문장으로 번역해 보세요' });
  const fixture = await input.inputValue();
  const translate = page.getByRole('button', { name: '예시 번역 보기 ⌘C ⌘C' });
  await translate.click();
  check(await page.locator('[data-result-panel]').isVisible(), 'Fixture result not visible');
  await input.fill(marker);
  check(
    !(await page.locator('[data-result-panel]').isVisible()),
    'Stale result remained after editing',
  );
  check(
    (await page.locator('[data-translation-demo]').getAttribute('data-state')) === 'input',
    'Editing did not restore input state',
  );
  await translate.click();
  check(
    !(await page.locator('[data-result-panel]').isVisible()),
    'Unknown input retained a result',
  );
  check(
    (await page.getByRole('status').textContent()).includes('예시 문장'),
    'Unknown input feedback missing',
  );
  await input.fill('');
  await translate.click();
  check(!(await page.locator('[data-result-panel]').isVisible()), 'Empty input retained a result');
  check((await input.getAttribute('maxlength')) === '500', 'Input length limit missing');
  await input.fill(fixture);
  await translate.click();
  check(
    await page.locator('[data-result-panel]').isVisible(),
    'Fixture did not recover after unsupported input',
  );
  passed.push('fixture translation and stale/unknown/empty input regression');
  await page.evaluate(() => {
    window.__clipboardText = null;
    window.__clipboardReject = false;
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: {
        writeText: async (text) => {
          if (window.__clipboardReject) throw new Error('Clipboard denied for smoke check');
          window.__clipboardText = text;
        },
      },
    });
  });
  const copy = page.locator('[data-result-panel] [data-copy-result]');
  await copy.click();
  check((await copy.textContent()) === '복사됨', 'Copy success feedback missing');
  check(
    (await page.evaluate(() => window.__clipboardText)).includes('업데이트된 일정'),
    'Copy did not use current result',
  );
  await page.evaluate(() => {
    window.__clipboardReject = true;
  });
  await copy.click();
  check((await copy.textContent()) === '복사할 수 없어요', 'Copy denial feedback missing');
  passed.push('clipboard success and denial with isolated browser mock');
  await page.getByRole('button', { name: 'Mac용 받기', exact: true }).click();
  check(
    await page.getByRole('dialog', { name: 'Mac 앱 설치 안내' }).isVisible(),
    'Install information did not open',
  );
  await page.getByRole('button', { name: '확인했어요', exact: true }).click();
  check(
    !(await page.getByRole('dialog', { name: 'Mac 앱 설치 안내' }).isVisible()),
    'Install information did not close',
  );
  passed.push('install information dialog');
  await page.goto(origin + '/examples/playful-bear/');
  const firstFaq = page.locator('[data-faq] details').first();
  const trigger = firstFaq.locator('summary');
  await trigger.focus();
  await trigger.press('Enter');
  check(await firstFaq.evaluate((item) => item.open), 'Keyboard FAQ activation failed');
  check(
    (await firstFaq.getAttribute('data-faq-motion')) === 'instant',
    'Keyboard activation should be instant',
  );
  for (let i = 0; i < 3; i++) await trigger.dispatchEvent('click', { detail: 1 });
  await page.waitForFunction(() => {
    const item = document.querySelector('[data-faq] details');
    return item && !item.open && item.style.height === '' && item.getAnimations().length === 0;
  });
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await trigger.click();
  check(await firstFaq.evaluate((item) => item.open), 'Reduced-motion FAQ activation failed');
  check(
    (await firstFaq.getAttribute('data-faq-motion')) === 'instant',
    'Reduced motion did not disable animation',
  );
  check(
    await firstFaq.evaluate(
      (item) => item.style.height === '' && item.getAnimations().length === 0,
    ),
    'FAQ did not settle',
  );
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  passed.push('FAQ keyboard, interrupted transitions, and reduced motion');
  check(pageErrors.length === 0, 'Browser JavaScript errors: ' + pageErrors.join('; '));
  check(unexpectedRequests.length === 0, 'Unexpected request or input transmission');
  return {
    passed,
    scenarios: passed.length,
    pageErrors,
    unexpectedRequests,
    clipboard: 'mocked; system clipboard not read or changed',
  };
}
