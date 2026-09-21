///|
priv struct Snapshot(@application.Model)

///|
impl Eq for Snapshot with fn equal(a, b) {
  @identity.same(a.0, b.0)
}

///|
// The scheduler may retain consumed queue slots. Empty the envelope as soon as
// the reducer receives it so those slots cannot retain old source responses.
priv struct Event {
  mut message : @application.Msg?
}

///|
fn Coordinator::forward(
  self : Coordinator,
  raw : @rabbita.Emit[Event],
) -> @rabbita.Emit[@application.Msg] {
  Emit(msg => @cmd.custom_cmd(_ => self.run(raw({ message: Some(msg), }))))
}

///|
pub fn start(id : String) -> Unit {
  initialize_layout()
  let coordinator = Coordinator::new()
  @rabbita.new(() => {
    let (model, raw) = @rabbita.create_state_with_init(
      init=raw => {
        let (model, command) = @application.app_init(coordinator.forward(raw))
        let generation = model.generation
        let revision = coordinator.begin_update(generation, [])
        (
          Snapshot(model),
          @cmd.custom_cmd(scheduler => {
            coordinator.scheduler = Some(scheduler)
            scheduler.add(
              @cmd.batch([
                coordinator.after_update(generation, revision, []),
                command,
              ]),
            )
          }),
        )
      },
      update=(before, event, raw) => {
        guard event.message is Some(msg) else { return (before, @rabbita.none) }
        event.message = None
        capture_editor()
        let transition = @application.update(
          before.0,
          msg,
          coordinator.forward(raw),
        )
        let generation = transition.model.generation
        // Landing/loading models can still retain the previous route's review.
        // Check the session's generation: a reload can retain an older draft ID.
        let draft_id = if transition.model.review.generation() == generation {
          transition.model.review.draft().map(d => d.id.key()).unwrap_or("")
        } else {
          ""
        }
        active_draft(
          draft_id,
          transition.model.review.draft_visible(),
          generation,
        )
        let revision = coordinator.begin_update(
          generation,
          transition.after_commit,
        )
        // Region actions bind to tickets after the central projection; page
        // navigation has already replaced the previous intent in begin_update.
        let after = coordinator.after_update(
          generation,
          revision,
          transition.after_commit.filter(action => action.scope is Region),
        )
        (Snapshot(transition.model), @cmd.batch([after, transition.command]))
      },
      subscriptions=(model, raw) => {
        @application.app_subscriptions(model.0, coordinator.forward(raw))
      },
    )
    let emit = coordinator.forward(raw)
    let projection = @view.RegionProjection::new()
    let inputs = model.map(snapshot => {
      @vector.Vector::from_array(
        projection
        .inputs(snapshot.0)
        .map(entry => {
          let (region, input) = entry
          ((snapshot.0.generation, region), input)
        }),
      )
    })
    let hosts = inputs.assoc(fn(key, input) {
      let (generation, region) = key
      region_component(coordinator, generation, region, input, emit)
    })
    model
    .map(snapshot => @view.shell_input(snapshot.0))
    .map2(hosts, (shell, hosts) => @view.shell_view(shell, hosts.to_array()))
  }).mount(id)
}
