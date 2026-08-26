#!/usr/bin/env bash
set -euo pipefail

validator_args=()
if [[ ${1:-} == "--ignore-warnings" ]]; then
  validator_args+=("--ignore-warnings")
  shift
fi

if [[ $# -ne 1 ]]; then
  echo "usage: $0 [--ignore-warnings] <trace.toon>" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
"${script_dir}/validate-toon.sh" "${validator_args[@]}" "$1"

url="https://bad33ndj3.github.io/flow-slice-skill/#b64=$(base64 < "$1" | tr -d '\n')"

case "$(uname -s)" in
  Darwin) open "$url" ;;
  Linux) xdg-open "$url" ;;
  *) python3 -m webbrowser "$url" ;;
esac

echo "Opened flow-slice viewer."
