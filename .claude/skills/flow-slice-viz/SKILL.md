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
software_system[1]{id,name}:
  <stable-id>,<display name>
containers[N]{id,name,kind}:
  <stable-id>,<display name>,<application|data-store>
external_systems[N]{id,name}:
  <stable-id>,<display name>
relationships[N]{id,from,to,transport,contract,confirmed,via,evidence}:
  <stable-id>,<container-or-external-id>,<container-or-external-id>,<http|grpc|event|database|unknown>,<contract or ->,<true|false>,<verifying op or unresolved>,<file:line or reason>
components[N]{id,container,name}:
  <stable-id>,<application-container-id>,<display name>
hops[N]{id,path,container,component,caller,callee,file,line,confirmed,via,outcome,relationship}:
  <stable-id>,<entrypoint (trigger)>,<container-id>,<component-id>,<caller>,<callee>,<file>,<line>,<true|false>,<verifying op or unresolved>,<return|db-write|db-read|->,<relationship-id or ->
```

- `software_system` is the C4 software-system boundary and contains exactly one row.
- `containers` are C2 applications and data stores. Data stores have no artificial C3
  layer.
- `external_systems` are outside the software-system boundary.
- `relationships` are C2 boundary crossings. `contract` is the HTTP operation, RPC
  signature, subject, or database contract carried from the trace.
- `components` are C3 modules inside application containers.
- `hops` are C4 caller-to-callee edges. All hops remain inside `container`; `component`
  must belong to it. A local boundary adapter hop optionally references its C2
  `relationship`. Keep one entrypoint path through callbacks and goroutines.
- Use `unresolved` in `via` exactly when `confirmed` is false. Use `-` for absent
  `contract`, `outcome`, or `relationship`. Never leave a cell blank.

V1 (`services`/`edges`) is intentionally unsupported. Run `setup-flow-slice`, retrace,
and emit v2 instead of migrating old traces.

## Viewer

The shared `viewer.html` opens at **Containers (C2)**. It includes external systems;
application containers drill into **Components (C3)**, and components drill into
**Code (C4)**. Data stores and external systems do not drill down. Breadcrumbs always
show `Software System / Container / Component` at the current depth. Tooltips retain
evidence, contracts, outcomes, and unresolved state; Share retains the base64 URL.
