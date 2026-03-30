# Repository Guidelines

## Project Structure & Module Organization
Active Stationeers IC10 scripts live under `terain-mars/`, grouped by subsystem such as `energy-control/`, `manufacture/`, `mining/`, `gas-station/`, and `inner-base/`. Use these folders for current work. Historical or superseded scripts are kept under `old/` and should be treated as reference material unless a migration explicitly targets them. The root `README.md` is minimal, so directory names and existing script files are the main source of project context.

## Build, Test, and Development Commands
This repository does not include a formal build system, package manager, or automated test runner. Common local commands are inspection-oriented:

`rg --files` lists all scripts quickly.
`Get-ChildItem terain-mars -Recurse` browses active script folders.
`Get-Content terain-mars\\manufacture\\kits\\mn-kit-con.ic10` reviews a script before editing.

Validation is done in-game by loading the edited IC10 script into the relevant device network and confirming expected behavior.

## Coding Style & Naming Conventions
Match the existing IC10 style exactly. Use uppercase `define` constants, short `alias` register names, and labels such as `main:` or `checkActivity:` for control flow. Indent instruction blocks with four spaces. Keep comments brief and practical, typically for device setup, register intent, or tricky branch behavior.

Follow existing file naming patterns: subsystem prefixes plus behavior, for example `mn-kit-con.ic10`, `groupa-balance-console.ic10`, or `storm-alarm-light.ic10`. Preserve the repository’s current path names, including the existing `terain-mars` spelling.

## Testing Guidelines
There is no automated coverage target. For every change, test the script on the intended Stationeers structure or network, verify startup behavior after `yield`, and check both nominal and edge states such as power-off, empty inputs, or storm events. If a script replaces an older version, compare behavior against the reference file in `old/`.

## Commit & Pull Request Guidelines
Recent history uses short conventional subjects like `fix: issue with default display power state that is off` and `add: rover control`. Follow `type: summary` with lowercase types such as `fix:` or `add:`. Keep each commit scoped to one subsystem.

Pull requests should state the affected area, summarize the in-game scenario tested, and include screenshots or a short device/setup note when UI displays or routing behavior change.
