import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { initialiseComments } from "../../src/frontend/comments";
import { COLOR_SCHEME_EVENT } from "../../src/frontend/color-scheme";

function installComments(): HTMLElement {
  document.body.innerHTML = `
    <section
      data-website-comments-load
      data-website-comments-repository="example/community"
      data-website-comments-repository-id="R_kgDOExample"
      data-website-comments-category="Blog comments"
      data-website-comments-category-id="DIC_kwDOExample"
      data-website-comments-term="website:post:blog/post"
      data-website-comments-language="en"
      data-website-comments-unavailable="Comments unavailable."
    >
      <p data-website-comments-status>Loading comments…</p>
      <div class="giscus" data-website-comments-container></div>
      <a href="https://github.com/example/community/discussions">Open discussions on GitHub</a>
    </section>`;
  return document.querySelector<HTMLElement>("[data-website-comments-load]")!;
}

function captureClient(section: HTMLElement): () => HTMLScriptElement {
  let client: HTMLScriptElement | undefined;
  const container = section.querySelector<HTMLElement>("[data-website-comments-container]")!;
  vi.spyOn(container, "append").mockImplementation((...nodes: (Node | string)[]) => {
    client = nodes[0] as HTMLScriptElement;
  });
  return () => client!;
}

describe("GitHub Discussions comments", () => {
  beforeEach(() => {
    document.documentElement.dataset.colorScheme = "dark";
    document.body.replaceChildren();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("creates one strictly configured lazy Giscus client", () => {
    const section = installComments();
    const capturedClient = captureClient(section);
    initialiseComments();
    initialiseComments();

    const script = capturedClient();
    expect(script.src).toBe("https://giscus.app/client.js");
    expect(script.async).toBe(true);
    expect(script.crossOrigin).toBe("anonymous");
    expect(script.dataset).toMatchObject({
      repo: "example/community",
      repoId: "R_kgDOExample",
      category: "Blog comments",
      categoryId: "DIC_kwDOExample",
      mapping: "specific",
      term: "website:post:blog/post",
      strict: "1",
      reactionsEnabled: "1",
      emitMetadata: "0",
      inputPosition: "top",
      theme: "dark",
      lang: "en",
      loading: "lazy"
    });
    expect(section.dataset.websiteCommentsState).toBe("loading");
  });

  it("keeps pre-iframe and mounted Giscus themes in sync", async () => {
    const section = installComments();
    const capturedClient = captureClient(section);
    const cleanup = initialiseComments();
    const script = capturedClient();

    document.documentElement.dataset.colorScheme = "light";
    document.dispatchEvent(new CustomEvent(COLOR_SCHEME_EVENT, { detail: { scheme: "light" } }));
    expect(script.dataset.theme).toBe("light");

    const frame = document.createElement("iframe");
    frame.className = "giscus-frame";
    section.querySelector("[data-website-comments-container]")!.appendChild(frame);
    const postMessage = vi.spyOn(frame.contentWindow!, "postMessage").mockImplementation(() => undefined);

    await vi.waitFor(() => {
      expect(postMessage).toHaveBeenCalledWith(
        { giscus: { setConfig: { theme: "light" } } },
        "https://giscus.app"
      );
    });
    cleanup();
  });

  it("keeps empty discussions usable and degrades when GitHub setup is unavailable", () => {
    const section = installComments();
    const capturedClient = captureClient(section);
    initialiseComments();
    const script = capturedClient();
    const status = section.querySelector<HTMLElement>("[data-website-comments-status]")!;

    window.dispatchEvent(new MessageEvent("message", {
      origin: "https://attacker.example",
      data: { giscus: { error: "forged" } }
    }));
    expect(section.dataset.websiteCommentsState).toBe("loading");

    window.dispatchEvent(new MessageEvent("message", {
      origin: "https://giscus.app",
      data: { giscus: { error: "Discussion not found" } }
    }));
    expect(section.dataset.websiteCommentsState).toBe("loading");
    expect(status.textContent).toBe("Loading comments…");

    window.dispatchEvent(new MessageEvent("message", {
      origin: "https://giscus.app",
      data: { giscus: { error: "giscus is not installed on this repository" } }
    }));
    expect(section.dataset.websiteCommentsState).toBe("unavailable");
    expect(status.textContent).toBe("Comments unavailable.");
    expect(section.querySelector<HTMLAnchorElement>("a")?.href)
      .toBe("https://github.com/example/community/discussions");

    section.dataset.websiteCommentsState = "loading";
    window.dispatchEvent(new MessageEvent("message", {
      origin: "https://giscus.app",
      data: { giscus: { error: "Discussions are disabled for this repository" } }
    }));
    expect(section.dataset.websiteCommentsState).toBe("unavailable");

    section.dataset.websiteCommentsState = "loading";
    script.dispatchEvent(new Event("error"));
    expect(section.dataset.websiteCommentsState).toBe("unavailable");
  });

  it("does not load a client without a complete production hook", () => {
    initialiseComments();
    expect(document.querySelector("script[src='https://giscus.app/client.js']")).toBeNull();

    const section = installComments();
    section.removeAttribute("data-website-comments-category-id");
    initialiseComments();
    expect(section.querySelector("script")).toBeNull();
    expect(section.dataset.websiteCommentsState).toBe("unavailable");
  });
});
