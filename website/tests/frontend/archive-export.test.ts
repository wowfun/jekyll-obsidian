import { expect, it } from 'vitest';
import { archiveState, matchArchive, type ArchiveCard, type ArchiveManifest } from '../../src/frontend/archive-query';
import { calendarDay, dateRangeError, defaultExportDates, exportFilename, exportMarkdownParts, exportState } from '../../src/frontend/archive-export-model';

const data = { total: 5, export_max_days: 7, page_size: 2, prefixes: { source: 'source/', topic: 'topics/' }, facets: {}, labels: { 'source/hn': 'Hacker News', 'topics/tools': '工具' }, aliases: {}, years: { '2026': [0, 2], '2025': [2, 4] }, months: {}, days: { '2026-01-03': [0, 1], '2026-01-01': [1, 2], '2025-12-31': [2, 4] } } as unknown as ArchiveManifest;

it('describes the default source scope without enumerating hundreds of sources', () => {
  const scoped = { ...data, tab_sources: ['arxiv'], facets: { source: Array.from({ length: 300 }, (_, i) => ({ id: `source-${i}`, name: `Source ${i}`, count: 1 })) } };
  const labels = { dates: 'Dates', source: 'Sources', topic: 'Topics', all: 'All', allWithoutTabs: 'All (excluding tab sources)', entries: 'Entries', date: 'Date', original: 'Original', article: 'Article' };
  const snapshot = { site: 'Garden', locale: 'en', start: '2026-01-01', end: '2026-01-03', filters: new URLSearchParams(), cards: [] };
  expect(exportMarkdownParts(snapshot, scoped, new Map(), labels)[0]).toContain('Sources: All (excluding tab sources)');
  expect(exportMarkdownParts({ ...snapshot, filters: new URLSearchParams('include_tabs=1') }, scoped, new Map(), labels)[0]).toContain('Sources: All\n');
});

it('validates inclusive calendar ranges independently of the browser timezone', () => {
  expect(dateRangeError('2025-12-28', '2026-01-03', 7)).toBeNull();
  expect(dateRangeError('2026-01-03', '2026-01-03', 7)).toBeNull();
  expect(dateRangeError('2025-12-27', '2026-01-03', 7)).toBe('limit');
  expect(dateRangeError('2026-01-04', '2026-01-03', 7)).toBe('order');
  expect(dateRangeError('', '2026-01-03', 7)).toBe('required');
  expect(dateRangeError('2026-02-30', '2026-03-01', 7)).toBe('invalid');
  expect(calendarDay('2024-02-29')).toBeDefined();
  expect(calendarDay('2025-02-29')).toBeUndefined();
  expect(calendarDay('2026-1-3')).toBeUndefined();
});

it('uses the selected day or newest matching day and ignores pagination for export', () => {
  expect(defaultExportDates(data, '?day=2026-01-01&page=2', [1])).toEqual(['2026-01-01', '2026-01-01']);
  expect(defaultExportDates(data, '?source=hn&page=2', [0, 2])).toEqual(['2025-12-28', '2026-01-03']);
  expect(defaultExportDates(data, '?source=hn', [2, 3])).toEqual(['2025-12-25', '2025-12-31']);
  expect(defaultExportDates(data, '', [4])).toEqual(['', '']);
  expect(defaultExportDates(data, '', [])).toEqual(['', '']);
  expect(defaultExportDates(data, '?day=2026-01-02', [])).toEqual(['2026-01-02', '2026-01-02']);
  const filters = new URLSearchParams('source=hn&topic=tools&year=2025&page=2');
  const state = exportState(data, filters, '2025-12-31', '2026-01-02');
  expect(state.parameters.toString()).toBe('source=hn&topic=tools');
  expect(filters.toString()).toBe('source=hn&topic=tools&year=2025&page=2');
  expect(state.query.range).toEqual([1, 4]);
  expect(exportState(data, filters, '2026-01-02', '2026-01-02').query.range).toEqual([0, 0]);
  expect(() => exportState(data, filters, '2025-12-01', '2026-01-03')).toThrow();
});

it.each([
  ['../../CON <script>|Garden:*?', '../zh-CN', 'con-script-garden-zh-CN'],
  ['../../<>:*?', '???', 'archive-en'],
  ['中文 花园', 'zh-CN', '中文-花园-zh-CN']
])('sanitizes download names for %s', (site, locale, prefix) => {
  expect(exportFilename({ site, locale, start: '2026-01-01', end: '2026-01-07', filters: new URLSearchParams(), cards: [] })).toBe(`${prefix}-2026-01-01_2026-01-07.md`);
});

it('returns every match exactly once beyond a 50-card page, in archive order', () => {
  const total = 105, bitmap = new Uint8Array(Math.ceil(total / 8)).fill(255);
  const state = archiveState({ ...data, total }, '?source=hn&page=2');
  expect(matchArchive(total, 50, state.query, { 'source/hn': bitmap }, 'all').ordinals).toEqual(Array.from({ length: total }, (_, i) => i));
  expect(matchArchive(total, 50, state.query, { 'source/hn': bitmap }, 'first')).toEqual({ count: 1, ordinals: [0], page: 1, pages: 1 });
  expect(matchArchive(total, 50, state.query, {}, 'first').ordinals).toEqual([]);
  expect(matchArchive(total, 50, state.query, { 'source/hn': bitmap }).ordinals).toEqual(Array.from({ length: 50 }, (_, i) => i + 50));
});

it('preserves full Markdown and metadata in stable order, requiring every body', () => {
  const card = (id: string): ArchiveCard => ({ id, title: id, url: 'https://example.test/feedgarden/zh-CN/' + id + '/', markdown_url: '/' + id + '.md', published_at: '2026-01-01T01:00:00+08:00', display_date: '2026-01-01', year: '2026', month: '2026-01', source_url: 'https://source.test/' + id, summary: 'TRUNCATED...', facets: { source: ['hn'], topic: ['tools'] } });
  const cards = [card('a'), card('b')], body = '# 中文正文\n\n完整段落。\n\n## HN 热门讨论\n\n> 引用\n\n- 列表\n\n```md\n# Code heading\n---\n```\n\n![图片](https://example.test/a.png)\n';
  const snapshot = { site: 'Feedgarden', locale: 'zh-CN', start: '2025-12-28', end: '2026-01-03', filters: new URLSearchParams('source=hn'), cards };
  const labels = { dates: '日期范围', source: '来源', topic: '主题', all: '全部', allWithoutTabs: '全部（不含独立栏目来源）', entries: '条目数', date: '日期', original: '原文', article: '站内文章' };
  const parts = exportMarkdownParts(snapshot, data, new Map([['b', '# Second\n\nEnd.'], ['a', body]]), labels), result = parts.join('');
  expect(parts).toContain(body.trimEnd());
  expect(result).toContain(body.trimEnd()); expect(result).toContain('来源: Hacker News'); expect(result).toContain('主题: 工具');
  expect(result).toContain('<https://source.test/a>'); expect(result).toContain('<https://example.test/feedgarden/zh-CN/a/>');
  expect(result.indexOf('# 中文正文')).toBeLessThan(result.indexOf('# Second'));
  expect(result).not.toContain('TRUNCATED'); expect(result).not.toContain('publish:');
  expect(exportFilename(snapshot)).toBe('feedgarden-zh-CN-2025-12-28_2026-01-03.md');
  expect(() => exportMarkdownParts(snapshot, data, new Map([['a', body]]), labels)).toThrow('Incomplete export');
  expect(exportMarkdownParts({ ...snapshot, site: '~~Garden~~' }, data, new Map([['a', body], ['b', body]]), labels)[0]).toContain('\\~\\~Garden\\~\\~');
});
