///|
pub fn region_view(
  input : RegionInput,
  emit : @rabbita.Emit[Msg],
  cache : FileDerivation,
) -> @rabbita.Html {
  match input {
    Toolbar(input) => hero_view(input, input.landing, emit)
    Status(input) =>
      match input {
        Empty => @html.nothing
        Loading(message) =>
          @html.div(class="empty-state loading", [
            @html.span(class="spinner", ""),
            @html.span(message),
          ])
        Failed(message, auth) =>
          @html.div(class="empty-state error", [
            @html.p(message),
            auth_controls(auth, emit),
            @html.button(
              type_="button",
              class="secondary",
              on_click=emit(Ui(Submit)),
              "Try again",
            ),
          ])
      }
    FileTree(input) =>
      @html.fragment([
        file_tree_view(input, emit),
        file_tree_resizer_view(input.state, emit),
      ])
    Navigation(input) => change_controls(input, emit)
    ViewedSummary(input) => viewed_progress_input(input, emit)
    Discussion(input) =>
      comments_overview(input.is_pull, input.review, input.auth, emit)
    File(input) => {
      let file = input.file
      let options = input.display
      @metrics.count(file.file.filename, "view")
      let projection = file_projection(
        file,
        input.index,
        options.mode,
        options.algorithm,
        options.ignore_comments,
        options.ignore_tests,
        cache,
      )
      let discussions = prepare_discussions(
        Some(file.file),
        Some(input.index),
        input.review,
        emit,
        cache~,
        projection~,
      )
      @html.fragment([
        file_card(
          file,
          input.generation,
          input.index,
          options.mode,
          options.algorithm,
          options.ignore_comments,
          options.ignore_tests,
          input.review,
          emit,
          navigation_enabled=input.navigation_enabled,
          viewed=viewed_checkbox_input(input.viewed, emit),
          viewed_error=viewed_error_input(input.viewed, emit),
          discussions~,
        ),
        fallback_discussions(discussions, Some(input.index)),
      ])
    }
  }
}

///|
pub(all) struct MountHost {
  region : @application.Region
  id : String
} derive(Eq)

///|
fn region_host(host : MountHost) -> @rabbita.Html {
  // Only this empty element belongs to the shell. A child root owns its interior.
  @html.div(
    id=host.id,
    class="render-region",
    attrs=@html.Attrs::build().data_set("region", host.region.key()),
    ([] : Array[@rabbita.Html]),
  )
}

///|
pub fn shell_view(
  input : ShellInput,
  hosts : Array[MountHost],
) -> @rabbita.Html {
  fn host(region : @application.Region) -> @rabbita.Html {
    hosts
    .iter()
    .find_first(h => h.region == region)
    .map(region_host)
    .unwrap_or(@html.nothing)
  }
  let files : Map[String, @rabbita.Html] = Map([])
  for h in hosts {
    if h.region is File(_) {
      files[h.id] = region_host(h)
    }
  }
  @html.main_(
    class=if input.landing { "shell landing" } else { "shell workspace" },
    [
      host(Toolbar),
      if input.showing {
        @html.section(class="results", [
          @html.div(
            class="change-layout",
            style=["--file-tree-preferred-width: \{input.preferred_width}px"],
            [
              host(FileTree),
              @html.div(
                class="change-main",
                attrs=@html.Attrs::build()
                  .inert(input.drawer_open)
                  .data_set(
                    "navigation-generation",
                    input.generation.to_string(),
                  )
                  .data_set(
                    "navigation-layout",
                    "\{input.display.mode is Split}:\{input.display.algorithm is AstAlgorithm}:\{input.display.ignore_comments}:\{input.display.ignore_tests}",
                  ),
                [
                  commit_message_view(input.message, host(Navigation)),
                  host(ViewedSummary),
                  host(Discussion),
                  if files.is_empty() {
                    @html.div(
                      class="file-list",
                      @html.div(
                        class="empty-state",
                        "No changed files were returned for this change.",
                      ),
                    )
                  } else {
                    @html.div(class="file-list", files)
                  },
                ],
              ),
            ],
          ),
        ])
      } else {
        host(Status)
      },
      @html.footer([
        @html.span("Built with Moondiff · "),
        @html.a(
          href="https://github.com/moonbit-community/moondiff",
          target=Blank,
          rel="noopener noreferrer",
          "Source on GitHub",
        ),
      ]),
    ],
  )
}

///|
pub fn RegionInput::draft_id(self : RegionInput) -> String {
  match self {
    File(input) => input.review.draft().map(d => d.id.key()).unwrap_or("")
    Discussion(input) => input.review.draft().map(d => d.id.key()).unwrap_or("")
    _ => ""
  }
}
