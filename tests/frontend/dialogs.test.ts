import { beforeEach, describe, expect, it, vi } from "vitest";
import { closeObsidianDialog, openObsidianDialog } from "../../src/frontend/dialogs";

describe("mobile context dialogs", () => {
  beforeEach(() => {
    document.body.replaceChildren();
    document.body.insertAdjacentHTML(
      "beforeend",
      `<template data-dialog-template="context"><a href="#heading">Outline</a></template>
       <dialog data-dialog="context"><div data-dialog-content></div></dialog>`
    );
  });

  it("hydrates template content once and opens modally", () => {
    const dialog = document.querySelector<HTMLDialogElement>("dialog")!;
    dialog.showModal = vi.fn(() => dialog.setAttribute("open", ""));

    openObsidianDialog("context");
    openObsidianDialog("context");

    expect(dialog.showModal).toHaveBeenCalledTimes(1);
    expect(dialog.querySelectorAll("a")).toHaveLength(1);
    expect(dialog.dataset.hydrated).toBe("true");
  });

  it("closes an open dialog", () => {
    const dialog = document.querySelector<HTMLDialogElement>("dialog")!;
    dialog.setAttribute("open", "");
    dialog.close = vi.fn(() => dialog.removeAttribute("open"));
    closeObsidianDialog("context");
    expect(dialog.close).toHaveBeenCalledOnce();
  });
});
