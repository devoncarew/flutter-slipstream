# Contributing

Contributions welcome! For anything but a non-trivial change, please start a
discussion with an issue first.

## Development

Load the Claude Code plugin locally:

```
claude --plugin-dir /path/to/flutter-slipstream
```

Load the Gemini CLI extension locally:

```sh
gemini extensions link /path/to/flutter-slipstream
```

Run all tests:

```sh
dart test
```

Regenerate the README command tables:

```sh
dart run tool/repo.dart generate-docs
```

## Pull requests

- Keep changes focused; one logical change per PR.
- Run `dart format .` and `dart test` before submitting.
- PR descriptions should be concise: a one-sentence summary plus a bullet list
  of the main changes.

## Code style

- Follow standard Dart conventions (`dart format`, `dart analyze`).
- Prefer explicit types on class fields.
- Hooks: exit 0 always; hard-blocking is reserved for cases where proceeding
  would be clearly wrong, and fail open on infrastructure errors (network
  timeouts, etc.).

## Releasing

Releases are automated: when a commit that bumps the plugin version lands on
`main`, CI publishes a GitHub release tagged `vX.Y.Z` with the matching
`CHANGELOG.md` section as the release notes.

Changelog entries accumulate during development under a top `## X.Y.Z-wip`
heading. Add your entry there in your feature PR, creating the heading if it
doesn't exist yet.

To cut a release:

1. Run `dart run tool/repo.dart bump-version`. With no argument it reads the
   version from the top `-wip` changelog heading, then:
   - bumps the `version` field in all four manifests
     (`.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`,
     `.github/plugin/plugin.json`, and `gemini-extension.json`), and
   - renames the `## X.Y.Z-wip` changelog heading to `## X.Y.Z`.

   Pass an explicit version (e.g. `dart run tool/repo.dart bump-version 1.7.0`)
   to override the derived one.
2. Open a PR with those changes. The Release workflow detects the version bump,
   labels the PR `release-pr`, and posts a comment with the notes that will be
   published.
3. Once the PR lands on `main`, the same workflow creates the GitHub release
   tagged `vX.Y.Z`.

`dart run tool/repo.dart check-versions` validates that the version is in sync
across all four manifests and the changelog; CI runs it on every PR.
