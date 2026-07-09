#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Startuje Vault, Postgres i Concourse (docker compose up -d)..."
docker compose up -d

echo "==> Czekam az Vault odpowie na :8200..."
until docker exec -e VAULT_ADDR=http://127.0.0.1:8200 vault vault status >/dev/null 2>&1; do
  sleep 2
done

echo "==> Wlaczam silnik KV v2 pod sciezka 'concourse' w Vault..."
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root vault \
  vault secrets enable -path=concourse kv-v2 \
  || echo "(silnik juz istnieje pod ta sciezka, pomijam)"

echo "==> Wgrywam przykladowe sekrety do Vault..."
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root vault \
  vault kv put concourse/main/mule-app/dev/db_password value=SuperTajneHaslo-DEV
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root vault \
  vault kv put concourse/main/mule-app/dev/api_key value=dev-api-key-abc123
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root vault \
  vault kv put concourse/main/mule-app/prod/db_password value=SuperTajneHaslo-PROD
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root vault \
  vault kv put concourse/main/mule-app/prod/api_key value=prod-api-key-xyz789

echo "==> Czekam az Concourse odpowie na :8080 (moze potrwac do minuty)..."
until curl -sf http://localhost:8080/api/v1/info >/dev/null 2>&1; do
  sleep 3
done

echo ""
echo "==> Gotowe."
echo "Vault UI:      http://localhost:8200   (token: root)"
echo "Concourse UI:  http://localhost:8080   (login: test / test)"
