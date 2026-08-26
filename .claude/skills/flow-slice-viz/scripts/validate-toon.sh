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
    "software_system": ["id", "name"],
    "containers": ["id", "name", "kind"],
    "external_systems": ["id", "name"],
    "relationships": ["id", "from", "to", "transport", "contract", "confirmed", "via", "evidence"],
    "components": ["id", "container", "name"],
    "hops": ["id", "path", "container", "component", "caller", "callee", "file", "line", "confirmed", "via", "outcome", "relationship"],
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
    if len(parsed["software_system"]) != 1:
        raise ValueError(f"{source}: software_system must contain exactly one row")
    if not parsed["containers"]:
        raise ValueError(f"{source}: containers must not be empty")

    id_rows = [*parsed["software_system"], *parsed["containers"], *parsed["external_systems"], *parsed["relationships"], *parsed["components"], *parsed["hops"]]
    ids = [row["id"] for row in id_rows]
    if any(not ID.fullmatch(value) for value in ids):
        raise ValueError(f"{source}: ids must be lowercase kebab-case")
    if len(ids) != len(set(ids)):
        raise ValueError(f"{source}: ids must be globally unique")

    containers = {row["id"]: row for row in parsed["containers"]}
    externals = {row["id"] for row in parsed["external_systems"]}
    endpoints = set(containers) | externals
    components = {row["id"]: row for row in parsed["components"]}
    relationships = {row["id"]: row for row in parsed["relationships"]}
    for row in containers.values():
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

    for row in relationships.values():
        if row["from"] not in endpoints or row["to"] not in endpoints:
            raise ValueError(f"{source}: relationship {row['id']} has an unknown endpoint")
        if row["from"] == row["to"]:
            raise ValueError(f"{source}: relationship {row['id']} must cross a boundary")
        if row["from"] not in containers and row["to"] not in containers:
            raise ValueError(f"{source}: relationship {row['id']} must touch a container")
        if row["transport"] not in {"http", "grpc", "event", "database", "unknown"}:
            raise ValueError(f"{source}: invalid relationship transport {row['transport']}")
        if row["transport"] == "unknown" and row["confirmed"] != "false":
            raise ValueError(f"{source}: unknown transport requires confirmed false")
        stores = sum(containers.get(endpoint, {}).get("kind") == "data-store" for endpoint in (row["from"], row["to"]))
        if (row["transport"] == "database") != (stores == 1):
            raise ValueError(f"{source}: database transport must connect exactly one data-store")
        if row["transport"] == "database" and not any(containers.get(endpoint, {}).get("kind") == "application" for endpoint in (row["from"], row["to"])):
            raise ValueError(f"{source}: database transport must connect an application to a data-store")

    for row in parsed["hops"]:
        container = containers.get(row["container"])
        if not container or container["kind"] != "application":
            raise ValueError(f"{source}: hop {row['id']} must belong to an application container")
        component = components.get(row["component"])
        if not component:
            raise ValueError(f"{source}: hop {row['id']} has an unknown component")
        if component["container"] != row["container"]:
            raise ValueError(f"{source}: hop {row['id']} crosses containers through its component")
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
        if relationship and row["container"] not in {relationship["from"], relationship["to"]}:
            raise ValueError(f"{source}: hop {row['id']} references a relationship outside its container")
        database_outcome = row["outcome"] in {"db-write", "db-read"}
        database_relationship = relationship and relationship["transport"] == "database"
        if database_outcome != bool(database_relationship):
            raise ValueError(f"{source}: hop {row['id']} has an invalid outcome/relationship combination")
        if row["outcome"] == "return" and relationship:
            raise ValueError(f"{source}: return hops cannot reference a relationship")

    groups = defaultdict(list)
    for row in parsed["hops"]:
        groups[(row["container"], row["path"])].append(row)
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
software_system[1]{id,name}:
  budget-system,Budget System
containers[3]{id,name,kind}:
  web,Web,application
  api,API,application
  postgres,Postgres,data-store
external_systems[1]{id,name}:
  bank-api,Bank API
relationships[3]{id,from,to,transport,contract,confirmed,via,evidence}:
  web-api,web,api,http,POST /transactions,true,read,web.ts:10
  api-db,api,postgres,database,transactions table,true,read,repository.go:40
  api-bank,api,bank-api,http,POST /payments,true,read,bank.go:20
components[2]{id,container,name}:
  web-ui,web,Transaction UI
  api-transactions,api,Transactions
hops[5]{id,path,container,component,caller,callee,file,line,confirmed,via,outcome,relationship}:
  hop-web,CreateTransaction (http),web,web-ui,Form.submit,ApiClient.create,web.ts,10,true,outgoingCalls,-,web-api
  hop-service,CreateTransaction (http),api,api-transactions,Handler.Create,Service.Create,handler.go,12,true,outgoingCalls,-,-
  hop-callback,CreateTransaction (http),api,api-transactions,Service.Create,TxManager.Run,service.go,20,true,outgoingCalls,-,-
  hop-db,CreateTransaction (http),api,api-transactions,TxManager.Run,Repository.Insert,repository.go,40,true,outgoingCalls,db-write,api-db
  hop-bank,CreateTransaction (http),api,api-transactions,TxManager.Run,BankClient.Send,bank.go,20,true,outgoingCalls,-,api-bank
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
    expect_error("unknown-endpoint", VALID.replace("api-bank,api,bank-api", "api-bank,api,missing"), "unknown endpoint")
    expect_error("invalid-parent", VALID.replace("web-ui,web,Transaction UI", "web-ui,postgres,Transaction UI"), "data-store")
    expect_error("cross-container-hop", VALID.replace("hop-service,CreateTransaction (http),api,api-transactions", "hop-service,CreateTransaction (http),api,web-ui"), "crosses containers")
    expect_error("unknown-relationship", VALID.replace("-,web-api\n", "-,missing\n", 1), "unknown relationship")
    expect_error("invalid-outcome", VALID.replace("outgoingCalls,db-write,api-db", "outgoingCalls,return,api-db"), "outcome/relationship")
    expect_error("invalid-suffix", VALID.replace("CreateTransaction (http)", "CreateTransaction (smtp)"), "invalid entrypoint suffix")
    expect_error("disconnected-callback", VALID.replace("TxManager.Run,Repository.Insert", "DetachedCallback,Repository.Insert"), "unreachable hop")
    callback = VALID.replace("CreateTransaction (http)", "CreateTransaction (callback)")
    assert any("original entrypoint" in warning for warning in quality_warnings(validate(callback, "self-test-callback"), "self-test-callback"))
    v1 = "topic: old\nservices[1]{id,affected}:\n  api,false\nedges[0]{from,to,kind,confirmed,via,evidence,contract}:\nhops[0]{service,path,from,file,line,to,confirmed,via,outcome}:\n"
    expect_error("v1", v1, "setup-flow-slice")
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
