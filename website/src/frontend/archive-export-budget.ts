export const MAX_EXPORT_ENTRIES = 5000;
export const MAX_EXPORT_BYTES = 64 * 1024 * 1024;
export class ExportSizeError extends Error {
  constructor() { super('Export body size limit exceeded'); }
}

// Counts decoded response bytes across successful bodies and in-flight streams.
// Failed streams return their reservation so retry does not spend it twice.
export class ArchiveBodyBudget {
  private used = 0;
  constructor(private readonly limit = MAX_EXPORT_BYTES) {}
  reserve(bytes: number): void {
    if (this.used + bytes > this.limit) throw new ExportSizeError();
    this.used += bytes;
  }
  release(bytes: number): void { this.used -= bytes; }
}
