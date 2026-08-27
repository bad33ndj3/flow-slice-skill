---
name: flow-slice
description: Use before planning, implementing, or reviewing a feature/change/topic that crosses container boundaries (gRPC, GraphQL/HTTP, events, or databases) to trace its verified C2, C3, and C4 flow.
---

# Flow Slice

A flow slice is the verified path a feature takes through one configured focus software
system and its dependencies. Every code hop carries its evidence; every boundary
crossing references one explicit relationship.

## Steps

1. Read the `flow-slice:c4` block in the governing `AGENTS.md` or `CLAUDE.md`. If it is
   missing, stale, or still contains candidates that affect this trace, run
   `setup-flow-slice` and obtain confirmation before tracing.
2. Find entry points across configured transports, contracts, and wiring roots. Record
   each candidate as file:line and name its path `<name> (<trigger>)`, where trigger is
   `grpc`, `graphql`, `nats-consumer`, `cron`, or `http`.
3. Trace each entry point forward until every branch reaches a genuine outcome or an
   unresolved edge. Keep the original path on callbacks and goroutines: record each
   callback/async handoff as an ordinary caller-to-callee hop, then continue from its
   body. A path such as `CreateTransaction (callback)` loses its entrypoint and is
   invalid.
4. Classify each runtime as its configured C2 container and each module as its
   configured C3 component. Give every code hop explicit caller and callee component
   IDs. Record code calls only inside one container. Represent every cross-container or
   cross-system call once as a relationship at the most precise confirmed endpoint;
   attach its ID to the local client/publisher/database hop instead of drawing a code
   hop into the other container.
5. Write v2 TOON to the configured `trace-dir` using `flow-slice-viz`. Preserve every
   unresolved hop and the operation that confirmed every resolved hop.

## Seam rules

- **Interface seam.** Follow an interface method to the implementation selected by a
  configured wiring root. The wiring file is ground truth. Record the interface call
  and implementation call separately.
- **Generated contract seam.** Use generated server/client code to cross an RPC or API
  seam when the schema has no semantic tooling. Read the source contract for shapes;
  retain the HTTP operation, RPC signature, or subject on the boundary relationship.
- **Event seam.** Link publish to subscribe through the subject constant and wiring.
  Call hierarchy alone cannot establish this edge.
- **Call graph.** Prefer available semantic operations such as `outgoingCalls`,
  `incomingCalls`, `findReferences`, and `goToImplementation`. If an LSP is unavailable,
  use `ast-grep` with structural patterns to reliably trace calls, interface
  implementations, and variable usage (`via:ast`). Only as a last resort, read the call
  site and use `via:read`; never label a guessed edge as confirmed.
- **No semantic compression.** Keep transaction wrappers, callback registration and
  invocation, goroutine handoffs, adapters, and clients as separate hops.
- **Genuine outcomes.** Use `return` only for a plain leaf return. Use `db-read` or
  `db-write` only on the outbound database hop and reference its database relationship.
  A call to another container or external system has `outcome:-`; its relationship is
  the terminal fact.

## Completion criterion

The v2 trace validates without ignored warnings. Every code path is reachable from its
entrypoint through recorded callback/goroutine handoffs, every code hop stays inside one
container, every boundary uses a relationship ID, and every unresolved edge remains
visible.
