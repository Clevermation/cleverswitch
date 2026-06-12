<!-- markdownlint-disable MD033 MD041 -->
<div align="center">

<img src="packaging/icon-source.png" width="120" alt="CleverSwitch icon" />

# CleverSwitch

### Juggle multiple AI coding accounts from your macOS menu bar.

One click to switch the active **Claude Code** or **Codex** session · live usage per account · auto-switch **before** you hit the limit.

[![Release](https://img.shields.io/github/v/release/Clevermation/cleverswitch?color=4f46e5&label=release)](https://github.com/Clevermation/cleverswitch/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/Clevermation/cleverswitch/ci.yml?branch=main&label=CI&color=4f46e5)](https://github.com/Clevermation/cleverswitch/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-4f46e5)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift&logoColor=white)](Package.swift)
[![i18n](https://img.shields.io/badge/i18n-16_languages-4f46e5)](#features)
[![Made in Germany](https://img.shields.io/badge/made_in-Germany-4f46e5)](https://clevermation.com)

<img src="docs/showcase.svg" width="560" alt="CleverSwitch menu showing two Claude accounts and one Codex account with live usage; email addresses are masked" />

</div>

## Install

```bash
brew install --cask clevermation/tap/cleverswitch
```

The app appears in your menu bar and walks you through setup on first launch.

> No Apple Developer account, no notarization: CleverSwitch is ad-hoc signed and open source.
> The Homebrew cask clears the quarantine flag for you, so it just opens.

## Update & uninstall

CleverSwitch checks GitHub for new releases every few hours. When one is out, the menu shows
an update entry that installs it and restarts the app. It also watches your `claude` and
`codex` CLIs: if one is outdated, you get a one-click update that uses the right command for
how that CLI was installed (native installer, npm, bun or Homebrew). Mixing those up by hand
is a classic way to end up with two competing installations.

Prefer the terminal?

```bash
brew upgrade   --cask cleverswitch        # update the app
brew uninstall --cask cleverswitch        # remove the app
brew uninstall --zap --cask cleverswitch  # remove the app plus local state and logs
```

## Why

If you have more than one Claude Max or ChatGPT/Codex subscription, you know the drill: the
5-hour session wall hits mid-task and you log into another account by hand. CleverSwitch keeps
all your logins ready, shows how close each one is to its limit, and switches the active CLI
session **before** you hit the wall.

## Features

- **🔀 One-click switch** between multiple Claude Code and Codex accounts — swaps the OAuth token the CLI reads, no re-login.
- **📊 Live usage** per account: each provider's session window + weekly window, in %, color-coded by load, with a *resets-in* countdown. The menu bar shows the highest session usage at a glance — scoped to all accounts or one provider, your choice.
- **🤖 Auto-switch**, three modes:

  | Mode | What it does |
  |---|---|
  | **Off** | Never switches automatically. |
  | **Failover** | Switches to a healthy account **just before** the limit (not at 100%, when it's already too late). |
  | **Balance** | Spreads usage evenly across accounts — runs on whichever has the most headroom, with hysteresis so it doesn't flap. |

- **🔑 Automatic token refresh** — expired tokens are renewed on the fly; switching never leaves you logged out.
- **🔒 Privacy-first** — credentials stay in the macOS Keychain / the CLI's own file; the account list holds no secrets. Hide email addresses in one click (great for screen recordings & streams): `you@company.com` → `y•••@c•••.com`.
- **🌍 16 languages**, automatically following your system language.
- **⚙️ Settings**: start at login · notifications · show/hide emails · menu bar number source.
- **⬆️ Built-in update check** — the menu tells you when a new CleverSwitch version is out and installs it via Homebrew in one click.
- **🧰 CLI updates too** — detects whether `claude`/`codex` came from the native installer, npm, bun or Homebrew, and runs the matching update command when a new CLI version ships.
- **🚀 Guided onboarding** on first launch: five short steps from hello to your live usage numbers.

## How it works

Each CLI reads its credentials from exactly one place (Claude: a macOS Keychain entry, Codex:
`~/.codex/auth.json`). CleverSwitch keeps a copy of every account's token and, when you switch,
swaps the target account's token into that "live slot", refreshing it first if needed. The
whole decision layer (when and where to auto-switch) is pure, provider-neutral, and unit-tested.

Adding an account runs the official `claude auth login` / `codex login` flow headless: no
terminal window, the browser opens on its own, and the new account is imported automatically.

## Requirements

- **macOS 14 (Sonoma) or newer.** That's the only requirement to *run* the app — it's a small
  native Swift binary, no runtime to install, no Xcode.
- **Homebrew** to install via the command above.
- The **`claude` and/or `codex` CLI** installed for the accounts you want to manage. CleverSwitch
  drives their official login flows and reads their usage; it doesn't replace them. If a CLI
  isn't installed, its "Add account" simply tells you so.

## Troubleshooting

**"CleverSwitch can't be opened because Apple cannot check it for malware."**
The Homebrew cask clears the quarantine flag, so this normally won't appear. If you moved the app
manually, run once: `xattr -dr com.apple.quarantine /Applications/CleverSwitch.app`

**The menu shows no usage / "—".**
Make sure the `claude` and/or `codex` CLI is installed and you've logged in at least once via
*Add account*. Usage is read from each provider's official endpoint and may lag a few seconds
after a switch — use *Refresh usage*.

**Switching doesn't seem to take effect.**
A running CLI session reads its token once at start; restart it. New sessions pick up the
switched account immediately.

Logs live at `~/Library/Logs/CleverSwitch.log`.

## Privacy & security

CleverSwitch stores OAuth credentials only locally (macOS Keychain / `~/.codex/auth.json`) and
talks only to the official auth/usage endpoints of each provider. Nothing is sent anywhere else.
Please check your provider's terms regarding multi-account use.

## Build from source

Native Swift / SwiftUI (`MenuBarExtra`), built with the Swift Package Manager — no third-party
runtime dependencies.

```bash
swift build        # build
swift test         # run the test suite (CleverSwitchKit)
zsh packaging/assemble-app.sh   # assemble CleverSwitch.app
```

The logic lives in `CleverSwitchKit` (policy, store, OAuth, usage, providers) and is fully
testable without a GUI. Architecture & behaviour spec: [`docs/SPEC.md`](docs/SPEC.md).

## Contributing

Issues and PRs welcome. The behaviour is specified in [`docs/SPEC.md`](docs/SPEC.md); the policy
layer in `CleverSwitchKit` is pure and unit-tested, so logic changes come with tests.

## License

[MIT](LICENSE) — an independent, clean-room implementation. See [`NOTICE`](NOTICE).

<div align="center"><sub>🇩🇪 Made in Germany by <a href="https://clevermation.com"><b>Clevermation</b></a> · <i>Reclaim your impact.</i></sub></div>
