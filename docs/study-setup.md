# User study setup

> For humans: setup script and prompt for running periodic user studies.

## Setup

```bash
flutter create --platforms=android,ios,macos,web showcase && \
  cd showcase && \
  rm test/*_test.dart && \
  mkdir .claude && \
  echo "{}" > .claude/settings.json && \
  flutter run -d macos
```

## .claude/settings.json

```
{
  "permissions": {
    "allow": [
      "Bash(dart *)",
      "Bash(flutter *)",
      "Edit",
      "Write",
      "mcp__plugin_flutter-slipstream_packages__package_summary",
      "mcp__plugin_flutter-slipstream_packages__class_stub",
      "mcp__plugin_flutter-slipstream_inspector__run_app",
      "mcp__plugin_flutter-slipstream_inspector__get_output",
      "mcp__plugin_flutter-slipstream_inspector__take_screenshot",
      "mcp__plugin_flutter-slipstream_inspector__perform_set_text",
      "mcp__plugin_flutter-slipstream_inspector__perform_tap",
      "mcp__plugin_flutter-slipstream_inspector__navigate",
      "mcp__plugin_flutter-slipstream_inspector__perform_scroll_until_visible",
      "mcp__plugin_flutter-slipstream_inspector__perform_scroll",
      "mcp__plugin_flutter-slipstream_inspector__reload",
      "mcp__plugin_flutter-slipstream_inspector__perform_semantic_action",
      "mcp__plugin_flutter-slipstream_inspector__get_semantics",
      "mcp__plugin_flutter-slipstream_inspector__get_route",
      "mcp__plugin_flutter-slipstream_inspector__close_app"
    ]
  }
}
```

## Study Prompt

Hi! You'll be building a Flutter widget-showcase app to test a new plugin. The
plugin — **flutter-slipstream** — has two MCP servers: `inspector` (launch,
reload, screenshot, and interact with a running Flutter app) and `packages`
(accurate API signatures pulled from the local pub cache). Take a moment to read
the available tools before starting.

Use `provider` for state and `go_router` for routing. Add `slipstream_agent` as
a dependency and call `SlipstreamAgent.init()` in `main` — this unlocks
finder-based interaction tools in the inspector. Assume a mobile phone screen.

Please work through these steps in order:

**1. Scaffold** — Build a minimal shell: Scaffold with a drawer, a bottom
navigation bar (3 tabs), and a light/dark theme toggle in the app bar. No tab
content yet. Run the app, take a screenshot, and verify it looks right.

**2. Inputs tab** — A text field, a slider, and a row of toggle chips or switch
tiles. Reload, screenshot, then use `perform_set_text` and `perform_tap` to
interact with the controls.

**3. List tab** — A scrollable list of 25+ cards (title + subtitle). Reload,
screenshot, scroll with `perform_scroll`, and tap a card.

**4. Form tab** — A validated form with a name field, an email field, a
checkbox, and a Submit button that shows a result. Reload, screenshot, fill the
form with `perform_set_text`, and submit it.

**5. Navigate** — Use `navigate` to jump between tabs; verify with `get_route`.
Open the drawer and tap a drawer item.

A few reminders: call `get_output` after every reload and interaction to catch
errors early; use `package_summary` or `class_stub` rather than guessing at
APIs; skip a step if you get stuck.

When done, write your feedback — pros, cons, bugs, areas for improvement — and a
brief work log to `feedback.md` in this directory.

Do you have any questions before you begin?
