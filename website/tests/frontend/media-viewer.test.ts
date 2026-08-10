import { beforeEach, describe, expect, it } from "vitest";
import { initialiseDialogs } from "../../src/frontend/dialogs";
import {
  initialiseImageViewer,
  initialiseMediaViewerControls
} from "../../src/frontend/media-viewer";

describe("content media viewer", () => {
  beforeEach(() => {
    document.documentElement.lang = "en";
    document.documentElement.dir = "ltr";
    document.body.innerHTML = `
      <div class="note-content" lang="en" dir="ltr"
        data-image-label="Image"
        data-expand-image-label="Expand image"
        data-close-image-label="Close image">
        <h2 id="website-image-action-1">Existing authored heading</h2>
        <svg id="authored-caption" lang="ar" dir="rtl"><text>مخطط البحث</text></svg>
        <span id="authored-detail">A detailed field sketch</span>
        <img id="standalone" data-website-image="true" src="folio.svg" alt="Research folio" title="Author caption" aria-labelledby="authored-caption" aria-describedby="authored-detail" lang="ar" dir="rtl">
        <a id="authored-link" href="/original/"><img id="linked" data-website-image="true" src="linked.svg" alt="Linked image"></a>
        <button id="authored-button"><img id="button-image" data-website-image="true" src="button.svg" alt="Button image"></button>
        <label><input type="checkbox"><img id="label-image" data-website-image="true" src="label.svg" alt="Label image"></label>
        <img id="hidden-image" data-website-image="true" src="hidden.svg" alt="Hidden image" aria-hidden="TRUE">
        <span inert><img id="inert-image" data-website-image="true" src="inert.svg" alt="Inert image"></span>
        <img id="mapped-image" data-website-image="true" src="mapped.svg" alt="Mapped image" usemap="#image-map">
        <img id="interactive-image" data-website-image="true" src="interactive.svg" alt="Interactive image" role="button" tabindex="0">
        <picture id="authored-picture"><source srcset="small.webp 1x, large.webp 3x"><img id="picture-image" data-website-image="true" src="small.png" srcset="small.png 100w, large.png 1000w" sizes="100px" alt="Responsive image"></picture>
      </div>
      <dialog data-dialog="media" data-media-zoom-level="Zoom: {percent}%">
        <h2 data-media-dialog-title></h2>
        <button data-media-zoom-out>Zoom out</button>
        <button data-media-zoom-reset>Reset zoom</button>
        <button data-media-zoom-in>Zoom in</button>
        <button data-dialog-close>Close</button>
        <output data-media-zoom-status></output>
        <div data-media-dialog-viewport tabindex="0" role="group"><div data-media-dialog-canvas></div></div>
      </dialog>`;
    HTMLDialogElement.prototype.showModal = function showModal() { this.open = true; };
    HTMLDialogElement.prototype.close = function close() {
      this.open = false;
      this.dispatchEvent(new Event("close"));
    };
    initialiseDialogs();
    initialiseMediaViewerControls();
  });

  it("opens standalone images while preserving authored image links", () => {
    const cleanup = initialiseImageViewer();
    const standalone = document.querySelector<HTMLImageElement>("#standalone")!;
    const linked = document.querySelector<HTMLImageElement>("#linked")!;
    const authoredLink = document.querySelector<HTMLAnchorElement>("#authored-link")!;
    const buttonImage = document.querySelector<HTMLImageElement>("#button-image")!;
    const labelImage = document.querySelector<HTMLImageElement>("#label-image")!;
    const hiddenImage = document.querySelector<HTMLImageElement>("#hidden-image")!;
    const inertImage = document.querySelector<HTMLImageElement>("#inert-image")!;
    const mappedImage = document.querySelector<HTMLImageElement>("#mapped-image")!;
    const interactiveImage = document.querySelector<HTMLImageElement>("#interactive-image")!;
    const picture = document.querySelector<HTMLPictureElement>("#authored-picture")!;
    const pictureImage = document.querySelector<HTMLImageElement>("#picture-image")!;
    const linkedControl = authoredLink.nextElementSibling as HTMLButtonElement;

    expect(standalone.getAttribute("role")).toBe("button");
    expect(standalone.tabIndex).toBe(0);
    const standaloneLabel = document.getElementById(standalone.getAttribute("aria-labelledby")!)!;
    expect(standaloneLabel.id).not.toBe("website-image-action-1");
    expect(document.querySelectorAll(`#${standaloneLabel.id}`)).toHaveLength(1);
    expect(standaloneLabel.textContent).toBe("Expand image: مخطط البحث");
    expect(standaloneLabel.hidden).toBe(true);
    expect(standaloneLabel.querySelectorAll("span")[1]?.lang).toBe("ar");
    expect(standaloneLabel.querySelectorAll("span")[1]?.dir).toBe("rtl");
    expect(standalone.title).toBe("Author caption");
    expect(linked.hasAttribute("data-image-expand")).toBe(false);
    expect(linkedControl.matches("button[data-image-expand]")).toBe(true);
    expect(authoredLink.querySelector("button")).toBeNull();
    expect(buttonImage.hasAttribute("data-image-expand")).toBe(false);
    expect(buttonImage.hasAttribute("role")).toBe(false);
    expect(labelImage.hasAttribute("role")).toBe(false);
    expect(labelImage.hasAttribute("tabindex")).toBe(false);
    expect(hiddenImage.hasAttribute("role")).toBe(false);
    expect(hiddenImage.hasAttribute("tabindex")).toBe(false);
    expect(inertImage.hasAttribute("role")).toBe(false);
    expect(inertImage.hasAttribute("tabindex")).toBe(false);
    expect(mappedImage.hasAttribute("role")).toBe(false);
    expect(mappedImage.hasAttribute("tabindex")).toBe(false);
    expect(interactiveImage.getAttribute("role")).toBe("button");
    expect(interactiveImage.getAttribute("tabindex")).toBe("0");
    expect(pictureImage.getAttribute("role")).toBe("button");
    expect(picture.querySelector("[data-image-viewer-label]")).toBeNull();

    standalone.click();
    const dialog = document.querySelector<HTMLDialogElement>('dialog[data-dialog="media"]')!;
    const clone = dialog.querySelector<HTMLImageElement>("[data-media-dialog-canvas] > img")!;
    expect(dialog.open).toBe(true);
    expect(clone).not.toBe(standalone);
    expect(clone.src).toBe(standalone.src);
    expect(clone.alt).toBe("Research folio");
    expect(clone.title).toBe("Author caption");
    expect(clone.hasAttribute("id")).toBe(false);
    expect(clone.hasAttribute("role")).toBe(false);
    expect(clone.hasAttribute("aria-labelledby")).toBe(false);
    expect(clone.getAttribute("aria-label")).toBe("مخطط البحث");
    expect(clone.hasAttribute("aria-describedby")).toBe(false);
    expect(clone.getAttribute("aria-description")).toBe("A detailed field sketch");
    expect(dialog.querySelector("[data-media-dialog-title]")?.textContent).toBe("مخطط البحث");
    expect(dialog.querySelector<HTMLElement>("[data-media-dialog-title]")?.lang).toBe("ar");
    expect(dialog.querySelector<HTMLElement>("[data-media-dialog-title]")?.dir).toBe("rtl");
    expect(dialog.querySelector<HTMLElement>("[data-media-dialog-viewport]")?.lang).toBe("ar");
    expect(dialog.querySelector<HTMLElement>("[data-media-dialog-viewport]")?.dir).toBe("rtl");
    expect(dialog.querySelector("[data-dialog-close]")?.getAttribute("aria-label")).toBe("Close image");
    dialog.close();
    expect(document.activeElement).toBe(standalone);

    standalone.dispatchEvent(new KeyboardEvent("keydown", {
      key: "Enter",
      bubbles: true,
      cancelable: true
    }));
    expect(dialog.open).toBe(true);
    dialog.close();

    linkedControl.click();
    expect(dialog.open).toBe(true);
    expect(dialog.querySelector<HTMLImageElement>("[data-media-dialog-canvas] > img")?.src)
      .toBe(linked.src);
    dialog.close();
    expect(document.activeElement).toBe(linkedControl);

    pictureImage.click();
    const clonedPicture = dialog.querySelector<HTMLPictureElement>("[data-media-dialog-canvas] > picture")!;
    expect(dialog.open).toBe(true);
    expect(clonedPicture).not.toBe(picture);
    expect(clonedPicture.querySelector("source")?.getAttribute("srcset")).toBe("large.webp");
    expect(clonedPicture.querySelector("source")?.hasAttribute("sizes")).toBe(false);
    expect(clonedPicture.querySelector("img")?.getAttribute("sizes")).toBe("300vw");
    dialog.close();

    cleanup();
    expect(standalone.hasAttribute("data-image-expand")).toBe(false);
    expect(standalone.getAttribute("aria-labelledby")).toBe("authored-caption");
    expect(authoredLink.nextElementSibling).not.toBe(linkedControl);
  });

  it("zooms with a vertical wheel and leaves browser zoom and horizontal scrolling alone", () => {
    initialiseImageViewer();
    document.querySelector<HTMLImageElement>("#standalone")!.click();
    const dialog = document.querySelector<HTMLDialogElement>('dialog[data-dialog="media"]')!;
    const viewport = dialog.querySelector<HTMLElement>("[data-media-dialog-viewport]")!;
    const canvas = dialog.querySelector<HTMLElement>("[data-media-dialog-canvas]")!;
    const status = dialog.querySelector<HTMLOutputElement>("[data-media-zoom-status]")!;

    const zoomIn = new WheelEvent("wheel", {
      bubbles: true,
      cancelable: true,
      clientX: 10,
      clientY: 10,
      deltaY: -100
    });
    viewport.dispatchEvent(zoomIn);
    expect(zoomIn.defaultPrevented).toBe(true);
    expect(Number(canvas.dataset.mediaZoom)).toBeGreaterThan(1);
    expect(status.textContent).not.toBe("Zoom: 100%");

    const horizontal = new WheelEvent("wheel", {
      bubbles: true,
      cancelable: true,
      deltaX: 40,
      deltaY: 0
    });
    const beforeHorizontal = canvas.dataset.mediaZoom;
    viewport.dispatchEvent(horizontal);
    expect(horizontal.defaultPrevented).toBe(false);
    expect(canvas.dataset.mediaZoom).toBe(beforeHorizontal);

    const browserZoom = new WheelEvent("wheel", {
      bubbles: true,
      cancelable: true,
      ctrlKey: true,
      deltaY: -100
    });
    Object.defineProperty(browserZoom, "ctrlKey", { value: true });
    viewport.dispatchEvent(browserZoom);
    expect(browserZoom.defaultPrevented).toBe(false);
    expect(canvas.dataset.mediaZoom).toBe(beforeHorizontal);

    for (let index = 0; index < 100; index += 1) {
      viewport.dispatchEvent(new WheelEvent("wheel", { cancelable: true, deltaY: -100 }));
    }
    expect(canvas.dataset.mediaZoom).toBe("3");
    const bounded = new WheelEvent("wheel", { cancelable: true, deltaY: -100 });
    viewport.dispatchEvent(bounded);
    expect(bounded.defaultPrevented).toBe(true);
    expect(canvas.dataset.mediaZoom).toBe("3");
  });
});
