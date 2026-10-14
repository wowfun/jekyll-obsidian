import { expect, it } from "vitest";
import { pdfBlob } from "../../src/frontend/pdf-preview";

it("accepts only PDF bytes and assigns their verified MIME type", async () => {
  const blob = await pdfBlob(new Response("%PDF-1.4\n", { headers: { "content-type": "application/pdf; charset=binary" } }));
  expect(blob.type).toBe("application/pdf"); expect(await blob.text()).toBe("%PDF-1.4\n");
});
it("rejects HTML even when its URL or claimed MIME type says PDF", async () => {
  for (const type of ["text/html", "application/pdf"]) await expect(pdfBlob(new Response("<script>parent.document.body.remove()</script>", { headers: { "content-type": type } }))).rejects.toThrow();
});
it("rejects failures and oversized declared responses before reading bytes", async () => {
  await expect(pdfBlob(new Response("%PDF-", { status: 404, headers: { "content-type": "application/pdf" } }))).rejects.toThrow();
  await expect(pdfBlob(new Response("%PDF-", { headers: { "content-type": "application/pdf", "content-length": String(21 * 1024 * 1024) } }))).rejects.toThrow("too large");
});
it("enforces the byte limit when the server omits content-length", async () => {
  await expect(pdfBlob(new Response(new Uint8Array(21 * 1024 * 1024), { headers: { "content-type": "application/pdf" } }))).rejects.toThrow("too large");
});
