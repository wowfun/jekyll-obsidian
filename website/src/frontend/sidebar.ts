import { closeWebsiteDialog } from "./dialogs";

const sidebarController = Symbol.for("jekyll-obsidian.sidebar-controller");
type ControlledDocument = Document & { [sidebarController]?: () => void };

export function initialiseSidebar(): void {
  const controlled = document as ControlledDocument;
  controlled[sidebarController]?.();
  if (document.body.dataset.navigationLayout !== "sidebar") return;
  const dialog = document.querySelector<HTMLDialogElement>('.website-dialog--navigation');
  if (!dialog) return;
  // Keep aligned with the desktop topbar breakpoint in sidebar.css.
  const desktop = window.matchMedia("(min-width: 1081px)");
  const scroller = document.querySelector<HTMLElement>(".site-sidebar__navigation");
  let scrollTop = scroller?.scrollTop ?? 0;
  const rememberScroll = () => {
    if (scroller?.getClientRects().length) scrollTop = scroller.scrollTop;
  };
  const restoreScroll = () => {
    if (scroller) scroller.scrollTop = scrollTop;
  };
  // Capture before close hides the drawer; moving into a hidden parent resets scroll.
  const beforeToggle = (event: ToggleEvent) => {
    if (event.newState === "closed") rememberScroll();
  };
  const toggle = () => { if (dialog.open) restoreScroll(); };
  const desktopScroll = () => { if (desktop.matches && !dialog.open) rememberScroll(); };
  const resize = () => {
    if (!desktop.matches) return;
    const wasOpen = dialog.open;
    closeWebsiteDialog("browse");
    restoreScroll();
    if (wasOpen) document.querySelector<HTMLElement>('[data-site-navigation] a[aria-current="page"], [data-site-navigation] a')?.focus();
  };
  // Chromium can move Tab focus into browser chrome at a native dialog boundary.
  const keepFocus = (event: KeyboardEvent) => {
    if (event.key !== "Tab" || !dialog.open) return;
    const controls = [...dialog.querySelectorAll<HTMLElement>('a[href], button:not([disabled]), summary, [tabindex]')]
      .filter(node => node.tabIndex >= 0 && node.getClientRects().length > 0);
    const first = controls[0], last = controls.at(-1);
    if (!first || !last) return;
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  };
  desktop.addEventListener("change", resize);
  scroller?.addEventListener("scroll", desktopScroll, { passive: true });
  dialog.addEventListener("beforetoggle", beforeToggle);
  dialog.addEventListener("toggle", toggle);
  dialog.addEventListener("keydown", keepFocus);
  const cleanup = () => {
    desktop.removeEventListener("change", resize);
    scroller?.removeEventListener("scroll", desktopScroll);
    dialog.removeEventListener("beforetoggle", beforeToggle);
    dialog.removeEventListener("toggle", toggle);
    dialog.removeEventListener("keydown", keepFocus);
    if (controlled[sidebarController] === cleanup) delete controlled[sidebarController];
  };
  controlled[sidebarController] = cleanup;
}
