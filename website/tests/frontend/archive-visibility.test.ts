import { afterEach, expect, it } from "vitest";
import { archiveState, matchArchive, type ArchiveCollection } from "../../src/frontend/archive-query";
import { archiveView, syncArchiveVisibility, toggleArchiveVisibility, visibilityButtons, visibleArchiveOption, type VisibilityKey } from "../../src/frontend/archive-visibility";
import { favoriteManifest } from "../../src/frontend/favorite-archive";

const data: ArchiveCollection = {
  total: 5, page_size: 1, prefixes: { source: "source/", topic: "topics/" }, labels: {}, aliases: { "source/old": "source/arxiv" },
  years: { "2026": [0, 5] }, months: {}, days: { "2026-10-21": [0, 5] },
  hidden_tags: ["topics/research"], tab_sources: ["arxiv", "podcast"],
  facets: { source: [{ id: "news", name: "News", count: 3 }, { id: "arxiv", name: "arXiv", count: 2 }],
    topic: [{ id: "research", name: "Research", count: 4 }] },
  default_view: { total: 3, facets: { source: { news: 3 }, topic: { research: 2 } }, years: { "2026": 3 }, months: {}, days: { "2026-10-21": 3 } }
};
const bitmaps = { "$tab_sources": new Uint8Array([0b01010]), "source/arxiv": new Uint8Array([0b01010]), "source/news": new Uint8Array([0b10101]), "topic/research": new Uint8Array([0b01111]) };
afterEach(() => { document.body.innerHTML = ""; });

it("discloses hidden choices independently for each facet without changing the query", () => {
  const policy = { ...data, hidden_tags: ["source/news", "topics/research"] };
  const parameters = new URLSearchParams("day=2026-10-21&page=2");
  const toggle = (name: string) => toggleArchiveVisibility(parameters,
    visibilityButtons(policy, parameters, name).at(-1)!.dataset.archiveVisibility as VisibilityKey, policy, name);
  toggle("source");
  expect(visibleArchiveOption(policy, parameters, "source", "news")).toBe(true);
  expect(visibleArchiveOption(policy, parameters, "topic", "research")).toBe(false);
  expect(visibilityButtons(policy, parameters, "topic")[0]!.getAttribute("aria-expanded")).toBe("false");
  toggle("topic");
  toggle("source");
  expect(visibleArchiveOption(policy, parameters, "source", "news")).toBe(false);
  expect(visibleArchiveOption(policy, parameters, "topic", "research")).toBe(true);
  expect(parameters.getAll("show_hidden")).toEqual(["topic"]);
  expect(archiveState(policy, parameters.toString()).query).toEqual(archiveState(policy, "day=2026-10-21&page=2").query);
});

it("canonicalizes known disclosure facets, including custom facets, without duplicating them", () => {
  const policy = { ...data, prefixes: { ...data.prefixes, region: "regions/" }, facets: { ...data.facets, region: [] } };
  const state = archiveState(policy, "show_hidden=topic&show_hidden=source&show_hidden=topic&show_hidden=region&show_hidden=unknown");
  expect(state.parameters.getAll("show_hidden")).toEqual(["region", "source", "topic"]);
});

it("excludes tab sources across page, export and first queries without losing historical postings", () => {
  const state = archiveState(data, "?topic=research&page=9");
  expect(state.keys).toEqual(["topic/research", "$tab_sources"]);
  expect(matchArchive(5, 1, state.query, bitmaps)).toEqual({ count: 2, pages: 2, page: 2, ordinals: [2] });
  expect(matchArchive(5, 1, state.query, bitmaps, "all").ordinals).toEqual([0, 2]);
  expect(matchArchive(5, 1, state.query, bitmaps, "first").ordinals).toEqual([0]);
  expect(matchArchive(5, 1, archiveState(data, "?include_tabs=1&topic=research").query, bitmaps, "all").count).toBe(4);
});

it("restores old source links and preserves hidden-topic selection, date, and disclosure state", () => {
  const state = archiveState(data, "?source=old&topic=research&day=2026-10-21&show_hidden=topic&page=2");
  expect(state.parameters.get("source")).toBe("arxiv");
  expect(state.parameters.get("include_tabs")).toBe("1");
  toggleArchiveVisibility(state.parameters, "show_hidden", data, "topic");
  expect(state.parameters.get("page")).toBe("2");
  expect(visibleArchiveOption(data, state.parameters, "topic", "research")).toBe(true);
  toggleArchiveVisibility(state.parameters, "include_tabs", data, "source");
  expect(state.parameters.toString()).toBe("topic=research&day=2026-10-21");
  expect(visibleArchiveOption(data, state.parameters, "source", "arxiv")).toBe(false);
  expect(visibleArchiveOption(data, new URLSearchParams(), "topic", "research")).toBe(false);
  expect(archiveView(data, state.parameters).total).toBe(3);
  expect(archiveView(data, new URLSearchParams("include_tabs=1")).total).toBe(5);
});

it("retains focused toggles, updates counts and leaves card labels alone", () => {
  document.body.innerHTML = `<main><nav class="archive-facet"><div class="archive-facet-heading"><h2 class="archive-facet-label">Topics</h2></div><ul><li><button data-archive-facet="topic" data-archive-value="research">Research <span>4</span></button></li></ul></nav><a class="card-label">Research</a></main>`;
  const root = document.querySelector("main")!;
  syncArchiveVisibility(root, data, new URLSearchParams());
  expect(root.querySelector("li")!.hidden).toBe(true);
  const toggle = root.querySelector<HTMLButtonElement>("[data-archive-visibility]")!; toggle.focus();
  syncArchiveVisibility(root, data, new URLSearchParams("show_hidden=topic&include_tabs=1"));
  expect(root.querySelector("li")!.hidden).toBe(false);
  expect(root.querySelector("li span")!.textContent).toBe("4");
  expect(document.activeElement).toBe(toggle);
  expect(toggle.getAttribute("aria-expanded")).toBe("true");
  expect(root.querySelectorAll("[data-archive-visibility]")).toHaveLength(1);
  expect(root.querySelectorAll(".archive-facet-heading")).toHaveLength(1);
  expect(root.querySelector(".card-label")!.textContent).toBe("Research");
});

it("offers hidden topics only when they exist in the current source scope or remain selected", () => {
  const excluded = { ...data, default_view: { ...data.default_view!, facets: { source: { news: 3 }, topic: {} } } };
  expect(visibilityButtons(excluded, new URLSearchParams(), "topic")).toEqual([]);
  expect(visibilityButtons(excluded, new URLSearchParams("show_hidden=topic"), "topic")).toEqual([]);
  for (const query of ["include_tabs=1", "topic=research"]) {
    expect(visibilityButtons(excluded, new URLSearchParams(query), "topic")[0]?.textContent).toBe("Show hidden topics");
  }
});

it("favorites retain hidden policy but never inherit homepage exclusions, including offline snapshots", () => {
  const favorites = favoriteManifest([], data);
  expect(favorites.hidden_tags).toEqual(data.hidden_tags);
  expect(favorites.tab_sources).toBeUndefined();
  expect(favorites.default_view).toBeUndefined();
  document.body.innerHTML = `<template data-archive-visibility-ui data-hidden-tags='["topics/research"]'></template>`;
  expect(favoriteManifest([]).hidden_tags).toEqual(data.hidden_tags);
});

function sourceRoot(): HTMLElement {
  document.body.innerHTML = `<main><nav class="archive-facet"><div class="archive-facet-heading"><h2>Sources</h2></div><ul><li><button data-archive-facet="source" data-archive-value="news">News <span>3</span></button></li></ul></nav></main>`;
  return document.querySelector("main")!;
}

it("offers independent controls for hidden source tags and tab sources", () => {
  const root = sourceRoot(), policy = { ...data, hidden_tags: ["source/news"] };
  syncArchiveVisibility(root, policy, new URLSearchParams());
  expect([...root.querySelectorAll<HTMLElement>("[data-archive-visibility]")].map(button => button.dataset.archiveVisibility)).toEqual(["include_tabs", "show_hidden"]);
  const toggle = root.querySelector('[data-archive-visibility="show_hidden"]')!;
  expect(toggle.textContent).toBe("Show hidden tags");
  expect(toggle.getAttribute("aria-controls")).toBe(root.querySelector("ul")!.id);
  syncArchiveVisibility(root, policy, new URLSearchParams("show_hidden=source"));
  expect(root.querySelector("li")!.hidden).toBe(false);
});

it("replaces the control when a new generation changes its purpose", () => {
  const root = sourceRoot(); syncArchiveVisibility(root, data, new URLSearchParams());
  const old = root.querySelector("[data-archive-visibility]");
  syncArchiveVisibility(root, { ...data, tab_sources: [], hidden_tags: ["source/news"] }, new URLSearchParams());
  const next = root.querySelector<HTMLElement>("[data-archive-visibility]")!;
  expect(next.dataset.archiveVisibility).toBe("show_hidden");
  expect(next).not.toBe(old);
});

it("collapses alias-expressed tab source selections", () => {
  for (const query of ["include_tabs=1&source=old&source=news&page=2", "source=old&source=news&page=2"]) {
    const parameters = new URLSearchParams(query);
    toggleArchiveVisibility(parameters, "include_tabs", data, "source");
    expect(archiveState(data, parameters.toString()).parameters.toString()).toBe("source=news");
  }
});

it("does not rewrite visibility DOM when only pagination changes", () => {
  const root = sourceRoot(); syncArchiveVisibility(root, data, new URLSearchParams());
  const observer = new MutationObserver(() => {}); observer.observe(root, { subtree: true, attributes: true, childList: true, characterData: true });
  syncArchiveVisibility(root, data, new URLSearchParams("page=2"));
  expect(observer.takeRecords()).toHaveLength(0); observer.disconnect();
});

it("ignores malformed offline display metadata", () => {
  for (const value of ["{bad", "{}", '[1]']) {
    document.body.innerHTML = `<template data-archive-visibility-ui></template>`;
    document.querySelector<HTMLElement>("template")!.dataset.hiddenTags = value;
    expect(favoriteManifest([]).hidden_tags).toEqual([]);
  }
});
