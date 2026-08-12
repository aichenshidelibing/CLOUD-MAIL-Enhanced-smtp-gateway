#!/usr/bin/env bash
set -Eeuo pipefail

# CLOUD-MAIL SMTP-to-HTTP Gateway installer.
# Linux + Docker Compose only. It does not install Node.js or systemd.

INSTALL_DIR="/opt/cloud-mail-smtp-gateway"
CONFIG_SOURCE=""
ASSUME_YES=0
RECONFIGURE=0
NON_INTERACTIVE=0
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

usage() {
  cat <<'USAGE'
CLOUD-MAIL SMTP-to-HTTP Gateway installer (Linux + Docker Compose only)

Usage:
  sudo ./install.sh [options]

Options:
  --dir DIR           Installation directory (default: /opt/cloud-mail-smtp-gateway)
  --config FILE       Copy FILE as installation config.json
  --reconfigure       Create config.json through the interactive configuration wizard
  --non-interactive   Do not prompt; read configuration from environment variables
  --yes               Do not ask before replacing an existing config.json
  -h, --help          Show this help

First installation:
  sudo ./install.sh

The first installation copies the package, asks for the local SMTP and Cloud Mail
settings, writes INSTALL_DIR/config.json, validates it, checks upstream connectivity,
builds the image, starts the service, and waits for a healthy Docker container.

Non-interactive variables:
  CLOUD_MAIL_LISTEN_HOST (default: 0.0.0.0)
  CLOUD_MAIL_LISTEN_PORT (default: 2525)
  CLOUD_MAIL_SMTP_USER
  CLOUD_MAIL_SMTP_PASSWORD
  CLOUD_MAIL_MAX_MESSAGE_SIZE (default: 10485760)
  CLOUD_MAIL_UPSTREAM_URL
  CLOUD_MAIL_UPSTREAM_HEALTH_URL
  CLOUD_MAIL_UPSTREAM_USER
  CLOUD_MAIL_UPSTREAM_API_KEY
  CLOUD_MAIL_UPSTREAM_TIMEOUT_MS (default: 15000)
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

require_value() {
  [ -n "$2" ] || die "$1 must not be empty"
  case "$2" in
    *$'\n'*|*$'\r'*|*$'\t'*) die "$1 must be a single line without control characters" ;;
  esac
}

json_escape() {
  # Installer input is single-line text. Escape the JSON characters we accept.
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

prompt_value() {
  local label="$1" default="$2" value
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$label" "$default" >&2
  else
    printf '%s: ' "$label" >&2
  fi
  IFS= read -r value || true
  printf '%s' "${value:-$default}"
}

prompt_secret() {
  local label="$1" value
  printf '%s: ' "$label" >&2
  IFS= read -r -s value || true
  printf '\n' >&2
  printf '%s' "$value"
}

write_config_interactive() {
  local output="$1"
  local listen_host listen_port smtp_user smtp_password max_message_size
  local upstream_url upstream_health_url upstream_user upstream_api_key timeout_ms
  local temporary

  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    listen_host="${CLOUD_MAIL_LISTEN_HOST:-0.0.0.0}"
    listen_port="${CLOUD_MAIL_LISTEN_PORT:-2525}"
    smtp_user="${CLOUD_MAIL_SMTP_USER:-}"
    smtp_password="${CLOUD_MAIL_SMTP_PASSWORD:-}"
    max_message_size="${CLOUD_MAIL_MAX_MESSAGE_SIZE:-10485760}"
    upstream_url="${CLOUD_MAIL_UPSTREAM_URL:-}"
    upstream_health_url="${CLOUD_MAIL_UPSTREAM_HEALTH_URL:-}"
    upstream_user="${CLOUD_MAIL_UPSTREAM_USER:-}"
    upstream_api_key="${CLOUD_MAIL_UPSTREAM_API_KEY:-}"
    timeout_ms="${CLOUD_MAIL_UPSTREAM_TIMEOUT_MS:-15000}"
  else
    printf '\nCLOUD-MAIL SMTP-to-HTTP Gateway configuration\n' >&2
    printf 'Press Enter to accept a value shown in [brackets]. Secrets are hidden.\n\n' >&2
    listen_host="$(prompt_value 'SMTP listen host' '0.0.0.0')"
    listen_port="$(prompt_value 'SMTP listen port' '2525')"
    smtp_user="$(prompt_value 'Local SMTP username' 'legacy-app')"
    smtp_password="$(prompt_secret 'Local SMTP password')"
    max_message_size="$(prompt_value 'Maximum message size in bytes' '10485760')"
    upstream_url="$(prompt_value 'Cloud Mail send URL' 'https://mail.example.com/api/smtp/send')"
    upstream_health_url="$(prompt_value 'Cloud Mail health URL' 'https://mail.example.com/api/smtp/health')"
    upstream_user="$(prompt_value 'Cloud Mail SMTP HTTP username' 'my-app')"
    upstream_api_key="$(prompt_secret 'Cloud Mail SMTP API key')"
    timeout_ms="$(prompt_value 'Cloud Mail request timeout in milliseconds' '15000')"
  fi

  require_value 'smtp username' "$smtp_user"
  require_value 'smtp password' "$smtp_password"
  require_value 'upstream URL' "$upstream_url"
  require_value 'upstream health URL' "$upstream_health_url"
  require_value 'upstream username' "$upstream_user"
  require_value 'upstream API key' "$upstream_api_key"

  case "$listen_port" in *[!0-9]*|'') die 'listen port must be an integer' ;; esac
  case "$max_message_size" in *[!0-9]*|'') die 'maximum message size must be an integer' ;; esac
  case "$timeout_ms" in *[!0-9]*|'') die 'upstream timeout must be an integer' ;; esac

  temporary="${output}.tmp.$$"
  umask 077
  cat > "$temporary" <<JSON
{
  "listen": {
    "host": "$(json_escape "$listen_host")",
    "port": $listen_port
  },
  "smtp": {
    "user": "$(json_escape "$smtp_user")",
    "password": "$(json_escape "$smtp_password")",
    "maxMessageSize": $max_message_size
  },
  "upstream": {
    "url": "$(json_escape "$upstream_url")",
    "healthUrl": "$(json_escape "$upstream_health_url")",
    "user": "$(json_escape "$upstream_user")",
    "apiKey": "$(json_escape "$upstream_api_key")",
    "timeoutMs": $timeout_ms
  }
}
JSON
  mv -f -- "$temporary" "$output"
  printf 'Configuration written to %s\n' "$output" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)
      [ "$#" -ge 2 ] || die '--dir requires a directory'
      INSTALL_DIR="$2"
      shift 2
      ;;
    --config)
      [ "$#" -ge 2 ] || die '--config requires a file'
      CONFIG_SOURCE="$2"
      shift 2
      ;;
    --reconfigure)
      RECONFIGURE=1
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1 (use --help for usage)"
      ;;
  esac
done

[ "$(uname -s)" = 'Linux' ] || die 'This installer supports Linux only'
[ "$(id -u)" -eq 0 ] || die 'Run this installer as root (for example: sudo ./install.sh)'

[ "$NON_INTERACTIVE" -eq 0 ] || [ -z "$CONFIG_SOURCE" ] || die '--config and --non-interactive cannot be used together'
[ "$RECONFIGURE" -eq 0 ] || [ -z "$CONFIG_SOURCE" ] || die '--config and --reconfigure cannot be used together'

for required in Dockerfile docker-compose.yml package.json config.example.json src; do
  [ -e "$SCRIPT_DIR/$required" ] || die "installer package is incomplete: missing $required"
done

command -v docker >/dev/null 2>&1 || die 'Docker Engine is not installed or docker is not in PATH'
docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required (docker compose)'

case "$INSTALL_DIR" in
  /*) ;;
  *) die 'installation directory must be an absolute path' ;;
esac

if [ -e "$INSTALL_DIR" ] && [ ! -d "$INSTALL_DIR" ]; then
  die "installation path exists but is not a directory: $INSTALL_DIR"
fi

info "Preparing installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
  for item in Dockerfile docker-compose.yml package.json .dockerignore config.example.json README.md install.sh src; do
    [ -e "$SCRIPT_DIR/$item" ] || continue
    cp -a "$SCRIPT_DIR/$item" "$INSTALL_DIR/"
  done
fi

if [ -n "$CONFIG_SOURCE" ]; then
  [ -f "$CONFIG_SOURCE" ] || die "config file not found: $CONFIG_SOURCE"
  if [ -f "$INSTALL_DIR/config.json" ] && [ "$ASSUME_YES" -ne 1 ]; then
    printf 'config.json already exists in %s. Replace it? [y/N] ' "$INSTALL_DIR"
    read -r answer
    case "$answer" in
      y|Y|yes|YES) ;;
      *) die 'configuration replacement cancelled' ;;
    esac
  fi
  cp -f -- "$CONFIG_SOURCE" "$INSTALL_DIR/config.json"
elif [ "$RECONFIGURE" -eq 1 ] || [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -f "$INSTALL_DIR/config.json" ]; then
  if [ -f "$INSTALL_DIR/config.json" ] && [ "$ASSUME_YES" -ne 1 ]; then
    printf 'Existing config.json will be replaced by the configuration wizard. Continue? [y/N] ' >&2
    read -r answer
    case "$answer" in
      y|Y|yes|YES) ;;
      *) die 'configuration update cancelled' ;;
    esac
  fi
  if [ -f "$INSTALL_DIR/config.json" ]; then
    cp -f -- "$INSTALL_DIR/config.json" "$INSTALL_DIR/config.json.bak.$(date +%Y%m%d%H%M%S)"
  fi
  write_config_interactive "$INSTALL_DIR/config.json"
fi

[ -f "$INSTALL_DIR/config.json" ] || die "configuration file was not created: $INSTALL_DIR/config.json"
chown root:root "$INSTALL_DIR/config.json"
chmod 640 "$INSTALL_DIR/config.json"
cd "$INSTALL_DIR"

info 'Validating Docker Compose configuration'
docker compose config >/dev/null || die 'docker compose config failed'

info 'Building the gateway image'
docker compose build smtp-gateway || die 'Docker image build failed'

info 'Validating gateway configuration'
docker compose run --rm --no-deps smtp-gateway node src/cli.js validate --config /app/config.json || die 'gateway configuration validation failed'

info 'Checking Cloud Mail upstream connectivity'
docker compose run --rm --no-deps smtp-gateway node src/cli.js test --config /app/config.json || die 'Cloud Mail upstream health check failed; the gateway was not started'

info 'Starting the gateway'
docker compose up -d --force-recreate smtp-gateway || die 'Docker Compose could not start the gateway'

container_id="$(docker compose ps -q smtp-gateway)"
[ -n "$container_id" ] || die 'gateway container was not created'

info 'Waiting for Docker healthcheck'
for attempt in $(seq 1 60); do
  status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$container_id" 2>/dev/null || true)"
  case "$status" in
    healthy)
      printf '\nInstallation completed successfully.\n'
      printf 'Install directory: %s\n' "$INSTALL_DIR"
      printf 'SMTP endpoint: %s\n' "$(docker compose port smtp-gateway 2525 || true)"
      printf 'Logs: cd %s && docker compose logs -f smtp-gateway\n' "$INSTALL_DIR"
      exit 0
      ;;
    unhealthy|no-healthcheck|exited|dead)
      docker compose logs --tail=100 smtp-gateway >&2 || true
      die "gateway Docker healthcheck failed (status: $status)"
      ;;
    *)
      sleep 2
      ;;
  esac
done

docker compose logs --tail=100 smtp-gateway >&2 || true
die 'timed out waiting for the gateway Docker healthcheck'
