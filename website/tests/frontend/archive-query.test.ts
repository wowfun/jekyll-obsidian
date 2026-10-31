import { describe, it, expect } from 'vitest';
import { matchArchive, archiveState, type ArchiveManifest } from '../../src/frontend/archive-query';
describe('paged archive queries', () => {
  it('bounds adversarial URL selections before any posting requests', () => {
    const manifest = { total: 1, prefixes: { source: 'source/', topic: 'topics/', category: 'category/' }, aliases: {}, years: {}, months: {}, days: {} } as unknown as ArchiveManifest;
    const input = new URLSearchParams();
    for (const name of Object.keys(manifest.prefixes)) for (let i = 0; i < 1_000; i++) input.append(name, String(i));
    const state = archiveState(manifest, input.toString());
    expect(state.keys.length).toBeLessThanOrEqual(32);
    expect(state.parameters.getAll('source').length).toBeLessThanOrEqual(16);
    expect(state.limited).toBe(true);
    expect(archiveState(manifest, state.parameters.toString()).parameters.toString()).toBe(state.parameters.toString());
  });
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
  it('matches a direct filter oracle for sparse ranges and clamped partial pages without mutating postings', () => {
    const total=33, values={'source/a':new Uint8Array([85,170,17,255,1]),'source/b':new Uint8Array([34,68,170,1,0]),'topic/x':new Uint8Array([255,0,85,170,1])};
    const before=structuredClone(values);
    for(const groups of [[],[['source/a']],[['source/a','source/b'],['topic/x']],[['missing']],[['source/a','missing']]]) {
      for(const range of [[0,total],[3,19],[17,total],[0,0]] as [number,number][]) {
        const expected=Array.from({length:range[1]-range[0]},(_,i)=>range[0]+i).filter(ordinal=>groups.every(keys=>keys.some(key=>Boolean(values[key as keyof typeof values]?.[ordinal>>3]! & (1<<(ordinal&7))))));
        for(const size of [1,3,5]) for(const requested of [1,2,999]) {
          const pages=Math.max(1,Math.ceil(expected.length/size)),page=Math.min(pages,requested);
          expect(matchArchive(total,size,{groups,range,page:requested},values)).toEqual({count:expected.length,pages,page,ordinals:expected.slice((page-1)*size,page*size)});
        }
      }
    }
    expect(values).toEqual(before);
  });
  it('caps collected export ordinals while preserving the exact matching count and order', () => {
    const query = { groups: [['topic/x']], range: [0, 100_000] as [number, number], page: 1 };
    const result = matchArchive(100_000, 50, query, { 'topic/x': new Uint8Array(12_500).fill(0b01010101) }, 'all', 5000);
    expect(result.count).toBe(50_000);
    expect(result.ordinals).toEqual(Array.from({ length: 5000 }, (_, i) => i * 2));
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

it('does not inherit an alias for a custom facet tag named constructor', () => {
  const data = { total: 1, page_size: 50, facets: { category: [] }, prefixes: { category: 'c' }, aliases: {}, years: {}, months: {}, days: {} } as unknown as ArchiveManifest;
  expect(archiveState(data, '?category=onstructor').parameters.toString()).toBe('category=onstructor');
});
