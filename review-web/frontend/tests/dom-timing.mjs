import { expect } from '@playwright/test';

// Hold selected regional paints without freezing Playwright's actionability
// frames. The corresponding hook exists only in serve.mjs's temporary bundle.
export async function holdRegionFrames(page, regions) {
  await page.evaluate(regions => {
    if (globalThis.__moondiffFrameBarrier) throw new Error('A frame barrier is already installed');
    globalThis.__moondiffFrameBarrier = {
      regions: new Set(regions),
      pending: new Map(),
      hold(sandbox, resume) {
        const region = document.getElementById(sandbox.mount)?.closest('[data-region]')?.dataset.region;
        if (!this.regions.has(region)) return false;
        this.pending.set(sandbox, { region, resume });
        return true;
      },
    };
  }, regions);
  return {
    async blocked(selected = regions) {
      await page.waitForFunction(regions => {
        const pending = [...globalThis.__moondiffFrameBarrier.pending.values()];
        return regions.every(region => pending.some(entry => entry.region === region));
      }, selected, { timeout: 5_000 });
    },
    async release(selected = regions) {
      await page.evaluate(selected => {
        const barrier = globalThis.__moondiffFrameBarrier;
        if (!barrier) return;
        for (const region of selected) barrier.regions.delete(region);
        if (!barrier.regions.size) delete globalThis.__moondiffFrameBarrier;
        for (const [sandbox, { region, resume }] of barrier.pending) {
          if (!selected.includes(region)) continue;
          barrier.pending.delete(sandbox);
          resume();
        }
      }, selected);
    },
  };
}

export function operationCheckpoint(label) {
  let reached;
  const checkpoint = new Promise(resolve => { reached = resolve; });
  let tracked = false;
  let settled = false;
  let settledAtCheckpoint;
  return {
    track(operation) {
      if (tracked) throw new Error(`Operation checkpoint is already tracking: ${label}`);
      tracked = true;
      operation.then(() => { settled = true; }, () => { settled = true; });
      return operation;
    },
    reach() {
      if (settledAtCheckpoint !== undefined) return;
      settledAtCheckpoint = settled;
      reached();
    },
    async expectPending() {
      if (!tracked) throw new Error(`Operation checkpoint is not tracking: ${label}`);
      await checkpoint;
      expect(settledAtCheckpoint, label).toBe(false);
    },
  };
}
