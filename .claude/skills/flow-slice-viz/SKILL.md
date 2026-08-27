---
name: flow-slice-viz
description: Use to encode a verified flow-slice as v2 TOON and explore its C2 containers, C3 components, and C4 code in the shared interactive viewer.
---

# Flow Slice Viz

Encode the current `flow-slice` trace as compact v2 TOON, validate it, and open the
permanent Cytoscape viewer.

## Steps

1. Run `flow-slice` first when no current verified trace exists.
2. Write the schema below to the configured `trace-dir`, reusing stable C4 IDs from the
   project's `flow-slice:c4` block. Do not invent evidence.
3. Run `scripts/open-viewer.sh <trace.toon>`. Fix every error and quality warning. Use
   `--ignore-warnings` only after manually proving a warning is a false positive.
4. When browser control is available, confirm C2 → C3 → C4 drill-down, breadcrumbs,
   back navigation, tooltips, unresolved styling, and reload of the generated `#b64=`
   share URL. Otherwise report rendered-state verification as outstanding.

The launcher embeds the complete trace in the URL fragment; the hosted viewer never
receives it from the server.

## V2 schema

```toon
version: 2
topic: <feature/change/topic>
systems[N]{id,name,role}:
  <stable-id>,<display name>,<focus|internal|external>
containers[N]{id,system,name,kind}:
  <stable-id>,<system-id>,<display name>,<application|data-store>
relationships[N]{id,from,to,transport,contract,confirmed,via,evidence}:
  <stable-id>,<system-container-or-component-id>,<system-container-or-component-id>,<http|grpc|event|database|unknown>,<contract or ->,<true|false>,<verifying op or unresolved>,<file:line or reason>
components[N]{id,container,name}:
  <stable-id>,<application-container-id>,<display name>
hops[N]{id,path,from_component,to_component,caller,callee,file,line,confirmed,via,outcome,relationship}:
  <stable-id>,<entrypoint (trigger)>,<caller-component-id>,<callee-component-id>,<caller>,<callee>,<file>,<line>,<true|false>,<verifying op or unresolved>,<return|db-write|db-read|->,<relationship-id or ->
```

- `systems` are C1 software systems and contain exactly one `focus` row. Other rows are
  known internal peers or external systems.
- `containers` are C2 applications and data stores owned by a system. Data stores have
  no artificial C3 layer.
- `relationships` cross a container or system boundary. End them at the most precise
  confirmed C1, C2, or C3 element. `contract` is the HTTP operation, RPC signature,
  subject, or database contract carried from the trace.
- `components` are C3 modules inside application containers.
- `hops` are C4 caller-to-callee edges with explicit component endpoints. Both
  components must belong to the same application container. A local boundary adapter
  hop optionally references its boundary `relationship`. Keep one entrypoint path
  through callbacks and goroutines.
- Use `unresolved` in `via` exactly when `confirmed` is false. Use `-` for absent
  `contract`, `outcome`, or `relationship`. Never leave a cell blank.

V1 and the earlier v2 shape (`software_system`/`external_systems`) are intentionally
unsupported. Run `setup-flow-slice`, retrace, and emit the current v2 shape.

## Viewer

The shared `viewer.html` opens at **Containers (C2)**. Application containers in the
focus system drill into **Components (C3)**, and local components drill into **Code
(C4)**. C3 shows directed component calls plus collapsed out-of-scope containers and
systems; click those boundaries to reveal only participating descendants. Data stores
remain leaves. ELK lays out every level. Breadcrumbs show `Software System / Container
/ Component`; tooltips retain evidence, contracts, outcomes, counts, and unresolved
state. Share retains the base64 trace URL and reloads with external scopes collapsed.
