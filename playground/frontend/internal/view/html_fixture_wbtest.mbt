///|
// Browser fixtures run through npm run test:views, with Chromium's real DOM.
fn render_test_html(builder : () -> @html.Html) -> String {
  let id = create_view_fixture()
  defer remove_view_fixture(id)
  @rabbita.new(() => @rabbita.Val::constant(builder())).mount(id)
  view_fixture_html(id)
}

///|
extern "js" fn create_view_fixture() -> String =
  #| () => {
  #|   const serial = globalThis.__moondiffViewFixtureSerial =
  #|     (globalThis.__moondiffViewFixtureSerial ?? 0) + 1;
  #|   const root = document.createElement('div');
  #|   root.id = 'moonbit-view-fixture-' + serial;
  #|   document.body.appendChild(root);
  #|   return root.id;
  #| }

///|
extern "js" fn remove_view_fixture(id : String) -> Unit =
  #| id => document.getElementById(id).remove()

///|
extern "js" fn view_fixture_html(id : String) -> String =
  #| id => {
  #|   const root = document.getElementById(id);
  #|   const snapshot = root.cloneNode(true);
  #|   // innerHTML omits a textarea's live value. Include that real DOM property
  #|   // in the detached snapshot so existing editor-body assertions retain it.
  #|   const values = [...root.querySelectorAll('textarea')].map(node => node.value);
  #|   snapshot.querySelectorAll('textarea').forEach((node, index) => {
  #|     node.textContent = values[index];
  #|   });
  #|   return snapshot.innerHTML;
  #| }
