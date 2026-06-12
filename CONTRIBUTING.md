# Contributing

Issues and PRs are welcome. Three things keep this codebase healthy:

1. **Logic lives in `CleverSwitchKit`** (the library target) and comes with
   tests. The app target is not unit-testable on purpose.
2. **`swift build && swift test && swift format lint --strict --recursive Sources Tests`**
   must pass with zero warnings before a PR is ready.
3. Behaviour is specified in [`docs/SPEC.md`](docs/SPEC.md); the working
   agreements (including for AI agents) are in [`AGENTS.md`](AGENTS.md).

Code identifiers are English; comments and commit messages are German with
real umlauts (the project is German-made). PR descriptions in English are fine.
