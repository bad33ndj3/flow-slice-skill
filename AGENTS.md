# Repository Guidelines

## Project Structure & Module Organization

This repository distributes two agent skills. Canonical skill sources live under `.claude/skills/`:

- `flow-slice/` contains the cross-service tracing instructions.
- `flow-slice-viz/` contains visualization instructions and the shared `viewer.html`.
- Each skill's `agents/openai.yaml` defines its UI metadata.
- `.agents/skills/` contains symlinks used by Codex; edit the canonical `.claude/skills/` files, not the links.
- `Taskfile.yml` provides installation tasks. Generated traces belong in ignored `.scratch/` directories.

## Build, Test, and Development Commands

The project has no compilation step or dependency installation.

- `task --list` shows available tasks.
- `task install:codex` links both skills into `~/.agents/skills`.
- `task install:claude` links both skills into `~/.claude/skills`.
- `git diff --check` catches whitespace errors before review.

Pushing to GitHub with Pages enabled (Source: GitHub Actions) deploys `viewer.html`
as the site root via `.github/workflows/pages.yml`. The resulting URL
`https://bad33ndj3.github.io/flow-slice-skill/#b64=<data>` is a fully self-contained shareable
trace link.

Agents running shell commands in this repository should prefix commands with `rtk`, for example `rtk git diff --check`.

## Coding Style & Naming Conventions

Write concise Markdown with ATX headings and short, imperative instructions. Use two-space YAML indentation and quote values only when YAML requires it. Skill directory names and frontmatter `name` values use lowercase kebab-case, such as `flow-slice-viz`. Keep UI metadata aligned with the corresponding skill description. Modify `viewer.html` directly; do not add generated bundles or per-trace viewers.

## Testing Guidelines

There is no automated test suite. For instruction changes, read the complete affected skill and verify examples, paths, and output schemas remain consistent. For viewer changes, serve the repository locally with `python3 -m http.server 8000`, load a representative `.toon` file, and manually check overview, drill-down, tooltips, and unresolved-edge rendering. Run `git diff --check` for every change.

## Commit & Pull Request Guidelines

History currently uses short, imperative, sentence-case subjects (for example, `Initial flow-slice skills`). Keep each commit focused on one behavior. Pull requests should explain the user-visible change, list verification performed, and call out any schema compatibility impact. Include screenshots for visual changes to `viewer.html`; link an issue when one exists.
