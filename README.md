# Flow Slice

Flow Slice is a set of agent skills for tracing one verified feature path through a
system: containers (C2), components (C3), and code (C4). It keeps boundary
relationships explicit, attaches evidence to each hop, and renders the result in a
shareable interactive viewer.

## Install

Clone this repository, then link the skills for the agent you use:

```bash
task install:codex
task install:claude
task install:agy
```

Each task links the canonical sources in `.claude/skills/` and refuses to replace an
existing non-matching skill.

## Use

In the repository you want to trace:

1. Run `$setup-flow-slice` once to discover and record its C4 map in `AGENTS.md` or
   `CLAUDE.md`.
2. Run `$flow-slice` for a feature or change that crosses HTTP, gRPC, events, or a
   database boundary. It writes a verified v2 TOON trace.
3. Run `$flow-slice-viz` to validate and open that trace. The viewer starts at C2 and
   drills into C3 and C4 while retaining evidence, contracts, and unresolved edges.

`ast-grep` is included for structural code search. Install its CLI when a traced
repository does not already provide it:

```bash
task install:ast-grep
```

## Open a trace

The viewer launcher validates before opening a self-contained GitHub Pages URL:

```bash
.claude/skills/flow-slice-viz/scripts/open-viewer.sh path/to/trace.toon
```

Use `--ignore-warnings` only after manually proving that each warning is a false
positive. The trace data stays in the URL fragment and is not sent to the viewer
server.

## Development

There is no build step. Check whitespace and the TOON validator before changing a
skill or viewer:

```bash
git diff --check
.claude/skills/flow-slice-viz/scripts/validate-toon.sh --self-test
```

The viewer is deployed to GitHub Pages from `main`.
