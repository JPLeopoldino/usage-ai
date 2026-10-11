# Changelog

## 0.1.0 — Unreleased

First version.

- Menu bar app with Claude, Cursor and OpenAI usage.
- Claude via the Claude Code status line bridge (default; your status line looks the same as before) or the unofficial OAuth usage endpoint.
- Cursor via the Cursor app's local session or a pasted session cookie.
- OpenAI spend via the official Costs API, with an optional monthly budget.
- Configurable menu bar item with a vertical usage bar (or each service's logo and value), warning colors at 80% and 95%.
- Each service's logo in the menu and Settings; usage bars in the system accent color.
- The menu only lists services that are set up, with an empty state until one is.
- Claude's plan next to its name: detected with the OAuth source, picked in Settings with the status line.
- A Settings button in the menu's header; Quit lives in Settings › General. Usage refreshes on its own and when the menu opens.
- Claude: current session always shown (0% until a session starts); per-model weekly limits such as Fable with the OAuth source.
- Icon Composer app icon with Liquid Glass on macOS 26 and later.
- Settings: open at login, refresh interval, accounts, diagnostics.
- English and Brazilian Portuguese.
