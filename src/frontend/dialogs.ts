export type ObsidianDialogName = "search" | "browse" | "context" | "outline";

function dialogFor(name: ObsidianDialogName): HTMLDialogElement | null {
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

export function openObsidianDialog(name: ObsidianDialogName): HTMLDialogElement | null {
  const dialog = dialogFor(name);
  if (!dialog) return null;
  hydrateDialog(dialog);
  if (!dialog.open) dialog.showModal();
  const initialFocus = dialog.querySelector<HTMLElement>(
    "[autofocus], input, button:not([disabled]), a[href]"
  );
  initialFocus?.focus();
  return dialog;
}

export function closeObsidianDialog(name: ObsidianDialogName): void {
  const dialog = dialogFor(name);
  if (dialog?.open) dialog.close();
}

export function initialiseDialogs(): void {
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const opener = target.closest<HTMLElement>("[data-dialog-open]");
    if (opener) {
      const name = opener.dataset.dialogOpen;
      if (name === "search" || name === "browse" || name === "context" || name === "outline") {
        event.preventDefault();
        openObsidianDialog(name);
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
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) dialog.close();
    });
  }
}
