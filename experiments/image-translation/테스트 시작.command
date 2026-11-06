#!/bin/bash
set -euo pipefail
poc_launcher_dir="$(cd "$(dirname "$0")" && pwd)"
poc_project_root="$(cd "$poc_launcher_dir/../.." && pwd)"
exec "$poc_project_root/scripts/image-translation-poc.sh" --open
