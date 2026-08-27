---
name: setup-flow-slice
description: Use once per project before flow-slice tracing to discover and confirm compact C4 boundaries, stable IDs, wiring roots, transports, generated code, and available semantic tooling.
---

# Setup Flow Slice

Discover the project's C4 map, confirm it with the user, then store one compact
configuration block in the project's existing agent instructions.

## Steps

1. Inspect the repository without changing it. Find the focus software system; known
   internal and external software systems; application and data-store containers;
   components; transports and contracts; composition/wiring roots; generated-code
   paths; available semantic tools (especially `ast-grep` / `sg`); and the current
   ignore rules. Primarily use `ast-grep` (falling back to LSP) to find entrypoints
   and wiring roots over manual search. Prefer manifests, schemas, and generated headers over guesses.
2. Assign lowercase kebab-case C4 IDs that remain stable when display names change.
   Mark every finding `confirmed`, `candidate`, or `unavailable`, and show the proposed
   configuration before writing. If no semantic tool is confirmed, offer to install one
   before finishing setup, in this order: `ast-grep` first, then an LSP for the project's
   language, then `ripgrep`. Name the concrete install command (e.g. `task
   install:ast-grep`). Install only on explicit yes.
3. Select the instruction file. Use the one of `AGENTS.md` or `CLAUDE.md` that already
   governs the traced code. Ask only when both independently govern the same scope, or
   neither exists. Treat a symlink between them as one file. Read the rest of that file
   first: if it already names the same services, transports, or entry points elsewhere,
   reuse those names as the C4 IDs and skip restating what it already says — the C4 Map
   section adds only the classification (role, status, roots) that section lacks.
4. Propose `.scratch/flow-slices` as `trace-dir` unless the project already has a local,
   ignored trace location. Confirm that the chosen path is ignored; include the narrow
   ignore rule when the user accepts the proposal.
5. After confirmation, replace or append exactly the `## C4 Map` section — that heading
   through the next heading of equal or shallower level, or end of file. Keep it inline
   in the instruction file — one file stays the single source of truth; do not create a
   separate `.flow-slice.yml`. Re-running this skill regenerates the whole section in
   place.

## C4 Map section

Markdown, not YAML — it reads as documentation, not config, and its own heading is the
only anchor `flow-slice` and `setup-flow-slice` need to find it; no HTML comment markers.
IDs are the only name each item needs (kebab-case is already a display name); do not add
a separate `name` field. A status tag is only ever written for a `candidate` — an item
with no tag is confirmed, so the common case costs zero words. `semantic-tools` is a flat
list, confirmed tools only, `ast-grep` first when present. Omit a role line, sentence, or
whole subsection that has nothing to report — a monolith with no external systems has no
`external:` line; a project with no generated code drops that sentence.

Three subsections, weighted by how much each earns:

- **Systems** — few, each a real boundary: list every one, grouped by role.
- **Boundaries** — transports, the wiring root, and generated-code paths, as two or three
  plain sentences, not a bulleted inventory. Name what's confirmed and say more
  transports may turn up — tracing, not this skill, is what completes that list.
- **Containers & components** — these can be numerous; give one confirmed example of
  each as a sentence, enough to pin the project's granularity (what counts as a
  container, what counts as a component here), not a full inventory. `flow-slice` treats
  an encountered-but-unlisted container or component as a stale map and reruns this
  skill, which is when the rest get added.

```markdown
## C4 Map

System → container → component, coarsest to finest. Managed by `setup-flow-slice` —
edit via the skill, not by hand.

trace-dir: `.scratch/flow-slices`
semantic-tools: ast-grep, gopls

### Systems
- focus: `billing-platform`
- internal: `auth-service`, `contract-service` (candidate)
- external: `clerk`, `postgres`

### Boundaries
Transports confirmed so far: `public-http` (HTTP, `openapi.yaml`). More may exist —
tracing will surface them. Wiring root: `cmd/api/main.go`. Generated code lives under
`internal/gen`.

### Containers & components
Example container: `api` in `billing-platform` (application, roots: `cmd/api`). Example
component: `api-transactions` in `api` (roots: `internal/transactions`). Use this
granularity — one container per deployable, one component per module — for anything
else you meet while tracing.
```

Exactly one system has role `focus`; other known systems have role `internal` or
`external`. Every container belongs to one system. Allowed container kinds are
`application` and `data-store`; a component belongs to one application container.
Record remote containers and components only when evidence confirms them. Otherwise
keep the relationship endpoint at system level. Use the same IDs in every v2 trace.

## Completion criterion

The user has confirmed the proposed map, one `## C4 Map` section exists in the selected
agent file, the trace directory is locally ignored, and missing tooling was reported and
offered — installed only on explicit yes.
