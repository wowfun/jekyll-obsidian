export function disposeAll(cleanups: (() => void)[]): void {
  const failures: unknown[] = [];
  for (const cleanup of cleanups.splice(0).reverse()) {
    try { cleanup(); } catch (error) { failures.push(error); }
  }
  if (failures.length) throw new AggregateError(failures, "Page feature cleanup failed");
}

/** Roll back acquired resources if initialization cannot return its disposer. */
export function withCleanup(initialize: (add: (cleanup: () => void) => void) => void): () => void {
  const cleanups: (() => void)[] = [];
  const dispose = () => disposeAll(cleanups);
  try {
    initialize(cleanup => cleanups.push(cleanup));
  } catch (error) {
    try { dispose(); } catch (cleanupError) { throw new AggregateError([error, cleanupError], "Page feature initialization failed"); }
    throw error;
  }
  return dispose;
}
