#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HELP_OUTPUT="$(bash "$ROOT/install.sh" --help)"
grep -q -- '--letsencrypt-mode MODE' <<<"$HELP_OUTPUT"
grep -q -- '--letsencrypt-webroot DIR' <<<"$HELP_OUTPUT"
grep -q -- 'CLOUD_MAIL_SMTP_LETSENCRYPT_MODE' <<<"$HELP_OUTPUT"
grep -q -- 'CLOUD_MAIL_SMTP_LETSENCRYPT_WEBROOT' <<<"$HELP_OUTPUT"
grep -q -- '--no-auto-install' "$ROOT/install.sh"
grep -q -- 'ensure_runtime_dependencies' "$ROOT/install.sh"
grep -q -- 'docker-compose-plugin' "$ROOT/install.sh"
grep -q -- 'docker.asc' "$ROOT/install.sh"
grep -q -- 'non_debian' "$ROOT/install.sh"
grep -q -- 'systemctl enable --now docker' "$ROOT/install.sh"
grep -q -- 'CLOUD_MAIL_SMTP_AUTO_INSTALL' "$ROOT/install.sh"
grep -q -- 'signed-by=' "$ROOT/install.sh"
grep -q -- 'https://download.docker.com/linux/' "$ROOT/install.sh"
grep -q -- 'apt-get install --no-install-recommends -y' "$ROOT/install.sh"
grep -q -- 'case "$DISTRO_ID" in' "$ROOT/install.sh"

grep -q -- 'certbot_args+=(--webroot -w "$LE_WEBROOT")' "$ROOT/install.sh"
grep -q -- 'check_webroot_prerequisites' "$ROOT/install.sh"
grep -q -- 'webroot_challenge_diagnostics' "$ROOT/install.sh"
grep -q -- 'webroot_file_left' "$ROOT/install.sh"
grep -q -- 'curl_attempt' "$ROOT/install.sh"
grep -q -- 'CLOUD_MAIL_SMTP_TLS_CERT_FILE' "$ROOT/README.md"
grep -q -- 'Origin CA' "$ROOT/README.md"

echo 'install script webroot/manual certificate checks passed'
grep -q -- 'validate_certificate_and_key' "$ROOT/install.sh"
grep -q -- 'if ! apt-get update' "$ROOT/install.sh"
