#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
eval "$(pwsh -NoLogo -NoProfile -Command '
  $c = Get-Content ./runner-config.json -Raw | ConvertFrom-Json
  foreach ($p in $c.PSObject.Properties) {
    if ([string]$p.Value -notmatch "^[A-Za-z0-9./:_-]+$") { throw "Unsafe runner input." }
    "export $($p.Name)=$($p.Value)"
  }')"
az login --identity --client-id "$RUNNER_CLIENT_ID" --allow-no-subscriptions --output none
az account set --subscription "$SUBSCRIPTION_ID"
secret_ids="$(az keyvault secret list --vault-name "$VAULT_NAME" --query "[?name=='diagnostics-token'].id" -o tsv)"
if [[ -n "$secret_ids" ]]; then
  echo 'Reusing the existing deployment diagnostics secret.'
else
  az keyvault secret set --vault-name "$VAULT_NAME" --name diagnostics-token \
    --value "$(openssl rand -hex 32)" --output none
fi
az login --identity --client-id "$MIGRATION_CLIENT_ID" --allow-no-subscriptions --output none
export PGPASSWORD="$(az account get-access-token --resource-type oss-rdbms --query accessToken --output tsv)"
export PGHOST="$POSTGRES_HOST" PGUSER=id-csl-migrations PGDATABASE=postgres PGSSLMODE=verify-full
export PGSSLROOTCERT=/etc/ssl/certs/ca-certificates.crt
database_exists="$(psql -v ON_ERROR_STOP=1 -tAc "SELECT 1 FROM pg_database WHERE datname='csl'")"
if [[ "$database_exists" != "1" ]]; then
  psql -v ON_ERROR_STOP=1 -c 'CREATE DATABASE csl'
fi
runtime_role_exists="$(psql -v ON_ERROR_STOP=1 -tAc "SELECT 1 FROM pg_roles WHERE rolname='id-csl-runtime'")"
if [[ "$runtime_role_exists" != "1" ]]; then
  psql -v ON_ERROR_STOP=1 -c \
    "SELECT * FROM pg_catalog.pgaadauth_create_principal_with_oid('id-csl-runtime','$RUNTIME_PRINCIPAL_ID','service',false,false)"
fi
export PGDATABASE=csl
psql -v ON_ERROR_STOP=1 -f src/Demo.Api/Migrations/001-create-orders.sql
psql -v ON_ERROR_STOP=1 -c \
  'GRANT CONNECT ON DATABASE csl TO "id-csl-runtime"; GRANT USAGE ON SCHEMA public TO "id-csl-runtime"; GRANT SELECT, INSERT ON TABLE orders TO "id-csl-runtime";'
unset PGPASSWORD
az login --identity --client-id "$RUNNER_CLIENT_ID" --allow-no-subscriptions --output none
az account set --subscription "$SUBSCRIPTION_ID"
printf '%s  application.zip\n' "$PACKAGE_SHA256" | sha256sum --check
for host in "$API_FQDN" "$SCM_FQDN"; do
  addresses="$(getent ahostsv4 "$host" | awk '{print $1}' | sort -u)"
  if [[ -z "$addresses" ]] || grep -qv '^10\.81\.10\.' <<< "$addresses"; then
    echo "Private application/SCM DNS qualification failed for $host." >&2
    exit 1
  fi
done
az webapp deploy --resource-group "$APP_RESOURCE_GROUP" --name "$APP_NAME" \
  --src-path application.zip --type zip --timeout 600000 --async false --track-status false --output none
az rest --method post \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$APP_RESOURCE_GROUP/providers/Microsoft.Web/sites/$APP_NAME/config/configreferences/appsettings/refresh?api-version=2022-03-01" \
  --output none
echo 'Private database migration and checksummed Linux SCM package publication completed; private startup/participation qualification follows in PC orchestration.'
