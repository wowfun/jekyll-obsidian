import { beforeEach, describe, expect, it, vi } from "vitest";
import { initialisePreviews } from "../../src/frontend/preview";

describe("note previews", () => {
  beforeEach(() => {
    document.head.replaceChildren();
    document.body.replaceChildren();
    document.head.insertAdjacentHTML(
      "beforeend",
      '<meta name="obsidian:preview" content="/base/assets/obsidian/catalog.v1.json">'
    );
  });

  it("renders catalog prose through textContent instead of HTML", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response(
          JSON.stringify({
            schema_version: 1,
            notes: [
              {
                id: "safe.md",
                title: "<img src=x onerror=alert(1)>",
                url: "/base/safe/",
                aliases: [],
                tags: ["security"],
                description: null,
                preview: "<script>not markup</script>",
                updated: null,
                content_type: "page",
                published_at: null
              }
            ]
          }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        )
      )
    );
    const anchor = document.createElement("a");
    anchor.className = "obsidian-link";
    anchor.dataset.noteId = "safe.md";
    document.body.append(anchor);
    initialisePreviews();

    anchor.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));

    await vi.waitFor(() => expect(document.querySelector("[data-note-preview]")).not.toBeNull());
    const preview = document.querySelector<HTMLElement>("[data-note-preview]")!;
    expect(preview.textContent).toContain("<img src=x onerror=alert(1)>");
    expect(preview.textContent).toContain("<script>not markup</script>");
    expect(preview.querySelector("img, script")).toBeNull();
  });
});
