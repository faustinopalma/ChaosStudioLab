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
if [[ -z "$(az keyvault secret list --vault-name "$VAULT_NAME" --query "[?name=='diagnostics-token'].id" -o tsv)" ]]; then
  az keyvault secret set --vault-name "$VAULT_NAME" --name diagnostics-token --value "$(openssl rand -hex 32)" -o none
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
az aks get-credentials -g "$APP_RESOURCE_GROUP" -n "$CLUSTER_NAME" --overwrite-existing -o none
kubelogin convert-kubeconfig -l msi --client-id "$RUNNER_CLIENT_ID"
kubectl get nodes -o wide
az acr login -n "$REGISTRY_NAME" -o none
docker build -f src/Demo.Api/Dockerfile.aks -t "$REGISTRY_HOST/csl-api:$SOURCE_REVISION" .
docker push "$REGISTRY_HOST/csl-api:$SOURCE_REVISION"
digest="$(docker inspect --format='{{index .RepoDigests 0}}' "$REGISTRY_HOST/csl-api:$SOURCE_REVISION")"
printf '%s\n' "$digest" > image-digest.txt
umask 077
mkdir -p tls
if [[ ! -f tls/server.pfx ]]; then
  openssl req -x509 -newkey rsa:3072 -nodes -keyout tls/ca.key -out tls/ca.crt -days 30 -subj "/CN=CSL private laboratory CA"
  openssl req -newkey rsa:3072 -nodes -keyout tls/server.key -out tls/server.csr -subj "/CN=$API_FQDN"
  printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "$API_FQDN" > tls/extensions.cnf
  openssl x509 -req -in tls/server.csr -CA tls/ca.crt -CAkey tls/ca.key -CAcreateserial -out tls/server.crt -days 14 -extfile tls/extensions.cnf
  openssl pkcs12 -export -out tls/server.pfx -inkey tls/server.key -in tls/server.crt -certfile tls/ca.crt -passout pass:
fi
sudo install -m 0644 tls/ca.crt /usr/local/share/ca-certificates/csl-lab.crt
sudo update-ca-certificates
kubectl create namespace csl --dry-run=client -o yaml | kubectl apply -f -
token="$(az keyvault secret show --vault-name "$VAULT_NAME" --name diagnostics-token --query value -o tsv)"
printf '%s' "$token" > tls/token.txt
unset token
kubectl -n csl create secret generic api-auth --from-file=token=tls/token.txt --dry-run=client -o json > tls/auth-secret.json
kubectl -n csl create secret generic api-tls --from-file=server.pfx=tls/server.pfx --dry-run=client -o json > tls/tls-secret.json
kubectl apply -f tls/auth-secret.json -f tls/tls-secret.json
rm -f tls/token.txt tls/auth-secret.json tls/tls-secret.json
IMAGE_DIGEST="$digest" pwsh -NoLogo -NoProfile -Command '
  $c=Get-Content ./runner-config.json -Raw|ConvertFrom-Json
  $t=Get-Content ./k8s/aks-workload.yaml -Raw
  foreach($p in @{RUNTIME_CLIENT_ID=$c.RUNTIME_CLIENT_ID;POSTGRES_HOST=$c.POSTGRES_HOST;SOURCE_REVISION=$c.SOURCE_REVISION;IMAGE_DIGEST=$env:IMAGE_DIGEST}.GetEnumerator()){$t=$t.Replace("__"+$p.Key+"__",$p.Value)}
  $t|Set-Content ./k8s/rendered.yaml'
kubectl apply --dry-run=server -f k8s/rendered.yaml
kubectl apply -f k8s/rendered.yaml
kubectl -n csl rollout status deployment/api --timeout=600s
curl --fail --silent --show-error --connect-timeout 5 --max-time 15 \
  --retry 20 --retry-all-errors --retry-delay 3 --retry-max-time 120 "https://$API_FQDN/health/ready"
printf '\nCSL_AKS_APPLICATION_READY\n'
