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
TLS_DOMAIN="${CLOUD_MAIL_SMTP_TLS_DOMAIN:-}"
LE_ENABLED="${CLOUD_MAIL_SMTP_LETSENCRYPT:-0}"
LE_EMAIL="${CLOUD_MAIL_SMTP_LETSENCRYPT_EMAIL:-}"
LE_STAGING="${CLOUD_MAIL_SMTP_LETSENCRYPT_STAGING:-0}"
LE_MODE="${CLOUD_MAIL_SMTP_LETSENCRYPT_MODE:-standalone}"
LE_WEBROOT="${CLOUD_MAIL_SMTP_LETSENCRYPT_WEBROOT:-/var/www/letsencrypt}"
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
    zh:le_domain) printf 'SMTP TLS 域名（必须已解析到本服务器）' ;; en:le_domain) printf 'SMTP TLS domain (must resolve to this server)' ;;
    zh:le_email) printf 'Let’s Encrypt 通知邮箱' ;; en:le_email) printf 'Let’s Encrypt notification email' ;;
    zh:le_enable) printf '是否自动申请 Let’s Encrypt 证书 [Y/n]' ;; en:le_enable) printf 'Enable automatic Let’s Encrypt certificate [Y/n]' ;;
    zh:le_prepare) printf '准备 Let’s Encrypt 证书' ;; en:le_prepare) printf 'Preparing Let’s Encrypt certificate' ;;
    zh:le_success) printf 'Let’s Encrypt 证书已申请并安装' ;; en:le_success) printf 'Let’s Encrypt certificate issued and installed' ;;
    zh:le_renewal) printf '已配置自动续签和续签后自动重启网关' ;; en:le_renewal) printf 'Automatic renewal and post-renewal gateway restart configured' ;;
    zh:le_dns_check) printf '检查域名 DNS 是否指向本服务器' ;; en:le_dns_check) printf 'Checking that DNS points to this server' ;;
    zh:le_port_check) printf '检查 TCP 80 端口是否可用于 HTTP-01 验证' ;; en:le_port_check) printf 'Checking whether TCP port 80 is available for HTTP-01 validation' ;;
    zh:le_mode) printf 'Let’s Encrypt 验证模式（standalone/webroot）' ;; en:le_mode) printf 'Let’s Encrypt challenge mode (standalone/webroot)' ;;
    zh:le_webroot) printf 'Let’s Encrypt Webroot 目录' ;; en:le_webroot) printf 'Let’s Encrypt webroot directory' ;;
    zh:le_webroot_check) printf '验证 Webroot 挑战文件可从域名访问' ;; en:le_webroot_check) printf 'Checking that the webroot challenge file is reachable through the domain' ;;
    zh:tls_cert_file) printf '已有 TLS 证书文件路径（可留空）' ;; en:tls_cert_file) printf 'Existing TLS certificate path (optional)' ;;
    zh:tls_key_file) printf '已有 TLS 私钥文件路径（可留空）' ;; en:tls_key_file) printf 'Existing TLS private key path (optional)' ;;
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
  --domain DOMAIN       Let’s Encrypt SMTP certificate domain
  --letsencrypt         Enable Let’s Encrypt certificate issuance
  --letsencrypt-email E Email address for Let’s Encrypt notices
  --letsencrypt-staging Use the Let’s Encrypt staging CA
  --letsencrypt-mode MODE  Challenge mode: standalone or webroot
  --letsencrypt-webroot DIR Directory served for /.well-known/acme-challenge
  --tls-cert-file FILE     Existing certificate to copy into the gateway
  --tls-key-file FILE      Existing private key to copy into the gateway

Let’s Encrypt:
  Set CLOUD_MAIL_SMTP_TLS_DOMAIN and CLOUD_MAIL_SMTP_LETSENCRYPT=1, or enter the
  domain in the interactive wizard. HTTP-01 always uses public TCP port 80.
  standalone temporarily listens on port 80; webroot writes the challenge into
  an existing Nginx/Apache/Caddy webroot and does not bind port 80.
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
  CLOUD_MAIL_SMTP_TLS_DOMAIN (public DNS name for Let's Encrypt)
  CLOUD_MAIL_SMTP_LETSENCRYPT (1 to request Let's Encrypt; default: 0)
  CLOUD_MAIL_SMTP_LETSENCRYPT_EMAIL (required when Let's Encrypt is enabled)
  CLOUD_MAIL_SMTP_LETSENCRYPT_STAGING (1 to use the Let's Encrypt staging CA)
  CLOUD_MAIL_SMTP_LETSENCRYPT_MODE (standalone or webroot; default: standalone)
  CLOUD_MAIL_SMTP_LETSENCRYPT_WEBROOT (default: /var/www/letsencrypt)

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
validate_letsencrypt_mode() {
  case "$LE_MODE" in
    standalone|webroot) ;;
    *) die 'Let’s Encrypt mode must be standalone or webroot' ;;
  esac
  if [ "$LE_MODE" = webroot ]; then
    require_value 'Let’s Encrypt webroot' "$LE_WEBROOT"
    case "$LE_WEBROOT" in /*) ;; *) die 'Let’s Encrypt webroot must be an absolute path' ;; esac
  fi
}
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
  local config_file="$1" env_file="$2" bind_host bind_port tls_domain
  bind_host="$(json_string_value "$config_file" host)"; bind_port="$(json_number_value "$config_file" port)"; tls_domain="$(json_string_value "$config_file" serverName)"
  [ -n "$bind_host" ] || die 'listen.host could not be read from config.json'; [ -n "$bind_port" ] || die 'listen.port could not be read from config.json'
  tls_domain="$(printf '%s' "$tls_domain" | sed 's/[[:space:]]//g; s/,.*//')"
  [ -n "$tls_domain" ] || tls_domain='smtp-gateway'
  case "$bind_port" in *[!0-9]*|'') die 'listen.port must be an integer' ;; esac
  umask 077; cat > "$env_file" <<ENV
SMTP_BIND_HOST=$bind_host
SMTP_PORT=$bind_port
SMTP_TLS_DOMAIN=$tls_domain
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

validate_certificate_and_key() {
  local cert_file="$1" key_file="$2" expected_domain="${3:-}" cert_pub key_pub san_output
  command -v openssl >/dev/null 2>&1 || die 'openssl is required to validate TLS certificate files'
  [ -f "$cert_file" ] || die "TLS certificate is not a regular file: $cert_file"
  [ -f "$key_file" ] || die "TLS private key is not a regular file: $key_file"
  [ -r "$cert_file" ] || die "TLS certificate is not readable: $cert_file"
  [ -r "$key_file" ] || die "TLS private key is not readable: $key_file"
  openssl x509 -in "$cert_file" -noout >/dev/null 2>&1 || die "TLS certificate cannot be parsed: $cert_file"
  openssl pkey -in "$key_file" -noout >/dev/null 2>&1 || die "TLS private key cannot be parsed: $key_file"
  openssl x509 -in "$cert_file" -checkend 0 -noout >/dev/null 2>&1 || die "TLS certificate is expired: $cert_file"

  cert_pub="$(openssl x509 -in "$cert_file" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  key_pub="$(openssl pkey -in "$key_file" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  [ -n "$cert_pub" ] && [ "$cert_pub" = "$key_pub" ] || die 'TLS certificate and private key do not match'

  if [ -n "$expected_domain" ]; then
    san_output="$(openssl x509 -in "$cert_file" -noout -ext subjectAltName 2>/dev/null || true)"
    [ -n "$san_output" ] || die "TLS certificate has no Subject Alternative Name for $expected_domain"
    printf '%s' "$san_output" | grep -Fq "DNS:$expected_domain" || die "TLS certificate SAN does not contain $expected_domain"
  fi
}

validate_domain() {
  local domain="$1"
  [ -n "$domain" ] || die 'Let’s Encrypt domain must not be empty'
  valid_ipv4 "$domain" && die 'Let’s Encrypt requires a DNS name, not an IPv4 address'
  case "$domain" in
    *[!A-Za-z0-9.-]*|.*|*.) die 'Let’s Encrypt domain contains invalid characters' ;;
  esac
  case "$domain" in
    *.*) ;;
    *) die 'Let’s Encrypt requires a fully qualified domain name' ;;
  esac
}

local_server_ipv4s() {
  local ip
  printf '127.0.0.1\n'
  for ip in $(hostname -I 2>/dev/null || true); do valid_ipv4 "$ip" && printf '%s\n' "$ip"; done
  if command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | while IFS= read -r ip; do
      valid_ipv4 "$ip" && printf '%s\n' "$ip"
    done
  fi
  if command -v curl >/dev/null 2>&1; then
    local endpoint public_ip
    for endpoint in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
      public_ip="$(curl -4 --silent --show-error --connect-timeout 2 --max-time 4 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
      if valid_ipv4 "$public_ip"; then printf '%s\n' "$public_ip"; break; fi
    done
  fi
}

check_webroot_prerequisites() {
  local domain="$1" challenge_dir token challenge_file expected response response_file http_code
  command -v curl >/dev/null 2>&1 || die 'curl is required for the webroot challenge check'
  challenge_dir="$LE_WEBROOT/.well-known/acme-challenge"
  mkdir -p "$challenge_dir"
  chmod 755 "$LE_WEBROOT" "$LE_WEBROOT/.well-known" "$challenge_dir" 2>/dev/null || true
  token="cloud-mail-smtp-gateway-$(date +%s)-$$"
  challenge_file="$challenge_dir/$token"
  expected="cloud-mail-smtp-gateway-webroot-check"
  printf '%s' "$expected" > "$challenge_file"
  info "$(text le_webroot_check): http://$domain/.well-known/acme-challenge/$token"
  response_file="$(mktemp)"
  http_code="$(curl --silent --show-error --location --insecure --connect-timeout 10 --max-time 20 --output "$response_file" --write-out '%{http_code}' "http://$domain/.well-known/acme-challenge/$token" 2>/dev/null || true)"
  response="$(cat "$response_file" 2>/dev/null || true)"
  rm -f -- "$challenge_file" "$response_file"
  [ "$http_code" = 200 ] && [ "$response" = "$expected" ] || die "webroot challenge is not reachable at http://$domain/.well-known/acme-challenge/ (HTTP $http_code)"
}

check_letsencrypt_prerequisites() {
  local domain="$1" resolved ip matched=0
  command -v getent >/dev/null 2>&1 || die 'getent is required to verify the Let’s Encrypt domain DNS record'
  resolved="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u || true)"
  [ -n "$resolved" ] || die "Let’s Encrypt domain does not resolve to an IPv4 address: $domain"

  if [ "$LE_MODE" = standalone ]; then
    info "$(text le_dns_check): $domain"
    while IFS= read -r ip; do
      [ -n "$ip" ] || continue
      if local_server_ipv4s | grep -Fxq "$ip"; then matched=1; break; fi
    done <<EOF_DNS
$resolved
EOF_DNS
    [ "$matched" -eq 1 ] || die "DNS for $domain does not point to this server. Resolved: $(printf '%s' "$resolved" | tr '\n' ' ')"
    info "$(text le_port_check)"
    if command -v ss >/dev/null 2>&1 && ss -H -ltn '( sport = :80 )' 2>/dev/null | grep -q .; then
      die 'TCP port 80 is already in use; use --letsencrypt-mode webroot or DNS-01 instead'
    fi
  else
    # Webroot works with an existing reverse proxy, CDN, or load balancer. The
    # public challenge URL is the authoritative reachability check; requiring
    # the DNS A record to equal a local interface would incorrectly reject
    # Cloudflare-proxied and reverse-proxied domains.
    info "$(text le_dns_check): $domain (webroot/reverse proxy mode)"
    check_webroot_prerequisites "$domain"
  fi
}

ensure_renewal_scheduler() {
  local cron_file='/etc/cron.d/cloud-mail-smtp-gateway-certbot'
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files certbot.timer >/dev/null 2>&1 && systemctl cat certbot.timer >/dev/null 2>&1; then
    if systemctl enable --now certbot.timer >/dev/null 2>&1; then return; fi
    printf '%s\n' 'certbot.timer is present but could not be started; falling back to cron.' >&2
  fi
  command -v certbot >/dev/null 2>&1 || die 'certbot is required for automatic renewal'
  cat > "$cron_file" <<CRON
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
17 3,15 * * * root certbot renew --quiet
CRON
  chmod 644 "$cron_file"
}

ensure_certbot() {
  if command -v certbot >/dev/null 2>&1; then return; fi
  command -v apt-get >/dev/null 2>&1 || die 'certbot is not installed; install certbot manually on non-Debian systems'
  info 'Installing certbot with apt-get'
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y certbot
  command -v certbot >/dev/null 2>&1 || die 'certbot installation failed'
}

install_letsencrypt_hook() {
  local hook_dir='/etc/letsencrypt/renewal-hooks/deploy' hook_file="$INSTALL_DIR/renew-letsencrypt.sh"
  mkdir -p "$hook_dir"
  cat > "$hook_file" <<HOOK
#!/usr/bin/env bash
set -Eeuo pipefail
CERT_DIR="/etc/letsencrypt/live/$TLS_DOMAIN"
GATEWAY_DIR="$INSTALL_DIR"
install -m 0640 -o root -g root "\$CERT_DIR/fullchain.pem" "\$GATEWAY_DIR/tls/server.crt"
install -m 0640 -o root -g root "\$CERT_DIR/privkey.pem" "\$GATEWAY_DIR/tls/server.key"
cd "\$GATEWAY_DIR"
docker compose restart smtp-gateway >/dev/null
HOOK
  chmod 750 "$hook_file"
  ln -sfn "$hook_file" "$hook_dir/cloud-mail-smtp-gateway"
  chown root:root "$hook_file"
  info "$(text le_renewal)"
}

obtain_letsencrypt_certificate() {
  local cert_dir="/etc/letsencrypt/live/$TLS_DOMAIN" cert_file="$INSTALL_DIR/tls/server.crt" key_file="$INSTALL_DIR/tls/server.key" staging_args=()
  validate_domain "$TLS_DOMAIN"
  require_value 'Let’s Encrypt email' "$LE_EMAIL"
  case "$LE_EMAIL" in *[[:space:]]*) die 'Let’s Encrypt email must not contain whitespace' ;; esac
  case "$LE_EMAIL" in *@*.*) ;; *) die 'Let’s Encrypt email appears invalid' ;; esac
  case "$LE_ENABLED" in 0|1) ;; *) die 'CLOUD_MAIL_SMTP_LETSENCRYPT must be 0 or 1' ;; esac
  case "$LE_STAGING" in 0|1) ;; *) die 'CLOUD_MAIL_SMTP_LETSENCRYPT_STAGING must be 0 or 1' ;; esac
  ensure_certbot
  check_letsencrypt_prerequisites "$TLS_DOMAIN"
  if [ "$LE_STAGING" -eq 1 ]; then staging_args+=(--staging); fi
  info "$(text le_prepare): $TLS_DOMAIN"
  local certbot_args=(certbot certonly --non-interactive --agree-tos --no-eff-email --keep-until-expiring
    --preferred-challenges http "${staging_args[@]}" --email "$LE_EMAIL" -d "$TLS_DOMAIN")
  if [ "$LE_MODE" = standalone ]; then
    certbot_args+=(--standalone)
  else
    certbot_args+=(--webroot -w "$LE_WEBROOT")
  fi
  if ! "${certbot_args[@]}"; then
    die 'Let’s Encrypt certificate request failed. Confirm DNS, TCP 80, and the webroot configuration.'
  fi
  [ -s "$cert_dir/fullchain.pem" ] || die "Let’s Encrypt certificate not found: $cert_dir/fullchain.pem"
  [ -s "$cert_dir/privkey.pem" ] || die "Let’s Encrypt private key not found: $cert_dir/privkey.pem"
  validate_certificate_and_key "$cert_dir/fullchain.pem" "$cert_dir/privkey.pem" "$TLS_DOMAIN"
  install -m 0640 -o root -g root "$cert_dir/fullchain.pem" "$cert_file"
  install -m 0640 -o root -g root "$cert_dir/privkey.pem" "$key_file"
  install_letsencrypt_hook
  ensure_renewal_scheduler
  TLS_HOSTNAME="$TLS_DOMAIN"
  info "$(text le_success): $cert_file"
}

prepare_tls_material() {
  local tls_dir="$INSTALL_DIR/tls" cert_file="$INSTALL_DIR/tls/server.crt" key_file="$INSTALL_DIR/tls/server.key"
  local san_list tmp_conf tmp_key tmp_cert name backup_stamp
  info "$(text tls_prepare)"
  mkdir -p "$tls_dir"; chmod 750 "$tls_dir"
  if [ "$LE_ENABLED" -eq 1 ]; then
    obtain_letsencrypt_certificate
    chown root:root "$cert_file" "$key_file"; chmod 640 "$cert_file" "$key_file"
    return
  fi
  if [ -n "$TLS_CERT_SOURCE" ] || [ -n "$TLS_KEY_SOURCE" ]; then
    [ -n "$TLS_CERT_SOURCE" ] && [ -n "$TLS_KEY_SOURCE" ] || die 'both TLS certificate and private key source files are required'
    validate_certificate_and_key "$TLS_CERT_SOURCE" "$TLS_KEY_SOURCE" "$TLS_DOMAIN"
    install -m 0640 -o root -g root "$TLS_CERT_SOURCE" "$cert_file"
    install -m 0640 -o root -g root "$TLS_KEY_SOURCE" "$key_file"
    info "$(text tls_existing): $cert_file"
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

update_config_server_name() {
  local config_file="$1" server_name="$TLS_DOMAIN" temporary
  [ -n "$server_name" ] || return 0
  validate_domain "$server_name"
  if grep -Eq '"serverName"[[:space:]]*:' "$config_file"; then
    temporary="${config_file}.tmp.$$"
    sed -E "s#(\"serverName\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")#\1$(json_escape "$server_name")\2#" "$config_file" > "$temporary"
    mv -f -- "$temporary" "$config_file"
  fi
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
  local output="$1" listen_host listen_port smtp_user smtp_password max_message_size cloud_mail_address upstream_url upstream_health_url upstream_user upstream_api_key timeout_ms temporary le_answer
  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    listen_host="${CLOUD_MAIL_LISTEN_HOST:-0.0.0.0}"; listen_port="${CLOUD_MAIL_LISTEN_PORT:-2525}"; max_message_size="${CLOUD_MAIL_MAX_MESSAGE_SIZE:-10485760}"
    upstream_user="${CLOUD_MAIL_UPSTREAM_USER:-${CLOUD_MAIL_SMTP_USER:-}}"; upstream_api_key="${CLOUD_MAIL_UPSTREAM_API_KEY:-${CLOUD_MAIL_SMTP_PASSWORD:-}}"
    if [ -n "${CLOUD_MAIL_ADDRESS:-}" ]; then cloud_mail_address="$(normalize_cloud_mail_address "$CLOUD_MAIL_ADDRESS")"; upstream_url="${cloud_mail_address}/api/smtp/send"; upstream_health_url="${cloud_mail_address}/api/smtp/health"; else upstream_url="${CLOUD_MAIL_UPSTREAM_URL:-}"; upstream_health_url="${CLOUD_MAIL_UPSTREAM_HEALTH_URL:-}"; fi
    timeout_ms="${CLOUD_MAIL_UPSTREAM_TIMEOUT_MS:-15000}"
    TLS_DOMAIN="${CLOUD_MAIL_SMTP_TLS_DOMAIN:-${TLS_DOMAIN:-}}"
    TLS_HOSTNAME="${TLS_DOMAIN:-${CLOUD_MAIL_SMTP_TLS_HOSTNAME:-smtp-gateway}}"
    if [ -z "${CLOUD_MAIL_SMTP_LETSENCRYPT:-}" ] && [ "$LE_ENABLED" -eq 0 ]; then LE_ENABLED=0; fi
  else
    printf '\n%s\n' "$(text config_title)" >&2; printf '%s\n\n' "$(text config_hint)" >&2
    listen_host="$(prompt_value listen_host '0.0.0.0')"; listen_port="$(prompt_value listen_port '2525')"; max_message_size="$(prompt_value max_size '10485760')"
    cloud_mail_address="$(prompt_value cloud_address 'mail.example.com')"; cloud_mail_address="$(normalize_cloud_mail_address "$cloud_mail_address")"; upstream_url="${cloud_mail_address}/api/smtp/send"; upstream_health_url="${cloud_mail_address}/api/smtp/health"
    upstream_user="$(prompt_value cloud_user 'my-app')"; upstream_api_key="$(prompt_secret cloud_key)"; timeout_ms="$(prompt_value timeout '15000')"
    TLS_DOMAIN="$(prompt_value le_domain "$TLS_DOMAIN")"
    if [ -n "$TLS_DOMAIN" ]; then
      TLS_HOSTNAME="$TLS_DOMAIN"
      le_answer="$(prompt_value le_enable "$([ "$LE_ENABLED" -eq 1 ] && printf Y || printf n)")"
      case "$le_answer" in n|N|no|NO) LE_ENABLED=0 ;; *) LE_ENABLED=1 ;; esac
      if [ "$LE_ENABLED" -eq 1 ]; then
        LE_EMAIL="$(prompt_value le_email "$LE_EMAIL")"
        LE_MODE="$(prompt_value le_mode "$LE_MODE")"
        validate_letsencrypt_mode
        if [ "$LE_MODE" = webroot ]; then LE_WEBROOT="$(prompt_value le_webroot "$LE_WEBROOT")"; fi
      else
        TLS_CERT_SOURCE="$(prompt_value tls_cert_file "$TLS_CERT_SOURCE")"
        TLS_KEY_SOURCE="$(prompt_value tls_key_file "$TLS_KEY_SOURCE")"
      fi
    else
      LE_ENABLED=0
      TLS_HOSTNAME="${CLOUD_MAIL_SMTP_TLS_HOSTNAME:-smtp-gateway}"
      TLS_CERT_SOURCE="$(prompt_value tls_cert_file "$TLS_CERT_SOURCE")"
      TLS_KEY_SOURCE="$(prompt_value tls_key_file "$TLS_KEY_SOURCE")"
    fi
    printf '%s\n\n' "$(text credential_notice)" >&2
  fi
  require_value 'Cloud Mail SMTP username' "$upstream_user"; require_value 'Cloud Mail SMTP API key' "$upstream_api_key"; require_value 'upstream URL' "$upstream_url"; require_value 'upstream health URL' "$upstream_health_url"
  case "$LE_ENABLED" in 0|1) ;; *) die 'CLOUD_MAIL_SMTP_LETSENCRYPT must be 0 or 1' ;; esac
  validate_letsencrypt_mode
  if [ "$LE_ENABLED" -eq 1 ]; then
    validate_domain "$TLS_DOMAIN"; require_value 'Let’s Encrypt email' "$LE_EMAIL"
    [ -z "$TLS_CERT_SOURCE" ] && [ -z "$TLS_KEY_SOURCE" ] || die 'Do not combine Let’s Encrypt with manual TLS certificate files'
  elif [ -n "$TLS_CERT_SOURCE" ] || [ -n "$TLS_KEY_SOURCE" ]; then
    [ -n "$TLS_CERT_SOURCE" ] && [ -n "$TLS_KEY_SOURCE" ] || die 'both TLS certificate and private key source files are required'
  fi
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
    --domain) [ "$#" -ge 2 ] || die '--domain requires a DNS name'; TLS_DOMAIN="$2"; TLS_HOSTNAME="$2"; shift 2 ;;
    --letsencrypt) LE_ENABLED=1; shift ;;
    --letsencrypt-mode) [ "$#" -ge 2 ] || die '--letsencrypt-mode requires standalone or webroot'; LE_MODE="$2"; shift 2 ;;
    --letsencrypt-webroot) [ "$#" -ge 2 ] || die '--letsencrypt-webroot requires a directory'; LE_WEBROOT="$2"; LE_MODE=webroot; shift 2 ;;
    --tls-cert-file) [ "$#" -ge 2 ] || die '--tls-cert-file requires a file'; TLS_CERT_SOURCE="$2"; shift 2 ;;
    --tls-key-file) [ "$#" -ge 2 ] || die '--tls-key-file requires a file'; TLS_KEY_SOURCE="$2"; shift 2 ;;
    --letsencrypt-email) [ "$#" -ge 2 ] || die '--letsencrypt-email requires an email address'; LE_EMAIL="$2"; shift 2 ;;
    --letsencrypt-staging) LE_STAGING=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (use --help for usage)" ;;
  esac
done

set_language "$UI_LANGUAGE"
case "$LE_ENABLED" in 0|1) ;; *) die 'CLOUD_MAIL_SMTP_LETSENCRYPT must be 0 or 1' ;; esac
case "$LE_STAGING" in 0|1) ;; *) die 'CLOUD_MAIL_SMTP_LETSENCRYPT_STAGING must be 0 or 1' ;; esac
validate_letsencrypt_mode
if [ -n "$TLS_DOMAIN" ]; then TLS_HOSTNAME="$TLS_DOMAIN"; fi
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
if [ -n "$TLS_DOMAIN" ]; then TLS_HOSTNAME="$TLS_DOMAIN"; fi
update_config_server_name "$INSTALL_DIR/config.json"
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
