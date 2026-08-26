---
name: flow-slice
description: Use before planning, implementing, or reviewing a feature/change/topic that crosses service boundaries (gRPC, GraphQL/HTTP, NATS JetStream) — traces the real end-to-end flow into a verified slice instead of a grep guess.
---

# Flow Slice

A flow slice is the set of files/symbols/messages/subjects forming the actual path a
feature takes through the system. Every hop carries the tool op that confirmed it. A
hop that can't be confirmed is listed as unresolved, never silently dropped — that's
what makes the slice reliable instead of a confident guess.

## Steps

1. **Find entry points.** Grep/Explore the topic across proto RPC names, GraphQL
   resolvers, `internal/adapter/inbound/`, and `.Subscribe(` call sites. Record each
   candidate as file:line.
2. **Dispatch one tracer subagent per entry point** (parallel when entry points are
   independent). Give each the entry point's file:line plus the seam
   rules below verbatim, and ask it to trace forward until the flow dead-ends,
   crossing whatever seams it hits. This is what keeps this thread's context clean:
   the LSP calls, greps, and file reads a trace takes happen inside the subagent, not
   here. Name the entry point as `<name> (<trigger>)`, trigger one of `grpc |
   graphql | nats-consumer | cron | http` — the viewer parses this suffix for an
   entry-point icon, so a `path` that doesn't fit the convention just renders
   without one; don't force a fit. A tracer subagent reports back **only** the hop
   list, one line per hop, tagged with its own entry point as `path` (this is what
   lets the viewer group hops by which entry point produced them — see
   `flow-slice-viz`):

   `path:<entry point name (trigger)> | <caller> -> <callee> | <file>:<line> | confirmed:<yes/no> | via:<op or "unresolved"> | contract:<RPC signature or subject, if this hop crosses a proto/NATS seam, else "-"> | outcome:<return|db-write|db-read, if this hop is a genuine dead end, else "-"> | note:<reason, if unresolved>`

   No exploration transcript, no prose — a report that isn't in this shape means the
   subagent under-delegated and dumped its scratch work back into the parent; ask it to
   re-report.
3. **Assemble the slice** from the subagent reports: ordered hops, then two closing
   sections — confirmed hops, and unresolved edges.

## Seam rules (hand these to every tracer subagent)

- **Interface seam.** This codebase is hexagonal, interfaces with no ports:
  `outgoingCalls` on a core service method lands on an interface method and stops —
  that is not the end of the flow. `goToImplementation` on the interface method, then
  confirm which implementation is actually wired by reading the `cmd/` entrypoint that
  constructs it. The wiring file is ground truth; an interface can have more than one
  implementation.
- **Proto/gRPC seam.** There is no `.proto` LSP here (verified: the LSP tool returns
  "No LSP server available" for `.proto` — `buf lsp serve` isn't reachable through it,
  and there's no generic client to drive it). Cross the seam via the generated Go side
  instead: find the RPC method on the generated `*_grpc.pb.go` `XServiceServer`
  interface, then `goToImplementation`/`findReferences` on it to reach the real handler
  — that part of the seam the Go LSP already covers. Use `buf ls-files` / `buf build`
  (root `buf.yaml`) or just read the `.proto` source for message shapes and service
  definitions. Hold onto the RPC method + request/response type names you find here —
  report them as this hop's `contract` (`<Method>(<Request>) -> <Response>`), don't
  just confirm the edge exists and discard them.
- **NATS seam.** Publish→subscribe is a text edge, not a call edge: `findReferences`
  on the subject constant (`natsconfig.*Subject`, `event.Subject*`, pattern confirmed
  via `.Subscribe(consumer, subject, handler)` call sites) links publisher to
  subscriber. Call hierarchy will never show this hop. Report the subject constant
  itself (e.g. `natsconfig.SnapshotsCreatedSubject = "snapshots.created"`) as this
  hop's `contract`.
- **Call graph.** Walk with the LSP tool (gopls-backed): `outgoingCalls` /
  `incomingCalls` / `findReferences`. If call-hierarchy ops fail with "no package
  metadata" (this repo's vendoring drifts from `go.mod` periodically — not yours to
  fix), fall back to reading the call site directly and report `via:read` instead of
  the op name; that's still a confirmed hop, just not an LSP-confirmed one.
- **No semantic compression.** Record transaction wrappers, callbacks, async handoffs,
  and adapter/client implementation calls as hops; don't keep only business-named calls.
- **Dead end = `outcome`, not a name guess.** A hop is only a dead end when its
  callee genuinely doesn't lead anywhere further you can trace — not just because
  its name looks terminal. `Create*`/`Get*`-style names lie: a service-level
  `Create` can itself be an orchestrator doing a DB write, an external gRPC call,
  and event publishes underneath one name. If the callee does more than one of
  those, it isn't the dead end — keep tracing into it and report each real leaf as
  its own hop. Once you've reached a genuine leaf, classify by what the callee's
  *file* is, not its name: a method in `internal/adapter/outbound/*repository*`
  → db (then use the method name only as the read/write tiebreaker within that
  adapter: `Get*/Find*/List*` → `db-read`, `Create*/Save*/Update*/Delete*` →
  `db-write`), a plain value return with no further call → `return`. A leaf that
  publishes an event or calls another service already gets its `contract` recorded
  above and its cross-service `edges` row in the assembled slice — don't also set
  `outcome` for those, that'd be the same fact in two places that can drift out of
  sync; leave `outcome` as `-` there. Leave `outcome` as `-` on every non-terminal
  hop too.

## Completion criterion

Every confirmed hop names its verifying op (or `read`, for the LSP-unavailable
fallback). Every edge that couldn't be confirmed is listed under "unresolved," not
omitted.

## Gap: dynamic routes/subjects

If an unresolved edge is a route or subject built dynamically (string concat,
config-driven lookup) and this keeps recurring, build a `tools/flowscan` (go/packages +
go/ast, see `tools/AGENTS.md`) to resolve it statically. Don't build it for one
unresolved edge — grep/const-ref covers the static cases.
