///|
// One shared frame batches all region measurements before writing any offsets.
extern "js" fn initialize_layout() -> Unit =
  #| () => {
  #|   globalThis.__moondiffRegionLayout ??= {
  #|     dirty: new Set(), records: new Map(), callbacks: [], frame: 0,
  #|     schedule() {
  #|       if (this.frame) return;
  #|       this.frame = requestAnimationFrame(() => {
  #|         this.frame = 0;
  #|         const reads = [];
  #|         for (const record of this.dirty) {
  #|           if (record.alive && record.host.isConnected) {
  #|             reads.push([record, record.elements.map(el => el.getBoundingClientRect().height)]);
  #|           }
  #|         }
  #|         this.dirty.clear();
  #|         for (const [record, heights] of reads) record.write(heights);
  #|         const callbacks = this.callbacks.splice(0);
  #|         for (const callback of callbacks) callback();
  #|       });
  #|     }
  #|   };
  #| }

///|
extern "js" fn observe_layout(host : String, region : String) -> () -> Unit =
  #| (hostId, region) => {
  #|   const state = globalThis.__moondiffRegionLayout;
  #|   const host = document.getElementById(hostId);
  #|   const main = host.closest('.change-main') ?? document.querySelector('.change-main');
  #|   const elements = [];
  #|   let write = () => {};
  #|   if (region.startsWith('file:')) {
  #|     const file = host.querySelector('.file-card');
  #|     const heading = file?.querySelector('.file-heading');
  #|     if (heading) {
  #|       elements.push(heading, file);
  #|       write = heights => {
  #|         file.style.setProperty('--file-heading-inset', `${heights[0]}px`);
  #|         if (main) main.__moondiffChangeLanding = null;
  #|       };
  #|     }
  #|   } else if (region === 'toolbar') {
  #|     const toolbar = host.querySelector('.hero-workspace');
  #|     if (toolbar) {
  #|       const workspace = host.closest('.workspace');
  #|       elements.push(toolbar);
  #|       write = heights => { workspace.style.setProperty('--toolbar-inset', `${heights[0]}px`); };
  #|     }
  #|   } else if (region === 'navigation' && main) {
  #|     const title = host.closest('.change-titlebar');
  #|     elements.push(title, main);
  #|     write = heights => {
  #|       main.style.setProperty('--change-title-height', `${heights[0]}px`);
  #|       main.__moondiffChangeLanding = null;
  #|     };
  #|   }
  #|   const record = { alive: true, host, elements, write };
  #|   const onResize = () => { if (main) main.__moondiffChangeLanding = null; state.dirty.add(record); state.schedule(); };
  #|   const onScroll = () => {
  #|     const landing = main?.__moondiffChangeLanding;
  #|     if (landing && Math.abs(window.scrollY - landing.scrollY) > 1) main.__moondiffChangeLanding = null;
  #|   };
  #|   if (region === 'navigation') {
  #|     window.addEventListener('resize', onResize);
  #|     window.addEventListener('scroll', onScroll, { passive: true });
  #|   }
  #|   const observer = elements.length ? new ResizeObserver(() => { state.dirty.add(record); state.schedule(); }) : null;
  #|   for (const element of elements) observer.observe(element);
  #|   if (observer) {
  #|     state.dirty.add(record); state.schedule();
  #|     if (globalThis.__moondiffMetrics) globalThis.__moondiffMetrics.active.observers = (globalThis.__moondiffMetrics.active.observers ?? 0) + 1;
  #|   }
  #|   state.records.set(hostId, record);
  #|   return () => {
  #|     record.alive = false;
  #|     observer?.disconnect();
  #|     if (region === 'navigation') {
  #|       window.removeEventListener('resize', onResize);
  #|       window.removeEventListener('scroll', onScroll);
  #|     }
  #|     if (region === 'toolbar') host.closest('.workspace')?.style.removeProperty('--toolbar-inset');
  #|     state.dirty.delete(record); state.records.delete(hostId);
  #|     if (observer && globalThis.__moondiffMetrics) globalThis.__moondiffMetrics.active.observers--;
  #|     if (main) main.__moondiffChangeLanding = null;
  #|   };
  #| }

///|
// ResizeObserver may deliver after a frame's callbacks. Explicitly include the
// just-committed region in the next read/write batch before acknowledging it.
extern "js" fn invalidate_layout(host : String) -> Unit =
  #| host => {
  #|   const state = globalThis.__moondiffRegionLayout;
  #|   const record = state.records.get(host);
  #|   if (record) state.dirty.add(record);
  #| }

///|
extern "js" fn after_layout(callback : () -> Unit) -> Unit =
  #| callback => {
  #|   const state = globalThis.__moondiffRegionLayout;
  #|   state.callbacks.push(callback);
  #|   state.schedule();
  #| }
