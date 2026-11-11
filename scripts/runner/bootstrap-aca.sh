#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
eval "$(pwsh -NoLogo -NoProfile -Command '
  $c = Get-Content ./runner-config.json -Raw | ConvertFrom-Json
  foreach ($p in $c.PSObject.Properties) {
    if ([string]$p.Value -notmatch "^[A-Za-z0-9./:_-]+$") { throw "Unsafe runner input." }
    "export $($p.Name)=$($p.Value)"
  }')"
az login --identity --client-id "$RUNNER_CLIENT_ID" --allow-no-subscriptions -o none
az account set --subscription "$SUBSCRIPTION_ID"
if [[ -f diagnostics-token.txt ]]; then
  az keyvault secret set --vault-name "$VAULT_NAME" --name diagnostics-token --file diagnostics-token.txt --encoding utf-8 -o none
  rm -f diagnostics-token.txt
fi
az login --identity --client-id "$MIGRATION_CLIENT_ID" --allow-no-subscriptions -o none
export PGPASSWORD="$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)"
export PGHOST="$POSTGRES_HOST" PGUSER=id-csl-migrations PGDATABASE=postgres PGSSLMODE=verify-full PGSSLROOTCERT=/etc/ssl/certs/ca-certificates.crt
if [[ "$(psql -v ON_ERROR_STOP=1 -tAc "SELECT 1 FROM pg_database WHERE datname='csl'")" != "1" ]]; then
  psql -v ON_ERROR_STOP=1 -c 'CREATE DATABASE csl'
fi
if [[ "$(psql -v ON_ERROR_STOP=1 -tAc "SELECT 1 FROM pg_roles WHERE rolname='id-csl-runtime'")" != "1" ]]; then
  psql -v ON_ERROR_STOP=1 -c "SELECT * FROM pg_catalog.pgaadauth_create_principal_with_oid('id-csl-runtime','$RUNTIME_PRINCIPAL_ID','service',false,false)"
fi
export PGDATABASE=csl
psql -v ON_ERROR_STOP=1 -f src/Demo.Api/Migrations/001-create-orders.sql
psql -v ON_ERROR_STOP=1 -c 'GRANT CONNECT ON DATABASE csl TO "id-csl-runtime"; GRANT USAGE ON SCHEMA public TO "id-csl-runtime"; GRANT SELECT, INSERT ON TABLE orders TO "id-csl-runtime";'
unset PGPASSWORD
az login --identity --client-id "$RUNNER_CLIENT_ID" --allow-no-subscriptions -o none
az account set --subscription "$SUBSCRIPTION_ID"
az acr login -n "$REGISTRY_NAME" -o none
docker build -f src/Demo.Api/Dockerfile.aks -t "$REGISTRY_HOST/csl-api:$SOURCE_REVISION" .
docker push "$REGISTRY_HOST/csl-api:$SOURCE_REVISION"
digest="$(docker inspect --format='{{index .RepoDigests 0}}' "$REGISTRY_HOST/csl-api:$SOURCE_REVISION")"
printf '%s\n' "$digest" > image-digest.txt
printf '\nCSL_ACA_IMAGE_PUBLISHED\n'
