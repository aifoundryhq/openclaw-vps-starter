#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

trap 'echo; echo "[x] Error on line $LINENO. Command: $BASH_COMMAND"; exit 1' ERR

# ============================================================
# OpenClaw Starter Installer
# Public GitHub Edition
#
# Goal:
# - Provide a clean, safe, local-only starter install for Ubuntu VPS
# - Build trust and help users get a working baseline quickly
# - Leave advanced hardening, recovery, client presets, and support
#   workflows for the premium/internal edition
# ============================================================

SCRIPT_NAME="$(basename "$0")"
START_TIME="$(date +%s)"

DEFAULT_INSTALL_DIR="$HOME/projects/openclaw"
DEFAULT_GATEWAY_PORT="18789"
DEFAULT_BRIDGE_PORT="18790"
DEFAULT_BROWSER_PORT="18791"
DEFAULT_IMAGE="ghcr.io/openclaw/openclaw:latest"
DEFAULT_CONFIG_DIR="$HOME/.openclaw"
DEFAULT_TIMEZONE="UTC"

OPENCLAW_REPO_URL="https://github.com/openclaw/openclaw.git"

INSTALL_DIR=""
GATEWAY_PORT=""
BRIDGE_PORT=""
BROWSER_PORT=""
OPENCLAW_IMAGE=""
OPENCLAW_CONFIG_DIR=""
OPENCLAW_WORKSPACE_DIR=""
OPENCLAW_TZ=""
ENABLE_UFW="n"
NON_INTERACTIVE="false"

ANTHROPIC_API_KEY=""
TELEGRAM_BOT_TOKEN=""
BRAVE_SEARCH_API_KEY=""

log() {
  printf '\n[+] %s\n' "$*"
}

warn() {
  printf '\n[!] %s\n' "$*" >&2
}

die() {
  printf '\n[x] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [options]

Options:
  --install-dir PATH         Install directory
  --gateway-port PORT        Gateway port (default: $DEFAULT_GATEWAY_PORT)
  --bridge-port PORT         Bridge port (default: $DEFAULT_BRIDGE_PORT)
  --browser-port PORT        Browser control port (default: $DEFAULT_BROWSER_PORT)
  --image IMAGE              OpenClaw image (default: $DEFAULT_IMAGE)
  --timezone TZ              Timezone (default: $DEFAULT_TIMEZONE)

  --anthropic-key KEY        Anthropic API key
  --telegram-token TOKEN     Telegram bot token
  --brave-key KEY            Brave Search API key

  --enable-ufw               Enable UFW firewall with OpenSSH allowed
  --yes                      Non-interactive mode; accept defaults where applicable
  -h, --help                 Show this help message

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME --enable-ufw
  $SCRIPT_NAME --yes --install-dir \$HOME/openclaw --telegram-token "123:abc"
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_non_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    die "Run this installer as a non-root sudo user, not root."
  fi
}

require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    log "Requesting sudo access..."
    sudo -v || die "Sudo access is required."
  fi
}

trim() {
  local var="$1"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  printf '%s' "$var"
}

validate_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || die "Port must be numeric: $port"
  (( port >= 1 && port <= 65535 )) || die "Port out of range: $port"
}

validate_not_reserved_path() {
  local path="$1"
  [[ -n "$path" ]] || die "Install directory cannot be empty."
  [[ "$path" != "/" ]] || die "Refusing to use / as install directory."
}

prompt_default() {
  local label="$1"
  local default="$2"
  local value=""

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    printf '%s' "$default"
    return
  fi

  read -r -p "$label [$default]: " value
  value="$(trim "$value")"

  if [[ -z "$value" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$value"
  fi
}

prompt_secret_optional() {
  local label="$1"
  local value=""

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    printf ''
    return
  fi

  read -r -s -p "$label (optional): " value
  printf '\n'
  value="$(trim "$value")"
  printf '%s' "$value"
}

prompt_yes_no() {
  local label="$1"
  local default="$2"
  local answer=""
  local prompt_suffix="[y/N]"
  [[ "$default" == "y" ]] && prompt_suffix="[Y/n]"

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    [[ "$default" == "y" ]]
    return
  fi

  while true; do
    read -r -p "$label $prompt_suffix: " answer
    answer="$(trim "${answer,,}")"

    if [[ -z "$answer" ]]; then
      answer="$default"
    fi

    case "$answer" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) warn "Please answer y or n." ;;
    esac
  done
}

parse_args() {
  INSTALL_DIR="$DEFAULT_INSTALL_DIR"
  GATEWAY_PORT="$DEFAULT_GATEWAY_PORT"
  BRIDGE_PORT="$DEFAULT_BRIDGE_PORT"
  BROWSER_PORT="$DEFAULT_BROWSER_PORT"
  OPENCLAW_IMAGE="$DEFAULT_IMAGE"
  OPENCLAW_CONFIG_DIR="$DEFAULT_CONFIG_DIR"
  OPENCLAW_WORKSPACE_DIR="$DEFAULT_CONFIG_DIR/workspace"
  OPENCLAW_TZ="$DEFAULT_TIMEZONE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install-dir)
        INSTALL_DIR="${2:-}"
        shift 2
        ;;
      --gateway-port)
        GATEWAY_PORT="${2:-}"
        shift 2
        ;;
      --bridge-port)
        BRIDGE_PORT="${2:-}"
        shift 2
        ;;
      --browser-port)
        BROWSER_PORT="${2:-}"
        shift 2
        ;;
      --image)
        OPENCLAW_IMAGE="${2:-}"
        shift 2
        ;;
      --timezone)
        OPENCLAW_TZ="${2:-}"
        shift 2
        ;;
      --anthropic-key)
        ANTHROPIC_API_KEY="${2:-}"
        shift 2
        ;;
      --telegram-token)
        TELEGRAM_BOT_TOKEN="${2:-}"
        shift 2
        ;;
      --brave-key)
        BRAVE_SEARCH_API_KEY="${2:-}"
        shift 2
        ;;
      --enable-ufw)
        ENABLE_UFW="y"
        shift
        ;;
      --yes)
        NON_INTERACTIVE="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

check_supported_os() {
  local os_id
  os_id="$(. /etc/os-release && echo "$ID")"

  if [[ "$os_id" != "ubuntu" ]]; then
    die "This installer currently supports Ubuntu only."
  fi
}

collect_missing_inputs() {
  log "Collecting installer inputs"

  INSTALL_DIR="$(prompt_default "Installation directory" "$INSTALL_DIR")"
  GATEWAY_PORT="$(prompt_default "Gateway port" "$GATEWAY_PORT")"
  BRIDGE_PORT="$(prompt_default "Bridge port" "$BRIDGE_PORT")"
  BROWSER_PORT="$(prompt_default "Browser control port" "$BROWSER_PORT")"

  validate_not_reserved_path "$INSTALL_DIR"
  validate_port "$GATEWAY_PORT"
  validate_port "$BRIDGE_PORT"
  validate_port "$BROWSER_PORT"

  if [[ "$GATEWAY_PORT" == "$BRIDGE_PORT" || "$GATEWAY_PORT" == "$BROWSER_PORT" || "$BRIDGE_PORT" == "$BROWSER_PORT" ]]; then
    die "Gateway, bridge, and browser ports must all be different."
  fi

  if [[ -z "$ANTHROPIC_API_KEY" ]]; then
    ANTHROPIC_API_KEY="$(prompt_secret_optional "Anthropic API key")"
  fi

  if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
    TELEGRAM_BOT_TOKEN="$(prompt_secret_optional "Telegram bot token")"
  fi

  if [[ -z "$BRAVE_SEARCH_API_KEY" ]]; then
    BRAVE_SEARCH_API_KEY="$(prompt_secret_optional "Brave Search API key")"
  fi

  if [[ "$ENABLE_UFW" != "y" ]]; then
    if prompt_yes_no "Enable UFW firewall now?" "y"; then
      ENABLE_UFW="y"
    fi
  fi

  OPENCLAW_WORKSPACE_DIR="$OPENCLAW_CONFIG_DIR/workspace"
}

update_system() {
  log "Updating package index"
  sudo apt-get update -y
}

install_base_dependencies() {
  log "Installing base dependencies"
  sudo apt-get install -y \
    ca-certificates \
    curl \
    git \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker and Docker Compose plugin already installed"
  else
    log "Installing Docker Engine and Docker Compose plugin"

    sudo install -m 0755 -d /etc/apt/keyrings
    sudo rm -f /etc/apt/keyrings/docker.asc
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    local codename arch source_file
    codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
    arch="$(dpkg --print-architecture)"
    source_file="/etc/apt/sources.list.d/docker.sources"

    sudo tee "$source_file" >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt-get update -y
    sudo apt-get install -y \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-buildx-plugin \
      docker-compose-plugin
  fi

  log "Enabling Docker service"
  sudo systemctl enable --now docker

  if ! getent group docker >/dev/null 2>&1; then
    sudo groupadd docker
  fi

  if ! id -nG "$USER" | grep -qw docker; then
    log "Adding $USER to docker group"
    sudo usermod -aG docker "$USER"
    warn "You were added to the docker group. New shells pick this up automatically."
    warn "This installer will continue using sudo for Docker commands."
  fi
}

prepare_directories() {
  log "Preparing directories"
  mkdir -p "$INSTALL_DIR"
  mkdir -p "$OPENCLAW_CONFIG_DIR"
  mkdir -p "$OPENCLAW_WORKSPACE_DIR"
}

clone_or_update_openclaw() {
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    log "Existing OpenClaw repository found; pulling latest changes"
    git -C "$INSTALL_DIR" pull --ff-only || warn "Git pull failed. Review repository state manually."
    return
  fi

  if [[ -d "$INSTALL_DIR" ]] && [[ -n "$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
    die "Install directory is not empty and is not a git repository: $INSTALL_DIR"
  fi

  log "Cloning OpenClaw into $INSTALL_DIR"
  git clone "$OPENCLAW_REPO_URL" "$INSTALL_DIR"
}

write_env_file() {
  log "Writing $INSTALL_DIR/.env"

  cat > "$INSTALL_DIR/.env" <<EOF
# Generated by OpenClaw Starter Installer
OPENCLAW_IMAGE=${OPENCLAW_IMAGE}
OPENCLAW_GATEWAY_PORT=${GATEWAY_PORT}
OPENCLAW_BRIDGE_PORT=${BRIDGE_PORT}
OPENCLAW_CONFIG_DIR=${OPENCLAW_CONFIG_DIR}
OPENCLAW_WORKSPACE_DIR=${OPENCLAW_WORKSPACE_DIR}
OPENCLAW_GATEWAY_BIND=loopback
OPENCLAW_TZ=${OPENCLAW_TZ}
OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=

# Optional credentials
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
BRAVE_SEARCH_API_KEY=${BRAVE_SEARCH_API_KEY}
EOF

  chmod 600 "$INSTALL_DIR/.env"
}

write_compose_file() {
  log "Writing docker-compose.yml with localhost-only bindings"

  cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
services:
  openclaw-gateway:
    image: \${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}
    environment:
      HOME: /home/node
      TERM: xterm-256color
      OPENCLAW_GATEWAY_TOKEN: \${OPENCLAW_GATEWAY_TOKEN:-}
      OPENCLAW_ALLOW_INSECURE_PRIVATE_WS: \${OPENCLAW_ALLOW_INSECURE_PRIVATE_WS:-}
      ANTHROPIC_API_KEY: \${ANTHROPIC_API_KEY:-}
      TELEGRAM_BOT_TOKEN: \${TELEGRAM_BOT_TOKEN:-}
      BRAVE_SEARCH_API_KEY: \${BRAVE_SEARCH_API_KEY:-}
      TZ: \${OPENCLAW_TZ:-UTC}
    volumes:
      - \${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - \${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
    ports:
      - "127.0.0.1:\${OPENCLAW_GATEWAY_PORT:-18789}:18789"
      - "127.0.0.1:\${OPENCLAW_BRIDGE_PORT:-18790}:18790"
      - "127.0.0.1:${BROWSER_PORT}:18791"
    init: true
    restart: unless-stopped
    command:
      [
        "node",
        "dist/index.js",
        "gateway",
        "--bind",
        "\${OPENCLAW_GATEWAY_BIND:-loopback}",
        "--port",
        "18789"
      ]
    healthcheck:
      test:
        [
          "CMD",
          "node",
          "-e",
          "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
        ]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 20s

  openclaw-cli:
    image: \${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}
    network_mode: "service:openclaw-gateway"
    cap_drop:
      - NET_RAW
      - NET_ADMIN
    security_opt:
      - no-new-privileges:true
    environment:
      HOME: /home/node
      TERM: xterm-256color
      OPENCLAW_GATEWAY_TOKEN: \${OPENCLAW_GATEWAY_TOKEN:-}
      OPENCLAW_ALLOW_INSECURE_PRIVATE_WS: \${OPENCLAW_ALLOW_INSECURE_PRIVATE_WS:-}
      BROWSER: echo
      ANTHROPIC_API_KEY: \${ANTHROPIC_API_KEY:-}
      TELEGRAM_BOT_TOKEN: \${TELEGRAM_BOT_TOKEN:-}
      BRAVE_SEARCH_API_KEY: \${BRAVE_SEARCH_API_KEY:-}
      TZ: \${OPENCLAW_TZ:-UTC}
    volumes:
      - \${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - \${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
    stdin_open: true
    tty: true
    init: true
    entrypoint: ["node", "dist/index.js"]
    depends_on:
      - openclaw-gateway
EOF
}

bootstrap_openclaw_config() {
  log "Bootstrapping OpenClaw config"

  mkdir -p "$OPENCLAW_CONFIG_DIR"

  cat > "$OPENCLAW_CONFIG_DIR/openclaw.json" <<EOF
{
  "gateway": {
    "mode": "local"
  }
}
EOF

  chmod 600 "$OPENCLAW_CONFIG_DIR/openclaw.json"
  chown -R "$USER":"$(id -gn "$USER")" "$OPENCLAW_CONFIG_DIR"
}

configure_firewall() {
  if [[ "$ENABLE_UFW" != "y" ]]; then
    warn "Skipping UFW enablement by choice."
    return
  fi

  log "Configuring UFW"
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow OpenSSH
  sudo ufw --force enable
}

start_openclaw() {
  log "Starting OpenClaw"
  cd "$INSTALL_DIR"
  sudo docker compose up -d
}

verify_openclaw_stable() {
  log "Verifying OpenClaw gateway health"

  local attempts=36
  local sleep_seconds=5
  local health_status=""
  local container_id=""

  container_id="$(cd "$INSTALL_DIR" && sudo docker compose ps -q openclaw-gateway)"
  [[ -n "$container_id" ]] || die "Could not determine gateway container ID."

  for ((i=1; i<=attempts; i++)); do
    health_status="$(sudo docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$container_id" 2>/dev/null || true)"

    if [[ "$health_status" == "healthy" ]]; then
      log "Gateway is healthy"
      cd "$INSTALL_DIR" && sudo docker compose ps
      return 0
    fi

    printf '[.] Waiting for gateway health (%d/%d) current=%s\n' "$i" "$attempts" "${health_status:-unknown}"
    sleep "$sleep_seconds"
  done

  warn "Gateway did not become healthy in time. Recent logs:"
  cd "$INSTALL_DIR" && sudo docker compose logs --tail 100 openclaw-gateway || true
  die "OpenClaw gateway failed health verification."
}

post_install_checks() {
  log "Running post-install checks"

  log "Docker containers"
  sudo docker ps

  log "Listening ports"
  sudo ss -tuln

  log "UFW status"
  sudo ufw status verbose || true

  log "Basic SSH hardening check"
  if grep -Eq '^\s*PermitRootLogin\s+no' /etc/ssh/sshd_config; then
    log "PermitRootLogin is disabled"
  else
    warn "PermitRootLogin is not set to 'no'"
  fi

  if grep -Eq '^\s*PasswordAuthentication\s+no' /etc/ssh/sshd_config; then
    log "PasswordAuthentication is disabled"
  else
    warn "PasswordAuthentication is not set to 'no'"
  fi
}

print_summary() {
  local end_time elapsed elapsed_minutes elapsed_seconds
  end_time="$(date +%s)"
  elapsed=$((end_time - START_TIME))
  elapsed_minutes=$((elapsed / 60))
  elapsed_seconds=$((elapsed % 60))

  cat <<EOF

============================================================
OpenClaw Starter install complete.

Deployment time:
  ${elapsed_minutes}m ${elapsed_seconds}s

Location:
  Repo directory      : $INSTALL_DIR
  Config directory    : $OPENCLAW_CONFIG_DIR
  Workspace directory : $OPENCLAW_WORKSPACE_DIR
  Env file            : $INSTALL_DIR/.env
  Compose file        : $INSTALL_DIR/docker-compose.yml

Useful commands:
  Status:
    cd $INSTALL_DIR && sudo docker compose ps

  Logs:
    cd $INSTALL_DIR && sudo docker compose logs -f openclaw-gateway

  Restart:
    cd $INSTALL_DIR && sudo docker compose restart

  Stop:
    cd $INSTALL_DIR && sudo docker compose down

Next steps:
  1. Verify status:
     cd $INSTALL_DIR && sudo docker compose ps

  2. Run onboarding if needed:
     cd $INSTALL_DIR && sudo docker compose run --rm openclaw-cli onboard

  3. Check current status:
     cd $INSTALL_DIR && sudo docker compose run --rm openclaw-cli status

  4. If Telegram is configured, pair your operator:
     - message your bot with /pair
     - approve it with:
       cd $INSTALL_DIR && sudo docker compose run --rm openclaw-cli pairing approve telegram <PAIR_CODE>

Reboot verification:
  1. sudo reboot
  2. SSH back in
  3. cd $INSTALL_DIR && sudo docker compose ps
  4. Test your bot in Telegram

Starter edition notes:
  - Ports are bound to 127.0.0.1 only
  - UFW was $( [[ "$ENABLE_UFW" == "y" ]] && echo "enabled" || echo "left unchanged" )
  - This installer is intentionally simple
  - Advanced hardening, repair workflows, and premium support tooling are not included
============================================================

EOF
}

main() {
  parse_args "$@"

  require_non_root
  require_sudo
  need_cmd sudo
  need_cmd apt-get
  need_cmd curl
  need_cmd git

  check_supported_os
  collect_missing_inputs
  update_system
  install_base_dependencies
  install_docker
  prepare_directories
  clone_or_update_openclaw
  write_env_file
  write_compose_file
  bootstrap_openclaw_config
  configure_firewall
  start_openclaw
  verify_openclaw_stable
  post_install_checks
  print_summary
}

main "$@"
