#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v vivado >/dev/null 2>&1; then
  echo "ERROR: vivado was not found in PATH." >&2
  echo "Source the Vivado settings64.sh file first." >&2
  exit 1
fi

exec vivado -mode batch -source "$script_dir/run_vivado.tcl" -tclargs "$@"
