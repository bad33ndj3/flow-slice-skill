---
name: setup-flow-slice
description: Use once per project before flow-slice tracing to discover and confirm compact C4 boundaries, stable IDs, wiring roots, transports, generated code, and available semantic tooling.
---

# Setup Flow Slice

Discover the project's C4 map, confirm it with the user, then store one compact
configuration block in the project's existing agent instructions.

## Steps

1. Inspect the repository without changing it. Find the software system boundary;
   application and data-store containers; components; external systems; transports and
   contracts; composition/wiring roots; generated-code paths; available LSP or semantic
   tools; and the current ignore rules. Prefer manifests, entrypoints, wiring, schemas,
   and generated-file headers over directory-name guesses.
2. Assign lowercase kebab-case C4 IDs that remain stable when display names change.
   Mark every finding `confirmed`, `candidate`, or `unavailable`, and show the proposed
   configuration before writing. Report unavailable tooling with a concrete
   recommendation; do not install it.
3. Select the instruction file. Use the one of `AGENTS.md` or `CLAUDE.md` that already
   governs the traced code. Ask only when both independently govern the same scope, or
   neither exists. Treat a symlink between them as one file.
4. Propose `.scratch/flow-slices` as `trace-dir` unless the project already has a local,
   ignored trace location. Confirm that the chosen path is ignored; include the narrow
   ignore rule when the user accepts the proposal.
5. After confirmation, replace or append exactly one block delimited by
   `<!-- flow-slice:c4:start -->` and `<!-- flow-slice:c4:end -->`. Preserve all content
   outside the markers. Re-running this skill updates that block in place; do not create
   a separate `.flow-slice.yml`.

## Configuration block

Use YAML inside the markers and omit empty collections. Keep evidence as repository
paths, optionally with a line number.

```yaml
version: 2
software-system:
  id: billing-platform
  name: Billing Platform
  status: confirmed
trace-dir: .scratch/flow-slices
containers:
  - id: api
    name: API
    kind: application
    status: confirmed
    roots: [cmd/api, internal]
components:
  - id: api-transactions
    container: api
    name: Transactions
    status: candidate
    roots: [internal/transactions]
external-systems:
  - id: payment-provider
    name: Payment Provider
    status: confirmed
transports:
  - id: public-http
    kind: http
    contract: openapi.yaml
    status: confirmed
wiring-roots:
  - path: cmd/api/main.go
    status: confirmed
generated-code:
  - path: gen
    status: confirmed
semantic-tools:
  - name: gopls
    status: confirmed
```

Allowed container kinds are `application` and `data-store`. A component belongs to one
application container. External systems sit outside the configured software system.
Use the same IDs in every v2 trace.

## Completion criterion

The user has confirmed the proposed map, one marker block exists in the selected agent
file, the trace directory is locally ignored, and unavailable tooling is reported
without installation.
