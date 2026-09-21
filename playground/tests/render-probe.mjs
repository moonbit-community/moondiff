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
    return `
      const pendingPaints = globalThis.__moondiffPendingPaints ??= new Set();
      if (!self.paint_scheduled) {
        pendingPaints.add(self);
        if (globalThis.__moondiffMetrics) globalThis.__moondiffMetrics.pendingPaints = pendingPaints.size;
      }
      if (globalThis.__moondiffFrameBarrier?.hold(self, () => ${flush}(self))) return;`;
  });
  inject(/self\.paint_scheduled = false;/, `
    globalThis.__moondiffPendingPaints?.delete(self);
    if (globalThis.__moondiffMetrics) globalThis.__moondiffMetrics.pendingPaints = globalThis.__moondiffPendingPaints?.size ?? 0;`);
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
    globalThis.__moondiffPendingPaints = new Set();
    globalThis.__moondiffMetrics = { files: {}, active: {}, errors: [], longTasks: [], pendingPaints: 0 };
    addEventListener('error', event => __moondiffMetrics.errors.push(event.message));
    new PerformanceObserver(list => {
      for (const entry of list.getEntries()) __moondiffMetrics.longTasks.push({ start: entry.startTime, duration: entry.duration });
    }).observe({ type: 'longtask', buffered: true });
  });
}

export async function settleRegions(page, timeout = 5_000) {
  // Two consecutive idle animation frames cover central/regional paints and a
  // layout callback that schedules more work later in the same frame.
  const result = await page.evaluate(timeout => new Promise(resolve => {
    let stableFrames = 0;
    let animationFrame = 0;
    let finished = false;
    const snapshot = () => {
      const layout = globalThis.__moondiffRegionLayout;
      const pending = globalThis.__moondiffPendingPaints;
      return {
        pendingPaints: pending?.size ?? 0,
        pendingMounts: pending ? [...pending].map(sandbox => sandbox.mount) : [],
        layoutFrame: layout?.frame ?? 0,
        layoutDirty: layout?.dirty?.size ?? 0,
        layoutCallbacks: layout?.callbacks?.length ?? 0,
      };
    };
    const done = value => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      if (animationFrame) cancelAnimationFrame(animationFrame);
      resolve(value);
    };
    const next = () => {
      animationFrame = requestAnimationFrame(() => {
        animationFrame = 0;
        const state = snapshot();
        const idle = state.pendingPaints === 0 && state.layoutFrame === 0 &&
          state.layoutDirty === 0 && state.layoutCallbacks === 0;
        stableFrames = idle ? stableFrames + 1 : 0;
        if (stableFrames >= 2) done({ ok: true, state });
        else next();
      });
    };
    const timer = setTimeout(() => done({ ok: false, state: snapshot(), stableFrames }), timeout);
    next();
  }), timeout);
  if (!result.ok) throw new Error(`Regional rendering did not become idle: ${JSON.stringify(result)}`);
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

// Measure a trusted pointer interaction through the second animation frame
// after the native details state changes. The extra frame makes the duration a
// stable proxy for the first paint that can display the new state.
export async function toggleDetailsPaint(page, selector, inputSession) {
  const box = await page.evaluate(selector => {
    const summary = document.querySelector(selector);
    const details = summary?.closest('details');
    if (!summary || !details) throw new Error(`Missing details summary: ${selector}`);
    summary.scrollIntoView({ block: 'nearest' });
    const rect = summary.getBoundingClientRect();
    if (!rect.width || !rect.height) throw new Error(`Details summary is not visible: ${selector}`);
    globalThis.__moondiffDetailsPaint = new Promise(resolve => {
      const open = details.open;
      summary.addEventListener('pointerdown', event => {
        const dispatched = performance.now();
        const started = event.timeStamp;
        const observer = new MutationObserver(() => {
          if (details.open === open) return;
          observer.disconnect();
          requestAnimationFrame(() => requestAnimationFrame(() => {
            const finished = performance.now();
            resolve({
              duration: finished - started,
              inputDelay: dispatched - started,
              frameDelay: finished - dispatched,
              open: details.open,
            });
          }));
        });
        observer.observe(details, { attributes: true, attributeFilter: ['open'] });
      }, { once: true });
    });
    return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
  }, selector);
  const session = inputSession ?? await page.context().newCDPSession(page);
  try {
    await session.send('Input.dispatchMouseEvent', { type: 'mouseMoved', ...box });
    await session.send('Input.dispatchMouseEvent', { type: 'mousePressed', ...box, button: 'left', buttons: 1, clickCount: 1 });
    await session.send('Input.dispatchMouseEvent', { type: 'mouseReleased', ...box, button: 'left', buttons: 0, clickCount: 1 });
    return await page.evaluate(async () => {
      const result = await globalThis.__moondiffDetailsPaint;
      delete globalThis.__moondiffDetailsPaint;
      return result;
    });
  } finally {
    if (!inputSession) await session.detach();
  }
}
