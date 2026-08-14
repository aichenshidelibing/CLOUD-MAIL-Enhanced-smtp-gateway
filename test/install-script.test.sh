#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HELP_OUTPUT="$(bash "$ROOT/install.sh" --help)"
grep -q -- '--letsencrypt-mode MODE' <<<"$HELP_OUTPUT"
grep -q -- '--letsencrypt-webroot DIR' <<<"$HELP_OUTPUT"
grep -q -- 'CLOUD_MAIL_SMTP_LETSENCRYPT_MODE' <<<"$HELP_OUTPUT"
grep -q -- 'CLOUD_MAIL_SMTP_LETSENCRYPT_WEBROOT' <<<"$HELP_OUTPUT"

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
