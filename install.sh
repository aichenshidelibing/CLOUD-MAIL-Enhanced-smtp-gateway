#!/usr/bin/env bash
set -Eeuo pipefail

# Cloud Mail SMTP-to-HTTP Gateway installer.
# Linux + Docker Compose only. It never installs Node.js or systemd services.

INSTALL_DIR="/opt/cloud-mail-smtp-gateway"
CONFIG_SOURCE=""
ASSUME_YES=0
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

usage() {
  cat <<'USAGE'
Cloud Mail SMTP-to-HTTP Gateway installer (Linux + Docker Compose only)

Usage:
  sudo ./install.sh [options]

Options:
  --dir DIR       Installation directory (default: /opt/cloud-mail-smtp-gateway)
  --config FILE   Copy FILE as the installation config.json
  --yes           Do not ask before replacing a supplied config.json
  -h, --help      Show this help

The installer verifies Linux/Docker/Compose, copies files, validates the
configuration, builds the image, tests Cloud Mail upstream connectivity, starts
the service only after that test succeeds, and waits for Docker healthcheck.

If no config.json exists yet, a template is created and the installer stops.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '\n==> %s\n' "$*"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)
      [ "$#" -ge 2 ] || die "--dir requires a directory"
      INSTALL_DIR="$2"
      shift 2
      ;;
    --config)
      [ "$#" -ge 2 ] || die "--config requires a file"
      CONFIG_SOURCE="$2"
      shift 2
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

[ "$(uname -s)" = "Linux" ] || die "This installer supports Linux only"
[ "$(id -u)" -eq 0 ] || die "Run this installer as root (for example: sudo ./install.sh)"

for required in Dockerfile docker-compose.yml package.json config.example.json src; do
  [ -e "$SCRIPT_DIR/$required" ] || die "installer package is incomplete: missing $required"
done

command -v docker >/dev/null 2>&1 || die "Docker Engine is not installed or docker is not in PATH"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required (docker compose)"

case "$INSTALL_DIR" in
  /*) ;;
  *) die "installation directory must be an absolute path" ;;
esac

if [ -e "$INSTALL_DIR" ] && [ ! -d "$INSTALL_DIR" ]; then
  die "installation path exists but is not a directory: $INSTALL_DIR"
fi

info "Preparing installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
  for item in Dockerfile docker-compose.yml package.json .dockerignore config.example.json README.md src; do
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
      *) die "configuration replacement cancelled" ;;
    esac
  fi
  cp -f -- "$CONFIG_SOURCE" "$INSTALL_DIR/config.json"
elif [ ! -f "$INSTALL_DIR/config.json" ]; then
  cp -f -- "$INSTALL_DIR/config.example.json" "$INSTALL_DIR/config.json"
  chown root:root "$INSTALL_DIR/config.json"
  chmod 640 "$INSTALL_DIR/config.json"
  printf '\nA template was created at:\n  %s/config.json\n\nEdit it with real Cloud Mail credentials and run this installer again.\n' "$INSTALL_DIR" >&2
  exit 2
fi

chown root:root "$INSTALL_DIR/config.json"
chmod 640 "$INSTALL_DIR/config.json"
cd "$INSTALL_DIR"

info "Validating Docker Compose configuration"
docker compose config >/dev/null || die "docker compose config failed"

info "Building the gateway image"
docker compose build smtp-gateway || die "Docker image build failed"

info "Validating gateway configuration"
docker compose run --rm --no-deps smtp-gateway node src/cli.js validate --config /app/config.json || die "gateway configuration validation failed"

info "Checking Cloud Mail upstream connectivity"
docker compose run --rm --no-deps smtp-gateway node src/cli.js test --config /app/config.json || die "Cloud Mail upstream health check failed; the gateway was not started"

info "Starting the gateway"
docker compose up -d --force-recreate smtp-gateway || die "Docker Compose could not start the gateway"

container_id="$(docker compose ps -q smtp-gateway)"
[ -n "$container_id" ] || die "gateway container was not created"

info "Waiting for Docker healthcheck"
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
die "timed out waiting for the gateway Docker healthcheck"

