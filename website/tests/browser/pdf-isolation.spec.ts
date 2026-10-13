import { test, expect } from "@playwright/test";

test("a PDF URL returning same-origin HTML cannot modify its parent", async ({ page }) => {
  await page.route("https://**/*", route => route.fulfill({ contentType: "text/html", body: "<p>Offline media</p>" }));
  await page.goto("/__site__/minimal-media/");
  const markup = await page.locator("iframe[data-website-external-pdf]").evaluate(frame => frame.outerHTML);
  await page.unroute("https://**/*");
  await page.route("https://pdf-review.test/**", route => route.fulfill({ contentType: "text/html", body: route.request().url().includes("paper.pdf")
    ? '<script>try { parent.document.body.dataset.escaped="yes"; } catch {} parent.postMessage("pdf-response-ran", "*");</script>'
    : '<script>addEventListener("message", event => { if (event.data === "pdf-response-ran") document.body.dataset.checked="yes"; });</script>' + markup.replace("https://papers.example/paper.pdf", "https://pdf-review.test/paper.pdf") }));
  await page.goto("https://pdf-review.test/");
  await expect(page.locator("body")).toHaveAttribute("data-checked", "yes");
  await expect(page.locator("body")).not.toHaveAttribute("data-escaped", "yes");
});
