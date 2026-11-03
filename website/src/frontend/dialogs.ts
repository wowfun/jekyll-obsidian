export type WebsiteDialogName = "search" | "browse" | "context" | "graph-global" | "graph-local" | "media" | "export";

const DIALOG_NAMES = new Set<WebsiteDialogName>([
  "search",
  "browse",
  "context",
  "graph-global",
  "graph-local",
  "media",
  "export"
]);

const movablePlaceholders = new WeakMap<Element, Comment>();
const dialogsController = Symbol.for("jekyll-obsidian.dialogs-controller");

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
  if (name !== "browse" && document.querySelector('.website-dialog--navigation[open]')) closeWebsiteDialog("browse");
  hydrateDialog(dialog);
  moveDialogContent(dialog);
  if (!dialog.open) dialog.showModal();
  for (const opener of document.querySelectorAll(`[data-dialog-open="${name}"][aria-expanded]`)) opener.setAttribute("aria-expanded", "true");
  const initialFocus = dialog.querySelector<HTMLElement>("[autofocus]") ?? dialog.querySelector<HTMLElement>(
    "input, button:not([disabled]), a[href]"
  );
  initialFocus?.focus();
  return dialog;
}

export function closeWebsiteDialog(name: WebsiteDialogName): void {
  const dialog = dialogFor(name);
  if (!dialog) return;
  if (dialog.open) dialog.close();
  // Native close events are queued; restore before a page swap can remove the dialog.
  restoreDialogContent(dialog);
  for (const opener of document.querySelectorAll(`[data-dialog-open="${name}"][aria-expanded]`)) opener.setAttribute("aria-expanded", "false");
}

export function initialiseDialogs(): void {
  const controlledDocument = document as Document & { [dialogsController]?: boolean };
  if (!controlledDocument[dialogsController]) {
    document.addEventListener("click", (event) => {
      const target = event.target;
      if (!(target instanceof Element)) return;

      const opener = target.closest<HTMLElement>("[data-dialog-open]");
      if (opener) {
        const name = opener.dataset.dialogOpen;
        if (name && DIALOG_NAMES.has(name as WebsiteDialogName)) {
          event.preventDefault();
          openWebsiteDialog(name as WebsiteDialogName);
        }
        return;
      }

      const closer = target.closest<HTMLElement>("[data-dialog-close]");
      if (closer) closer.closest<HTMLDialogElement>("dialog")?.close();
    });
    controlledDocument[dialogsController] = true;
  }

  for (const dialog of document.querySelectorAll<HTMLDialogElement>(
    "dialog[data-dialog]"
  )) {
    if (dialog.dataset.websiteDialogInitialised === "true") continue;
    dialog.dataset.websiteDialogInitialised = "true";
    dialog.addEventListener("close", () => {
      // An earlier close event can arrive after this dialog has reopened.
      if (dialog.open) return;
      restoreDialogContent(dialog);
      for (const opener of document.querySelectorAll(`[data-dialog-open="${dialog.dataset.dialog}"][aria-expanded]`)) opener.setAttribute("aria-expanded", "false");
    });
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) dialog.close();
    });
  }
}
