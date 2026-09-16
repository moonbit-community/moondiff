// Instrument only the temporary E2E bundle. Dependency sources are never edited.
export function instrumentRenderProbe(source) {
  const inject = (pattern, code) => {
    let matches = 0;
    source = source.replace(pattern, match => { matches++; return `${match}\n${typeof code === 'function' ? code(match) : code}\n`; });
    if (matches !== 1) throw new Error(`Render probe expected one ${pattern}, found ${matches}`);
  };
  // A test may hold a region's next paint while the shell and network proceed.
  // Keep the hook in the temporary bundle, alongside the existing render probe.
  inject(/function \w+runtime7Sandbox5flush\(self\) \{/, match => {
    const flush = match.match(/function (\w+)/)[1];
    return `if (globalThis.__moondiffFrameBarrier?.hold(self, () => ${flush}(self))) return;`;
  });
  inject(/function \w+runtime10diff__node\(old, new_, sandbox, parent, anchor\) \{/, `
    const probe = globalThis.__moondiffMetrics;
    if (probe) {
      const region = sandbox.__moondiffProbeRegion ??= document.getElementById(sandbox.mount)?.closest('[data-region]')?.dataset.region ?? '';
      const element = old.$tag === 0 ? old._4 : parent;
      const path = region.startsWith('file:') ? region.slice(5) : element?.closest?.('[data-file-path]')?.dataset.filePath;
      if (path) {
        const counts = probe.files[path] ??= {};
        counts.vdom = (counts.vdom ?? 0) + 1;
      }
    }`);
  inject(/function \w+view12region__view\(input, emit, cache\) \{/, `
    const file = input._0?.file;
    const probe = globalThis.__moondiffMetrics;
    if (probe && file) (probe.sources ??= []).push(new WeakRef(file));`);
  inject(/function \w+runtime14cleanup__store\(id, sub_map, scheduler\) \{/, `
    if (globalThis.__moondiffMetrics) globalThis.__moondiffMetrics.active.runtimeStores--;`);
  // Both central Snapshot and region Int instantiations; avoid relying on generated suffixes.
  let stores = 0;
  source = source.replace(/function \w+runtime7Sandbox22create__state__machine\w*\(scheduler, initialize, update, subscriptions\) \{/g, match => {
    stores++;
    return `${match}\nif (globalThis.__moondiffMetrics) globalThis.__moondiffMetrics.active.runtimeStores = (globalThis.__moondiffMetrics.active.runtimeStores ?? 0) + 1;`;
  });
  if (stores !== 2) throw new Error(`Render probe expected two state instantiations, found ${stores}`);
  return source;
}

export async function installRenderProbe(page) {
  await page.addInitScript(() => {
    globalThis.__moondiffMetrics = { files: {}, active: {}, errors: [], longTasks: [] };
    addEventListener('error', event => __moondiffMetrics.errors.push(event.message));
    new PerformanceObserver(list => {
      for (const entry of list.getEntries()) __moondiffMetrics.longTasks.push({ start: entry.startTime, duration: entry.duration });
    }).observe({ type: 'longtask', buffered: true });
  });
}

export async function settleRegions(page) {
  // Includes the central commit, regional commit, and batched layout acknowledgement.
  await page.evaluate(() => new Promise(resolve => {
    let frames = 5;
    const next = () => --frames ? requestAnimationFrame(next) : resolve();
    requestAnimationFrame(next);
  }));
}

export async function renderCounts(page) {
  await settleRegions(page);
  return page.evaluate(() => structuredClone({ ...__moondiffMetrics, sources: undefined }));
}

// Time the actual state/DOM commit, excluding Playwright actionability waits and
// the deliberately extra frames used to settle layout observers in assertions.
export async function toggleCommit(page, id = 'moondiff-file-0') {
  return page.evaluate(id => new Promise(resolve => {
    const file = document.getElementById(id);
    const expanded = file.classList.contains('expanded');
    const observer = new MutationObserver(() => {
      if (file.classList.contains('expanded') === expanded) return;
      observer.disconnect();
      resolve(performance.now() - started);
    });
    observer.observe(file, { attributes: true, attributeFilter: ['class'] });
    const started = performance.now();
    file.querySelector('.file-toggle').click();
  }), id);
}
