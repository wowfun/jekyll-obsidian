import { describe, expect, it, vi } from "vitest";
import { boundedText } from "../../src/frontend/response";

describe("bounded response bodies", () => {
  it("counts streamed bytes, cancels excess data, and decodes split Unicode", async () => {
    const bytes = new TextEncoder().encode("你好");
    const response = () => new Response(new ReadableStream({ start(controller) {
      controller.enqueue(bytes.slice(0, 2)); controller.enqueue(bytes.slice(2)); controller.close();
    } }));
    expect(await boundedText(response(), 6)).toBe("你好");
    await expect(boundedText(response(), 5)).rejects.toThrow(RangeError);
  });
  it("cancels a pending read when the preview becomes obsolete", async () => {
    const cancel = vi.fn(), controller = new AbortController();
    const pending = boundedText(new Response(new ReadableStream({ cancel })), 100, controller.signal);
    controller.abort();
    await expect(pending).rejects.toMatchObject({ name: 'AbortError' });
    expect(cancel).toHaveBeenCalledOnce();
  });
});
