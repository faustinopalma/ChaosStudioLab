#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "$0")/install.sh"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y docker.io openssl
systemctl enable --now docker
usermod -aG docker csloperator
az aks install-cli --client-version v1.35.9 --install-location /usr/local/bin/kubectl \
  --kubelogin-install-location /usr/local/bin/kubelogin
docker version
kubectl version --client
kubelogin --version
printf '\nCSL_AKS_INSTALL_COMPLETED\n'
