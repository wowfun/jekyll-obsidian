function ensureActive(signal: AbortSignal): void {
  if (signal.aborted) throw new DOMException("Copy request was cancelled", "AbortError");
}

export async function writeClipboard(text: string, signal: AbortSignal): Promise<void> {
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
  const activeElement = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  const selection = document.getSelection();
  const ranges = selection
    ? Array.from({ length: selection.rangeCount }, (_item, index) => selection.getRangeAt(index).cloneRange())
    : [];
  const field = document.createElement("textarea");
  field.value = text;
  field.setAttribute("readonly", "");
  field.style.position = "fixed";
  field.style.inset = "0 auto auto -9999px";
  document.body.append(field);
  let copied = false;
  try {
    field.select();
    copied = document.execCommand("copy");
  } finally {
    field.remove();
    if (activeElement?.isConnected) activeElement.focus({ preventScroll: true });
    if (selection) {
      selection.removeAllRanges();
      for (const range of ranges) {
        try {
          selection.addRange(range);
        } catch {
          // The copied action may outlive content that owned the original range.
        }
      }
    }
  }
  if (!copied) throw new Error("The browser rejected the copy command");
}
