/** Expiring recommendations must remain correct even when the static build is old. */
export function initialiseRecommendations(): () => void {
  const containers = [...document.querySelectorAll<HTMLElement>("[data-recommendations]")];
  let timer: ReturnType<typeof setTimeout> | undefined;
  const refresh = () => {
    clearTimeout(timer);
    const now = Date.now();
    let next = Infinity;
    for (const container of containers) {
      for (const card of container.querySelectorAll<HTMLElement>("[data-recommendation-expires-at]")) {
        const expires = Date.parse(card.dataset.recommendationExpiresAt ?? "");
        if (!Number.isFinite(expires) || expires <= now) card.remove();
        else next = Math.min(next, expires);
      }
      container.hidden = !container.querySelector("[data-recommendation-expires-at]");
    }
    if (Number.isFinite(next)) timer = setTimeout(refresh, Math.min(next - now, 2_147_483_647));
  };
  refresh();
  document.addEventListener("visibilitychange", refresh);
  window.addEventListener("pageshow", refresh);
  return () => {
    clearTimeout(timer);
    document.removeEventListener("visibilitychange", refresh);
    window.removeEventListener("pageshow", refresh);
  };
}
