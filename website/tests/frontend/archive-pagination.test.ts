import { beforeEach, expect, it } from "vitest";
import { pageWindow, renderArchivePagination } from "../../src/frontend/archive-pagination";

beforeEach(() => {
  history.replaceState(null, "", "/garden/?source=hn&topic=agents&day=2026-10-10&page=4");
  document.body.innerHTML = '<nav data-archive-pagination><button data-archive-page="prev"></button><span data-archive-page-status></span><div data-archive-page-numbers></div><form data-archive-page-jump><input type="number"></form><button data-archive-page="next"></button></nav>';
});

it("centers a five-page window and fills it at each boundary", () => {
  expect(pageWindow(1, 30)).toEqual([1, 2, 3, 4, 5]);
  expect(pageWindow(15, 30)).toEqual([13, 14, 15, 16, 17]);
  expect(pageWindow(30, 30)).toEqual([26, 27, 28, 29, 30]);
  expect(pageWindow(3, 4)).toEqual([1, 2, 3, 4]);
  expect(pageWindow(1, 1)).toEqual([1]);
});

it("renders real links retaining every selected filter and marks the current page", () => {
  const root = document.querySelector<HTMLElement>("nav")!;
  renderArchivePagination(root, 4, 30, 60);
  expect([...root.querySelectorAll("a")].map(link => link.textContent)).toEqual(["2", "3", "4", "5", "6"]);
  expect(root.querySelector('a[aria-current="page"]')!.textContent).toBe("4");
  expect(root.querySelector<HTMLAnchorElement>('a[data-archive-page="6"]')!.getAttribute("href")).toBe("/garden/?source=hn&topic=agents&day=2026-10-10&page=6");
  expect(root.querySelector<HTMLInputElement>("input")!.max).toBe("30");
  expect(root.querySelector<HTMLInputElement>("input")!.value).toBe("4");
  renderArchivePagination(root, 1, 1, 0);
  expect(root.querySelector<HTMLElement>("[data-archive-page-numbers]")!.hidden).toBe(true);
  expect(root.querySelector<HTMLFormElement>("form")!.hidden).toBe(true);
  expect(root.querySelector<HTMLInputElement>("input")!.disabled).toBe(true);
});
