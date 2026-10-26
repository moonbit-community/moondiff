import { waitUntil, browserDiagnostic } from './browser-control.mjs';

// Register before the trusted wheel/key event. scrollend alone is insufficient:
// a layout callback may still change the position, hence three stable frames.
export async function scrollAndWait(page, action) {
  await page.evaluate(() => {
    const state = { startX: scrollX, startY: scrollY, moved: false, ended: false, stable: 0, done: false };
    const moved = () => {
      if (scrollX !== state.startX || scrollY !== state.startY) state.moved = true;
      state.ended = false; state.stable = 0;
    };
    const ended = () => { if (state.moved) state.ended = true; };
    document.addEventListener('scroll', moved, true);
    document.addEventListener('scrollend', ended, true);
    let frame;
    const tick = () => {
      const same = scrollX === state.x && scrollY === state.y;
      state.stable = state.moved && state.ended && same ? state.stable + 1 : 0;
      state.x = scrollX; state.y = scrollY;
      state.done = state.stable >= 3;
      if (!state.done) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    globalThis.__moondiffScrollWait = { state, cleanup() {
      cancelAnimationFrame(frame);
      document.removeEventListener('scroll', moved, true);
      document.removeEventListener('scrollend', ended, true);
    } };
  });
  try {
    await action();
    await waitUntil(() => page.evaluate(() => globalThis.__moondiffScrollWait.state.done), {
      label: 'native scrollend and three stable frames',
      diagnostic: async () => ({ ...(await browserDiagnostic(page)), scroll: await page.evaluate(() => globalThis.__moondiffScrollWait.state) }),
    });
  } finally {
    if (!page.isClosed()) await page.evaluate(() => {
      globalThis.__moondiffScrollWait?.cleanup();
      delete globalThis.__moondiffScrollWait;
    });
  }
}
