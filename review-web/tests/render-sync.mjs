import { clockFor, waitUntil, browserDiagnostic, withRealTimeout } from './browser-control.mjs';

export async function settleRegions(page, timeout = 5_000) {
  let finished = false;
  // A single evaluation includes probe validation, both idle frames and normal
  // cleanup. Each extra Playwright call captures the large DOM in traces and
  // can itself take seconds under 6x CPU throttling.
  const observation = page.evaluate(() => {
    if (!(globalThis.__moondiffPendingPaints instanceof Set) || !globalThis.__moondiffMetrics?.layout) {
      throw new Error('settleRegions requires pending paints and layout metrics');
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
    if (error.message.includes('requires pending paints and layout metrics')) throw error;
    throw new Error(`Regional rendering did not become idle: ${JSON.stringify(await browserDiagnostic(page))}`, { cause: error });
  } finally { finished = true; }
}
