#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <trace.toon>" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
"${script_dir}/validate-toon.sh" "$1"

url="https://bad33ndj3.github.io/flow-slice-skill/#b64=$(base64 < "$1" | tr -d '\n')"

case "$(uname -s)" in
  Darwin) open "$url" ;;
  Linux) xdg-open "$url" ;;
  *) python3 -m webbrowser "$url" ;;
esac

echo "Opened flow-slice viewer."
