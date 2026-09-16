///|
fn sticky_layout_after_update(generation : Int) -> @rabbita.Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, _ => sync_sticky_layout(generation))
}

///|
// CSS minimum heights remain independent of these measured offsets, so a
// responsive toolbar can shrink again after wrapping. Refresh after patching
// also observes newly loaded files before any navigation command runs.
extern "js" fn sync_sticky_layout(generation : Int) -> Unit =
  #| generation => {
  #|   if (typeof document === 'undefined') return;
  #|   const workspace = document.querySelector('.workspace');
  #|   const toolbar = workspace?.querySelector('.hero-workspace');
  #|   const main = workspace?.querySelector('.change-main');
  #|   const title = main?.querySelector('.change-titlebar');
  #|   let state = globalThis.__moondiffStickyLayout;
  #|   if (state && (state.main !== main || state.generation !== generation)) {
  #|     state.dispose();
  #|     globalThis.__moondiffStickyLayout = state = null;
  #|   }
  #|   if (!main || !toolbar || !title) return;
  #|   if (!state) {
  #|     const observed = new Set();
  #|     let signature = '';
  #|     const measure = () => {
  #|       if (!main.isConnected) return;
  #|       const toolbarHeight = toolbar.getBoundingClientRect().height;
  #|       const titleHeight = title.getBoundingClientRect().height;
  #|       const sizes = [window.innerWidth, window.innerHeight, toolbarHeight, titleHeight, main.getBoundingClientRect().width, main.offsetHeight];
  #|       const files = Array.from(main.querySelectorAll('.file-card'));
  #|       const heights = files.map(file => file.querySelector('.file-heading').getBoundingClientRect().height);
  #|       for (const [i, file] of files.entries()) {
  #|         sizes.push(heights[i], file.dataset.navigationEnabled, file.className);
  #|       }
  #|       const next = JSON.stringify([
  #|         main.dataset.navigationLayout, sizes,
  #|         Array.from(main.querySelectorAll('.semantic-section'), section => [section.dataset.sectionKey, section.open]),
  #|       ]);
  #|       if (next !== signature) main.__moondiffChangeLanding = null;
  #|       signature = next;
  #|       // Batch reads before writes when a page contains many files.
  #|       workspace.style.setProperty('--toolbar-inset', `${toolbarHeight}px`);
  #|       main.style.setProperty('--change-title-height', `${titleHeight}px`);
  #|       for (const [i, file] of files.entries()) file.style.setProperty('--file-heading-inset', `${heights[i]}px`);
  #|     };
  #|     const observer = new ResizeObserver(measure);
  #|     const onScroll = () => {
  #|       const landing = main.__moondiffChangeLanding;
  #|       if (landing && Math.abs(window.scrollY - landing.scrollY) > 1) main.__moondiffChangeLanding = null;
  #|     };
  #|     window.addEventListener('scroll', onScroll, { passive: true });
  #|     window.addEventListener('resize', measure);
  #|     state = globalThis.__moondiffStickyLayout = {
  #|       main, generation,
  #|       refresh() {
  #|         const elements = new Set([toolbar, title, main, ...main.querySelectorAll('.file-heading')]);
  #|         for (const element of observed) {
  #|           if (!elements.has(element)) { observer.unobserve(element); observed.delete(element); }
  #|         }
  #|         for (const element of elements) {
  #|           if (!observed.has(element)) { observer.observe(element); observed.add(element); }
  #|         }
  #|         measure();
  #|       },
  #|       dispose() {
  #|         observer.disconnect();
  #|         window.removeEventListener('scroll', onScroll);
  #|         window.removeEventListener('resize', measure);
  #|         workspace.style.removeProperty('--toolbar-inset');
  #|         main.__moondiffChangeLanding = null;
  #|       },
  #|     };
  #|   }
  #|   state.refresh();
  #| }
