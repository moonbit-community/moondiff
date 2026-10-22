///|
extern "js" fn clone_element(element : @dom.Element) -> @dom.Element = "el => el.cloneNode(true)"

///|
// Browser fixtures run through npm run test:views, with Chromium's real DOM.
fn render_test_html(builder : () -> @html.Html) -> String {
  let id = create_view_fixture()
  defer remove_view_fixture(id)
  @rabbita.new(() => @rabbita.Val::constant(builder())).mount(id)
  view_fixture_html(id)
}

///|
let view_fixture_serial : Ref[Int32] = Ref(0)

///|
fn create_view_fixture() -> String {
  view_fixture_serial.val += 1
  let id = "moonbit-view-fixture-\{view_fixture_serial.val}"
  let root = @dom.document().create_element("div")
  root.set_attribute("id", id)
  @dom.document().get_body().unwrap().append_child(root.as_node())
  id
}

///|
fn remove_view_fixture(id : String) -> Unit {
  @browser.remove(@browser.element(id).unwrap())
}

///|
fn view_fixture_html(id : String) -> String {
  let root = @browser.element(id).unwrap()
  let snapshot = clone_element(root)
  // HTML serialization omits live textarea values; copy them into the detached clone.
  let values : Array[String] = root
    .query_selector_all("textarea")
    .iter()
    .map(node => @browser.property(node, "value"))
    .collect()
  for index, node in snapshot.query_selector_all("textarea").iter().collect() {
    @browser.set_property(node, "textContent", values[index])
  }
  @browser.property(snapshot, "innerHTML")
}
