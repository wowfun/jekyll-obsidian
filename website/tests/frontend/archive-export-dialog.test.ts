import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { initialiseArchiveExport } from '../../src/frontend/archive-export';
import type { ArchiveClient } from '../../src/frontend/archive-client';
import type { ArchiveCard, ArchiveManifest } from '../../src/frontend/archive-query';

let dispose = () => {}, client: ArchiveClient;
const data = { export_max_days: 7, total: 2, page_size: 1, prefixes: {}, facets: {}, aliases: {}, labels: {}, days: { '2026-10-09': [0, 2] }, months: {}, years: {} } as unknown as ArchiveManifest;
const cards = ['a', 'b'].map(id => ({ id, title: id, url: '/' + id + '/', markdown_url: '/' + id + '.md', facets: {}, display_date: '2026-10-09' })) as ArchiveCard[];
const element = <T extends HTMLElement>(name: string) => document.querySelector<T>(`[data-export-${name}]`)!;
beforeEach(() => {
  history.replaceState(null, '', '/');
  document.body.innerHTML = `<button data-archive-export-open>Export</button><dialog data-dialog="export" data-site="Garden" data-progress="Preparing {done} of {count}" data-matches="{count} entries" data-complete="Downloaded {count}" data-failed="{count} failed" data-calculating="Calculating" data-required="Required" data-unavailable="Unavailable">
    <fieldset data-export-fields><input type="date" data-export-start><input type="date" data-export-end><p data-export-limit></p><div data-export-facets></div></fieldset>
    <p data-export-status></p><progress data-export-progress></progress><button data-export-download>Save</button><button data-export-retry>Retry</button><button data-export-cancel>Cancel</button></dialog>`;
  client = {
    manifest: vi.fn(async () => data),
    select: vi.fn(async (_state, mode) => ({ ordinals: mode === 'first' ? [0] : [0, 1], count: mode === 'first' ? 1 : 2, page: 1, pages: 1 })),
    cards: vi.fn(async () => cards), markdown: vi.fn(async card => '# ' + card.id)
  } as unknown as ArchiveClient;
  vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:export');
  vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => {});
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
  dispose = initialiseArchiveExport(client);
});
afterEach(() => { dispose(); vi.useRealTimers(); vi.restoreAllMocks(); });
async function open() {
  document.querySelector<HTMLButtonElement>('[data-archive-export-open]')!.click();
  await vi.waitFor(() => expect(element<HTMLButtonElement>('download').disabled).toBe(false));
}

it('uses one bounded default-date probe and skips it for an explicit day', async () => {
  await open();
  expect(vi.mocked(client.select).mock.calls.map(call => call[1])).toEqual(['first', 'all']);
  vi.mocked(client.select).mockClear();
  history.replaceState(null, '', '/?day=2026-10-09');
  await open();
  expect(vi.mocked(client.select).mock.calls.map(call => call[1])).toEqual(['all']);
  expect(element<HTMLInputElement>('start').value).toBe('2026-10-09');
});

it('invalidates immediately and coalesces consecutive valid date edits', async () => {
  await open(); vi.mocked(client.select).mockClear(); vi.useFakeTimers();
  for (const day of ['04', '05', '06']) {
    element<HTMLInputElement>('start').value = '2026-10-' + day;
    element('start').dispatchEvent(new Event('input', { bubbles: true }));
  }
  expect(element<HTMLButtonElement>('download').disabled).toBe(true);
  expect(client.select).not.toHaveBeenCalled();
  await vi.advanceTimersByTimeAsync(200);
  expect(client.select).toHaveBeenCalledTimes(1);
  expect(element<HTMLButtonElement>('download').disabled).toBe(false);
});

it('counts only successful bodies and retries just the failed part of the frozen job', async () => {
  let resolve!: (body: string) => void;
  vi.mocked(client.markdown).mockRejectedValueOnce(new Error('Failed'))
    .mockImplementationOnce(() => new Promise<string>(done => { resolve = done; }))
    .mockResolvedValue('# a');
  await open(); element('download').click();
  await vi.waitFor(() => expect(client.markdown).toHaveBeenCalledTimes(2));
  expect(element<HTMLProgressElement>('progress').value).toBe(0);
  resolve('# b');
  await vi.waitFor(() => expect(element('status').textContent).toBe('1 failed'));
  expect(element<HTMLProgressElement>('progress').value).toBe(1);
  expect(URL.createObjectURL).not.toHaveBeenCalled();
  element('retry').click();
  await vi.waitFor(() => expect(element('status').textContent).toBe('Downloaded 2'));
  expect(vi.mocked(client.markdown).mock.calls.map(call => call[0].id)).toEqual(['a', 'b', 'a']);
  expect(client.cards).toHaveBeenCalledTimes(1);
  expect(URL.createObjectURL).toHaveBeenCalledTimes(1);
});
