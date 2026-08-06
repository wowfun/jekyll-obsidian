import { COLOR_SCHEME_EVENT, preferredColorScheme, type ColorScheme } from "./color-scheme";

const WIDGET_ORIGIN = "https://platform.twitter.com";
const WIDGET_SCRIPT = `${WIDGET_ORIGIN}/widgets.js`;

type TweetOptions = {
  dnt: true;
  theme: ColorScheme;
};

type XWidgets = {
  widgets: {
    createTweet(id: string, target: HTMLElement, options: TweetOptions): Promise<HTMLElement | undefined>;
  };
};

declare global {
  interface Window {
    twttr?: XWidgets;
  }
}

let widgetPromise: Promise<XWidgets> | null = null;

function currentScheme(doc: Document): ColorScheme {
  const value = doc.documentElement.dataset.colorScheme;
  return value === "light" || value === "dark" ? value : preferredColorScheme();
}

function loadWidgets(doc: Document): Promise<XWidgets> {
  const view = doc.defaultView;
  if (view?.twttr?.widgets) return Promise.resolve(view.twttr);
  if (widgetPromise) return widgetPromise;

  widgetPromise = new Promise<XWidgets>((resolve, reject) => {
    const existing = doc.querySelector<HTMLScriptElement>("script[data-website-x-widgets]");
    const script = existing || doc.createElement("script");
    const fail = (message: string) => {
      script.remove();
      reject(new Error(message));
    };
    const ready = () => {
      const widgets = view?.twttr;
      if (widgets?.widgets) resolve(widgets);
      else fail("X widgets did not initialise");
    };
    script.addEventListener("load", ready, { once: true });
    script.addEventListener("error", () => fail("X widgets could not be loaded"), { once: true });
    if (!existing) {
      script.src = WIDGET_SCRIPT;
      script.async = true;
      script.dataset.websiteXWidgets = "";
      doc.head.append(script);
    }
  }).catch((error) => {
    widgetPromise = null;
    throw error;
  });
  return widgetPromise;
}

function initialiseTweet(section: HTMLElement, doc: Document): () => void {
  if (section.dataset.websiteTweetInitialised === "true") return () => undefined;
  section.dataset.websiteTweetInitialised = "true";
  const id = section.dataset.websiteTweet || "";
  const mount = section.querySelector<HTMLElement>("[data-website-tweet-mount]");
  const fallback = section.querySelector<HTMLElement>("[data-website-tweet-fallback]");
  if (!id || !/^\d+$/.test(id) || !mount || !fallback) {
    section.dataset.websiteTweetState = "unavailable";
    return () => undefined;
  }

  let disposed = false;
  let rendering = false;
  let pendingReplace = false;
  let ready = false;
  const render = async (replace = false) => {
    if (disposed) return;
    if (rendering) {
      pendingReplace ||= replace;
      return;
    }
    rendering = true;
    section.dataset.websiteTweetState = "loading";
    try {
      const provider = await loadWidgets(doc);
      if (disposed) return;
      if (replace) mount.replaceChildren();
      const widget = await provider.widgets.createTweet(id, mount, {
        dnt: true,
        theme: currentScheme(doc)
      });
      if (disposed || !widget) throw new Error("X post is unavailable");
      ready = true;
      fallback.hidden = true;
      section.dataset.websiteTweetState = "ready";
    } catch {
      if (!disposed) {
        fallback.hidden = false;
        section.dataset.websiteTweetState = "unavailable";
      }
    } finally {
      rendering = false;
      if (pendingReplace && !disposed) {
        pendingReplace = false;
        void render(true);
      }
    }
  };

  const onScheme = () => {
    if (rendering) {
      pendingReplace = true;
    } else if (ready) {
      void render(true);
    }
  };
  doc.addEventListener(COLOR_SCHEME_EVENT, onScheme);

  let observer: IntersectionObserver | null = null;
  const view = doc.defaultView;
  if (view && "IntersectionObserver" in view) {
    observer = new view.IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      observer?.disconnect();
      void render();
    }, { rootMargin: "400px 0px" });
    observer.observe(section);
  } else {
    void render();
  }

  return () => {
    disposed = true;
    observer?.disconnect();
    doc.removeEventListener(COLOR_SCHEME_EVENT, onScheme);
  };
}

export function initialiseTweets(doc: Document = document): () => void {
  const cleanups = Array.from(doc.querySelectorAll<HTMLElement>("[data-website-tweet]"))
    .map((section) => initialiseTweet(section, doc));
  return () => cleanups.forEach((cleanup) => cleanup());
}

export function resetTweetLoaderForTests(): void {
  widgetPromise = null;
}
