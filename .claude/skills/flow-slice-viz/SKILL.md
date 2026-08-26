---
name: flow-slice-viz
description: Use to turn a flow-slice trace into an interactive visualization — chains flow-slice if no recent trace exists for the topic, writes the result as TOON, and opens it in the shared Cytoscape viewer.
---

# Flow Slice Viz

Turns a `flow-slice` trace into a clickable service/call graph. Written as TOON, not
JSON: this file is meant to be re-read across sessions (by you or the viewer), and
TOON's tabular rows are both cheaper in context and a near-direct fit for `flow-slice`'s
hop list.

## Steps

1. If there's no `flow-slice` trace for this topic already in context, run the
   `flow-slice` skill first.
2. Convert the trace to TOON using the schema below. Write it to the path the user
   specified; otherwise use the environment's writable temporary directory, normally
   `/tmp/flow-slice-viz/<topic-slug>.toon`. Keep the confirmed/unresolved distinction
   `flow-slice` produced — never invent a `via` or `evidence` value that trace didn't
   confirm.
3. Validate and open the hosted viewer with the complete TOON payload embedded in the
   URL hash:
   ```
   scripts/open-viewer.sh <path-to-toon>
   ```

   The launcher is the validation gate: fix any reported error and rerun it. A separate
   `validate-toon.sh` call is optional. The launcher passes the URL directly to the
   system browser instead of printing the long payload in the terminal.
   Quality warnings block likely weak traces: interface-seam truncation, boundary-looking
   calls marked as returns, or every confirmed hop falling back to `read`. Fix the trace;
   use `--ignore-warnings` only after manually confirming a false positive.
   The URL is self-contained; the viewer does not fetch the `.toon` file, and the
   fragment is never sent to the hosting server. The `base64` / `tr` pipeline is
   POSIX-portable (macOS and Linux).

   Before completing, inspect the opened browser when browser control is available and
   confirm both that its URL still contains `#b64=` and that the viewer shows the trace
   topic and graph instead of the empty file picker. Otherwise state that rendered-state
   verification remains outstanding; the user already has the opened page.

## Schema

```
topic: <feature/change/topic string>
services[N]{id,affected}:
  <service-id>,<true|false>
edges[N]{from,to,kind,confirmed,via,evidence,contract}:
  <service>,<service>,<http|grpc|event|unknown>,<true|false>,<verifying op or "unresolved">,<file:line or reason>,<HTTP operation, RPC signature, subject, or "-">
hops[N]{service,path,from,file,line,to,confirmed,via,outcome}:
  <service>,<entry point name (trigger)>,<caller symbol>,<file>,<line>,<callee symbol>,<true|false>,<verifying op or "unresolved">,<return|db-write|db-read or "-">
```

- `services` — level 1 nodes. `affected` is unused in v1 (always `false`), reserved
  for a later impact-coloring phase.
- `edges` — level 1 links, cross-service only (HTTP/gRPC calls, NATS subject-constant
  matches). `contract` is the HTTP operation, RPC signature
  (`<Method>(<Request>) -> <Response>`), or event subject — carried over verbatim from
  `flow-slice`'s seam-crossing, never re-derived here. Use `unknown` only for an
  unconfirmed edge whose protocol could not be established.
- `hops` — level 2, one row per caller→callee call *inside* one service. A hop with no
  further recorded call simply isn't a row. `path` is the entry point (from
  `flow-slice`'s per-entry-point tracer subagent) that produced this hop chain — lets
  the viewer group/color hops by which entry point they belong to, and — by convention
  — is named `<name> (<trigger>)` with trigger one of `grpc | graphql | nats-consumer |
  cron | http`; a `path` that doesn't fit the convention is still valid, the viewer just
  renders it without a trigger icon. `outcome` marks a hop as a genuine dead end
  (`-` on every non-terminal hop): `return`, `db-write`, or `db-read`. A leaf that
  publishes an event or calls another service is *not* given an `outcome` — that fact
  already lives in `contract`/`edges`, and duplicating it here risks the two drifting
  apart.
- Never leave a cell blank — TOON quotes empty strings, which complicates the parser
  for no benefit here. Use `unresolved` in `via` for an unconfirmed edge/hop, a short
  reason string in `evidence`, and `-` in `contract`/`outcome` when there's nothing to
  show (same-service hops have no contract; non-terminal hops have no outcome).

This skill's encoder only uses the tabular-array subset of TOON (header line +
comma rows) plus top-level `key: value` scalars — no nested field groups, list form, or
keyed tabular, because this schema doesn't need them. Full format:
https://github.com/toon-format/spec.

## Viewer

`.claude/skills/flow-slice-viz/viewer.html` is the one, permanent viewer — don't
generate a new HTML page per run. It loads Cytoscape.js from a CDN, parses the TOON
subset above client-side, and renders:

- Level 1 on open: services + edges, colored by `kind` (grpc = blue/solid, event =
  purple/dashed) with a legend. Click a service to drill into level 2.
- Level 2: hops for that service as a call graph, colored by `path` (one color per
  entry point) with a legend, and a back button to level 1. The entry node (parsed
  from the `path` trigger suffix) gets a trigger badge; terminal hops (non-`-`
  `outcome`) get an outcome marker, both with a legend.
- Hover any node/edge: tooltip with `file:line`, the verifying op (or "unresolved"),
  and — on level 1 edges — the `contract` (RPC signature or subject), or — on level
  2 terminal hops — the `outcome`.
- Click any confirmed edge to copy its full `file:line` path; the tooltip and copy
  cursor make this interaction visible.
- Click **Share** to open a self-contained hosted URL for the current slice.
- Unconfirmed edges/hops render dashed and red, overriding the kind/path color.

No filters, no before/after, no impact color-coding yet — add those to the viewer only
once a real use case needs them.
