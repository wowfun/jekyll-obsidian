export type ColorScheme = "light" | "dark";

export const COLOR_SCHEME_STORAGE_KEY = "website:color-scheme";
export const COLOR_SCHEME_EVENT = "website:color-scheme-changed";

export function preferredColorScheme(
  storage: Pick<Storage, "getItem"> = localStorage,
  media: Pick<MediaQueryList, "matches"> = matchMedia("(prefers-color-scheme: dark)")
): ColorScheme {
  let saved: string | null = null;
  try {
    saved = storage.getItem(COLOR_SCHEME_STORAGE_KEY);
  } catch {
    saved = null;
  }
  if (saved === "light" || saved === "dark") return saved;
  return media.matches ? "dark" : "light";
}

export function applyColorScheme(
  scheme: ColorScheme,
  root: HTMLElement = document.documentElement
): void {
  root.dataset.colorScheme = scheme;
  root.style.colorScheme = scheme;
  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-color-scheme-toggle]")) {
    const next = scheme === "dark" ? "light" : "dark";
    button.setAttribute("aria-label", next === "dark"
      ? button.dataset.schemeUseDark || "Use dark color scheme"
      : button.dataset.schemeUseLight || "Use light color scheme");
    button.setAttribute("aria-pressed", String(scheme === "dark"));
    const label = button.querySelector<HTMLElement>("[data-color-scheme-label]");
    if (label) label.textContent = next === "dark"
      ? button.dataset.schemeDark || "Dark"
      : button.dataset.schemeLight || "Light";
  }
  document.dispatchEvent(new CustomEvent(COLOR_SCHEME_EVENT, { detail: { scheme } }));
}

export function initialiseColorScheme(): () => void {
  let scheme = preferredColorScheme();
  applyColorScheme(scheme);

  const toggle = () => {
    scheme = scheme === "dark" ? "light" : "dark";
    try {
      localStorage.setItem(COLOR_SCHEME_STORAGE_KEY, scheme);
    } catch {
      // A blocked storage backend must not disable the visible theme control.
    }
    applyColorScheme(scheme);
  };

  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-color-scheme-toggle]")) {
    button.addEventListener("click", toggle);
  }
  return toggle;
}
