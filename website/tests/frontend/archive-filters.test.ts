import { afterEach, expect, it } from 'vitest';
import { initialiseArchiveFilters } from '../../src/frontend/archive-filters';

let cleanup: (() => void) | undefined;
afterEach(() => { cleanup?.(); document.body.replaceChildren(); history.replaceState(null, '', '/'); });

it('filters a full archive by day and topic, toggles dates and restores history', () => {
  history.replaceState(null, '', '/blog/?topic=tools&day=2026-01-02');
  document.body.innerHTML = `
    <nav data-topic-filter-nav><a data-topic-filter-option data-topic-anchor="tools" href="?topic=tools">Tools</a></nav>
    <nav data-timeline-nav>
      <a data-year-filter-option data-filter-year="2026" href="?year=2026">2026</a>
      <a data-day-filter-option data-filter-day="2026-01-02" href="?day=2026-01-02">01-02</a>
      <a data-day-filter-option data-filter-day="2026-01-01" href="?day=2026-01-01">01-01</a>
    </nav>
    <main data-filter-page><section data-filter-group>
      <p data-filter-item data-topic-anchors="tools" data-filter-month="2026-01" data-filter-day="2026-01-02">A</p>
      <p data-filter-item data-topic-anchors="agents" data-filter-month="2026-01" data-filter-day="2026-01-02">B</p>
      <p data-filter-item data-topic-anchors="tools" data-filter-month="2026-01" data-filter-day="2026-01-01">C</p>
    </section><p data-filter-empty hidden>Empty</p></main>`;
  cleanup = initialiseArchiveFilters();
  const visible = () => [...document.querySelectorAll<HTMLElement>('[data-filter-item]')].filter(item => !item.hidden).map(item => item.textContent);
  const day = document.querySelector<HTMLAnchorElement>('[data-day-filter-option]')!;
  expect(visible()).toEqual(['A']);
  expect(day.getAttribute('aria-current')).toBe('page');
  day.click();
  expect(window.location.search).toBe('?topic=tools');
  expect(visible()).toEqual(['A', 'C']);
  day.click();
  document.querySelector<HTMLAnchorElement>('[data-year-filter-option]')!.click();
  expect(window.location.search).toBe('?topic=tools&year=2026');
  expect(day.hasAttribute('aria-current')).toBe(false);
  history.replaceState(null, '', '/blog/?topic=tools&day=2026-01-01');
  window.dispatchEvent(new PopStateEvent('popstate'));
  expect(visible()).toEqual(['C']);
});
