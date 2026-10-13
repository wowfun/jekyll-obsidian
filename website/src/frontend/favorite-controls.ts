import type { ArchiveCard } from "./archive-query";
import { FAVORITES_CHANGE, favoriteCard, favoritesDamaged, FavoritesStorageError, favoritesKey, readFavorites, toggleFavorite } from "./favorites-store";

const buttonCards = new WeakMap<HTMLButtonElement, { raw: string; card: ArchiveCard }>();
const pendingButtons = new WeakSet<HTMLButtonElement>();
function buttonCard(button: HTMLButtonElement): ArchiveCard {
  const raw = button.dataset.favoriteCard || "", cached = buttonCards.get(button);
  if (cached?.raw === raw) return cached.card;
  const card = favoriteCard(JSON.parse(raw));
  if (card.id !== button.dataset.favoriteId) throw new Error("Invalid favorite button");
  buttonCards.set(button, { raw, card }); return card;
}

export function favoritesUI(): DOMStringMap {
  return document.querySelector<HTMLElement>("[data-favorites-ui]")?.dataset || {};
}
export function showFavoriteError(error?: unknown): void {
  const status = document.querySelector<HTMLElement>("[data-favorite-status]");
  const ui = favoritesUI();
  const reason = error instanceof FavoritesStorageError ? error.code : error instanceof Error ? error.name : "";
  const messages: Record<string, string> = {
    damaged: ui.damaged || "Some saved data is damaged. Healthy favorites are shown; original data is backed up before repair.",
    unreadable: ui.unreadable || "Could not read favorites. The stored data is damaged; original data has been kept.",
    unsupported: ui.unsupported || "Could not save favorites. Use a current browser over HTTPS or localhost.",
    QuotaExceededError: ui.quota || "Could not save favorites. Browser storage is full; free some space and retry.",
    SecurityError: ui.blocked || "Could not save favorites. Allow browser storage and retry."
  };
  if (status) status.textContent = messages[reason] || ui.error || "Could not save favorites. Allow browser storage or free some space, then retry.";
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
  catch (error) {
    showFavoriteError(error);
    for (const button of document.querySelectorAll<HTMLButtonElement>("[data-favorite-toggle]")) { button.hidden = false; button.disabled = pendingButtons.has(button); }
    return;
  }
  const ui = favoritesUI();
  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-favorite-toggle]")) {
    try {
      const active = selected.has(button.dataset.favoriteId!), card = buttonCard(button);
      button.disabled = pendingButtons.has(button);
      button.hidden = false; button.setAttribute("aria-pressed", String(active));
      button.setAttribute("aria-label", `${active ? ui.remove || "Remove favorite" : ui.save || "Save"}: ${card.title}`);
      const label = button.querySelector<HTMLElement>("[data-favorite-label]");
      if (label) label.textContent = active ? ui.saved || "Saved" : ui.save || "Save";
    } catch (error) { button.hidden = false; button.disabled = true; showFavoriteError(error); }
  }
  if (favoritesDamaged() && !document.querySelector("[data-favorite-status]")?.textContent) showFavoriteError(new FavoritesStorageError("damaged"));
}
export function initialiseFavorites(): () => void {
  if (!document.querySelector("[data-favorites-ui]")) return () => {};
  let taxonomy: { labels: Record<string, string>; prefixes: Record<string, string> } | undefined;
  const click = async (event: MouseEvent) => {
    const button = event.target instanceof Element ? event.target.closest<HTMLButtonElement>("[data-favorite-toggle]") : null;
    if (!button || button.disabled) return;
    pendingButtons.add(button); button.disabled = true;
    try {
      const card = { ...buttonCard(button) };
      if (!Object.keys(card.favorite_labels || {}).length) {
        const ui = favoritesUI();
        taxonomy ||= { labels: JSON.parse(ui.labels || "null") || {}, prefixes: JSON.parse(ui.prefixes || "null") || {} };
        card.favorite_labels = Object.fromEntries(Object.entries(card.facets).flatMap(([name, ids]) => ids.map(id => [name + "/" + id, taxonomy!.labels[(taxonomy!.prefixes[name] || name + "/") + id] || id])));
      }
      await toggleFavorite(card, document.documentElement.lang || "en", button.getAttribute("aria-pressed") !== "true");
      const status = document.querySelector<HTMLElement>("[data-favorite-status]"); if (status) status.textContent = "";
    } catch (error) { showFavoriteError(error); }
    finally { pendingButtons.delete(button); refreshFavoriteButtons(); }
  };
  const storage = (event: StorageEvent) => {
    if (event.key === null || event.key === favoritesKey()) window.dispatchEvent(new Event(FAVORITES_CHANGE));
  };
  refreshFavoriteButtons();
  document.addEventListener("click", click); window.addEventListener(FAVORITES_CHANGE, refreshFavoriteButtons);
  window.addEventListener("storage", storage); window.addEventListener("pageshow", refreshFavoriteButtons);
  return () => { document.removeEventListener("click", click); window.removeEventListener(FAVORITES_CHANGE, refreshFavoriteButtons); window.removeEventListener("storage", storage); window.removeEventListener("pageshow", refreshFavoriteButtons); };
}
