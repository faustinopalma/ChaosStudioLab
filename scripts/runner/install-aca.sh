#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "$0")/install.sh"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y docker.io openssl
systemctl enable --now docker
usermod -aG docker csloperator
docker version
printf '\nCSL_ACA_INSTALL_COMPLETED\n'
