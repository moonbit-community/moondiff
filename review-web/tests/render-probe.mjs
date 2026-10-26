import { clockFor, waitUntil, browserDiagnostic, withRealTimeout } from './browser-control.mjs';

// Instrument only the temporary E2E bundle. Dependency sources are never edited.
export function instrumentRenderProbe(source) {
  const inject = (pattern, code) => {
    let matches = 0;
    source = source.replace(pattern, match => { matches++; return `${match}\n${typeof code === 'function' ? code(match) : code}\n`; });
    if (matches !== 1) throw new Error(`Render probe expected one ${pattern}, found ${matches}`);
  };
  inject(/const (\w+github__client6client) = [^\n]+;/, match => {
    const client = match.match(/const (\w+)/)[1];
    return `
      // Return fresh scalar/array copies; no mutable application objects escape.
      globalThis.__moondiffTestState = () => {
        const client = ${client}, w = client.workspace;
        return {
          generation: client.generation, identityEpoch: w.epoch,
          checking: w.checking, sourcePaused: w.source_pause !== undefined,
          home: w.home, prefetchReady: w.prefetch_ready, limited: w.limited,
          round: w.round, candidateIndex: w.index,
          candidates: w.candidates.map(c => 'pull:' + c.pull.owner.toLowerCase() + '/' + c.pull.repo.toLowerCase() + '/' + c.pull.number),
          sourceIndex: w.source_index, sourceCount: w.source_queue.length,
          backgroundOwner: w.background_owner ?? null,
          reads: w.reads.size, tasks: w.tasks.size,
          cache: w.cache.map(entry => ({ key: entry.key, kind: entry.payload.$tag, created: entry.created })),
          application: structuredClone(globalThis.__moondiffBusiness),
        };
      };`;
  });
  let updates = 0;
  source = source.replace(/function (\w+application6update)\(model, msg, emit\) \{[\s\S]*?\n\}/g, (body, name) => {
    updates++;
    return `${body.replace(`function ${name}(`, `function ${name}__probed(`)}
      function ${name}(model, msg, emit) {
        const result = ${name}__probed(model, msg, emit), next = result.model;
        globalThis.__moondiffBusiness = {
          generation: next.generation, pageVisible: next.page_visible,
          viewed: { ready: next.viewed.ready, loading: next.viewed.loading,
            readSerial: next.viewed.read_serial, pollScheduled: next.viewed.poll_scheduled,
            retry: next.viewed.retry, stale: next.viewed.stale },
          merge: { loading: next.pull_merge.loading, pollScheduled: next.pull_merge.poll_scheduled,
            serial: next.pull_merge.serial, retry: next.pull_merge.retry },
        };
        return result;
      }`;
  });
  if (updates !== 1) throw new Error(`Render probe expected one application update, found ${updates}`);
  // Every test using settleRegions needs the scalar layout snapshot, even when
  // it does not install the full performance probe. Initialize before the
  // coordinator starts; this hook exists only in the temporary E2E bundle.
  inject(/function \w+rendering5start\(id\) \{/, `
    globalThis.__moondiffMetrics ??= { files: {}, active: {} };
    globalThis.__moondiffPendingPaints ??= new Set();`);
  // A test may hold a region's next paint while the shell and network proceed.
  // Keep the hook in the temporary bundle, alongside the existing render probe.
  // BrowserHost replaced Sandbox; retain the mount ID for regional barriers.
  inject(/_host\.document = \w+VDom10initialize\([^;]+;/,
    '_host.mount = element_id;');
  inject(/function \w+runtime11BrowserHost14request__frame\(self\) \{/, match => {
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
  inject(/function \w+vdom10diff__node\(old, new_, scheduler, captured_link_listener, parent, anchor\) \{/, `
    const probe = globalThis.__moondiffMetrics;
    if (probe) {
      const sandbox = scheduler.self;
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
  inject(/function \w+runtime14cleanup__store\(stores, id, sub_map, scheduler\) \{/, `
    if (globalThis.__moondiffMetrics) globalThis.__moondiffMetrics.active.runtimeStores--;`);
  // Both central Snapshot and region Int instantiations; avoid relying on generated suffixes.
  let stores = 0;
  source = source.replace(/function \w+runtime22create__state__machine\w*\(initialize, update, subscriptions\) \{/g, match => {
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
  let finished = false;
  // A single evaluation includes probe validation, both idle frames and normal
  // cleanup. Each extra Playwright call captures the large DOM in traces and
  // can itself take seconds under 6x CPU throttling.
  const observation = page.evaluate(() => {
    if (typeof globalThis.__moondiffTestState !== 'function' || !(globalThis.__moondiffPendingPaints instanceof Set)) {
      throw new Error('settleRegions requires instrumentRenderProbe in the temporary browser bundle');
    }
    if (globalThis.__moondiffSettleFrame) throw new Error('Concurrent regional render wait');
    return new Promise(resolve => {
      const state = { stable: 0 };
      state.cancel = () => { cancelAnimationFrame(state.frame); resolve(false); };
      const next = () => {
        state.frame = requestAnimationFrame(() => {
          const layout = globalThis.__moondiffMetrics?.layout;
          const idle = globalThis.__moondiffPendingPaints.size === 0 &&
            layout?.frame === 0 && layout?.dirty === 0 && layout?.callbacks === 0;
          state.stable = idle ? state.stable + 1 : 0;
          if (state.stable >= 2) { delete globalThis.__moondiffSettleFrame; resolve(true); }
          else next();
        });
      };
      globalThis.__moondiffSettleFrame = state;
      next();
    });
  }).then(result => { finished = true; return result; });
  const completed = withRealTimeout(observation, timeout, 'regional render commit (two idle frames)');
  try {
    const clock = clockFor(page);
    if (clock) {
      const advance = async () => {
        // Complete a round trip after registration before advancing frames.
        await page.evaluate(() => {});
        await waitUntil(async () => {
          if (!finished) await clock.frames();
          return finished;
        }, { label: 'controlled regional render frames', timeout });
      };
      await Promise.all([completed, advance()]);
    } else {
      await completed;
    }
  } catch (error) {
    finished = true;
    if (!page.isClosed()) await page.evaluate(() => {
      globalThis.__moondiffSettleFrame?.cancel();
      delete globalThis.__moondiffSettleFrame;
    });
    if (error.message.includes('requires instrumentRenderProbe')) throw error;
    throw new Error(`Regional rendering did not become idle: ${JSON.stringify(await browserDiagnostic(page))}`, { cause: error });
  } finally { finished = true; }
}

export async function waitForState(page, predicate, label = 'application state', options = {}) {
  const read = async () => {
    const state = await page.evaluate(() => {
      if (!globalThis.__moondiffTestState) throw new Error('Missing temporary application probe');
      return globalThis.__moondiffTestState();
    });
    return predicate(state) && state;
  };
  const clock = clockFor(page);
  const result = clock ? await clock.until(read, label, options)
    : await waitUntil(read, { ...options, label, diagnostic: () => browserDiagnostic(page) });
  await settleRegions(page);
  return result;
}

export async function waitForPrefetch(page, { owner, repo, number, sources = [] }) {
  const key = `pull:${owner.toLowerCase()}/${repo.toLowerCase()}/${number}`;
  return waitForState(page, state => !state.checking &&
    state.cache.some(entry => entry.key === key) && sources.every(source => state.cache.some(entry => {
      if (!entry.key.startsWith('{')) return false;
      const request = JSON.parse(entry.key).request;
      const args = request['0'];
      return request.$tag === 'ContentGet' && Object.entries(source).every(([key, value]) => args[key] === value);
    })), `prefetched snapshot and source pair for ${key}`);
}

export const waitForPrefetchRound = (page, { afterRound = -1 } = {}) => waitForState(page, state =>
  state.round > afterRound && state.home && state.prefetchReady && state.backgroundOwner === null &&
  state.candidateIndex === state.candidates.length && state.sourceIndex === state.sourceCount,
  'completed prefetch round');

export async function renderCounts(page, timeout = 5_000) {
  await settleRegions(page, timeout);
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
