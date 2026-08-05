const root = document.documentElement;
let savedScheme: string | null = null;

try {
  savedScheme = localStorage.getItem("website:color-scheme");
} catch {
  savedScheme = null;
}

const scheme = savedScheme === "light" || savedScheme === "dark"
  ? savedScheme
  : matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";

root.dataset.colorScheme = scheme;
root.style.colorScheme = scheme;
