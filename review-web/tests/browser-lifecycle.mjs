// The only dependency on Playwright's private navigation protocol. Tested with
// the pinned Playwright version by browser-lifecycle.spec.mjs. Public
// framenavigated events also include same-document navigation and cannot retire
// requests. Do not fall back to URLs or pagehide when this contract changes.
export function observeDocumentCommits(frame, committed) {
  const emitter = frame?._eventEmitter;
  const incompatible = detail => new Error(`Incompatible Playwright Frame navigation adapter: ${detail}`);
  if (frame?._type !== 'Frame' || typeof emitter?.on !== 'function' || typeof emitter?.off !== 'function') {
    throw incompatible('expected Frame._eventEmitter; run the lifecycle compatibility tests after upgrading Playwright');
  }
  const navigated = event => {
    if (!event || typeof event.url !== 'string' || typeof event.name !== 'string' ||
        (event.error !== undefined && typeof event.error !== 'string') ||
        (event.newDocument !== undefined && (!event.newDocument || typeof event.newDocument !== 'object' || Array.isArray(event.newDocument)))) {
      throw incompatible('unexpected navigated event shape');
    }
    const channel = event.newDocument?.request;
    const request = channel?._object;
    if (channel !== undefined && (request?._type !== 'Request' ||
        typeof request.redirectedFrom !== 'function' || typeof request.isNavigationRequest !== 'function' ||
        !request.isNavigationRequest())) {
      throw incompatible('expected newDocument.request to be a Request channel');
    }
    if (event.newDocument && !event.error) committed({ url: event.url, request });
  };
  emitter.on('navigated', navigated);
  let disposed = false;
  return () => {
    if (disposed) return;
    disposed = true;
    emitter.off('navigated', navigated);
  };
}
