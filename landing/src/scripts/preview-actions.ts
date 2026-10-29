const installDialog = document.querySelector<HTMLDialogElement>('#install-info');

document.addEventListener('click', async (event) => {
  const target = event.target;
  if (!(target instanceof Element)) return;
  if (target.closest('[data-install-info]') && installDialog) {
    if (
      event instanceof MouseEvent &&
      (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
    )
      return;
    event.preventDefault();
    if (!installDialog.open) installDialog.showModal();
  }
  if (target.closest('[data-close-install]')) installDialog?.close();
  const installCopy = target.closest<HTMLButtonElement>('[data-copy-install]');
  if (installCopy?.dataset.copyInstall) {
    const status = installCopy
      .closest('[data-install-options]')
      ?.querySelector<HTMLElement>('[data-install-copy-status]');
    try {
      await navigator.clipboard.writeText(installCopy.dataset.copyInstall);
      const label = installCopy.querySelector('[data-copy-label]');
      if (label) label.textContent = '복사됨';
      if (status) status.textContent = '터미널에 붙여넣어 실행하세요.';
    } catch {
      if (status) status.textContent = '명령어를 직접 선택해 복사해 주세요.';
    }
    return;
  }
  const button = target.closest<HTMLButtonElement>('[data-copy-result]');
  if (!button?.dataset.copyResult) return;
  try {
    await navigator.clipboard.writeText(button.dataset.copyResult);
    button.textContent = '복사됨';
  } catch {
    button.textContent = '복사할 수 없어요';
  }
});

installDialog?.addEventListener('click', (event) => {
  if (event.target !== installDialog) return;
  const box = installDialog.getBoundingClientRect();
  if (
    event.clientX < box.left ||
    event.clientX > box.right ||
    event.clientY < box.top ||
    event.clientY > box.bottom
  )
    installDialog.close();
});
