import { beforeEach, describe, expect, it, vi } from "vitest";
import { closeWebsiteDialog, initialiseDialogs, openWebsiteDialog } from "../../src/frontend/dialogs";

describe("mobile context dialogs", () => {
  it("focuses the search input immediately even when the close button comes first", () => {
    document.body.innerHTML = '<dialog data-dialog="search"><button>Close</button><input data-search-input autofocus></dialog>';
    const dialog = document.querySelector<HTMLDialogElement>("dialog")!;
    dialog.showModal = vi.fn(() => dialog.setAttribute("open", ""));
    openWebsiteDialog("search");
    expect(document.activeElement).toBe(dialog.querySelector("input"));
  });

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

    openWebsiteDialog("context");
    openWebsiteDialog("context");

    expect(dialog.showModal).toHaveBeenCalledTimes(1);
    expect(dialog.querySelectorAll("a")).toHaveLength(1);
    expect(dialog.dataset.hydrated).toBe("true");
  });

  it("closes an open dialog", () => {
    const dialog = document.querySelector<HTMLDialogElement>("dialog")!;
    dialog.setAttribute("open", "");
    dialog.close = vi.fn(() => dialog.removeAttribute("open"));
    closeWebsiteDialog("context");
    expect(dialog.close).toHaveBeenCalledOnce();
  });

  it("moves one live context node into the dialog and restores it on close", () => {
    document.body.insertAdjacentHTML(
      "afterbegin",
      '<aside data-dialog-movable="context"><a href="#heading">Live outline</a></aside>'
    );
    const dialog = document.querySelector<HTMLDialogElement>("dialog")!;
    dialog.showModal = vi.fn(() => dialog.setAttribute("open", ""));
    openWebsiteDialog("context");
    expect(dialog.querySelectorAll("[data-dialog-movable='context']")).toHaveLength(1);
    closeWebsiteDialog("context");
    expect(document.body.firstElementChild?.matches("[data-dialog-movable='context']")).toBe(true);
  });

  it("restores synchronously and ignores a queued close after reopening", async () => {
    document.body.insertAdjacentHTML('afterbegin', '<button data-dialog-open="context" aria-expanded="false">Context</button><aside data-dialog-movable="context">Live outline</aside>');
    const dialog = document.querySelector<HTMLDialogElement>('dialog')!;
    const opener = document.querySelector('[data-dialog-open]')!;
    const content = document.querySelector('[data-dialog-movable]')!;
    dialog.showModal = vi.fn(() => dialog.setAttribute('open', ''));
    dialog.close = vi.fn(() => {
      dialog.removeAttribute('open');
      queueMicrotask(() => dialog.dispatchEvent(new Event('close')));
    });
    initialiseDialogs();
    openWebsiteDialog('context');
    closeWebsiteDialog('context');
    expect(content.parentElement).toBe(document.body);
    expect(opener.getAttribute('aria-expanded')).toBe('false');
    openWebsiteDialog('context');
    await Promise.resolve();
    expect(dialog.contains(content)).toBe(true);
    expect(opener.getAttribute('aria-expanded')).toBe('true');
    dialog.close();
    await Promise.resolve();
    expect(content.parentElement).toBe(document.body);
    expect(opener.getAttribute('aria-expanded')).toBe('false');
  });
});
