///|
pub fn navigate_section_change(
  event : @dom.MouseEvent,
  generation : Int,
  file_index : Int,
  direction : Int,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  find_section_change(
    event,
    direction,
    section_change_inset,
    (key, block) => {
      emit(Load(NavigateChange(generation, file_index, key, block, direction)))
    },
    @rabbita.none,
  )
}

///|
// Share the measured sticky inset between selection and landing. Long titles
// and responsive toolbars can be taller than the CSS minimums.
extern "js" fn section_change_inset(section : @dom.Element) -> Double =
  #| section => {
  #|   const summary = section.querySelector('.semantic-section-title');
  #|   const heading = section.closest('.file-card').querySelector('.file-heading');
  #|   const toolbar = document.querySelector('.hero-workspace');
  #|   const stickyTop = Math.max(
  #|     parseFloat(getComputedStyle(summary).top) || 0,
  #|     (toolbar?.getBoundingClientRect().height || 0) + heading.getBoundingClientRect().height
  #|   );
  #|   return stickyTop + summary.getBoundingClientRect().height + 8;
  #| }

///|
// Re-read geometry on every activation, including after manual scrolling or a
// layout switch. Collapsed details still contain their source row markers.
extern "js" fn find_section_change(
  event : @dom.MouseEvent,
  direction : Int,
  inset : (@dom.Element) -> Double,
  navigate : (String, Int) -> @rabbita.Cmd,
  none : @rabbita.Cmd,
) -> @rabbita.Cmd =
  #| (event, direction, inset, navigate, none) => {
  #|   event.preventDefault();
  #|   event.stopPropagation();
  #|   const file = event.currentTarget.closest('.file-card');
  #|   if (!file?.classList.contains('expanded')) return none;
  #|   const sections = Array.from(file.querySelectorAll('.semantic-section'));
  #|   if (!sections.length) return none;
  #|   const heading = file.querySelector('.file-heading');
  #|   const stickyTop = Math.max(
  #|     parseFloat(getComputedStyle(heading).top) || 0,
  #|     document.querySelector('.hero-workspace')?.getBoundingClientRect().height || 0
  #|   ) + heading.getBoundingClientRect().height;
  #|   let section = sections[0];
  #|   for (const candidate of sections) {
  #|     if (candidate.getBoundingClientRect().top > stickyTop + 1) break;
  #|     section = candidate;
  #|   }
  #|   // A clamped landing cannot reach the reading edge. Keep that target
  #|   // until scrolling or layout changes invalidate its measured position.
  #|   const landing = file.__moondiffChangeLanding;
  #|   const atLanding = landing?.target.isConnected &&
  #|     landing.target.closest('.semantic-section')?.open &&
  #|     Math.abs(window.scrollY - landing.scrollY) <= 1 &&
  #|     document.documentElement.scrollHeight === landing.scrollHeight &&
  #|     Math.abs(landing.target.getBoundingClientRect().top - landing.top) <= 1;
  #|   if (atLanding) section = landing.target.closest('.semantic-section');
  #|   const blocks = Array.from(section.querySelectorAll('[data-change-block-start]'));
  #|   // Use the landing edge even before the section title becomes sticky.
  #|   const readingEdge = inset(section) + 1;
  #|   let current = -1;
  #|   for (let i = 0; section.open && i < blocks.length; i++) {
  #|     if (blocks[i].getBoundingClientRect().top > readingEdge) break;
  #|     current = i;
  #|   }
  #|   if (atLanding) current = blocks.indexOf(landing.target);
  #|   const next = current + direction;
  #|   if (next >= 0 && next < blocks.length) {
  #|     return navigate(section.dataset.sectionKey, Number(blocks[next].dataset.changeBlockStart));
  #|   }
  #|   // DOM order includes the trailing group of deleted declarations and
  #|   // confines traversal to this file, skipping sections without changes.
  #|   for (let i = sections.indexOf(section) + direction; i >= 0 && i < sections.length; i += direction) {
  #|     const targets = sections[i].querySelectorAll('[data-change-block-start]');
  #|     if (!targets.length) continue;
  #|     const target = targets[direction > 0 ? 0 : targets.length - 1];
  #|     return navigate(sections[i].dataset.sectionKey, Number(target.dataset.changeBlockStart));
  #|   }
  #|   return none;
  #| }

///|
fn navigate_change_after_render(
  generation : Int,
  file_index : Int,
  section_key : String,
  block : Int,
  direction : Int,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, _ => {
    scroll_to_section_change(
      generation,
      file_dom_id(file_index),
      section_key,
      block,
      direction,
      section_change_inset,
    )
  })
}

///|
extern "js" fn scroll_to_section_change(
  generation : Int,
  file_id : String,
  section_key : String,
  block : Int,
  direction : Int,
  inset : (@dom.Element) -> Double,
) -> Unit =
  #| (generation, fileId, sectionKey, block, direction, inset) => {
  #|   const file = document.getElementById(fileId);
  #|   const section = Array.from(file?.querySelectorAll('.semantic-section') || []).find(
  #|     element => element.dataset.sectionKey === sectionKey && element.dataset.navigationGeneration === String(generation)
  #|   );
  #|   if (!section?.open) return;
  #|   const target = section.querySelector(`[data-change-block-start="${block}"]`);
  #|   if (!target) return;
  #|   const top = window.scrollY + target.getBoundingClientRect().top - inset(section);
  #|   const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
  #|   window.scrollTo({ top: Math.max(0, Math.min(top, max)), behavior: 'instant' });
  #|   file.__moondiffChangeLanding = top > max || top < 0 ? {
  #|     target,
  #|     scrollY: window.scrollY,
  #|     scrollHeight: document.documentElement.scrollHeight,
  #|     top: target.getBoundingClientRect().top,
  #|   } : null;
  #|   file.querySelector(`.file-heading [data-change-direction="${direction}"]`)?.focus({ preventScroll: true });
  #| }
