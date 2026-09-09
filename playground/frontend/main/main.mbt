///|
fn main {
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state_with_init(
      init=app_init,
      update~,
      subscriptions=app_subscriptions,
    )
    model.map(model => app_view(model, emit))
  }).mount("app")
}
