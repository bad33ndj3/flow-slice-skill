#!/usr/bin/env bash
set -euo pipefail

ignore_warnings=false
if [[ ${1:-} == "--ignore-warnings" ]]; then
  ignore_warnings=true
  shift
fi
if [[ $# -ne 1 ]]; then
  echo "usage: $0 [--ignore-warnings] <trace.toon|--self-test>" >&2
  exit 2
fi

python3 - "$1" "$ignore_warnings" <<'PY'
import re
import sys
from collections import defaultdict
from pathlib import Path

SCALARS = {"version", "topic"}
SCHEMAS = {
    "systems": ["id", "name", "role"],
    "containers": ["id", "system", "name", "kind"],
    "relationships": ["id", "from", "to", "transport", "contract", "confirmed", "via", "evidence"],
    "components": ["id", "container", "name"],
    "hops": ["id", "path", "from_component", "to_component", "caller", "callee", "file", "line", "confirmed", "via", "outcome", "relationship"],
}
HEADER = re.compile(r"^(\w+)\[(\d+)]\{([^}]*)}:\s*$")
ID = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$")
PATH = re.compile(r"^.+ \(([^)]+)\)$")
TRIGGERS = {"grpc", "graphql", "nats-consumer", "cron", "http", "callback"}


def split_row(row, source, line_number):
    cells, current, quoted = [], [], False
    for char in row:
        if char == '"':
            quoted = not quoted
        elif char == "," and not quoted:
            cells.append("".join(current))
            current = []
        else:
            current.append(char)
    if quoted:
        raise ValueError(f"{source}:{line_number}: unmatched quote")
    cells.append("".join(current))
    return cells


def validate(text, source):
    if not text.strip():
        raise ValueError(f"{source}: file is empty")
    if re.search(r"^services\[|^edges\[", text, re.MULTILINE):
        raise ValueError(f"{source}: v1 traces are unsupported; run setup-flow-slice and retrace as v2")
    if re.search(r"^software_system\[|^external_systems\[", text, re.MULTILINE):
        raise ValueError(f"{source}: early v2 traces are unsupported; run setup-flow-slice and retrace")
    lines = text.replace("\r\n", "\n").split("\n")
    parsed, scalars, index = {}, {}, 0
    while index < len(lines):
        line, line_number = lines[index], index + 1
        if not line.strip() or line.lstrip().startswith("#"):
            index += 1
            continue
        scalar = re.match(r"^(\w+):\s(.*)$", line)
        if scalar:
            name, value = scalar.groups()
            if name not in SCALARS:
                raise ValueError(f"{source}:{line_number}: unknown scalar {name}")
            if name in scalars:
                raise ValueError(f"{source}:{line_number}: duplicate scalar {name}")
            if not value:
                raise ValueError(f"{source}:{line_number}: {name} is empty")
            scalars[name] = value
            index += 1
            continue
        match = HEADER.fullmatch(line)
        if not match:
            raise ValueError(f"{source}:{line_number}: invalid top-level line")
        name, count = match.group(1), int(match.group(2))
        fields = [field.strip() for field in match.group(3).split(",")]
        if name not in SCHEMAS:
            raise ValueError(f"{source}:{line_number}: unknown table {name}")
        if name in parsed:
            raise ValueError(f"{source}:{line_number}: duplicate table {name}")
        if fields != SCHEMAS[name]:
            raise ValueError(f"{source}:{line_number}: wrong columns for {name}")
        rows = []
        for _ in range(count):
            index += 1
            if index >= len(lines) or not lines[index].startswith("  "):
                raise ValueError(f"{source}:{index + 1}: missing indented {name} row")
            cells = split_row(lines[index].strip(), source, index + 1)
            if len(cells) != len(fields):
                raise ValueError(f"{source}:{index + 1}: expected {len(fields)} cells, got {len(cells)}")
            if any(cell == "" for cell in cells):
                raise ValueError(f"{source}:{index + 1}: cells must not be empty")
            rows.append(dict(zip(fields, cells)))
        parsed[name] = rows
        index += 1

    missing = sorted((SCALARS - scalars.keys()) | (SCHEMAS.keys() - parsed.keys()))
    if missing:
        raise ValueError(f"{source}: missing {', '.join(missing)}")
    if scalars["version"] != "2":
        raise ValueError(f"{source}: version must be 2; run setup-flow-slice and retrace")
    if sum(row["role"] == "focus" for row in parsed["systems"]) != 1:
        raise ValueError(f"{source}: systems must contain exactly one focus row")
    if not parsed["containers"]:
        raise ValueError(f"{source}: containers must not be empty")

    id_rows = [*parsed["systems"], *parsed["containers"], *parsed["relationships"], *parsed["components"], *parsed["hops"]]
    ids = [row["id"] for row in id_rows]
    if any(not ID.fullmatch(value) for value in ids):
        raise ValueError(f"{source}: ids must be lowercase kebab-case")
    if len(ids) != len(set(ids)):
        raise ValueError(f"{source}: ids must be globally unique")

    systems = {row["id"]: row for row in parsed["systems"]}
    containers = {row["id"]: row for row in parsed["containers"]}
    components = {row["id"]: row for row in parsed["components"]}
    endpoints = set(systems) | set(containers) | set(components)
    relationships = {row["id"]: row for row in parsed["relationships"]}
    for row in systems.values():
        if row["role"] not in {"focus", "internal", "external"}:
            raise ValueError(f"{source}: systems.role must be focus, internal, or external")
    for row in containers.values():
        if row["system"] not in systems:
            raise ValueError(f"{source}: container {row['id']} has an unknown system")
        if row["kind"] not in {"application", "data-store"}:
            raise ValueError(f"{source}: containers.kind must be application or data-store")
    for row in components.values():
        parent = containers.get(row["container"])
        if not parent:
            raise ValueError(f"{source}: component {row['id']} has an unknown container")
        if parent["kind"] != "application":
            raise ValueError(f"{source}: component {row['id']} cannot belong to a data-store")

    for table in ("relationships", "hops"):
        for row in parsed[table]:
            if row["confirmed"] not in {"true", "false"}:
                raise ValueError(f"{source}: {table}.confirmed must be true or false")
            if (row["confirmed"] == "false") != (row["via"] == "unresolved"):
                raise ValueError(f"{source}: {table}.via must be unresolved exactly when confirmed is false")

    def endpoint_container(endpoint):
        if endpoint in components:
            return components[endpoint]["container"]
        if endpoint in containers:
            return endpoint
        return None

    def endpoint_system(endpoint):
        container = endpoint_container(endpoint)
        return containers[container]["system"] if container else endpoint

    def endpoint_contains_component(endpoint, component):
        container = components[component]["container"]
        return endpoint in {component, container, containers[container]["system"]}

    for row in relationships.values():
        if row["from"] not in endpoints or row["to"] not in endpoints:
            raise ValueError(f"{source}: relationship {row['id']} has an unknown endpoint")
        if row["from"] == row["to"]:
            raise ValueError(f"{source}: relationship {row['id']} must cross a boundary")
        from_container, to_container = endpoint_container(row["from"]), endpoint_container(row["to"])
        if from_container and from_container == to_container:
            raise ValueError(f"{source}: relationship {row['id']} stays inside one container; use hops")
        if (not from_container or not to_container) and endpoint_system(row["from"]) == endpoint_system(row["to"]):
            raise ValueError(f"{source}: relationship {row['id']} stays inside one system hierarchy")
        if row["transport"] not in {"http", "grpc", "event", "database", "unknown"}:
            raise ValueError(f"{source}: invalid relationship transport {row['transport']}")
        if row["transport"] == "unknown" and row["confirmed"] != "false":
            raise ValueError(f"{source}: unknown transport requires confirmed false")
        stores = sum(containers.get(endpoint, {}).get("kind") == "data-store" for endpoint in (row["from"], row["to"]))
        if (row["transport"] == "database") != (stores == 1):
            raise ValueError(f"{source}: database transport must connect exactly one data-store")
        if row["transport"] == "database" and not any(
            endpoint_container(endpoint) and containers[endpoint_container(endpoint)]["kind"] == "application"
            for endpoint in (row["from"], row["to"])
        ):
            raise ValueError(f"{source}: database transport must connect an application to a data-store")

    for row in parsed["hops"]:
        from_component = components.get(row["from_component"])
        to_component = components.get(row["to_component"])
        if not from_component or not to_component:
            raise ValueError(f"{source}: hop {row['id']} has an unknown component")
        container_id = from_component["container"]
        if container_id != to_component["container"]:
            raise ValueError(f"{source}: hop {row['id']} crosses containers")
        if containers[container_id]["kind"] != "application":
            raise ValueError(f"{source}: hop {row['id']} must belong to an application container")
        if not row["line"].isdigit() or int(row["line"]) < 1:
            raise ValueError(f"{source}: hops.line must be a positive integer")
        match = PATH.fullmatch(row["path"])
        if not match or match.group(1) not in TRIGGERS:
            raise ValueError(f"{source}: hop {row['id']} has an invalid entrypoint suffix")
        if row["outcome"] not in {"-", "return", "db-write", "db-read"}:
            raise ValueError(f"{source}: invalid hops.outcome {row['outcome']}")
        relationship = relationships.get(row["relationship"]) if row["relationship"] != "-" else None
        if row["relationship"] != "-" and not relationship:
            raise ValueError(f"{source}: hop {row['id']} references an unknown relationship")
        if relationship and not any(
            endpoint_contains_component(endpoint, component)
            for endpoint in (relationship["from"], relationship["to"])
            for component in (row["from_component"], row["to_component"])
        ):
            raise ValueError(f"{source}: hop {row['id']} references a relationship outside its component lineage")
        database_outcome = row["outcome"] in {"db-write", "db-read"}
        database_relationship = relationship and relationship["transport"] == "database"
        if database_outcome != bool(database_relationship):
            raise ValueError(f"{source}: hop {row['id']} has an invalid outcome/relationship combination")
        if row["outcome"] == "return" and relationship:
            raise ValueError(f"{source}: return hops cannot reference a relationship")

    groups = defaultdict(list)
    for row in parsed["hops"]:
        container = components[row["from_component"]]["container"]
        groups[(container, row["path"])].append(row)
    for (container, path), rows in groups.items():
        outgoing = defaultdict(set)
        for row in rows:
            outgoing[row["caller"]].add(row["callee"])
        reachable, pending = {rows[0]["caller"]}, [rows[0]["caller"]]
        while pending:
            caller = pending.pop()
            for callee in outgoing[caller] - reachable:
                reachable.add(callee)
                pending.append(callee)
        disconnected = [row for row in rows if row["caller"] not in reachable]
        if disconnected:
            row = disconnected[0]
            raise ValueError(f"{source}: {container} path {path!r} has unreachable hop {row['id']}; record the callback or goroutine handoff")
    return parsed


def quality_warnings(parsed, source):
    warnings = []
    unresolved = [row for row in parsed["hops"] if row["confirmed"] == "false"]
    if unresolved:
        warnings.append(f"{source}: warning: {len(unresolved)} unconfirmed hop(s) remain")
    confirmed = [row for row in parsed["hops"] if row["confirmed"] == "true"]
    if confirmed and all(row["via"] == "read" for row in confirmed):
        warnings.append(f"{source}: warning: all {len(confirmed)} confirmed hops use via=read; confirm semantic tooling was unavailable")
    for path in sorted({row["path"] for row in parsed["hops"] if row["path"].endswith(" (callback)")}):
        warnings.append(f"{source}: warning: path {path!r} uses callback as its entrypoint; keep the original entrypoint path")
    for row in parsed["hops"]:
        location = f"{row['file']}:{row['line']}"
        file = row["file"].replace(chr(92), "/")
        if row["outcome"].startswith("db-") and not re.search(r"(?:adapter|repository|store|database|db)", file, re.I):
            warnings.append(f"{source}: warning: {location}: {row['outcome']} may stop before the wired database adapter")
        if row["outcome"] == "return" and re.search(r"(?:Client|Repo|Repository|Store)[.)]", row["callee"]):
            warnings.append(f"{source}: warning: {location}: boundary-looking target {row['callee']} is marked return; verify its implementation")
    return warnings


VALID = '''version: 2
topic: create transaction
systems[3]{id,name,role}:
  budget-system,Budget System,focus
  clearing-system,Clearing System,internal
  bank-system,Bank System,external
containers[4]{id,system,name,kind}:
  web,budget-system,Web,application
  api,budget-system,API,application
  postgres,budget-system,Postgres,data-store
  clearing-api,clearing-system,Clearing API,application
relationships[4]{id,from,to,transport,contract,confirmed,via,evidence}:
  web-api,web-ui,api-http,http,POST /transactions,true,read,web.ts:10
  api-db,api-transactions,postgres,database,transactions table,true,read,repository.go:40
  api-clearing,api-transactions,clearing-payments,grpc,Clearing.Pay,true,read,clearing.go:24
  api-bank,api-transactions,bank-system,http,POST /payments,true,read,bank.go:20
components[4]{id,container,name}:
  web-ui,web,Transaction UI
  api-http,api,HTTP handlers
  api-transactions,api,Transactions
  clearing-payments,clearing-api,Payments
hops[6]{id,path,from_component,to_component,caller,callee,file,line,confirmed,via,outcome,relationship}:
  hop-web,CreateTransaction (http),web-ui,web-ui,Form.submit,ApiClient.create,web.ts,10,true,outgoingCalls,-,web-api
  hop-service,CreateTransaction (http),api-http,api-transactions,Handler.Create,Service.Create,handler.go,12,true,outgoingCalls,-,-
  hop-callback,CreateTransaction (http),api-transactions,api-transactions,Service.Create,TxManager.Run,service.go,20,true,outgoingCalls,-,-
  hop-db,CreateTransaction (http),api-transactions,api-transactions,TxManager.Run,Repository.Insert,repository.go,40,true,outgoingCalls,db-write,api-db
  hop-clearing,CreateTransaction (http),api-transactions,api-transactions,TxManager.Run,ClearingClient.Pay,clearing.go,24,true,outgoingCalls,-,api-clearing
  hop-bank,CreateTransaction (http),api-transactions,api-transactions,TxManager.Run,BankClient.Send,bank.go,20,true,outgoingCalls,-,api-bank
'''


def expect_error(label, text, contains=None):
    try:
        validate(text, f"self-test-{label}")
    except ValueError as error:
        if contains and contains not in str(error):
            raise SystemExit(f"self-test failed: {label} raised {error!s}")
        return
    raise SystemExit(f"self-test failed: accepted {label}")


source = sys.argv[1]
ignore_warnings = sys.argv[2] == "true"
if source == "--self-test":
    parsed = validate(VALID, "self-test-valid")
    assert quality_warnings(parsed, "self-test-valid") == []
    expect_error("duplicate-id", VALID.replace("hop-web,Create", "web,Create"), "globally unique")
    expect_error("unknown-endpoint", VALID.replace("api-bank,api-transactions,bank-system", "api-bank,api-transactions,missing"), "unknown endpoint")
    expect_error("unknown-system", VALID.replace("web,budget-system,Web", "web,missing,Web"), "unknown system")
    expect_error("invalid-parent", VALID.replace("web-ui,web,Transaction UI", "web-ui,postgres,Transaction UI"), "data-store")
    expect_error("cross-container-hop", VALID.replace("api-http,api-transactions,Handler.Create", "web-ui,api-transactions,Handler.Create"), "crosses containers")
    expect_error("same-container-relationship", VALID.replace("web-api,web-ui,api-http", "web-api,api-http,api-transactions"), "stays inside one container")
    expect_error("same-system-hierarchy", VALID.replace("web-api,web-ui,api-http", "web-api,budget-system,api-http"), "stays inside one system hierarchy")
    expect_error("unknown-relationship", VALID.replace("-,web-api\n", "-,missing\n", 1), "unknown relationship")
    expect_error("unrelated-relationship", VALID.replace("-,api-clearing\n", "-,web-api\n", 1), "component lineage")
    expect_error("invalid-outcome", VALID.replace("outgoingCalls,db-write,api-db", "outgoingCalls,return,api-db"), "outcome/relationship")
    expect_error("invalid-suffix", VALID.replace("CreateTransaction (http)", "CreateTransaction (smtp)"), "invalid entrypoint suffix")
    expect_error("disconnected-callback", VALID.replace("TxManager.Run,Repository.Insert", "DetachedCallback,Repository.Insert"), "unreachable hop")
    expect_error("missing-focus", VALID.replace(",focus\n", ",internal\n"), "exactly one focus")
    expect_error("multiple-focus", VALID.replace("Clearing System,internal", "Clearing System,focus"), "exactly one focus")
    callback = VALID.replace("CreateTransaction (http)", "CreateTransaction (callback)")
    assert any("original entrypoint" in warning for warning in quality_warnings(validate(callback, "self-test-callback"), "self-test-callback"))
    v1 = "topic: old\nservices[1]{id,affected}:\n  api,false\nedges[0]{from,to,kind,confirmed,via,evidence,contract}:\nhops[0]{service,path,from,file,line,to,confirmed,via,outcome}:\n"
    expect_error("v1", v1, "setup-flow-slice")
    old_v2 = VALID.replace("systems[3]{id,name,role}:\n  budget-system,Budget System,focus\n  clearing-system,Clearing System,internal\n  bank-system,Bank System,external", "software_system[1]{id,name}:\n  budget-system,Budget System\nexternal_systems[1]{id,name}:\n  bank-system,Bank System")
    expect_error("old-v2", old_v2, "early v2")
    print("self-test passed")
else:
    path = Path(source)
    if not path.is_file():
        raise SystemExit(f"{source}: not a file")
    try:
        parsed = validate(path.read_text(), source)
    except (OSError, UnicodeError, ValueError) as error:
        raise SystemExit(error)
    warnings = quality_warnings(parsed, source)
    for warning in warnings:
        print(warning, file=sys.stderr)
    if warnings and not ignore_warnings:
        raise SystemExit(f"{source}: {len(warnings)} quality warning(s); fix them or rerun with --ignore-warnings")
    print(f"valid: {source}")
PY
