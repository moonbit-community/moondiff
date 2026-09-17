///|
// The native popover lives in the top layer, outside diff-scroll clipping.
// Position it without CSS anchor positioning to retain Chrome 116 support.
extern "js" fn toggle_action_menu(event : @dom.MouseEvent) -> Unit =
  #| event => {
  #|   event.preventDefault();
  #|   const button = event.currentTarget;
  #|   const menu = button.parentElement.querySelector('[role="menu"]');
  #|   button.popoverTargetElement = menu;
  #|   if (menu.matches(':popover-open')) { menu.hidePopover(); return; }
  #|   const rect = button.getBoundingClientRect();
  #|   const controller = new AbortController();
  #|   const options = { signal: controller.signal };
  #|   menu.addEventListener('beforetoggle', event => {
  #|     if (event.newState === 'closed') {
  #|       button.setAttribute('aria-expanded', 'false');
  #|       controller.abort();
  #|     }
  #|   }, options);
  #|   const dismiss = event => {
  #|     if (!menu.isConnected) { controller.abort(); return; }
  #|     if (event.type === 'scroll' && menu.contains(event.target)) return;
  #|     const current = button.getBoundingClientRect();
  #|     // A scroll queued by bringing the trigger into view may arrive after opening.
  #|     if (event.type === 'scroll' && current.top === rect.top && current.right === rect.right) return;
  #|     menu.hidePopover();
  #|     controller.abort();
  #|   };
  #|   window.addEventListener('scroll', dismiss, { ...options, capture: true });
  #|   window.addEventListener('resize', dismiss, options);
  #|   menu.showPopover();
  #|   button.setAttribute('aria-expanded', 'true');
  #|   const box = menu.getBoundingClientRect();
  #|   menu.style.left = Math.max(8, Math.min(rect.right - box.width, innerWidth - box.width - 8)) + 'px';
  #|   const top = rect.bottom + 4 + box.height <= innerHeight - 8 ? rect.bottom + 4 : rect.top - box.height - 4;
  #|   menu.style.top = Math.max(8, Math.min(top, innerHeight - box.height - 8)) + 'px';
  #|   menu.querySelector('[role="menuitem"]:not(:disabled)')?.focus({ preventScroll: true });
  #| }

///|
extern "js" fn dismiss_action_menu(event : @dom.MouseEvent) -> Unit =
  #| event => {
  #|   if (!event.target.closest('[role="menuitem"]:not(:disabled)')) return;
  #|   const menu = event.currentTarget;
  #|   menu.hidePopover();
  #|   menu.parentElement.querySelector('[aria-haspopup="menu"]').focus({ preventScroll: true });
  #| }

///|
extern "js" fn action_menu_button_key(event : @dom.KeyboardEvent) -> Unit =
  #| event => {
  #|   if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return;
  #|   event.preventDefault();
  #|   const button = event.currentTarget;
  #|   const menu = button.parentElement.querySelector('[role="menu"]');
  #|   if (!menu.matches(':popover-open')) button.click();
  #|   const items = menu.querySelectorAll('[role="menuitem"]:not(:disabled)');
  #|   items[event.key === 'ArrowUp' ? items.length - 1 : 0]?.focus({ preventScroll: true });
  #| }

///|
extern "js" fn action_menu_key(event : @dom.KeyboardEvent) -> Unit =
  #| event => {
  #|   const menu = event.currentTarget;
  #|   if (event.key === 'Escape' || event.key === 'Tab') {
  #|     if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); }
  #|     menu.hidePopover();
  #|     menu.parentElement.querySelector('[aria-haspopup="menu"]').focus({ preventScroll: true });
  #|     return;
  #|   }
  #|   if (event.key === ' ' && event.target.matches('a[role="menuitem"]')) {
  #|     event.preventDefault(); event.target.click(); return;
  #|   }
  #|   const items = Array.from(menu.querySelectorAll('[role="menuitem"]:not(:disabled)'));
  #|   const index = items.indexOf(document.activeElement);
  #|   let next;
  #|   if (event.key === 'ArrowDown') next = (index + 1) % items.length;
  #|   else if (event.key === 'ArrowUp') next = (index + items.length - 1) % items.length;
  #|   else if (event.key === 'Home') next = 0;
  #|   else if (event.key === 'End') next = items.length - 1;
  #|   else return;
  #|   event.preventDefault();
  #|   items[next]?.focus({ preventScroll: true });
  #| }
