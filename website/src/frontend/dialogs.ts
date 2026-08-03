export type WebsiteDialogName = "search" | "browse" | "context";

const movablePlaceholders = new WeakMap<Element, Comment>();

function dialogFor(name: WebsiteDialogName): HTMLDialogElement | null {
  return document.querySelector<HTMLDialogElement>(`dialog[data-dialog="${name}"]`);
}

function hydrateDialog(dialog: HTMLDialogElement): void {
  if (dialog.dataset.hydrated === "true") return;
  const name = dialog.dataset.dialog;
  if (!name) return;
  const template = document.querySelector<HTMLTemplateElement>(
    `template[data-dialog-template="${name}"]`
  );
  const target = dialog.querySelector<HTMLElement>("[data-dialog-content]");
  if (template && target) target.append(template.content.cloneNode(true));
  dialog.dataset.hydrated = "true";
}

function moveDialogContent(dialog: HTMLDialogElement): void {
  const name = dialog.dataset.dialog;
  const target = dialog.querySelector<HTMLElement>("[data-dialog-content]");
  if (!name || !target) return;
  const movable = document.querySelector<HTMLElement>(`[data-dialog-movable="${name}"]`);
  if (!movable || dialog.contains(movable)) return;
  const placeholder = document.createComment(`website-${name}`);
  movable.before(placeholder);
  movablePlaceholders.set(movable, placeholder);
  target.prepend(movable);
}

function restoreDialogContent(dialog: HTMLDialogElement): void {
  const movable = dialog.querySelector<HTMLElement>("[data-dialog-movable]");
  if (!movable) return;
  const placeholder = movablePlaceholders.get(movable);
  if (!placeholder?.parentNode) return;
  placeholder.replaceWith(movable);
  movablePlaceholders.delete(movable);
}

export function openWebsiteDialog(name: WebsiteDialogName): HTMLDialogElement | null {
  const dialog = dialogFor(name);
  if (!dialog) return null;
  hydrateDialog(dialog);
  moveDialogContent(dialog);
  if (!dialog.open) dialog.showModal();
  const initialFocus = dialog.querySelector<HTMLElement>(
    "[autofocus], input, button:not([disabled]), a[href]"
  );
  initialFocus?.focus();
  return dialog;
}

export function closeWebsiteDialog(name: WebsiteDialogName): void {
  const dialog = dialogFor(name);
  if (!dialog) return;
  if (dialog.open) dialog.close();
  restoreDialogContent(dialog);
}

export function initialiseDialogs(): void {
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const opener = target.closest<HTMLElement>("[data-dialog-open]");
    if (opener) {
      const name = opener.dataset.dialogOpen;
      if (name === "search" || name === "browse" || name === "context") {
        event.preventDefault();
        openWebsiteDialog(name);
      }
      return;
    }

    const closer = target.closest<HTMLElement>("[data-dialog-close]");
    if (closer) {
      closer.closest<HTMLDialogElement>("dialog")?.close();
    }
  });

  for (const dialog of document.querySelectorAll<HTMLDialogElement>(
    "dialog[data-dialog]"
  )) {
    dialog.addEventListener("close", () => restoreDialogContent(dialog));
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) dialog.close();
    });
  }
}
