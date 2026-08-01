import { beforeEach, describe, expect, it, vi } from "vitest";
import { activateSearch } from "../../src/frontend/search";

describe("Obsidian search", () => {
  beforeEach(() => {
    document.head.replaceChildren();
    document.body.replaceChildren();
    document.head.insertAdjacentHTML(
      "beforeend",
      '<meta name="obsidian:search" content="/project/assets/obsidian/search.v1.json">'
    );
  });

  it("finds CJK notes through the stable unigram/bigram index", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response(
          JSON.stringify({
            schema_version: 1,
            documents: [
              {
                id: "zh.md",
                title: "知识花园",
                url: "/project/zh/",
                aliases: ["数字花园"],
                tags: ["中文"],
                text: "这是支持中文搜索的公开笔记。"
              }
            ]
          }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        )
      )
    );
    document.body.insertAdjacentHTML(
      "beforeend",
      `<dialog><input data-search-input><p data-search-status></p><ol data-search-results></ol></dialog>`
    );
    const dialog = document.querySelector<HTMLDialogElement>("dialog")!;
    await activateSearch(dialog);
    const input = dialog.querySelector<HTMLInputElement>("input")!;

    input.value = "花园";
    input.dispatchEvent(new InputEvent("input", { bubbles: true }));

    expect(dialog.querySelector("[data-search-status]")?.textContent).toMatch(/1 note/);
    expect(dialog.querySelector<HTMLAnchorElement>("a")?.href).toContain("/project/zh/");
    expect(dialog.querySelector("a")?.textContent).toContain("知识花园");
  });
});
