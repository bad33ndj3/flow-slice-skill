#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <trace.toon|--self-test>" >&2
  exit 2
fi

python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path

SCHEMAS = {
    "services": ["id", "affected"],
    "edges": ["from", "to", "kind", "confirmed", "via", "evidence", "contract"],
    "hops": ["service", "path", "from", "file", "line", "to", "confirmed", "via", "outcome"],
}
HEADER = re.compile(r"^(\w+)\[(\d+)]\{([^}]*)}:\s*$")


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

    lines = text.replace("\r\n", "\n").split("\n")
    parsed, topic, index = {}, None, 0
    while index < len(lines):
        line, line_number = lines[index], index + 1
        if not line.strip() or line.lstrip().startswith("#"):
            index += 1
            continue
        if line.startswith("topic: "):
            if topic is not None:
                raise ValueError(f"{source}:{line_number}: duplicate topic")
            topic = line[7:]
            if not topic:
                raise ValueError(f"{source}:{line_number}: topic is empty")
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

    missing = [name for name in ("topic", *SCHEMAS) if (name == "topic" and topic is None) or (name != "topic" and name not in parsed)]
    if missing:
        raise ValueError(f"{source}: missing {', '.join(missing)}")

    services = [row["id"] for row in parsed["services"]]
    if not services:
        raise ValueError(f"{source}: services table must not be empty")
    if len(services) != len(set(services)):
        raise ValueError(f"{source}: service ids must be unique")
    service_ids = set(services)
    for row in parsed["services"]:
        if row["affected"] != "false":
            raise ValueError(f"{source}: services.affected must be false")

    for table in ("edges", "hops"):
        for row in parsed[table]:
            if row["confirmed"] not in {"true", "false"}:
                raise ValueError(f"{source}: {table}.confirmed must be true or false")
            if (row["confirmed"] == "false") != (row["via"] == "unresolved"):
                raise ValueError(f"{source}: {table}.via must be unresolved exactly when confirmed is false")

    for row in parsed["edges"]:
        if row["from"] not in service_ids or row["to"] not in service_ids:
            raise ValueError(f"{source}: edge references an unknown service")
        if row["kind"] not in {"http", "grpc", "event", "unknown"}:
            raise ValueError(f"{source}: edges.kind must be http, grpc, event, or unknown")
        if row["kind"] == "unknown" and row["confirmed"] != "false":
            raise ValueError(f"{source}: edges.kind unknown requires confirmed false")

    for row in parsed["hops"]:
        if row["service"] not in service_ids:
            raise ValueError(f"{source}: hop references an unknown service")
        if not row["line"].isdigit() or int(row["line"]) < 1:
            raise ValueError(f"{source}: hops.line must be a positive integer")
        if row["outcome"] not in {"-", "return", "db-write", "db-read"}:
            raise ValueError(f"{source}: invalid hops.outcome {row['outcome']}")


source = sys.argv[1]
if source == "--self-test":
    valid = """topic: self-test
services[2]{id,affected}:
  web,false
  api,false
edges[1]{from,to,kind,confirmed,via,evidence,contract}:
  web,api,http,true,read,web.ts:1,"POST /users (name, email) -> User"
hops[1]{service,path,from,file,line,to,confirmed,via,outcome}:
  api,CreateUser (http),handler,handler.go,12,service.Create,true,read,db-write
"""
    validate(valid, "self-test-valid")
    invalid = {
        "empty file": "",
        "empty services table": valid.replace("services[2]{id,affected}:\n  web,false\n  api,false", "services[0]{id,affected}:"),
        "duplicate service": valid.replace("web,false\n  api,false", "web,false\n  web,false"),
        "malformed quoted row": valid.replace('"POST /users (name, email) -> User"', '"POST /users (name, email) -> User'),
        "invalid edge kind": valid.replace("web,api,http,true", "web,api,smtp,true"),
        "confirmed unknown edge": valid.replace("web,api,http,true", "web,api,unknown,true"),
    }
    for label, text in invalid.items():
        try:
            validate(text, f"self-test-{label}")
        except ValueError:
            continue
        raise SystemExit(f"self-test failed: accepted {label}")
    print("self-test passed")
else:
    path = Path(source)
    if not path.is_file():
        raise SystemExit(f"{source}: not a file")
    try:
        validate(path.read_text(), source)
    except (OSError, UnicodeError, ValueError) as error:
        raise SystemExit(error)
    print(f"valid: {source}")
PY
