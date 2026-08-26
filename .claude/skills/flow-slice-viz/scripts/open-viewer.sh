#!/usr/bin/env bash
set -euo pipefail

open_browser=true
if [[ ${1:-} == "--print" ]]; then
  open_browser=false
  shift
fi

if [[ $# -ne 1 ]]; then
  echo "usage: $0 [--print] <trace.toon>" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
"${script_dir}/validate-toon.sh" "$1"

url="https://bad33ndj3.github.io/flow-slice-skill/#b64=$(base64 < "$1" | tr -d '\n')"
printf '%s\n' "$url"

if [[ $open_browser == false ]]; then
  exit 0
fi

case "$(uname -s)" in
  Darwin) open "$url" ;;
  Linux) xdg-open "$url" ;;
  *) echo "Open the printed URL in a browser." >&2 ;;
esac
