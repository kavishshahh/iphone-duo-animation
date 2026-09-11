#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash native/scripts/build.sh
open native/build/Still.app
