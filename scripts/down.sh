#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Zatrzymuje i usuwam kontenery + wolumeny (dane Vault/Concourse-DB)..."
docker compose down -v
