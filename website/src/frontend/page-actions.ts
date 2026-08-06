const COPY_RESET_DELAY = 2_000;

function ensureActive(signal: AbortSignal): void {
  if (signal.aborted) throw new DOMException("Copy request was cancelled", "AbortError");
}

async function writeClipboard(text: string, signal: AbortSignal): Promise<void> {
  ensureActive(signal);
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch {
      // A selection fallback still works on browsers that expose Clipboard
      // but deny it outside a secure browsing context.
      ensureActive(signal);
    }
  }

  ensureActive(signal);
  const field = document.createElement("textarea");
  field.value = text;
  field.setAttribute("readonly", "");
  field.style.position = "fixed";
  field.style.inset = "0 auto auto -9999px";
  document.body.append(field);
  field.select();
  const copied = document.execCommand("copy");
  field.remove();
  if (!copied) throw new Error("The browser rejected the copy command");
}

export function initialisePageActions(): () => void {
  const root = document.querySelector<HTMLElement>("[data-page-actions]");
  if (!root) return () => undefined;

  const source = root.dataset.markdownUrl;
  const status = root.querySelector<HTMLElement>("[data-copy-page-status]");
  const visibleError = root.querySelector<HTMLElement>("[data-copy-page-error]");
  const menu = root.querySelector<HTMLDetailsElement>("[data-page-actions-menu]");
  const buttons = [...root.querySelectorAll<HTMLButtonElement>("[data-copy-page]")];
  const labels = [...root.querySelectorAll<HTMLElement>("[data-copy-page-label]")];
  const defaultLabels = labels.map((label) => label.textContent || "Copy page");
  let resetTimer: number | undefined;
  let activeRequest: AbortController | undefined;
  let disposed = false;

  const reset = () => {
    labels.forEach((label, index) => { label.textContent = defaultLabels[index] || "Copy page"; });
    buttons.forEach((button) => { button.disabled = false; });
    resetTimer = undefined;
  };

  const handleClick = async (event: Event) => {
    const target = event.target;
    const button = target instanceof Element ? target.closest<HTMLButtonElement>("[data-copy-page]") : null;
    if (!button || !root.contains(button) || !source) return;
    event.preventDefault();
    activeRequest?.abort();
    const request = new AbortController();
    activeRequest = request;
    window.clearTimeout(resetTimer);
    if (status) status.textContent = "";
    if (visibleError) {
      visibleError.hidden = true;
      visibleError.textContent = "";
    }
    buttons.forEach((item) => { item.disabled = true; });

    try {
      const url = new URL(source, window.location.href);
      if (url.origin !== window.location.origin) throw new TypeError("Markdown URL must be same-origin");
      const response = await fetch(url, {
        credentials: "same-origin",
        headers: { Accept: "text/markdown" },
        signal: request.signal
      });
      if (!response.ok) throw new Error(`Markdown resource returned HTTP ${response.status}`);
      const markdown = await response.text();
      if (disposed || request.signal.aborted || activeRequest !== request) return;
      await writeClipboard(markdown, request.signal);
      if (disposed || request.signal.aborted || activeRequest !== request) return;
      const copied = root.dataset.copySuccess || "Copied";
      labels.forEach((label) => { label.textContent = copied; });
      if (status) status.textContent = copied;
      menu?.removeAttribute("open");
    } catch {
      if (disposed || request.signal.aborted || activeRequest !== request) return;
      const message = root.dataset.copyError || "Copy failed. Open View as Markdown and copy the text.";
      if (status) status.textContent = message;
      if (visibleError) {
        visibleError.textContent = message;
        visibleError.hidden = false;
      }
      if (menu) menu.open = true;
    } finally {
      if (activeRequest === request) {
        activeRequest = undefined;
        if (!disposed) resetTimer = window.setTimeout(reset, COPY_RESET_DELAY);
      }
    }
  };

  const handleOutsideClick = (event: MouseEvent) => {
    if (!menu?.open || (event.target instanceof Node && menu.contains(event.target))) return;
    menu.removeAttribute("open");
  };

  const handleKeydown = (event: KeyboardEvent) => {
    if (event.key !== "Escape" || !menu?.open) return;
    menu.removeAttribute("open");
    menu.querySelector<HTMLElement>("summary")?.focus();
  };

  root.addEventListener("click", handleClick);
  document.addEventListener("click", handleOutsideClick);
  document.addEventListener("keydown", handleKeydown);
  return () => {
    disposed = true;
    activeRequest?.abort();
    activeRequest = undefined;
    window.clearTimeout(resetTimer);
    root.removeEventListener("click", handleClick);
    document.removeEventListener("click", handleOutsideClick);
    document.removeEventListener("keydown", handleKeydown);
  };
}
