#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sed -i -E 's#https?://[a-z.]*archive\.ubuntu\.com/#https://archive.ubuntu.com/#g; s#http://security\.ubuntu\.com/#https://security.ubuntu.com/#g' /etc/apt/sources.list
apt-get -o APT::Update::Error-Mode=any update
apt-get install -y ca-certificates curl gnupg unzip zip postgresql-client docker.io
install -m 0755 -d /etc/apt/keyrings
curl --fail --silent --show-error https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor --yes -o /etc/apt/keyrings/microsoft.gpg
curl --fail --silent --show-error -o /tmp/packages-microsoft-prod.deb \
  https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb
dpkg -i /tmp/packages-microsoft-prod.deb
printf 'deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ jammy main\n' \
  > /etc/apt/sources.list.d/azure-cli.list
apt-get -o APT::Update::Error-Mode=any update
apt-get install -y azure-cli
powershell_version="$(apt-cache madison powershell-lts | awk '$3 ~ /^7[.]4[.]/ && !found { print $3; found=1 }')"
if [[ -z "$powershell_version" ]]; then
  echo 'No supported PowerShell 7.4 LTS package is available for the Automation runtime.' >&2
  exit 1
fi
apt-get install -y --allow-downgrades "powershell-lts=$powershell_version"
ln -sf /opt/microsoft/powershell/7-lts/pwsh /usr/local/bin/pwsh
printf '\npowershell_7_4_path="/opt/microsoft/powershell/7-lts/pwsh"\n' >> /etc/environment
systemctl enable --now docker
usermod -aG docker csloperator
curl --fail --silent --show-error -L -o /tmp/k6.tar.gz \
  https://github.com/grafana/k6/releases/download/v1.5.0/k6-v1.5.0-linux-amd64.tar.gz
tar -xzf /tmp/k6.tar.gz -C /tmp
install -m 0755 /tmp/k6-v1.5.0-linux-amd64/k6 /usr/local/bin/k6
rm -f /tmp/packages-microsoft-prod.deb /tmp/k6.tar.gz
az version
pwsh -NoLogo -NoProfile -Command '
  $v = $PSVersionTable.PSVersion
  if ($v.Major -ne 7 -or $v.Minor -ne 4) { throw "Automation requires PowerShell 7.4; installed $v." }
  $v.ToString()'
k6 version
docker version
printf '\nCSL_INSTALL_COMPLETED\n'
