#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/opt/cloud-mail-smtp-gateway"
CONFIG_SOURCE=""
ASSUME_YES=0
RECONFIGURE=0
NON_INTERACTIVE=0
UI_LANGUAGE="${CLOUD_MAIL_LANGUAGE:-zh}"
LANGUAGE_EXPLICIT=0
TLS_HOSTNAME="${CLOUD_MAIL_SMTP_TLS_HOSTNAME:-smtp-gateway}"
TLS_CERT_SOURCE="${CLOUD_MAIL_SMTP_TLS_CERT_FILE:-}"
TLS_KEY_SOURCE="${CLOUD_MAIL_SMTP_TLS_KEY_FILE:-}"
TLS_CERT_DAYS="${CLOUD_MAIL_SMTP_TLS_DAYS:-825}"
TLS_REGENERATE="${CLOUD_MAIL_SMTP_TLS_REGENERATE:-0}"
[ -n "${CLOUD_MAIL_LANGUAGE:-}" ] && LANGUAGE_EXPLICIT=1
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

text() {
  case "${UI_LANGUAGE}:$1" in
    zh:error) printf '错误' ;; en:error) printf 'ERROR' ;;
    zh:language_prompt) printf '语言 / Language [zh/中文]' ;; en:language_prompt) printf 'Language / 语言 [en/English]' ;;
    zh:language_invalid) printf '语言必须是 zh 或 en' ;; en:language_invalid) printf 'Language must be zh or en' ;;
    zh:config_title) printf 'CLOUD-MAIL SMTP-to-HTTP 网关配置' ;; en:config_title) printf 'CLOUD-MAIL SMTP-to-HTTP Gateway configuration' ;;
    zh:config_hint) printf '直接按回车接受方括号中的默认值。密码和 API Key 不会回显。' ;; en:config_hint) printf 'Press Enter to accept the value in brackets. Passwords and API keys are hidden.' ;;
    zh:listen_host) printf 'SMTP 监听地址（宿主机）' ;; en:listen_host) printf 'SMTP listen host (host machine)' ;;
    zh:listen_port) printf 'SMTP 监听端口（宿主机）' ;; en:listen_port) printf 'SMTP listen port (host machine)' ;;
    zh:max_size) printf '单封邮件大小上限（字节）' ;; en:max_size) printf 'Maximum message size in bytes' ;;
    zh:cloud_address) printf 'Cloud Mail 地址（根地址）' ;; en:cloud_address) printf 'Cloud Mail address (root URL)' ;;
    zh:cloud_user) printf 'Cloud Mail SMTP 用户名' ;; en:cloud_user) printf 'Cloud Mail SMTP username' ;;
    zh:cloud_key) printf 'Cloud Mail SMTP API Key' ;; en:cloud_key) printf 'Cloud Mail SMTP API key' ;;
    zh:timeout) printf 'Cloud Mail 请求超时时间（毫秒）' ;; en:timeout) printf 'Cloud Mail request timeout in milliseconds' ;;
    zh:credential_notice) printf '本地 SMTP 用户名和密码将自动使用上面的 Cloud Mail SMTP 用户名和 API Key。' ;; en:credential_notice) printf 'The local SMTP username and password will automatically use the Cloud Mail SMTP username and API key above.' ;;
    zh:config_written) printf '配置已写入' ;; en:config_written) printf 'Configuration written to' ;;
    zh:preparing) printf '准备安装目录' ;; en:preparing) printf 'Preparing installation directory' ;;
    zh:tls_prepare) printf '准备 SMTP STARTTLS 证书' ;; en:tls_prepare) printf 'Preparing SMTP STARTTLS certificate' ;;
    zh:tls_generated) printf '已生成自签名 STARTTLS 证书（仅用于内网/测试；生产环境建议使用受信任 CA 证书）' ;; en:tls_generated) printf 'Generated a self-signed STARTTLS certificate (for internal/testing use; use a trusted CA certificate in production)' ;;
    zh:tls_existing) printf '保留现有 STARTTLS 证书' ;; en:tls_existing) printf 'Keeping existing STARTTLS certificate' ;;
    zh:preflight) printf '在创建 Docker 容器前检查 Cloud Mail 连通性' ;; en:preflight) printf 'Checking Cloud Mail connectivity before creating a Docker container' ;;
    zh:validate_compose) printf '校验 Docker Compose 配置' ;; en:validate_compose) printf 'Validating Docker Compose configuration' ;;
    zh:build_image) printf '构建网关镜像' ;; en:build_image) printf 'Building the gateway image' ;;
    zh:validate_gateway) printf '校验网关配置' ;; en:validate_gateway) printf 'Validating gateway configuration' ;;
    zh:starting) printf '启动网关' ;; en:starting) printf 'Starting the gateway' ;;
    zh:waiting_health) printf '等待 Docker 健康检查' ;; en:waiting_health) printf 'Waiting for Docker healthcheck' ;;
    zh:tls_test) printf '验证 SMTP STARTTLS 和认证' ;; en:tls_test) printf 'Verifying SMTP STARTTLS and authentication' ;;
    zh:tls_failed) printf 'SMTP STARTTLS 验证失败，网关不会被视为安装完成' ;; en:tls_failed) printf 'SMTP STARTTLS verification failed; installation is not considered complete' ;;
    zh:success) printf '安装成功。' ;; en:success) printf 'Installation completed successfully.' ;;
    zh:install_dir) printf '安装目录' ;; en:install_dir) printf 'Install directory' ;;
    zh:smtp_endpoint) printf 'SMTP 地址' ;; en:smtp_endpoint) printf 'SMTP endpoint' ;;
    zh:logs) printf '日志' ;; en:logs) printf 'Logs' ;;
    zh:network_hint) printf 'Docker 网络：业务容器应使用 smtp-gateway:2525，不要使用 127.0.0.1。' ;; en:network_hint) printf 'Docker network: app containers should use smtp-gateway:2525, not 127.0.0.1.' ;;
    zh:replace_config) printf 'config.json 已存在于 %s。是否替换？[y/N] ' ;; en:replace_config) printf 'config.json already exists in %s. Replace it? [y/N] ' ;;
    zh:replace_wizard) printf '现有 config.json 将由配置向导替换。是否继续？[y/N] ' ;; en:replace_wizard) printf 'Existing config.json will be replaced by the configuration wizard. Continue? [y/N] ' ;;
    zh:cancelled) printf '配置替换已取消' ;; en:cancelled) printf 'configuration replacement cancelled' ;;
    zh:not_started) printf 'Cloud Mail 健康检查失败，网关未启动' ;; en:not_started) printf 'Cloud Mail upstream health check failed; the gateway was not started' ;;
    *) printf '%s' "$1" ;;
  esac
}

usage() {
  cat <<'USAGE'
CLOUD-MAIL SMTP-to-HTTP Gateway installer (Linux + Docker Compose)

Usage:
  sudo ./install.sh [options]

Options:
  --dir DIR             Installation directory (default: /opt/cloud-mail-smtp-gateway)
  --config FILE         Copy FILE as installation config.json
  --reconfigure         Create config.json through the configuration wizard
  --non-interactive     Do not prompt; read configuration from environment variables
  --language LANG       Interface language: zh or en (default: zh)
  --lang LANG           Alias for --language
  --yes                 Do not ask before replacing an existing config.json
  -h, --help            Show this help

Environment variables for --non-interactive:
  CLOUD_MAIL_LANGUAGE (zh or en)
  CLOUD_MAIL_LISTEN_HOST (default: 0.0.0.0)
  CLOUD_MAIL_LISTEN_PORT (default: 2525)
  CLOUD_MAIL_ADDRESS (for example: mail.example.com or https://mail.example.com)
  CLOUD_MAIL_UPSTREAM_USER
  CLOUD_MAIL_UPSTREAM_API_KEY
  CLOUD_MAIL_MAX_MESSAGE_SIZE (default: 10485760)
  CLOUD_MAIL_UPSTREAM_TIMEOUT_MS (default: 15000)
  CLOUD_MAIL_SMTP_TLS_HOSTNAME (default: smtp-gateway; comma-separated DNS names/IPs)
  CLOUD_MAIL_SMTP_TLS_CERT_FILE (optional existing certificate to copy)
  CLOUD_MAIL_SMTP_TLS_KEY_FILE (optional existing private key to copy)
  CLOUD_MAIL_SMTP_TLS_DAYS (default: 825 for generated self-signed certificate)

Legacy compatibility variables:
  CLOUD_MAIL_UPSTREAM_URL
  CLOUD_MAIL_UPSTREAM_HEALTH_URL
  CLOUD_MAIL_SMTP_USER
  CLOUD_MAIL_SMTP_PASSWORD
USAGE
}

die() { printf '%s: %s\n' "$(text error)" "$*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }

set_language() { case "$1" in zh|en) UI_LANGUAGE="$1" ;; *) die "$(text language_invalid): $1" ;; esac; }
select_language() {
  local value
  if [ "$LANGUAGE_EXPLICIT" -eq 1 ] || [ "$NON_INTERACTIVE" -eq 1 ]; then set_language "$UI_LANGUAGE"; return; fi
  printf '%s: ' "$(text language_prompt)" >&2; IFS= read -r value || true; set_language "${value:-zh}"
}
require_value() {
  [ -n "$2" ] || die "$1 must not be empty"
  case "$2" in *$'\n'*|*$'\r'*|*$'\t'*) die "$1 must be a single line without control characters" ;; esac
}
normalize_cloud_mail_address() {
  local value="$1"; value="$(printf '%s' "$value" | sed 's/[[:space:]]//g; s#/*$##')"
  case "$value" in http://*|https://*) ;; *) value="https://$value" ;; esac
  printf '%s' "$value"
}
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
json_string_values() { local file="$1" key="$2"; grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/'; }
json_string_value() { local file="$1" key="$2" mode="${3:-first}" values; values="$(json_string_values "$file" "$key")"; if [ "$mode" = last ]; then printf '%s\n' "$values" | tail -n 1; else printf '%s\n' "$values" | head -n 1; fi; }
json_number_value() { local file="$1" key="$2"; grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*[0-9]+" "$file" | sed -E 's/.*:[[:space:]]*([0-9]+)/\1/' | head -n 1; }

write_compose_env() {
  local config_file="$1" env_file="$2" bind_host bind_port
  bind_host="$(json_string_value "$config_file" host)"; bind_port="$(json_number_value "$config_file" port)"
  [ -n "$bind_host" ] || die 'listen.host could not be read from config.json'; [ -n "$bind_port" ] || die 'listen.port could not be read from config.json'
  case "$bind_port" in *[!0-9]*|'') die 'listen.port must be an integer' ;; esac
  umask 077; cat > "$env_file" <<ENV
SMTP_BIND_HOST=$bind_host
SMTP_PORT=$bind_port
ENV
  chmod 600 "$env_file"
}

valid_ipv4() {
  local ip="$1" octet
  case "$ip" in *[!0-9.]*|.*|*.|*..*) return 1 ;; esac
  IFS='.' read -r -a octets <<< "$ip"
  [ "${#octets[@]}" -eq 4 ] || return 1
  for octet in "${octets[@]}"; do
    case "$octet" in ''|*[!0-9]*) return 1 ;; esac
    [ "$octet" -le 255 ] 2>/dev/null || return 1
  done
}

append_tls_san() {
  local current="$1" candidate="$2"
  case ",$current," in
    *",$candidate,"*) printf '%s' "$current" ;;
    *) [ -n "$current" ] && current="$current,"; printf '%s%s' "$current" "$candidate" ;;
  esac
}

collect_tls_sans() {
  local san_list='DNS:smtp-gateway,DNS:localhost,IP:127.0.0.1' ip public_ip name endpoint

  for ip in $(hostname -I 2>/dev/null || true); do
    valid_ipv4 "$ip" || continue
    case "$ip" in 127.*) continue ;; esac
    san_list="$(append_tls_san "$san_list" "IP:$ip")"
  done
  if command -v ip >/dev/null 2>&1; then
    while IFS= read -r ip; do
      ip="${ip%%/*}"
      valid_ipv4 "$ip" || continue
      case "$ip" in 127.*) continue ;; esac
      san_list="$(append_tls_san "$san_list" "IP:$ip")"
    done < <(ip -4 -o addr show 2>/dev/null | awk '{print $4}')
  fi

  # hostname -I usually does not expose the public/NAT address. Try short-timeout services;
  # if outbound access is unavailable, installation continues with local addresses.
  if command -v curl >/dev/null 2>&1; then
    for endpoint in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
      public_ip="$(curl -4 --silent --show-error --connect-timeout 2 --max-time 4 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
      if valid_ipv4 "$public_ip"; then
        san_list="$(append_tls_san "$san_list" "IP:$public_ip")"
        break
      fi
    done
  fi

  IFS=',' read -r -a tls_names <<< "$TLS_HOSTNAME"
  for name in "${tls_names[@]}"; do
    name="$(printf '%s' "$name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$name" ] || continue
    if valid_ipv4 "$name"; then
      san_list="$(append_tls_san "$san_list" "IP:$name")"
    else
      case "$name" in *[!A-Za-z0-9._-]*) die 'CLOUD_MAIL_SMTP_TLS_HOSTNAME contains an invalid DNS name or IPv4 address' ;; esac
      san_list="$(append_tls_san "$san_list" "DNS:$name")"
    fi
  done
  printf '%s' "$san_list"
}

certificate_has_sans() {
  local cert_file="$1" required_sans="$2" san output value
  output="$(openssl x509 -in "$cert_file" -noout -ext subjectAltName 2>/dev/null || true)"
  [ -n "$output" ] || return 1
  IFS=',' read -r -a required_sans_array <<< "$required_sans"
  for san in "${required_sans_array[@]}"; do
    case "$san" in
      DNS:*) value="${san#DNS:}"; printf '%s' "$output" | grep -Fq "DNS:$value" || return 1 ;;
      IP:*) value="${san#IP:}"; printf '%s' "$output" | grep -Eq "IP( Address)?:[[:space:]]*$value([,[:space:]]|$)" || return 1 ;;
      *) return 1 ;;
    esac
  done
}

prepare_tls_material() {
  local tls_dir="$INSTALL_DIR/tls" cert_file="$INSTALL_DIR/tls/server.crt" key_file="$INSTALL_DIR/tls/server.key"
  local san_list tmp_conf tmp_key tmp_cert name backup_stamp
  info "$(text tls_prepare)"
  mkdir -p "$tls_dir"; chmod 750 "$tls_dir"
  if [ -n "$TLS_CERT_SOURCE" ] || [ -n "$TLS_KEY_SOURCE" ]; then
    [ -n "$TLS_CERT_SOURCE" ] && [ -n "$TLS_KEY_SOURCE" ] || die 'both TLS certificate and private key source files are required'
    [ -f "$TLS_CERT_SOURCE" ] || die "TLS certificate not found: $TLS_CERT_SOURCE"
    [ -f "$TLS_KEY_SOURCE" ] || die "TLS private key not found: $TLS_KEY_SOURCE"
    cp -f -- "$TLS_CERT_SOURCE" "$cert_file"; cp -f -- "$TLS_KEY_SOURCE" "$key_file"
    info "$(text tls_existing): $cert_file"
    chown root:root "$cert_file" "$key_file"; chmod 640 "$cert_file" "$key_file"
    return
  fi

  command -v openssl >/dev/null 2>&1 || die 'openssl is required to generate or inspect the default STARTTLS certificate'
  case "$TLS_CERT_DAYS" in *[!0-9]*|'') die 'CLOUD_MAIL_SMTP_TLS_DAYS must be a positive integer' ;; esac
  [ "$TLS_CERT_DAYS" -ge 1 ] || die 'CLOUD_MAIL_SMTP_TLS_DAYS must be at least 1'
  case "$TLS_REGENERATE" in 0|1) ;; *) die 'CLOUD_MAIL_SMTP_TLS_REGENERATE must be 0 or 1' ;; esac

  san_list="$(collect_tls_sans)"
  if [ -s "$cert_file" ] && [ -s "$key_file" ] && [ "$TLS_REGENERATE" -eq 0 ] && certificate_has_sans "$cert_file" "$san_list"; then
    info "$(text tls_existing): $cert_file"
  else
    if [ -s "$cert_file" ] || [ -s "$key_file" ]; then
      backup_stamp="$(date +%Y%m%d%H%M%S)"
      [ -s "$cert_file" ] && cp -f -- "$cert_file" "$cert_file.bak.$backup_stamp"
      [ -s "$key_file" ] && cp -f -- "$key_file" "$key_file.bak.$backup_stamp"
    fi
    tmp_conf="$(mktemp)"; tmp_key="$key_file.tmp.$$"; tmp_cert="$cert_file.tmp.$$"
    IFS=',' read -r -a tls_names <<< "$TLS_HOSTNAME"
    name="${tls_names[0]:-smtp-gateway}"
    cat > "$tmp_conf" <<OPENSSL_CONF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $name

[v3_req]
subjectAltName = $san_list
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
OPENSSL_CONF
    if ! openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days "$TLS_CERT_DAYS" -keyout "$tmp_key" -out "$tmp_cert" -config "$tmp_conf" >/dev/null 2>&1; then
      rm -f -- "$tmp_conf" "$tmp_key" "$tmp_cert"
      die 'failed to generate the STARTTLS certificate'
    fi
    mv -f -- "$tmp_key" "$key_file"; mv -f -- "$tmp_cert" "$cert_file"; rm -f -- "$tmp_conf"
    info "$(text tls_generated): $cert_file"
  fi
  chown root:root "$cert_file" "$key_file"; chmod 640 "$cert_file" "$key_file"
}

check_upstream_host() {
  local config_file="$1" response_file="$2" upstream_health_url upstream_user upstream_api_key timeout_ms timeout_seconds http_code
  upstream_health_url="$(json_string_value "$config_file" healthUrl)"; upstream_user="$(json_string_value "$config_file" user last)"; upstream_api_key="$(json_string_value "$config_file" apiKey)"; timeout_ms="$(json_number_value "$config_file" timeoutMs)"
  require_value 'upstream health URL' "$upstream_health_url"; require_value 'Cloud Mail SMTP username' "$upstream_user"; require_value 'Cloud Mail SMTP API key' "$upstream_api_key"
  case "$timeout_ms" in *[!0-9]*|'') timeout_ms=15000 ;; esac; timeout_seconds=$(( (timeout_ms + 999) / 1000 )); [ "$timeout_seconds" -ge 1 ] || timeout_seconds=1
  command -v curl >/dev/null 2>&1 || die 'curl is required for the pre-container Cloud Mail health check'
  http_code="$(curl --silent --show-error --location --connect-timeout 10 --max-time "$timeout_seconds" --user "$upstream_user:$upstream_api_key" --output "$response_file" --write-out '%{http_code}' "$upstream_health_url")" || die 'Cloud Mail upstream is not reachable'
  case "$http_code" in 2??) ;; *) die "Cloud Mail upstream health check returned HTTP $http_code" ;; esac
  grep -Eq '"ok"[[:space:]]*:[[:space:]]*true' "$response_file" || die 'Cloud Mail upstream health check did not report ok=true'
}

prompt_value() { local key="$1" default="$2" value; if [ -n "$default" ]; then printf '%s [%s]: ' "$(text "$key")" "$default" >&2; else printf '%s: ' "$(text "$key")" >&2; fi; IFS= read -r value || true; printf '%s' "${value:-$default}"; }
prompt_secret() { local key="$1" value; printf '%s: ' "$(text "$key")" >&2; IFS= read -r -s value || true; printf '\n' >&2; printf '%s' "$value"; }

write_config_interactive() {
  local output="$1" listen_host listen_port smtp_user smtp_password max_message_size cloud_mail_address upstream_url upstream_health_url upstream_user upstream_api_key timeout_ms temporary
  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    listen_host="${CLOUD_MAIL_LISTEN_HOST:-0.0.0.0}"; listen_port="${CLOUD_MAIL_LISTEN_PORT:-2525}"; max_message_size="${CLOUD_MAIL_MAX_MESSAGE_SIZE:-10485760}"
    upstream_user="${CLOUD_MAIL_UPSTREAM_USER:-${CLOUD_MAIL_SMTP_USER:-}}"; upstream_api_key="${CLOUD_MAIL_UPSTREAM_API_KEY:-${CLOUD_MAIL_SMTP_PASSWORD:-}}"
    if [ -n "${CLOUD_MAIL_ADDRESS:-}" ]; then cloud_mail_address="$(normalize_cloud_mail_address "$CLOUD_MAIL_ADDRESS")"; upstream_url="${cloud_mail_address}/api/smtp/send"; upstream_health_url="${cloud_mail_address}/api/smtp/health"; else upstream_url="${CLOUD_MAIL_UPSTREAM_URL:-}"; upstream_health_url="${CLOUD_MAIL_UPSTREAM_HEALTH_URL:-}"; fi
    timeout_ms="${CLOUD_MAIL_UPSTREAM_TIMEOUT_MS:-15000}"
  else
    printf '\n%s\n' "$(text config_title)" >&2; printf '%s\n\n' "$(text config_hint)" >&2
    listen_host="$(prompt_value listen_host '0.0.0.0')"; listen_port="$(prompt_value listen_port '2525')"; max_message_size="$(prompt_value max_size '10485760')"
    cloud_mail_address="$(prompt_value cloud_address 'mail.example.com')"; cloud_mail_address="$(normalize_cloud_mail_address "$cloud_mail_address")"; upstream_url="${cloud_mail_address}/api/smtp/send"; upstream_health_url="${cloud_mail_address}/api/smtp/health"
    upstream_user="$(prompt_value cloud_user 'my-app')"; upstream_api_key="$(prompt_secret cloud_key)"; timeout_ms="$(prompt_value timeout '15000')"; printf '%s\n\n' "$(text credential_notice)" >&2
  fi
  require_value 'Cloud Mail SMTP username' "$upstream_user"; require_value 'Cloud Mail SMTP API key' "$upstream_api_key"; require_value 'upstream URL' "$upstream_url"; require_value 'upstream health URL' "$upstream_health_url"
  smtp_user="$upstream_user"; smtp_password="$upstream_api_key"
  case "$listen_port" in *[!0-9]*|'') die 'listen port must be an integer' ;; esac; case "$max_message_size" in *[!0-9]*|'') die 'maximum message size must be an integer' ;; esac; case "$timeout_ms" in *[!0-9]*|'') die 'upstream timeout must be an integer' ;; esac
  [ "$listen_port" -ge 1 ] && [ "$listen_port" -le 65535 ] || die 'listen port must be 1-65535'
  temporary="${output}.tmp.$$"; umask 077
  cat > "$temporary" <<JSON
{
  "listen": { "host": "$(json_escape "$listen_host")", "port": $listen_port, "containerHost": "0.0.0.0", "containerPort": 2525 },
  "smtp": {
    "user": "$(json_escape "$smtp_user")",
    "password": "$(json_escape "$smtp_password")",
    "maxMessageSize": $max_message_size,
    "tls": { "enabled": true, "required": true, "certFile": "/app/tls/server.crt", "keyFile": "/app/tls/server.key", "minVersion": "TLSv1.2", "serverName": "$(json_escape "${TLS_HOSTNAME%%,*}")" }
  },
  "upstream": { "url": "$(json_escape "$upstream_url")", "healthUrl": "$(json_escape "$upstream_health_url")", "user": "$(json_escape "$upstream_user")", "apiKey": "$(json_escape "$upstream_api_key")", "timeoutMs": $timeout_ms }
}
JSON
  mv -f -- "$temporary" "$output"; printf '%s %s\n' "$(text config_written)" "$output" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) [ "$#" -ge 2 ] || die '--dir requires a directory'; INSTALL_DIR="$2"; shift 2 ;;
    --config) [ "$#" -ge 2 ] || die '--config requires a file'; CONFIG_SOURCE="$2"; shift 2 ;;
    --reconfigure) RECONFIGURE=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --language|--lang) [ "$#" -ge 2 ] || die '--language requires zh or en'; UI_LANGUAGE="$2"; LANGUAGE_EXPLICIT=1; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (use --help for usage)" ;;
  esac
done

set_language "$UI_LANGUAGE"
[ "$NON_INTERACTIVE" -eq 0 ] || [ -z "$CONFIG_SOURCE" ] || die '--config and --non-interactive cannot be used together'
[ "$RECONFIGURE" -eq 0 ] || [ -z "$CONFIG_SOURCE" ] || die '--config and --reconfigure cannot be used together'
[ "$(uname -s)" = 'Linux' ] || die 'This installer supports Linux only'
[ "$(id -u)" -eq 0 ] || die 'Run this installer as root (for example: sudo ./install.sh)'
for required in Dockerfile docker-compose.yml package.json config.example.json src; do [ -e "$SCRIPT_DIR/$required" ] || die "installer package is incomplete: missing $required"; done
command -v docker >/dev/null 2>&1 || die 'Docker Engine is not installed or docker is not in PATH'
docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required (docker compose)'
case "$INSTALL_DIR" in /*) ;; *) die 'installation directory must be an absolute path' ;; esac
if [ -e "$INSTALL_DIR" ] && [ ! -d "$INSTALL_DIR" ]; then die "installation path exists but is not a directory: $INSTALL_DIR"; fi

if [ "$RECONFIGURE" -eq 1 ] || [ ! -f "$INSTALL_DIR/config.json" ]; then select_language; fi
info "$(text preparing): $INSTALL_DIR"; mkdir -p "$INSTALL_DIR"
if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
  for item in Dockerfile docker-compose.yml package.json .dockerignore .gitignore config.example.json README.md install.sh src; do [ -e "$SCRIPT_DIR/$item" ] || continue; cp -a "$SCRIPT_DIR/$item" "$INSTALL_DIR/"; done
fi
if [ -n "$CONFIG_SOURCE" ]; then
  [ -f "$CONFIG_SOURCE" ] || die "config file not found: $CONFIG_SOURCE"
  if [ -f "$INSTALL_DIR/config.json" ] && [ "$ASSUME_YES" -ne 1 ]; then printf "$(text replace_config)" "$INSTALL_DIR" >&2; read -r answer; case "$answer" in y|Y|yes|YES) ;; *) die "$(text cancelled)" ;; esac; fi
  cp -f -- "$CONFIG_SOURCE" "$INSTALL_DIR/config.json"
elif [ "$RECONFIGURE" -eq 1 ] || [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -f "$INSTALL_DIR/config.json" ]; then
  if [ -f "$INSTALL_DIR/config.json" ] && [ "$ASSUME_YES" -ne 1 ]; then printf '%s' "$(text replace_wizard)" >&2; read -r answer; case "$answer" in y|Y|yes|YES) ;; *) die "$(text cancelled)" ;; esac; fi
  if [ -f "$INSTALL_DIR/config.json" ]; then cp -f -- "$INSTALL_DIR/config.json" "$INSTALL_DIR/config.json.bak.$(date +%Y%m%d%H%M%S)"; fi
  write_config_interactive "$INSTALL_DIR/config.json"
fi
[ -f "$INSTALL_DIR/config.json" ] || die "configuration file was not created: $INSTALL_DIR/config.json"
prepare_tls_material
chown root:root "$INSTALL_DIR/config.json"; chmod 640 "$INSTALL_DIR/config.json"
write_compose_env "$INSTALL_DIR/config.json" "$INSTALL_DIR/.env"
cd "$INSTALL_DIR"
preflight_response="$(mktemp)"; trap 'rm -f -- "$preflight_response"' EXIT
info "$(text preflight)"; check_upstream_host "$INSTALL_DIR/config.json" "$preflight_response" || die "$(text not_started)"
if ! docker network inspect cloud-mail-smtp >/dev/null 2>&1; then info 'Creating shared Docker network: cloud-mail-smtp'; docker network create cloud-mail-smtp >/dev/null || die 'could not create Docker network cloud-mail-smtp'; fi
info "$(text validate_compose)"; docker compose config >/dev/null || die 'docker compose config failed'
info "$(text build_image)"; docker compose build smtp-gateway || die 'Docker image build failed'
info "$(text validate_gateway)"; docker compose run --rm --no-deps smtp-gateway node src/cli.js validate --config /app/config.json || die 'gateway configuration validation failed'
info "$(text starting)"; docker compose up -d --force-recreate smtp-gateway || die 'Docker Compose could not start the gateway'
container_id="$(docker compose ps -q smtp-gateway)"; [ -n "$container_id" ] || die 'gateway container was not created'
info "$(text waiting_health)"
for attempt in $(seq 1 60); do
  status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$container_id" 2>/dev/null || true)"
  case "$status" in
    healthy)
      info "$(text tls_test)"
      if ! docker compose exec -T smtp-gateway node src/cli.js smtp-test --config /app/config.json; then docker compose logs --tail=100 smtp-gateway >&2 || true; die "$(text tls_failed)"; fi
      printf '\n%s\n' "$(text success)"; printf '%s: %s\n' "$(text install_dir)" "$INSTALL_DIR"; printf '%s: %s\n' "$(text smtp_endpoint)" "$(docker compose port smtp-gateway 2525 || true)"; printf '%s: cd %s && docker compose logs -f smtp-gateway\n' "$(text logs)" "$INSTALL_DIR"; printf '%s\n' "$(text network_hint)"; exit 0 ;;
    unhealthy|no-healthcheck|exited|dead) docker compose logs --tail=100 smtp-gateway >&2 || true; die "gateway Docker healthcheck failed (status: $status)" ;;
    *) sleep 2 ;;
  esac
done
docker compose logs --tail=100 smtp-gateway >&2 || true
die 'timed out waiting for the gateway Docker healthcheck'