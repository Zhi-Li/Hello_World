#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
trap 'read -r -p "Press Return to close… " _done' EXIT
bash scripts/build.sh
