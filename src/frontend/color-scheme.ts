export type ColorScheme = "light" | "dark";

export const COLOR_SCHEME_STORAGE_KEY = "jekyll-obsidian:color-scheme";

export function preferredColorScheme(
  storage: Pick<Storage, "getItem"> = localStorage,
  media: Pick<MediaQueryList, "matches"> = matchMedia("(prefers-color-scheme: dark)")
): ColorScheme {
  const saved = storage.getItem(COLOR_SCHEME_STORAGE_KEY);
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
    button.setAttribute("aria-label", `Use ${next} color scheme`);
    button.setAttribute("aria-pressed", String(scheme === "dark"));
    const label = button.querySelector<HTMLElement>("[data-color-scheme-label]");
    if (label) label.textContent = next === "dark" ? "Dark" : "Light";
  }
}

export function initialiseColorScheme(): () => void {
  let scheme = preferredColorScheme();
  applyColorScheme(scheme);

  const toggle = () => {
    scheme = scheme === "dark" ? "light" : "dark";
    localStorage.setItem(COLOR_SCHEME_STORAGE_KEY, scheme);
    applyColorScheme(scheme);
  };

  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-color-scheme-toggle]")) {
    button.addEventListener("click", toggle);
  }
  return toggle;
}
