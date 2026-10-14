import type { ArchiveCard } from "./archive-query";
import { FAVORITES_CHANGE, FAVORITES_RECOVERY_CHANGE, favoriteCard, favoriteRecoveryCopies, hasFavoriteRecovery, clearFavoriteRecovery, restoreFavoriteRecovery, favoritesDamaged, FavoritesStorageError, favoritesKey, readFavoriteCollection, toggleFavorite } from "./favorites-store";

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
    recovery_required: ui.recoveryRequired || "A recovery copy is already saved. Download and clear it before repairing more data.",
    unsupported: ui.unsupported || "Could not save favorites. Use a current browser over HTTPS or localhost.",
    QuotaExceededError: ui.quota || "Could not save favorites. Browser storage is full; free some space and retry.",
    SecurityError: ui.blocked || "Could not save favorites. Allow browser storage and retry."
  };
  if (status) status.textContent = messages[reason] || ui.error || "Could not save favorites. Allow browser storage or free some space, then retry.";
}
export function favoriteButton(card: ArchiveCard): HTMLButtonElement {
  const button = document.createElement("button"); button.type = "button"; button.className = "favorite-button";
  button.setAttribute("aria-pressed", "false");
  button.dataset.favoriteToggle = ""; button.dataset.favoriteId = card.id;
  // Browser-rendered cards already crossed the archive/storage boundary. SSR
  // buttons still parse and validate their serialized snapshot on first use.
  buttonCards.set(button, { raw: "", card });
  button.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M5 3h10v14l-5-3-5 3z"></path></svg><span data-favorite-label></span>';
  return button;
}
export function refreshFavoriteButtons(selection?: ReadonlySet<string>): void {
  if (!document.querySelector("[data-favorites-ui]")) return;
  let selected: ReadonlySet<string>;
  try { selected = selection || new Set(readFavoriteCollection().entries.keys()); }
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
  const recovery = document.querySelector<HTMLElement>("[data-favorites-recovery]");
  const refreshRecovery = () => {
    if (!recovery) return;
    try { recovery.hidden = !hasFavoriteRecovery(); } catch (error) { showFavoriteError(error); }
  };
  const onChange = () => {
    if (!document.querySelector("[data-favorites-page]")) refreshFavoriteButtons();
    refreshRecovery();
  };
  const click = async (event: MouseEvent) => {
    const action = event.target instanceof Element ? event.target.closest<HTMLButtonElement>("[data-favorite-recovery]") : null;
    if (action && !action.disabled) {
      action.disabled = true;
      try {
        if (action.dataset.favoriteRecovery === "download") {
          const url = URL.createObjectURL(new Blob([JSON.stringify({ version: 1, scope: favoritesKey(), copies: favoriteRecoveryCopies() }, null, 2)], { type: "application/json" }));
          const link = document.createElement("a"); link.href = url; link.download = "favorites-recovery.json"; link.click();
          setTimeout(() => URL.revokeObjectURL(url), 1000);
        } else if (action.dataset.favoriteRecovery === "restore") await restoreFavoriteRecovery();
        else await clearFavoriteRecovery();
        const status = document.querySelector<HTMLElement>("[data-favorite-status]");
        if (status && action.dataset.favoriteRecovery !== "download") status.textContent = action.dataset.favoriteRecovery === "restore" ? favoritesUI().recoveryRestored || "Available favorites restored. Original recovery copies are kept." : favoritesUI().recoveryCleared || "Recovery copies cleared. Current favorites are kept.";
      } catch (error) { showFavoriteError(error); }
      finally { action.disabled = false; refreshRecovery(); }
      return;
    }
    const button = event.target instanceof Element ? event.target.closest<HTMLButtonElement>("[data-favorite-toggle]") : null;
    if (!button || button.disabled) return;
    pendingButtons.add(button); button.disabled = true;
    try {
      const card = buttonCard(button);
      await toggleFavorite(card, document.documentElement.lang || "en", button.getAttribute("aria-pressed") !== "true");
      const status = document.querySelector<HTMLElement>("[data-favorite-status]"); if (status) status.textContent = "";
    } catch (error) { showFavoriteError(error); }
    finally { pendingButtons.delete(button); button.disabled = false; }
  };
  const storage = (event: StorageEvent) => {
    if (event.key === null || event.key === favoritesKey()) window.dispatchEvent(new Event(FAVORITES_CHANGE));
    if (event.key === null || event.key?.startsWith(favoritesKey() + ":recovery:")) refreshRecovery();
  };
  refreshFavoriteButtons(); refreshRecovery();
  document.addEventListener("click", click); window.addEventListener(FAVORITES_CHANGE, onChange); window.addEventListener(FAVORITES_RECOVERY_CHANGE, refreshRecovery);
  window.addEventListener("storage", storage); window.addEventListener("pageshow", onChange);
  return () => { document.removeEventListener("click", click); window.removeEventListener(FAVORITES_CHANGE, onChange); window.removeEventListener(FAVORITES_RECOVERY_CHANGE, refreshRecovery); window.removeEventListener("storage", storage); window.removeEventListener("pageshow", onChange); };
}
