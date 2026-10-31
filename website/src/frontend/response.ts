/** Enforce the limit on decoded response bytes, including chunked responses. */
export async function boundedText(response: Response, maximum: number, signal?: AbortSignal): Promise<string> {
  signal?.throwIfAborted();
  if (Number(response.headers.get("Content-Length")) > maximum) {
    await response.body?.cancel();
    throw new RangeError("Response exceeds its byte budget");
  }
  const reader = response.body?.getReader();
  if (!reader) return "";
  const decoder = new TextDecoder();
  let bytes = 0, text = "";
  const abort = () => { void reader.cancel().catch(() => {}); };
  signal?.addEventListener("abort", abort, { once: true });
  try {
    for (;;) {
      const { done, value } = await reader.read();
      signal?.throwIfAborted();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > maximum) throw new RangeError("Response exceeds its byte budget");
      text += decoder.decode(value, { stream: true });
    }
    return text + decoder.decode();
  } finally {
    signal?.removeEventListener("abort", abort);
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}
