import type { ArchiveCard } from "./archive-query";
import { FAVORITES_CHANGE, favoritesKey, readFavorites, toggleFavorite } from "./favorites-store";

export function favoritesUI(): DOMStringMap {
  return document.querySelector<HTMLElement>("[data-favorites-ui]")?.dataset || {};
}
export function showFavoriteError(): void {
  const status = document.querySelector<HTMLElement>("[data-favorite-status]");
  if (status) status.textContent = favoritesUI().error || "Could not save favorites. Allow browser storage or free some space, then retry.";
}
export function favoriteButton(card: ArchiveCard): HTMLButtonElement {
  const button = document.createElement("button"); button.type = "button"; button.className = "favorite-button";
  button.setAttribute("aria-pressed", "false");
  button.dataset.favoriteToggle = ""; button.dataset.favoriteId = card.id; button.dataset.favoriteCard = JSON.stringify(card);
  button.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M5 3h10v14l-5-3-5 3z"></path></svg><span data-favorite-label></span>';
  return button;
}
export function refreshFavoriteButtons(): void {
  if (!document.querySelector("[data-favorites-ui]")) return;
  let selected: Set<string>;
  try { selected = new Set(readFavorites().keys()); }
  catch {
    showFavoriteError();
    for (const button of document.querySelectorAll<HTMLButtonElement>("[data-favorite-toggle]")) button.hidden = false;
    return;
  }
  const ui = favoritesUI();
  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-favorite-toggle]")) {
    const active = selected.has(button.dataset.favoriteId!), card = JSON.parse(button.dataset.favoriteCard!) as ArchiveCard;
    button.hidden = false; button.setAttribute("aria-pressed", String(active));
    button.setAttribute("aria-label", `${active ? ui.remove || "Remove favorite" : ui.save || "Save"}: ${card.title}`);
    button.querySelector<HTMLElement>("[data-favorite-label]")!.textContent = active ? ui.saved || "Saved" : ui.save || "Save";
  }
}
export function initialiseFavorites(): () => void {
  if (!document.querySelector("[data-favorites-ui]")) return () => {};
  const click = (event: MouseEvent) => {
    const button = event.target instanceof Element ? event.target.closest<HTMLButtonElement>("[data-favorite-toggle]") : null;
    if (!button) return;
    try {
      const card = JSON.parse(button.dataset.favoriteCard!) as ArchiveCard;
      if (!card.favorite_labels) {
        const labels = JSON.parse(favoritesUI().labels || "null") as Record<string, string> | null;
        const prefixes = JSON.parse(favoritesUI().prefixes || "null") as Record<string, string> | null;
        card.favorite_labels = Object.fromEntries(Object.entries(card.facets).flatMap(([name, ids]) => ids.map(id => [name + "/" + id, labels?.[(prefixes?.[name] || name + "/") + id] || id])));
      }
      toggleFavorite(card);
      const status = document.querySelector<HTMLElement>("[data-favorite-status]"); if (status) status.textContent = "";
    } catch { showFavoriteError(); }
  };
  const storage = (event: StorageEvent) => {
    if (event.key === null || event.key === favoritesKey()) window.dispatchEvent(new Event(FAVORITES_CHANGE));
  };
  refreshFavoriteButtons();
  document.addEventListener("click", click); window.addEventListener(FAVORITES_CHANGE, refreshFavoriteButtons);
  window.addEventListener("storage", storage); window.addEventListener("pageshow", refreshFavoriteButtons);
  return () => { document.removeEventListener("click", click); window.removeEventListener(FAVORITES_CHANGE, refreshFavoriteButtons); window.removeEventListener("storage", storage); window.removeEventListener("pageshow", refreshFavoriteButtons); };
}
