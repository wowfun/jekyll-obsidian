import { archiveState, type ArchiveCard, type ArchiveManifest } from "./archive-query";
import { archiveConcurrent, type ArchiveClient } from "./archive-client";
import { dateRangeError, defaultExportDates, exportFilename, exportMarkdown, exportState, type ExportSnapshot } from "./archive-export-model";
import { openWebsiteDialog } from "./dialogs";

export function initialiseArchiveExport(client: ArchiveClient): () => void {
  const opener = document.querySelector<HTMLButtonElement>("[data-archive-export-open]");
  const dialog = document.querySelector<HTMLDialogElement>('[data-dialog="export"]');
  if (!opener || !dialog) return () => undefined;
  const start = dialog.querySelector<HTMLInputElement>("[data-export-start]")!, end = dialog.querySelector<HTMLInputElement>("[data-export-end]")!;
  const fields = dialog.querySelector<HTMLFieldSetElement>("[data-export-fields]")!;
  const facets = dialog.querySelector<HTMLElement>("[data-export-facets]")!;
  const status = dialog.querySelector<HTMLElement>("[data-export-status]")!;
  const download = dialog.querySelector<HTMLButtonElement>("[data-export-download]")!;
  const retry = dialog.querySelector<HTMLButtonElement>("[data-export-retry]")!;
  const cancel = dialog.querySelector<HTMLButtonElement>("[data-export-cancel]")!;
  const progress = dialog.querySelector<HTMLProgressElement>("[data-export-progress]")!;
  const labels = (name: string) => dialog.dataset[name] || "";
  let data: ArchiveManifest | undefined, filters = new URLSearchParams(), ordinals: number[] = [];
  let session = new AbortController(), calculation = new AbortController(), task: AbortController | undefined;
  let snapshot: ExportSnapshot | undefined, bodies = new Map<string, string>(), disposed = false;
  const message = (name: string, count: number) => labels(name).replace("{count}", String(count));
  function releaseTask(): void { task?.abort(); task = undefined; fields.disabled = false; cancel.hidden = true; progress.hidden = true; }
  function resetResults(): void { snapshot = undefined; bodies.clear(); retry.hidden = true; download.textContent = labels("download"); }
  function renderFacets(): void {
    facets.replaceChildren();
    for (const [name, options] of Object.entries(data!.facets)) {
      const group = document.createElement("fieldset"), legend = document.createElement("legend");
      legend.textContent = name === "source" ? labels("sources") : name === "topic" ? labels("topics") : name;
      group.append(legend);
      const choices = document.createElement("div"); choices.className = "archive-export__choices";
      const selected = filters.getAll(name);
      const entries = [...options, ...selected.filter(id => !options.some(option => option.id === id)).map(id => ({ id, name: id }))];
      const all = document.createElement("button"); all.type = "button"; all.textContent = labels("all");
      all.className = "tag-chip"; all.dataset.exportAll = name; all.setAttribute("aria-pressed", String(selected.length === 0)); choices.append(all);
      for (const option of entries) {
        const label = document.createElement("label"); label.className = "archive-export__choice";
        const input = document.createElement("input"); input.type = "checkbox"; input.dataset.exportFacet = name; input.value = option.id; input.checked = selected.includes(option.id);
        const text = document.createElement("span"); text.textContent = option.name; label.append(input, text); choices.append(label);
      }
      group.append(choices); facets.append(group);
    }
  }
  async function recount(): Promise<void> {
    calculation.abort(); calculation = new AbortController();
    const signal = AbortSignal.any([session.signal, calculation.signal]);
    ordinals = []; download.disabled = true; resetResults();
    if (!data) return;
    const error = dateRangeError(start.value, end.value, data.export_max_days);
    if (error) { status.textContent = labels(error).replace("{days}", String(data.export_max_days)); return; }
    status.textContent = labels("calculating");
    try {
      const result = await client.select(exportState(data, filters, start.value, end.value), "all", signal);
      if (signal.aborted || disposed) return;
      ordinals = result.ordinals;
      status.textContent = result.count ? message("matches", result.count) : labels("empty");
      download.disabled = result.count === 0;
    } catch { if (!signal.aborted) { status.textContent = labels("unavailable"); retry.hidden = false; } }
  }
  async function open(): Promise<void> {
    session.abort(); releaseTask(); calculation.abort(); session = new AbortController();
    const signal = session.signal, search = location.search;
    data = undefined; ordinals = []; resetResults(); facets.replaceChildren(); start.value = end.value = "";
    download.disabled = true; fields.disabled = true; status.textContent = labels("calculating");
    openWebsiteDialog("export");
    try {
      const manifest = await client.manifest(signal); if (signal.aborted) return; data = manifest;
      const initial = archiveState(data, search); filters = new URLSearchParams(initial.parameters);
      const result = await client.select(initial, "all", signal); if (signal.aborted) return;
      [start.value, end.value] = defaultExportDates(data, search, result.ordinals);
      for (const key of ["day", "month", "year", "page"]) filters.delete(key);
      renderFacets(); fields.disabled = false;
      dialog!.querySelector<HTMLElement>("[data-export-limit]")!.textContent = labels("limitHint").replace("{days}", String(data.export_max_days));
      await recount();
      if (!signal.aborted && !start.value && !end.value) status.textContent = labels("empty");
    } catch { if (!signal.aborted) { status.textContent = labels("unavailable"); retry.hidden = false; } }
  }
  async function save(): Promise<void> {
    if (!data || !ordinals.length || task) return;
    calculation.abort(); task = new AbortController();
    const current = task, signal = AbortSignal.any([session.signal, current.signal]);
    const selected = [...ordinals], selectedFilters = new URLSearchParams(filters), first = start.value, last = end.value;
    download.disabled = true; fields.disabled = true; retry.hidden = true; cancel.hidden = false; progress.hidden = false;
    progress.max = selected.length; progress.value = bodies.size;
    const update = (completed: number) => { progress.value = completed; status.textContent = labels("progress").replace("{done}", String(completed)).replace("{count}", String(selected.length)); };
    update(bodies.size);
    try {
      if (!snapshot) {
        const cards: ArchiveCard[] = await client.cards(selected, signal); signal.throwIfAborted();
        snapshot = { site: labels("site"), locale: document.documentElement.lang, start: first, end: last, filters: selectedFilters, cards };
      }
      let completed = bodies.size, failures = 0;
      await archiveConcurrent(snapshot.cards.filter(card => !bodies.has(card.id)), async card => {
        try { const body = await client.markdown(card, signal); signal.throwIfAborted(); bodies.set(card.id, body); }
        catch (error) { if (signal.aborted) throw error; failures++; }
        if (!signal.aborted) update(++completed);
      }, signal);
      signal.throwIfAborted();
      if (failures) { status.textContent = message("failed", failures); retry.hidden = false; return; }
      const markdown = exportMarkdown(snapshot, data, bodies, { dates: labels("dates"), source: labels("sources"), topic: labels("topics"), all: labels("all"), entries: labels("entries"), date: labels("date"), original: labels("original"), article: labels("article") });
      const url = URL.createObjectURL(new Blob([markdown], { type: "text/markdown;charset=utf-8" }));
      const link = document.createElement("a"); link.href = url; link.download = exportFilename(snapshot); document.body.append(link); link.click(); link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      status.textContent = message("complete", snapshot.cards.length);
      resetResults();
    } catch { if (!signal.aborted) { status.textContent = labels("unavailable"); retry.hidden = false; } }
    finally { if (task === current) { task = undefined; fields.disabled = false; cancel.hidden = true; progress.hidden = true; download.disabled = !retry.hidden; } }
  }
  function change(): void {
    if (task || !data) return;
    filters = new URLSearchParams();
    for (const input of facets.querySelectorAll<HTMLInputElement>("input:checked")) filters.append(input.dataset.exportFacet!, input.value);
    for (const all of facets.querySelectorAll<HTMLButtonElement>("[data-export-all]")) all.setAttribute("aria-pressed", String(!filters.has(all.dataset.exportAll!)));
    void recount();
  }
  function selectAll(event: MouseEvent): void {
    if (!(event.target instanceof Element)) return;
    const all = event.target.closest<HTMLElement>("[data-export-all]"); if (!all || task) return;
    for (const input of facets.querySelectorAll<HTMLInputElement>("input")) if (input.dataset.exportFacet === all.dataset.exportAll) input.checked = false;
    change();
  }
  function cancelTask(): void { releaseTask(); resetResults(); download.disabled = !ordinals.length; status.textContent = labels("cancelled"); }
  function abortSession(): void { session.abort(); calculation.abort(); releaseTask(); resetResults(); }
  function close(): void { abortSession(); if (!disposed) opener!.focus(); }
  // The native close event is queued. Abort at the user's close action so a
  // resolved fetch cannot trigger a download before that event is delivered.
  function closeIntent(event: MouseEvent): void {
    if (event.target === dialog || (event.target instanceof Element && event.target.closest('[data-dialog-close]'))) abortSession();
  }
  function retryTask(): void { if (ordinals.length) void save(); else if (data && !fields.disabled) void recount(); else void open(); }
  const onOpen = () => { void open(); }, onSave = () => { void save(); };
  opener.hidden = false;
  opener.addEventListener("click", onOpen); dialog.addEventListener("close", close);
  dialog.addEventListener("cancel", abortSession); dialog.addEventListener("click", closeIntent);
  fields.addEventListener("input", change); facets.addEventListener("click", selectAll);
  download.addEventListener("click", onSave); retry.addEventListener("click", retryTask); cancel.addEventListener("click", cancelTask);
  return () => {
    disposed = true; close(); if (dialog.open) dialog.close();
    opener.removeEventListener("click", onOpen); dialog.removeEventListener("close", close); fields.removeEventListener("input", change); facets.removeEventListener("click", selectAll);
    dialog.removeEventListener("cancel", abortSession); dialog.removeEventListener("click", closeIntent);
    download.removeEventListener("click", onSave); retry.removeEventListener("click", retryTask); cancel.removeEventListener("click", cancelTask);
  };
}
