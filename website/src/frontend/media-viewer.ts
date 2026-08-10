import { closeWebsiteDialog, openWebsiteDialog } from "./dialogs";

const MEDIA_ZOOM_MIN = 0.5;
const MEDIA_ZOOM_MAX = 3;
const MEDIA_ZOOM_STEP = 0.25;
const initialisedDialogs = new WeakSet<HTMLDialogElement>();
const dialogOpeners = new WeakMap<HTMLDialogElement, HTMLElement>();
let imageLabelSequence = 0;
let mediaCloneSequence = 0;

type ImageAttributes = Record<
  "role" | "tabindex" | "aria-label" | "aria-labelledby" | "title" | "lang" | "dir",
  string | null
>;

const originalImageAttributes = new WeakMap<HTMLImageElement, ImageAttributes>();

type MediaKind = "image" | "mermaid";

type OpenMedia = {
  source: HTMLElement | SVGSVGElement;
  opener: HTMLElement;
  kind: MediaKind;
  title: string;
  closeLabel: string;
  lang?: string;
  dir?: string;
};

function dialogElement(): HTMLDialogElement | null {
  return document.querySelector<HTMLDialogElement>('dialog[data-dialog="media"]');
}

function canvasElement(dialog: HTMLDialogElement): HTMLElement | null {
  return dialog.querySelector<HTMLElement>("[data-media-dialog-canvas]");
}

function mediaZoom(canvas: HTMLElement): number {
  const value = Number(canvas.dataset.mediaZoom);
  return Number.isFinite(value) ? value : 1;
}

function mediaContent(canvas: HTMLElement): HTMLElement | SVGSVGElement | null {
  return canvas.querySelector<HTMLElement | SVGSVGElement>(":scope > img, :scope > picture, :scope > svg");
}

function updatePanAffordance(viewport: HTMLElement): void {
  viewport.toggleAttribute(
    "data-media-pannable",
    viewport.scrollWidth > viewport.clientWidth || viewport.scrollHeight > viewport.clientHeight
  );
}

function setMediaZoom(dialog: HTMLDialogElement, requested: number): void {
  const canvas = canvasElement(dialog);
  if (!canvas) return;
  const zoom = Math.max(MEDIA_ZOOM_MIN, Math.min(MEDIA_ZOOM_MAX, requested));
  canvas.dataset.mediaZoom = String(zoom);
  canvas.style.inlineSize = `${zoom * 100}%`;
  const percent = String(Math.round(zoom * 100));
  const status = dialog.querySelector<HTMLOutputElement>("[data-media-zoom-status]");
  if (status) {
    status.textContent = (dialog.dataset.mediaZoomLevel || "Zoom: {percent}%")
      .replace("{percent}", percent);
  }
  const zoomIn = dialog.querySelector<HTMLButtonElement>("[data-media-zoom-in]");
  const zoomOut = dialog.querySelector<HTMLButtonElement>("[data-media-zoom-out]");
  if (zoomIn) zoomIn.disabled = zoom >= MEDIA_ZOOM_MAX;
  if (zoomOut) zoomOut.disabled = zoom <= MEDIA_ZOOM_MIN;
  const viewport = canvas.closest<HTMLElement>("[data-media-dialog-viewport]");
  if (viewport) updatePanAffordance(viewport);
}

function wheelScale(event: WheelEvent): number | null {
  if (
    event.defaultPrevented ||
    !event.cancelable ||
    event.ctrlKey ||
    event.metaKey ||
    !Number.isFinite(event.deltaY) ||
    event.deltaY === 0
  ) return null;
  const unit = event.deltaMode === WheelEvent.DOM_DELTA_LINE
    ? 0.05
    : event.deltaMode === WheelEvent.DOM_DELTA_PAGE
      ? 1
      : 0.002;
  return 2 ** (-event.deltaY * unit);
}

function zoomFromWheel(dialog: HTMLDialogElement, viewport: HTMLElement, event: WheelEvent): void {
  const scale = wheelScale(event);
  const canvas = canvasElement(dialog);
  const content = canvas ? mediaContent(canvas) : null;
  if (scale === null || !canvas || !content) return;

  event.preventDefault();
  const before = content.getBoundingClientRect();
  const anchorX = before.width > 0
    ? Math.max(0, Math.min(1, (event.clientX - before.left) / before.width))
    : 0.5;
  const anchorY = before.height > 0
    ? Math.max(0, Math.min(1, (event.clientY - before.top) / before.height))
    : 0.5;
  const beforeX = before.left + (before.width * anchorX);
  const beforeY = before.top + (before.height * anchorY);

  setMediaZoom(dialog, mediaZoom(canvas) * scale);

  const after = content.getBoundingClientRect();
  const afterX = after.left + (after.width * anchorX);
  const afterY = after.top + (after.height * anchorY);
  viewport.scrollLeft += afterX - beforeX;
  viewport.scrollTop += afterY - beforeY;
  updatePanAffordance(viewport);
}

function prepareDialog(dialog: HTMLDialogElement): void {
  if (initialisedDialogs.has(dialog)) return;
  initialisedDialogs.add(dialog);
  const viewport = dialog.querySelector<HTMLElement>("[data-media-dialog-viewport]");
  let pan: {
    pointerId: number;
    clientX: number;
    clientY: number;
    scrollLeft: number;
    scrollTop: number;
  } | undefined;

  const stopPanning = (pointerId?: number): void => {
    if (!viewport || !pan || (pointerId !== undefined && pointerId !== pan.pointerId)) return;
    const activePointerId = pan.pointerId;
    pan = undefined;
    delete viewport.dataset.mediaPanning;
    if (viewport.hasPointerCapture(activePointerId)) viewport.releasePointerCapture(activePointerId);
  };

  viewport?.addEventListener("wheel", (event) => zoomFromWheel(dialog, viewport, event), {
    passive: false
  });
  viewport?.addEventListener("pointerdown", (event) => {
    const target = event.target;
    if (
      event.button !== 0 ||
      event.pointerType !== "mouse" ||
      !event.isPrimary ||
      !(target instanceof Element) ||
      !target.closest("[data-media-dialog-canvas]") ||
      Boolean(target.closest("a[href], button, input, select, textarea, summary, [contenteditable]")) ||
      !viewport.hasAttribute("data-media-pannable")
    ) return;
    pan = {
      pointerId: event.pointerId,
      clientX: event.clientX,
      clientY: event.clientY,
      scrollLeft: viewport.scrollLeft,
      scrollTop: viewport.scrollTop
    };
    viewport.setPointerCapture(event.pointerId);
    viewport.dataset.mediaPanning = "";
    event.preventDefault();
    viewport.focus({ preventScroll: true });
  });
  viewport?.addEventListener("pointermove", (event) => {
    if (!pan || event.pointerId !== pan.pointerId) return;
    viewport.scrollLeft = pan.scrollLeft - (event.clientX - pan.clientX);
    viewport.scrollTop = pan.scrollTop - (event.clientY - pan.clientY);
  });
  viewport?.addEventListener("pointerup", (event) => stopPanning(event.pointerId));
  viewport?.addEventListener("pointercancel", (event) => stopPanning(event.pointerId));
  viewport?.addEventListener("lostpointercapture", (event) => stopPanning(event.pointerId));
  dialog.addEventListener("close", () => {
    stopPanning();
    const opener = dialogOpeners.get(dialog);
    dialogOpeners.delete(dialog);
    canvasElement(dialog)?.replaceChildren();
    if (opener?.isConnected) opener.focus();
  });
}

function prepareClonedImage(source: HTMLImageElement, clone: HTMLImageElement): void {
  clone.removeAttribute("id");
  clone.removeAttribute("data-image-expand");
  clone.removeAttribute("data-image-viewer-ready");
  const attributes = originalImageAttributes.get(source);
  if (attributes) {
    for (const [name, value] of Object.entries(attributes)) {
      if (value === null) clone.removeAttribute(name);
      else clone.setAttribute(name, value);
    }
  }
  const labelledBy = attributes?.["aria-labelledby"] || source.getAttribute("aria-labelledby");
  if (labelledBy) {
    const description = imageDescription(source, attributes);
    clone.removeAttribute("aria-labelledby");
    if (description) clone.setAttribute("aria-label", description);
  }
  const authoredDescription = referencedText(source.getAttribute("aria-describedby"));
  clone.removeAttribute("aria-describedby");
  if (authoredDescription) clone.setAttribute("aria-description", authoredDescription);
  prepareResponsiveSource(clone);
  clone.draggable = false;
}

function highestDensityCandidate(srcset: string): string | null {
  const candidates: Array<{ url: string; density: number }> = [];
  let position = 0;

  while (position < srcset.length) {
    while (position < srcset.length && /[\t\n\f\r ,]/.test(srcset[position]!)) position += 1;
    if (position >= srcset.length) break;

    const urlStart = position;
    while (position < srcset.length && !/[\t\n\f\r ]/.test(srcset[position]!)) position += 1;
    let url = srcset.slice(urlStart, position);
    const descriptors: string[] = [];

    if (url.endsWith(",")) {
      url = url.replace(/,+$/, "");
    } else {
      while (position < srcset.length) {
        while (position < srcset.length && /[\t\n\f\r ]/.test(srcset[position]!)) position += 1;
        if (srcset[position] === ",") {
          position += 1;
          break;
        }
        if (position >= srcset.length) break;
        const descriptorStart = position;
        while (position < srcset.length && !/[\t\n\f\r ,]/.test(srcset[position]!)) position += 1;
        descriptors.push(srcset.slice(descriptorStart, position));
      }
    }

    if (!url) return null;
    if (descriptors.length === 0) {
      candidates.push({ url, density: 1 });
      continue;
    }
    if (descriptors.length !== 1) return null;
    if (!/^(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)x$/.test(descriptors[0]!)) return null;
    const density = Number.parseFloat(descriptors[0]!.slice(0, -1));
    if (!Number.isFinite(density) || density <= 0) return null;
    candidates.push({ url, density });
  }

  if (candidates.length === 0) return null;
  return candidates.reduce((largest, candidate) => (
    candidate.density > largest.density ? candidate : largest
  )).url;
}

function prepareResponsiveSource(source: HTMLImageElement | HTMLSourceElement): void {
  const srcset = source.getAttribute("srcset");
  if (!srcset) return;
  const highestDensity = highestDensityCandidate(srcset);
  if (highestDensity) {
    source.setAttribute("srcset", highestDensity);
    source.removeAttribute("sizes");
  } else {
    source.setAttribute("sizes", "300vw");
  }
}

function cloneImage(source: HTMLImageElement): HTMLImageElement | HTMLPictureElement {
  const picture = source.parentElement instanceof HTMLPictureElement ? source.parentElement : null;
  if (!picture) {
    const clone = source.cloneNode(true) as HTMLImageElement;
    prepareClonedImage(source, clone);
    return clone;
  }

  const clone = picture.cloneNode(true) as HTMLPictureElement;
  clone.removeAttribute("id");
  for (const element of clone.querySelectorAll<HTMLElement>("[id]")) element.removeAttribute("id");
  for (const candidate of clone.querySelectorAll<HTMLSourceElement>("source[srcset]")) {
    prepareResponsiveSource(candidate);
  }
  const clonedImage = clone.querySelector<HTMLImageElement>("img");
  if (clonedImage) prepareClonedImage(source, clonedImage);
  return clone;
}

function safeClone(source: HTMLElement | SVGSVGElement): HTMLElement | SVGSVGElement {
  if (source instanceof HTMLImageElement) return cloneImage(source);
  const clone = source.cloneNode(true) as HTMLElement | SVGSVGElement;
  if (clone instanceof SVGSVGElement) {
    isolateSvgIds(clone);
  }
  return clone;
}

function replaceUrlReferences(value: string, ids: ReadonlyMap<string, string>): string {
  return value.replace(/url\(\s*(['"]?)#([^)'"\s]+)\1\s*\)/g, (match, quote: string, id: string) => {
    const replacement = ids.get(id);
    return replacement ? `url(${quote}#${replacement}${quote})` : match;
  });
}

function replaceStyleReferences(value: string, ids: ReadonlyMap<string, string>): string {
  let rewritten = replaceUrlReferences(value, ids);
  for (const [id, replacement] of ids) {
    const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    rewritten = rewritten.replace(
      new RegExp(`(^|[\\s,{}>+~(])#${escaped}(?![A-Za-z0-9_-])`, "gm"),
      `$1#${replacement}`
    );
  }
  return rewritten;
}

function isolateSvgIds(svg: SVGSVGElement): void {
  const identified = [
    ...(svg.id ? [{ element: svg as SVGElement, id: svg.id }] : []),
    ...Array.from(svg.querySelectorAll<SVGElement>("[id]"), (element) => ({
      element,
      id: element.id
    })).filter(({ id }) => Boolean(id))
  ];
  if (identified.length === 0) return;

  let prefix: string;
  do {
    prefix = `website-media-${++mediaCloneSequence}-`;
  } while (identified.some(({ id }) => document.getElementById(`${prefix}${id}`)));

  const ids = new Map<string, string>();
  for (const { element, id } of identified) {
    const replacement = `${prefix}${id}`;
    ids.set(id, replacement);
    element.setAttribute("id", replacement);
  }

  for (const element of [svg, ...svg.querySelectorAll<SVGElement>("*")]) {
    for (const attribute of Array.from(element.attributes)) {
      let value = replaceUrlReferences(attribute.value, ids);
      if (attribute.name === "aria-labelledby" || attribute.name === "aria-describedby") {
        value = value.split(/\s+/).map((id) => ids.get(id) || id).join(" ");
      } else if ((attribute.name === "href" || attribute.name.endsWith(":href")) && value.startsWith("#")) {
        value = `#${ids.get(value.slice(1)) || value.slice(1)}`;
      } else if (attribute.name === "begin" || attribute.name === "end") {
        value = value.split(";").map((timing) => {
          const match = timing.match(/^(\s*)([^.\s]+)(\..*)$/);
          return match ? `${match[1]}${ids.get(match[2]!) || match[2]}${match[3]}` : timing;
        }).join(";");
      }
      if (value !== attribute.value) element.setAttribute(attribute.name, value);
    }
  }
  for (const style of svg.querySelectorAll<SVGStyleElement>("style")) {
    if (style.textContent) style.textContent = replaceStyleReferences(style.textContent, ids);
  }
}

export function openMediaViewer({
  source,
  opener,
  kind,
  title,
  closeLabel,
  lang,
  dir
}: OpenMedia): void {
  const dialog = dialogElement();
  const canvas = dialog ? canvasElement(dialog) : null;
  if (!dialog || !canvas) return;

  const clone = safeClone(source);
  canvas.replaceChildren(clone);
  canvas.dataset.mediaKind = kind;
  if (lang) canvas.lang = lang;
  if (dir) canvas.dir = dir;
  const heading = dialog.querySelector<HTMLElement>("[data-media-dialog-title]");
  const viewport = dialog.querySelector<HTMLElement>("[data-media-dialog-viewport]");
  const close = dialog.querySelector<HTMLButtonElement>("[data-dialog-close]");
  if (heading) {
    heading.textContent = title;
    if (lang) heading.lang = lang;
    if (dir) heading.dir = dir;
  }
  if (viewport) {
    viewport.setAttribute("aria-label", title);
    if (lang) viewport.lang = lang;
    if (dir) viewport.dir = dir;
    viewport.scrollLeft = 0;
    viewport.scrollTop = 0;
  }
  if (close) {
    close.setAttribute("aria-label", closeLabel);
    close.title = closeLabel;
  }

  prepareDialog(dialog);
  dialogOpeners.set(dialog, opener);
  setMediaZoom(dialog, 1);
  openWebsiteDialog("media");
  dialog.querySelector<HTMLButtonElement>("[data-media-zoom-in]")?.focus();
  requestAnimationFrame(() => {
    if (viewport) updatePanAffordance(viewport);
  });
  const clonedImage = clone instanceof HTMLImageElement
    ? clone
    : clone instanceof HTMLPictureElement
      ? clone.querySelector<HTMLImageElement>("img")
      : null;
  if (clonedImage && !clonedImage.complete) {
    clonedImage.addEventListener("load", () => {
      if (viewport) updatePanAffordance(viewport);
    }, { once: true });
  }
}

export function activeMediaViewerOpener(): HTMLElement | undefined {
  const dialog = dialogElement();
  return dialog ? dialogOpeners.get(dialog) : undefined;
}

export function closeMediaViewer(): void {
  closeWebsiteDialog("media");
}

export function createMediaExpandIcon(): SVGSVGElement {
  const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  icon.classList.add("source-copy__icon");
  icon.setAttribute("viewBox", "0 0 20 20");
  icon.setAttribute("aria-hidden", "true");
  icon.innerHTML = '<path d="M7 3H3v4M13 3h4v4M7 17H3v-4M13 17h4v-4"/>';
  return icon;
}

function referencedElements(references: string | null): Element[] {
  if (!references) return [];
  return references
    .split(/\s+/)
    .map((id) => document.getElementById(id) as Element | null)
    .filter((element): element is Element => element !== null);
}

function referencedText(references: string | null): string {
  if (!references) return "";
  return referencedElements(references)
    .map((element) => element.textContent?.replace(/\s+/g, " ").trim() || "")
    .filter(Boolean)
    .join(" ");
}

function referencedLabel(
  image: HTMLImageElement,
  attributes?: ImageAttributes
): string {
  return referencedText(attributes
    ? attributes["aria-labelledby"]
    : image.getAttribute("aria-labelledby"));
}

function imageReferences(
  image: HTMLImageElement,
  attributes?: ImageAttributes
): Element[] {
  return referencedElements(attributes
    ? attributes["aria-labelledby"]
    : image.getAttribute("aria-labelledby"));
}

function imageLocale(
  image: HTMLImageElement,
  root: HTMLElement,
  attributes?: ImageAttributes
): { lang: string; dir: string } {
  const reference = imageReferences(image, attributes)[0];
  const languageOwner = reference?.closest("[lang]");
  const directionOwner = reference?.closest("[dir]");
  return {
    lang: (attributes ? attributes.lang : image.getAttribute("lang")) ||
      languageOwner?.getAttribute("lang") || root.lang || document.documentElement.lang,
    dir: (attributes ? attributes.dir : image.getAttribute("dir")) ||
      directionOwner?.getAttribute("dir") || root.dir || document.documentElement.dir
  };
}

function imageDescription(
  image: HTMLImageElement,
  attributes?: ImageAttributes
): string {
  return referencedLabel(image, attributes) ||
    (attributes ? attributes["aria-label"] : image.getAttribute("aria-label"))?.trim() ||
    image.alt.trim();
}

function imageTitle(image: HTMLImageElement, root: HTMLElement): string {
  return imageDescription(image, originalImageAttributes.get(image)) ||
    root.dataset.imageLabel ||
    "Image";
}

function imageActionLabel(
  image: HTMLImageElement,
  root: HTMLElement,
  action: string
): HTMLSpanElement {
  const label = document.createElement("span");
  label.hidden = true;
  label.dataset.imageViewerLabel = "";
  do {
    label.id = `website-image-action-${++imageLabelSequence}`;
  } while (document.getElementById(label.id));

  const actionText = document.createElement("span");
  actionText.lang = document.documentElement.lang;
  actionText.dir = document.documentElement.dir;
  actionText.textContent = action;
  label.append(actionText);

  const description = imageDescription(image);
  const references = imageReferences(image).filter((reference) => reference.textContent?.trim());
  if (references.length > 0) {
    label.append(document.createTextNode(": "));
    references.forEach((reference, index) => {
      if (index > 0) label.append(document.createTextNode(" "));
      const descriptionText = document.createElement("span");
      const locale = imageLocale(image, root);
      descriptionText.lang = reference.closest("[lang]")?.getAttribute("lang") || locale.lang;
      descriptionText.dir = reference.closest("[dir]")?.getAttribute("dir") || locale.dir;
      descriptionText.textContent = reference.textContent?.replace(/\s+/g, " ").trim() || "";
      label.append(descriptionText);
    });
  } else if (description) {
    label.append(document.createTextNode(": "));
    const descriptionText = document.createElement("span");
    const locale = imageLocale(image, root);
    descriptionText.lang = locale.lang;
    descriptionText.dir = locale.dir;
    descriptionText.textContent = description;
    label.append(descriptionText);
  }
  return label;
}

function openImage(image: HTMLImageElement, opener: HTMLElement): void {
  const root = image.closest<HTMLElement>(".note-content");
  if (!root) return;
  const attributes = originalImageAttributes.get(image);
  const locale = imageLocale(image, root, attributes);
  openMediaViewer({
    source: image,
    opener,
    kind: "image",
    title: imageTitle(image, root),
    closeLabel: root.dataset.closeImageLabel || "Close image",
    lang: locale.lang,
    dir: locale.dir
  });
}

function hiddenFromAccessibilityTree(image: HTMLImageElement): boolean {
  for (let element: Element | null = image; element; element = element.parentElement) {
    if (element.hasAttribute("inert")) return true;
    if (element.getAttribute("aria-hidden")?.trim().toLowerCase() === "true") return true;
  }
  return false;
}

export function initialiseImageViewer(): () => void {
  const controller = new AbortController();
  const decoratedImages: Array<{
    image: HTMLImageElement;
    attributes: ImageAttributes;
  }> = [];
  const linkedButtons: HTMLButtonElement[] = [];
  const accessibleLabels: HTMLSpanElement[] = [];

  for (const image of document.querySelectorAll<HTMLImageElement>(
    ".note-content img[data-website-image]:not([data-image-viewer-ready])"
  )) {
    if (image.closest("[data-mermaid-rendered], [data-math-rendered]")) continue;
    if (hiddenFromAccessibilityTree(image)) continue;
    if (image.matches('[usemap], [tabindex], [role]:not([role="img"])')) continue;
    if (image.closest("button, input, label, select, textarea, summary, [contenteditable]")) continue;
    const root = image.closest<HTMLElement>(".note-content");
    if (!root) continue;
    image.dataset.imageViewerReady = "";
    const label = root.dataset.expandImageLabel || "Expand image";
    const link = image.closest<HTMLAnchorElement>("a[href]");
    if (link) {
      if (link.querySelectorAll("img").length !== 1) {
        delete image.dataset.imageViewerReady;
        continue;
      }
      const button = document.createElement("button");
      button.className = "source-copy__button media-image__expand";
      button.type = "button";
      button.dataset.imageExpand = "";
      button.title = label;
      button.lang = document.documentElement.lang;
      button.dir = document.documentElement.dir;
      button.append(createMediaExpandIcon());
      link.after(button);
      const accessibleLabel = imageActionLabel(image, root, label);
      button.after(accessibleLabel);
      button.setAttribute("aria-labelledby", accessibleLabel.id);
      button.addEventListener("click", () => openImage(image, button), {
        signal: controller.signal
      });
      linkedButtons.push(button);
      accessibleLabels.push(accessibleLabel);
      continue;
    }
    image.dataset.imageExpand = "";
    const attributes = {
      role: image.getAttribute("role"),
      tabindex: image.getAttribute("tabindex"),
      "aria-label": image.getAttribute("aria-label"),
      "aria-labelledby": image.getAttribute("aria-labelledby"),
      title: image.getAttribute("title"),
      lang: image.getAttribute("lang"),
      dir: image.getAttribute("dir")
    };
    image.setAttribute("role", "button");
    image.tabIndex = 0;
    const accessibleLabel = imageActionLabel(image, root, label);
    const labelAnchor = image.parentElement instanceof HTMLPictureElement
      ? image.parentElement
      : image;
    labelAnchor.after(accessibleLabel);
    image.setAttribute("aria-labelledby", accessibleLabel.id);
    originalImageAttributes.set(image, attributes);
    image.addEventListener("click", () => openImage(image, image), {
      signal: controller.signal
    });
    image.addEventListener("keydown", (event) => {
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
      openImage(image, image);
    }, { signal: controller.signal });
    decoratedImages.push({ image, attributes });
    accessibleLabels.push(accessibleLabel);
  }

  return () => {
    controller.abort();
    for (const { image, attributes } of decoratedImages) {
      delete image.dataset.imageExpand;
      delete image.dataset.imageViewerReady;
      for (const [name, value] of Object.entries(attributes)) {
        if (value === null) image.removeAttribute(name);
        else image.setAttribute(name, value);
      }
      originalImageAttributes.delete(image);
    }
    for (const button of linkedButtons) {
      const image = button.previousElementSibling?.querySelector<HTMLImageElement>("img[data-image-viewer-ready]");
      if (image) delete image.dataset.imageViewerReady;
      button.remove();
    }
    for (const label of accessibleLabels) label.remove();
  };
}

export function initialiseMediaViewerControls(): void {
  const dialog = dialogElement();
  if (!dialog || dialog.dataset.mediaControlsInitialised === "true") return;
  dialog.dataset.mediaControlsInitialised = "true";
  dialog.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const control = target.closest<HTMLElement>(
      "[data-media-zoom-in], [data-media-zoom-out], [data-media-zoom-reset]"
    );
    const canvas = canvasElement(dialog);
    if (!control || !canvas) return;
    const current = mediaZoom(canvas);
    if (control.hasAttribute("data-media-zoom-in")) {
      setMediaZoom(dialog, current + MEDIA_ZOOM_STEP);
    } else if (control.hasAttribute("data-media-zoom-out")) {
      setMediaZoom(dialog, current - MEDIA_ZOOM_STEP);
    } else {
      setMediaZoom(dialog, 1);
    }
  });
}
