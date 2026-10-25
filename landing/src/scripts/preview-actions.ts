const installDialog = document.querySelector<HTMLDialogElement>('#install-info');

document.addEventListener('click', async (event) => {
  const target = event.target;
  if (!(target instanceof Element)) return;
  if (target.closest('[data-install-info]') && installDialog && !installDialog.open)
    installDialog.showModal();
  if (target.closest('[data-close-install]')) installDialog?.close();
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
