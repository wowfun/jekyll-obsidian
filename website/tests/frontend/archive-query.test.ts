import { describe, it, expect } from 'vitest';
import { matchArchive, archiveState, type ArchiveManifest } from '../../src/frontend/archive-query';
describe('paged archive queries', () => {
  it('ORs within facets, ANDs across facets and chronology; unknown is empty', () => {
    const bitmaps = { 'source/a': new Uint8Array([0b0011]), 'source/b': new Uint8Array([0b1100]), 'topic/x': new Uint8Array([0b1010]) };
    expect(matchArchive(4, 50, { groups: [['source/a', 'source/b'], ['topic/x']], range: [0, 4], page: 1 }, bitmaps).ordinals).toEqual([1, 3]);
    expect(matchArchive(4, 50, { groups: [['source/unknown']], range: [0, 4], page: 1 }, bitmaps).count).toBe(0);
    expect(matchArchive(4, 1, { groups: [], range: [1, 3], page: 999 }, bitmaps)).toEqual({ count: 2, pages: 2, page: 2, ordinals: [2] });
  });
  it('bounds 100,000 records to a 50-card page', () => {
    const total = 100_000, bitmap = new Uint8Array(Math.ceil(total / 8)).fill(255);
    const result = matchArchive(total, 50, { groups: [['topic/x']], range: [0, total], page: 1999 }, { 'topic/x': bitmap });
    expect(result.count).toBe(total); expect(result.ordinals).toHaveLength(50); expect(result.ordinals[0]).toBe(99900);
  });
  it('normalizes duplicate aliases while preserving unknown IDs', () => {
    const manifest = { total: 4, page_size: 50, facets: { topic: [] }, prefixes: { topic: 'topics/' }, aliases: { 'topics/old': 'topics/new' }, years: {}, months: {} } as unknown as ArchiveManifest;
    const state = archiveState(manifest, '?topic=old&topic=new&topic=unknown&page=bad');
    expect(state.parameters.toString()).toBe('topic=new&topic=unknown');
  });
  it('filters by a calendar day with facets, pagination and day precedence', () => {
    const manifest = { total: 6, prefixes: { source: 'source/' }, aliases: {}, days: { '2026-01-01': [1, 5] }, months: { '2026-01': [0, 5] }, years: { '2026': [0, 6] } } as unknown as ArchiveManifest;
    const state = archiveState(manifest, '?source=a&year=2026&month=2026-01&day=2026-01-01&page=2');
    expect(state.parameters.toString()).toBe('source=a&day=2026-01-01&page=2');
    expect(matchArchive(6, 1, state.query, { 'source/a': new Uint8Array([0b111101]) })).toEqual({ count: 3, pages: 3, page: 2, ordinals: [3] });
    for (const day of ['2026-01-02', '2026-02-30', '__proto__']) {
      expect(archiveState(manifest, '?day=' + day).query.range).toEqual([0, 0]);
    }
    expect(archiveState(manifest, '?month=2026-01').query.range).toEqual([0, 5]);
    expect(archiveState(manifest, '?year=2026').query.range).toEqual([0, 6]);
  });
});
