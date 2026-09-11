# Claude Usage — menu bar app design

Date: 2026-09-11
Status: approved in brainstorming, pending spec review

## Goal

A macOS menu bar app that shows my Claude subscription usage limits at a glance:
`42% · 62% · 93%` (current session, current week all models, current week Fable),
with a dropdown for details. Personal use only; not distributed.

## Data source

The app runs Claude Code's own `/usage` command in print mode:

```
claude -p "/usage" --no-session-persistence --output-format json
```

Why this and not an API:

- The endpoint behind `/usage` (`/api/oauth/usage`) is undocumented.
- A dedicated `claude setup-token` token only has the `user:inference` scope, and that endpoint
  requires `user:profile`, so it is rejected.
- Using subscription OAuth tokens outside Claude Code is a policy grey area. Running the unmodified
  `claude` binary with my own login is squarely within intended use.

Verified on 2026-09-11 with Claude Code 2.1.269: the command runs locally (`num_turns: 0`,
`total_cost_usd: 0`, ~0.5 s) and returns JSON. The `result` field holds human-readable text:

```
You are currently using your subscription to power your Claude Code usage

Current session: 42% used · resets Sep 12 at 12am (Europe/Amsterdam)
Current week (all models): 62% used · resets Sep 13 at 9pm (Europe/Amsterdam)
Current week (Fable): 93% used · resets Sep 13 at 9pm (Europe/Amsterdam)

What's contributing to your limits usage?
...
```

`--no-session-persistence` is mandatory; without it every poll leaves a transcript in
`~/.claude/projects` that shows up in `claude --resume`.

Known risk: the text is meant for humans and may change between Claude Code versions. The app must
fail visibly (see Error handling) rather than show wrong numbers.

## Architecture

Swift package, SwiftUI + AppKit, macOS 14+, Swift tools 6.0 with strict concurrency.
No third-party dependencies.

```
timer / popover opened / wake from sleep
        │
        ▼
UsageStore ──► UsageFetcher ──► `claude -p /usage` ──► result text
        ▲                                                 │
        └────────────── [Limit] ◄──── UsageParser ◄───────┘
        │
        ▼
MenuBarLabel ──► NSStatusItem "42% · 62% · 93%"      DropdownView (in NSPopover)
```

### UsageCore (library target, no UI code)

**`Limit`** — value type: `label` (e.g. "Current week (Fable)"), `shortName` (e.g. "Fable"),
`percent` (Double), `resetText` (e.g. "resets Sep 13 at 9pm").

**`UsageParser`** — pure function `parse(_ text: String) -> [Limit]`.

- Matches lines of the form `Current <name>: <n>% used · resets <when>`; `<n>` may be an integer or
  decimal. All other lines are ignored.
- `label` is `Current <name>`. `resetText` is `resets <when>` with a trailing ` (<timezone>)`
  removed.
- `shortName`: if `<name>` contains a parenthesised part other than `all models`, use that part
  ("Fable"); otherwise the first word, capitalised ("Session", "Week").
- Order is preserved as it appears in the text.
- Returns an empty array when nothing matches; the caller treats that as a parse failure.

**`UsageFetcher`** — runs the command and returns the `result` text or a typed error.

- Executable URL, arguments and timeout are injectable (tests use fake scripts and a 1 s timeout).
- Locating `claude` (GUI apps don't inherit the shell `PATH`): on every refresh, run
  `/bin/zsh -lc 'command -v claude'` (10 s timeout, last output line wins), falling back to
  `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`. One login shell per
  5 minutes is cheap, and it picks up a moved or reinstalled `claude` without caching logic. On this
  machine it resolves to `~/.local/bin/claude`, a symlink that survives Claude Code updates.
- Working directory: a neutral folder (the app's temporary directory), so no project's `.claude/`
  settings, hooks or `.mcp.json` are picked up.
- The environment is inherited, with the directory containing `claude` prepended to `PATH`.
- Timeout 30 s; on timeout the process is terminated.
- Decodes `{ "is_error": Bool, "result": String }` from stdout.
- Throws `UsageError`, one enum shared by the fetcher and the store:
  `.notFound(searched: [String])`, `.claudeError(message: String)` (when `is_error` is true, or a
  non-zero exit, carrying `result` or trimmed stderr), `.timedOut`,
  `.unreadableOutput(sample: String)`, and `.unparseable(sample: String)` (set only by the store).

**`UsageStore`** — `@MainActor @Observable`.

- State: `limits: [Limit]`, `lastSuccess: Date?`, `error: UsageError?`, `isRefreshing: Bool`.
- `refresh()`: no-op if a refresh is already running. On success it replaces `limits`, sets
  `lastSuccess` and clears `error`. A parse result of zero limits becomes
  `.unparseable(sample: first few lines)`. On failure it sets `error` and **keeps** the previous
  `limits`.
- Triggers: a 5-minute repeating timer, the popover opening, and `NSWorkspace.didWakeNotification`
  (the last two are wired up by the app target).
- The fetch function is injected so the store can be tested without processes.

**`MenuBarLabel`** — pure function from store state to display segments, so colouring is testable
without AppKit.

- Level per limit: `normal` below 80%, `warning` from 80%, `critical` from 95%.
- No data yet and no error: a single `–`.
- Error with no previous data: a single `⚠︎`.
- Error with previous data: `⚠︎` followed by the old numbers, all marked `stale`.
- Tooltip text: `Session 42% · Week 62% · Fable 93%` (short names).

### ClaudeUsage (app target)

- `NSStatusItem` whose button shows an attributed title built from `MenuBarLabel` segments, joined
  with ` · `. Font: monospaced-digit system font so the width doesn't jitter. Colours: default menu
  bar text colour (`normal`), `systemOrange` (`warning`), `systemRed` (`critical`), secondary label
  colour (`stale`). `MenuBarExtra` is not used because it renders its label in a single colour.
- Clicking opens a transient `NSPopover` hosting `DropdownView` (SwiftUI) and triggers a refresh.
- `LSUIElement = true` in Info.plist: no Dock icon, no main window.

**`DropdownView`**

```
┌──────────────────────────────────────┐
│ Current session                  42% │
│ ████████░░░░░░░░░░░░                 │
│ resets Sep 12 at 12am                │
│                                      │
│ Current week (all models)        62% │
│ ████████████░░░░░░░░                 │
│ resets Sep 13 at 9pm                 │
│                                      │
│ Current week (Fable)             93% │
│ ██████████████████░░   (orange)      │
│ resets Sep 13 at 9pm                 │
│──────────────────────────────────────│
│ Updated 2 min ago               ↻    │
│ ☑ Open at login                      │
│ Quit                                 │
└──────────────────────────────────────┘
```

- One row per limit, in parser order; bar colour follows the same levels as the menu bar.
- Label and reset text are shown exactly as parsed (no conversion to countdowns).
- When `error` is set, an error line is shown above the bars (see Error handling) and the footer
  reads "Last updated <relative time>".
- The ↻ button calls `refresh()` and shows a spinner while `isRefreshing`.

**Open at login** — toggle backed by `SMAppService.mainApp`, on by default at first launch. It is
unverified whether `SMAppService` accepts an ad-hoc-signed app; if it doesn't, fall back to writing
a LaunchAgent plist to `~/Library/LaunchAgents/local.roald.ClaudeUsage.plist`. Decided during
implementation.

## Error handling

Principle: never show wrong numbers, and never hide that something's off.

| Condition | Menu bar | Dropdown message |
|---|---|---|
| `claude` not found | `⚠︎` | "Couldn't find the `claude` command" + locations searched |
| `is_error` / non-zero exit | `⚠︎` | Claude Code's own message (e.g. "Login expired · run /login") |
| Timeout (30 s) | `⚠︎` | "Claude Code didn't respond" |
| Output not JSON | `⚠︎` | "Couldn't read Claude Code's output" + first few lines |
| JSON fine, zero limits parsed | `⚠︎` | "Couldn't read usage; the `/usage` format may have changed" + first few lines |

- With previous good data, the menu bar shows `⚠︎` plus the old numbers greyed out, and the dropdown
  keeps the old bars under the error line.
- A limit that stops appearing in `/usage` just disappears; that is not an error.
- Errors are shown in the UI only; no log file.

## Project layout

```
Package.swift
Sources/UsageCore/        Limit, UsageParser, UsageFetcher, UsageStore, MenuBarLabel
Sources/ClaudeUsage/      app entry, status item, DropdownView, login item
Tests/UsageCoreTests/     Swift Testing tests
Resources/Info.plist      bundle id local.roald.ClaudeUsage, LSUIElement
build.sh                  release build → build/Claude Usage.app (ad-hoc signed); `install` → /Applications + relaunch
test.sh                   swift test with Xcode's toolchain
```

Both scripts set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` unless it is already set.
The active developer directory on this machine is the Command Line Tools, where neither XCTest nor
Swift Testing works (XCTest is missing; Swift Testing's macros fail to build). With Xcode 27's
toolchain Swift Testing works (verified with a throwaway package). No global `xcode-select` change.

## Testing

Swift Testing (`@Test`, `#expect`) via `./test.sh`.

- **UsageParser:** the real output above as a fixture; output without the Fable line; output with
  an additional limit; reworded output (expect empty result); decimal percentages; timezone suffix
  removal; `shortName` derivation.
- **MenuBarLabel:** thresholds at 79.9 / 80 / 94.9 / 95; the `–`, `⚠︎` and stale states; tooltip
  text.
- **UsageFetcher:** fake shell scripts for success JSON, `is_error: true`, non-zero exit with stderr,
  non-JSON output, and a script that sleeps past the timeout; a missing executable for `.notFound`.
- **UsageStore:** keeps previous limits on error; zero parsed limits becomes `.unparseable`;
  concurrent `refresh()` calls run the fetch once.
- **End to end (manual):** run the fetcher and parser once against the real `claude`; build, launch
  and inspect the menu bar and dropdown; toggle Open at login.

## Out of scope

Notifications; countdown timers; the "What's contributing" section of `/usage`; configurable
thresholds or refresh interval; logging; notarization or distribution; an Xcode project file.
