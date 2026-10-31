import { expect, it, vi } from "vitest";
import { BEFORE_PAGE_CHANGE_EVENT, PAGE_CHANGE_EVENT } from "../../src/frontend/page-navigation-events";

const state = vi.hoisted(() => {
  let release!: () => void;
  return {
    loaded: new Promise<void>((resolve) => { release = resolve; }),
    release: () => release(),
    archiveImport: vi.fn(), favoritesImport: vi.fn(),
    archiveCleanup: vi.fn(), favoritesCleanup: vi.fn(),
    archiveInit: vi.fn(), favoritesInit: vi.fn()
  };
});
vi.mock("../../src/frontend/archive-filters", async () => {
  state.archiveImport();
  await state.loaded;
  return { initialiseArchiveFilters: () => { state.archiveInit(); return state.archiveCleanup; } };
});
vi.mock("../../src/frontend/favorite-controls", async () => {
  state.favoritesImport();
  await state.loaded;
  return { initialiseFavorites: () => { state.favoritesInit(); return state.favoritesCleanup; } };
});
import { initialiseWebsite } from "../../src/frontend/main";

it("loads only marked pages, discards stale imports, and cleans up each initialized generation", async () => {
  document.head.replaceChildren();
  document.body.replaceChildren();
  initialiseWebsite();
  await vi.dynamicImportSettled();
  expect(state.archiveImport).not.toHaveBeenCalled();
  expect(state.favoritesImport).not.toHaveBeenCalled();

  const navigate = (markup: string) => {
    document.dispatchEvent(new CustomEvent(BEFORE_PAGE_CHANGE_EVENT));
    document.body.innerHTML = markup;
    document.dispatchEvent(new CustomEvent(PAGE_CHANGE_EVENT));
  };
  const marked = '<main data-paged-archive><p data-archive-status></p><p data-filter-empty hidden>No matching entries</p></main><div data-favorites-ui></div><p data-favorite-status></p>';
  navigate(marked);
  await vi.waitFor(() => {
    expect(state.archiveImport).toHaveBeenCalledTimes(1);
    expect(state.favoritesImport).toHaveBeenCalledTimes(1);
  });
  navigate("<main>Next document</main>");
  state.release();
  await vi.dynamicImportSettled();
  expect(state.archiveInit).not.toHaveBeenCalled();
  expect(state.favoritesInit).not.toHaveBeenCalled();

  navigate(marked);
  await vi.dynamicImportSettled();
  expect(state.archiveInit).toHaveBeenCalledTimes(1);
  expect(state.favoritesInit).toHaveBeenCalledTimes(1);
  navigate(marked);
  await vi.dynamicImportSettled();
  expect(state.archiveCleanup).toHaveBeenCalledTimes(1);
  expect(state.favoritesCleanup).toHaveBeenCalledTimes(1);
  navigate("");
  expect(state.archiveCleanup).toHaveBeenCalledTimes(2);
  expect(state.favoritesCleanup).toHaveBeenCalledTimes(2);

  navigate(marked);
  await vi.dynamicImportSettled();
  state.archiveCleanup.mockImplementationOnce(() => { throw new Error("Cleanup failed"); });
  const reported = vi.spyOn(console, "error").mockImplementation(() => {});
  navigate(marked);
  await vi.dynamicImportSettled();
  expect(state.archiveInit).toHaveBeenCalledTimes(4);
  expect(state.favoritesCleanup).toHaveBeenCalledTimes(3);
  expect(reported).toHaveBeenCalled();
  reported.mockRestore();
  navigate("");

  state.archiveInit.mockImplementationOnce(() => { throw new Error("Module failed"); });
  state.favoritesInit.mockImplementationOnce(() => { throw new Error("Module failed"); });
  navigate(marked);
  await vi.dynamicImportSettled();
  expect(document.querySelector("[data-archive-status]")?.textContent).toContain("Reload");
  expect(document.querySelector<HTMLElement>("[data-filter-empty]")?.hidden).toBe(true);
  expect(document.querySelector("[data-filter-empty]")?.textContent).toBe("No matching entries");
  expect(document.querySelector("[data-favorite-status]")?.textContent).toContain("Reload");
  expect(document.querySelector("main")).not.toBeNull();

  state.archiveInit.mockImplementationOnce(() => { throw new Error("Module failed"); });
  navigate('<main data-filter-page><p data-filter-empty data-module-unavailable="筛选控件加载失败" hidden>No matching entries</p></main>');
  await vi.dynamicImportSettled();
  expect(document.querySelector<HTMLElement>("[data-filter-empty]")?.hidden).toBe(false);
  expect(document.querySelector("[data-filter-empty]")?.textContent).toBe("筛选控件加载失败");

  state.archiveInit.mockImplementationOnce(() => { throw new Error("Module failed"); });
  navigate('<main data-filter-page data-module-unavailable="归档控件加载失败"><a href="/article/">Article</a></main>');
  await vi.dynamicImportSettled();
  expect(document.querySelector('[role="status"]')?.textContent).toBe('归档控件加载失败');
  expect(document.querySelector('a')?.getAttribute('href')).toBe('/article/');
  navigate("");
});
