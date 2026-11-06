# Smoke test

> For humans: a prompt to paste into an agent session to smoke-test the plugin
> end to end.

## Smoke test prompt

Hi! You'll be smoke-testing **flutter-slipstream**, a plugin with two MCP
servers: `inspector` (launch, reload, screenshot, and interact with a running
Flutter app) and `packages` (accurate API signatures from the local pub cache).
The goal is to catch regressions and rough edges across the main workflows. This
directory has a Flutter app you can use.

Work through these steps:

**1. Packages** — Run `package_summary` on a package (e.g. `provider`), then use
`class_stub` to drill into one of its classes.

**2. Launch** — Start the app with `run_app`, call `get_output`, take a
screenshot.

**3. Edit and reload** — Make a small visible change (e.g. update the title or a
label), `reload`, then `get_output` and `take_screenshot` to confirm.

**4. Inspect** — Run `inspect_layout` on the root widget. Try `evaluate` with a
simple Dart expression.

**5. Interact** — Use `get_semantics` to find an interactive element, then tap
it with `perform_semantic_action`.

**6. Close** — Call `close_app`.

Skip a step if you get stuck. When done, write your feedback — what worked, what
didn't, any bugs or rough spots — and a brief work log to `feedback.md`.

Do you have any questions before you begin?
