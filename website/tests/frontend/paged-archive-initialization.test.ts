import { expect, it, vi } from "vitest";
import { initialisePagedArchive } from "../../src/frontend/paged-archive";

const resources = vi.hoisted(() => ({ client: vi.fn(), days: vi.fn(), reading: vi.fn(), export: vi.fn() }));
vi.mock("../../src/frontend/archive-client", () => ({ createArchiveClient: () => ({ dispose: resources.client }) }));
vi.mock("../../src/frontend/archive-days", () => ({ initialiseArchiveDays: () => ({ dispose: resources.days }) }));
vi.mock("../../src/frontend/archive-reading", () => ({ initialiseArchiveReading: () => ({ dispose: resources.reading }) }));
vi.mock("../../src/frontend/archive-export", () => ({ initialiseArchiveExport: () => resources.export }));

it("releases acquired resources even if later initialization and one disposer throw", () => {
  document.body.innerHTML = `<main data-paged-archive data-archive-url="/archive.json">
    <p data-archive-status></p><button data-archive-retry></button><div data-archive-empty></div>
    <div data-archive-pagination><button data-archive-page="prev"></button><button data-archive-page="next"></button></div>
  </main>`; // Missing the required jump form: fail after acquiring the subfeatures.
  resources.reading.mockImplementationOnce(() => { throw new Error("Reading cleanup failed"); });
  expect(() => initialisePagedArchive(document.querySelector("main")!)).toThrow(AggregateError);
  for (const dispose of Object.values(resources)) expect(dispose).toHaveBeenCalledTimes(1);
  document.body.replaceChildren();
});
