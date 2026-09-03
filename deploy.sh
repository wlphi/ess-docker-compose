#!/bin/bash
# Automated Matrix Stack Deployment Script
# This script handles the complete deployment from scratch
# Supports both local testing and production deployments

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Use sudo for docker commands
DOCKER_CMD="sudo docker"
DOCKER_COMPOSE_CMD="sudo docker compose"

echo -e "${YELLOW}Using sudo for docker commands.${NC}"
echo ""

# Test docker access (skip when SKIP_START=true for CI/testing without Docker)
if [[ "${SKIP_START:-false}" != "true" ]] && ! sudo docker ps &> /dev/null; then
    echo -e "${RED}Error: Cannot access Docker. Please ensure Docker is running.${NC}"
    exit 1
fi

clear 2>/dev/null || true
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Matrix Stack Automated Deployment Script            ║${NC}"
echo -e "${BLUE}║                  Interactive Setup                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# DEPLOYMENT TYPE SELECTION
# ============================================================================
echo -e "${CYAN}Select Deployment Type:${NC}"
echo ""
echo -e "  ${GREEN}1)${NC} Local Testing"
echo -e "     → Everything on one machine with self-signed certificates"
echo -e "     → Uses *.example.test domains (add to /etc/hosts)"
echo ""
echo -e "  ${GREEN}2)${NC} Production (Single-Server)"
echo -e "     → All services on one machine with Let's Encrypt certificates"
echo -e "     → Real domains — point DNS to this machine"
echo -e "     → Simplest production setup"
echo ""
echo -e "  ${GREEN}3)${NC} Production (Distributed)"
echo -e "     → Services on separate machines"
echo -e "     → Caddy and Authelia run on dedicated hosts"
echo -e "     → Generates config files to copy to each machine"
echo ""
read -p "Enter choice [1/2/3]: " DEPLOYMENT_TYPE

if [[ "$DEPLOYMENT_TYPE" == "1" ]]; then
    DEPLOYMENT_MODE="local"
    COMPOSE_FILE="compose-variants/docker-compose.local.yml"
    # Docker Compose v5+ resolves volume paths relative to the compose file's directory.
    # --project-directory . overrides this so all paths resolve from the project root.
    DOCKER_COMPOSE_CMD="sudo docker compose --project-directory ."
    echo -e "${GREEN}✓${NC} Selected: Local Testing Mode"
elif [[ "$DEPLOYMENT_TYPE" == "2" ]]; then
    DEPLOYMENT_MODE="production-single"
    COMPOSE_FILE="docker-compose.yml"
    DOCKER_COMPOSE_CMD="sudo docker compose --project-directory ."
    echo -e "${GREEN}✓${NC} Selected: Production (Single-Server)"
elif [[ "$DEPLOYMENT_TYPE" == "3" ]]; then
    DEPLOYMENT_MODE="production"
    COMPOSE_FILE="docker-compose.yml"
    echo -e "${GREEN}✓${NC} Selected: Production (Distributed)"
else
    echo -e "${RED}✗${NC} Invalid choice. Exiting."
    exit 1
fi
echo ""

# ============================================================================
# DATA DIRECTORY CHECK & AUTOMATIC CLEANUP
# ============================================================================
echo -e "${YELLOW}Checking for existing data directories...${NC}"

# In config-only mode there is no live stack, so skip all data-dir cleanup
if [[ "${SKIP_START:-false}" == "true" ]]; then
    echo -e "${GREEN}✓${NC} Config-only mode — skipping data directory cleanup"
    echo ""
fi

EXISTING_DATA=""
PRESERVED_CLIENT_SECRET=""  # Will store existing CLIENT_SECRET to preserve Authelia integration

if [[ "${SKIP_START:-false}" != "true" ]]; then
[[ -d "postgres/data" ]] && [[ "$(ls -A postgres/data 2>/dev/null)" ]] && EXISTING_DATA="${EXISTING_DATA}postgres/data "
[[ -d "synapse/data" ]] && [[ -f "synapse/data/homeserver.yaml" ]] && EXISTING_DATA="${EXISTING_DATA}synapse/data "
[[ -d "mas/data" ]] && [[ "$(ls -A mas/data 2>/dev/null)" ]] && EXISTING_DATA="${EXISTING_DATA}mas/data "
fi

if [[ -n "$EXISTING_DATA" ]]; then
    echo -e "${RED}⚠ WARNING: Existing data directories found:${NC}"
    for dir in $EXISTING_DATA; do
        echo -e "  • $dir"
    done
    echo ""
    echo -e "${YELLOW}Automatically cleaning to prevent password mismatch issues...${NC}"
    echo -e "${YELLOW}(Old database passwords won't match new deployment)${NC}"
    echo ""

    # Extract CLIENT_SECRET before cleanup to preserve Authelia integration
    if [[ -f "mas/config/config.yaml" ]]; then
        PRESERVED_CLIENT_SECRET=$(grep "client_secret:" mas/config/config.yaml | head -1 | sed "s/.*client_secret: '\(.*\)'/\1/")
        if [[ -n "$PRESERVED_CLIENT_SECRET" ]]; then
            echo -e "${GREEN}✓${NC} Found existing Authelia client_secret - will preserve it"
        fi
    fi

    # Stop all containers and remove volumes to prevent PostgreSQL password conflicts
    echo -e "${YELLOW}Stopping containers and removing volumes...${NC}"
    $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} down -v 2>/dev/null || true

    # Surgical cleanup: Only remove postgres/data (source of password mismatch)
    # Preserve synapse/data/homeserver.yaml (keeps custom mail config, etc.)
    # Preserve mas/config (keeps CLIENT_SECRET for Authelia)
    echo -e "${YELLOW}Cleaning PostgreSQL data to fix password mismatch...${NC}"
    echo -e "${GREEN}✓${NC} Preserving synapse/data/homeserver.yaml (custom configs maintained)"
    echo -e "${GREEN}✓${NC} Preserving mas/config (Authelia integration maintained)"

    # Remove bridge registration references from homeserver.yaml
    if [[ -f "synapse/data/homeserver.yaml" ]]; then
        sudo sed -i '/^  - \/bridges\//d' synapse/data/homeserver.yaml
        echo -e "${GREEN}✓${NC} Removed stale bridge registration references"
    fi

    sudo rm -rf postgres/data
    sudo rm -rf mas/data mas/certs
    sudo rm -rf caddy/data caddy/config
    sudo rm -rf bridges/*/config

    mkdir -p postgres/data synapse/data mas/data mas/certs caddy/data caddy/config
    mkdir -p bridges/telegram/config bridges/whatsapp/config bridges/signal/config

    echo -e "${GREEN}✓${NC} PostgreSQL data cleaned - custom configurations preserved"
    echo ""
else
    echo -e "${GREEN}✓${NC} No existing data found - starting with clean slate"
    echo ""
fi

# ============================================================================
# SSO / OIDC PROVIDER SELECTION
# ============================================================================
echo -e "${CYAN}Upstream SSO / OIDC provider:${NC}"
echo ""
echo -e "  ${GREEN}1)${NC} None      — MAS handles authentication directly"
echo -e "             → Simpler setup, password-based auth"
echo ""
echo -e "  ${GREEN}2)${NC} Authelia  — full SSO with 2FA"
echo -e "             → Users authenticate through Authelia"
echo -e "             → Additional auth layer with MFA policies"
echo ""
echo -e "  ${GREEN}3)${NC} Other OIDC — Authentik, Keycloak, Zitadel, etc."
echo -e "             → Any OIDC-compliant provider"
echo -e "             → No extra containers required"
echo ""
read -p "Choose [1/2/3, default: 1]: " _sso_choice

USE_AUTHELIA=false
USE_CUSTOM_OIDC=false
OIDC_ISSUER_URL=""
OIDC_CLIENT_ID=""
OIDC_CLIENT_SECRET=""

case "${_sso_choice}" in
    2)
        USE_AUTHELIA=true
        echo -e "${GREEN}✓${NC} Authelia SSO will be included"
        ;;
    3)
        USE_CUSTOM_OIDC=true
        echo ""
        read -p "OIDC issuer URL (e.g. https://auth.example.com/application/o/matrix/): " OIDC_ISSUER_URL
        read -p "OIDC client ID: " OIDC_CLIENT_ID
        read -s -p "OIDC client secret: " OIDC_CLIENT_SECRET
        echo
        echo -e "${GREEN}✓${NC} Custom OIDC provider configured"
        ;;
    *)
        echo -e "${GREEN}✓${NC} MAS will handle authentication directly"
        ;;
esac
echo ""

# ============================================================================
# ELEMENT CALL SELECTION
# ============================================================================
echo -e "${CYAN}Enable Element Call (video/voice calling)?${NC}"
echo ""
echo -e "  ${GREEN}Yes)${NC} Add LiveKit-based video/voice calls"
echo -e "       → Adds livekit + lk-jwt-service containers"
echo -e "       → Element Web will show video/voice call button"
echo -e "       → Requires ports TCP 7881 and UDP 50100-50200 open to the internet"
echo ""
echo -e "  ${GREEN}No)${NC}  Text-only Matrix stack (default)"
echo ""
read -p "Enable Element Call? [y/N]: " INCLUDE_ELEMENT_CALL

if [[ "$INCLUDE_ELEMENT_CALL" =~ ^[Yy]$ ]]; then
    USE_ELEMENT_CALL=true
    echo -e "${GREEN}✓${NC} Element Call will be enabled"
else
    USE_ELEMENT_CALL=false
    echo -e "${GREEN}✓${NC} Element Call disabled"
fi
echo ""

# ============================================================================
# FLUFFYCHAT SELECTION
# ============================================================================
echo -e "${CYAN}Enable FluffyChat (alternative Matrix web client)?${NC}"
echo ""
echo -e "  ${GREEN}Yes)${NC} Self-host FluffyChat alongside Element Web"
echo -e "       → Adds a fluffychat container"
echo -e "       → Registers FluffyChat as MAS OIDC client (fixes cross-signing reset)"
echo ""
echo -e "  ${GREEN}No)${NC}  Element Web only (default)"
echo ""
read -p "Enable FluffyChat? [y/N]: " INCLUDE_FLUFFYCHAT

if [[ "$INCLUDE_FLUFFYCHAT" =~ ^[Yy]$ ]]; then
    USE_FLUFFYCHAT=true
    echo -e "${GREEN}✓${NC} FluffyChat will be enabled"
else
    USE_FLUFFYCHAT=false
    echo -e "${GREEN}✓${NC} FluffyChat disabled"
fi
echo ""

# ============================================================================
# MONITORING SELECTION
# ============================================================================
echo -e "${CYAN}Enable Prometheus + Grafana monitoring?${NC}"
echo ""
echo -e "  ${GREEN}Yes)${NC} Adds Prometheus (metrics scraper) + Grafana (dashboard)"
echo -e "       → Synapse metrics endpoint enabled automatically"
echo -e "       → Import Synapse dashboard ID 10046 from grafana.com"
echo ""
echo -e "  ${GREEN}No)${NC}  No monitoring stack (default)"
echo ""
read -p "Enable monitoring? [y/N]: " INCLUDE_MONITORING

if [[ "$INCLUDE_MONITORING" =~ ^[Yy]$ ]]; then
    USE_MONITORING=true
    echo -e "${GREEN}✓${NC} Prometheus + Grafana will be enabled"
else
    USE_MONITORING=false
    echo -e "${GREEN}✓${NC} Monitoring disabled"
fi
echo ""

# ============================================================================
# HOOKSHOT SELECTION
# ============================================================================
echo -e "${CYAN}Enable matrix-hookshot (GitHub/GitLab/webhook integrations)?${NC}"
echo ""
echo -e "  ${GREEN}Yes)${NC} Connects Matrix rooms to GitHub, GitLab, JIRA, RSS, and generic webhooks"
echo -e "       → Registered as an appservice in Synapse"
echo -e "       → Generates hookshot/config.yaml (add GitHub/GitLab tokens manually)"
echo ""
echo -e "  ${GREEN}No)${NC}  No hookshot (default)"
echo ""
read -p "Enable hookshot? [y/N]: " INCLUDE_HOOKSHOT

if [[ "$INCLUDE_HOOKSHOT" =~ ^[Yy]$ ]]; then
    USE_HOOKSHOT=true
    echo -e "${GREEN}✓${NC} Hookshot will be enabled"
else
    USE_HOOKSHOT=false
    echo -e "${GREEN}✓${NC} Hookshot disabled"
fi
echo ""

# ============================================================================
# OPEN REGISTRATION
# ============================================================================
if [[ "$USE_AUTHELIA" == true || "$USE_CUSTOM_OIDC" == true ]]; then
    # SSO provider controls user provisioning — password registration prompt is not applicable
    OPEN_REGISTRATION=false
else
    echo -e "${CYAN}Allow open user registration?${NC}"
    echo ""
    echo -e "  ${GREEN}Yes)${NC} Anyone can create an account via the login page"
    echo -e "       → Same experience as matrix.org"
    echo -e "       ${YELLOW}⚠${NC}  Only enable if you intend a public server"
    echo ""
    echo -e "  ${GREEN}No)${NC}  Accounts must be created by an admin (default)"
    echo -e "       → Recommended for private/family servers"
    echo ""
    read -p "Allow open user registration? [y/N]: " reg_choice
    if [[ "$reg_choice" =~ ^[Yy]$ ]]; then
        OPEN_REGISTRATION=true
        echo -e "${GREEN}✓${NC} Open registration enabled"
    else
        OPEN_REGISTRATION=false
        echo -e "${GREEN}✓${NC} Registration restricted to admin-created accounts"
    fi
fi
echo ""

# ============================================================================
# DOCKER REGISTRY AND HARDENED IMAGES
# ============================================================================
echo -e "${CYAN}Docker Image Configuration:${NC}"
echo ""
read -p "Custom Docker registry prefix (leave blank for default): " DOCKER_REGISTRY_INPUT
DOCKER_REGISTRY="${DOCKER_REGISTRY_INPUT%/}"  # strip trailing slash
[ -n "$DOCKER_REGISTRY" ] && DOCKER_REGISTRY="${DOCKER_REGISTRY}/"

if [ -n "$DOCKER_REGISTRY" ]; then
    echo -e "${GREEN}✓${NC} Custom registry: ${DOCKER_REGISTRY}"
else
    echo -e "${GREEN}✓${NC} Using default registries"
fi

USE_HARDENED_IMAGES=false
read -p "Use hardened images from dhi.io for Redis/PostgreSQL/Caddy? [y/N]: " yn
[[ "$yn" =~ ^[Yy] ]] && USE_HARDENED_IMAGES=true
if [ "$USE_HARDENED_IMAGES" = true ]; then
    echo -e "${GREEN}✓${NC} Hardened images (dhi.io) enabled for Redis/PostgreSQL/Caddy"
else
    echo -e "${GREEN}✓${NC} Using standard images"
fi
echo ""

# Build image reference helper
build_image() {
    local image="$1"
    if [ -n "$DOCKER_REGISTRY" ]; then
        echo "${DOCKER_REGISTRY}${image}"
    else
        echo "${image}"
    fi
}

# Standard images (respect custom registry)
POSTGRES_IMAGE=$(build_image "postgres:16-alpine")
SYNAPSE_IMAGE=$(build_image "matrixdotorg/synapse:latest")
ELEMENT_IMAGE=$(build_image "vectorim/element-web:latest")
FLUFFYCHAT_IMAGE=$(build_image "ghcr.io/krille-chan/fluffychat:latest")
KETESA_IMAGE=$(build_image "etkecc/ketesa:latest")
MAS_IMAGE=$(build_image "ghcr.io/element-hq/matrix-authentication-service:latest")
TELEGRAM_IMAGE=$(build_image "dock.mau.dev/mautrix/telegram:latest")
WHATSAPP_IMAGE=$(build_image "dock.mau.dev/mautrix/whatsapp:latest")
SIGNAL_IMAGE=$(build_image "dock.mau.dev/mautrix/signal:latest")
DISCORD_IMAGE=$(build_image "dock.mau.dev/mautrix/discord:latest")
SLACK_IMAGE=$(build_image "dock.mau.dev/mautrix/slack:latest")
HOOKSHOT_IMAGE=$(build_image "ghcr.io/matrix-org/matrix-hookshot:latest")
PROMETHEUS_IMAGE=$(build_image "prom/prometheus:latest")
GRAFANA_IMAGE=$(build_image "grafana/grafana:latest")
LIVEKIT_IMAGE=$(build_image "livekit/livekit-server:latest")
LK_JWT_IMAGE=$(build_image "ghcr.io/element-hq/lk-jwt-service:latest")
ELEMENT_CALL_IMAGE=$(build_image "ghcr.io/element-hq/element-call:latest")
AUTHELIA_IMAGE=$(build_image "authelia/authelia:latest")

# Hardened images take priority for redis/postgres/caddy
if [ "$USE_HARDENED_IMAGES" = true ]; then
    REDIS_IMAGE="dhi.io/redis:7"
    POSTGRES_IMAGE="dhi.io/postgres:16"
    CADDY_IMAGE="dhi.io/caddy:2"
else
    REDIS_IMAGE=$(build_image "redis:7-alpine")
    CADDY_IMAGE=$(build_image "caddy:2-alpine")
fi

# Function to generate secure random string (32 bytes base64)
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Function to generate secure hex string (for MAS encryption)
generate_hex_secret() {
    openssl rand -hex 32
}

# Function to print status
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# ============================================================================
# DOMAIN AND CONFIGURATION PROMPTS
# ============================================================================
if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
    # Local testing with example.test domains (not .localhost - it's on the public suffix list!)
    DOMAIN_BASE="example.test"
    AUTHELIA_COOKIE_DOMAIN="example.test"  # No leading dot for cookie domain
    MATRIX_DOMAIN="matrix.example.test"
    ELEMENT_DOMAIN="element.example.test"
    ADMIN_DOMAIN="admin.example.test"
    AUTH_DOMAIN="auth.example.test"
    AUTHELIA_DOMAIN="authelia.example.test"
    FLUFFYCHAT_DOMAIN="chat.example.test"
    MONITORING_DOMAIN="monitoring.example.test"
    HOOKSHOT_DOMAIN="hooks.example.test"
    RTC_DOMAIN="rtc.example.test"
    CALL_DOMAIN="call.example.test"

    # Matrix server name (MXID identity domain)
    echo ""
    echo -e "${CYAN}Matrix User ID format:${NC}"
    echo -e "  [1] Short:     @user:${DOMAIN_BASE}  ← recommended"
    echo -e "  [2] Subdomain: @user:${MATRIX_DOMAIN}"
    read -p "Choose [1/2, default: 1]: " _sn_choice
    if [[ "$_sn_choice" == "2" ]]; then
        SERVER_NAME="${MATRIX_DOMAIN}"
    else
        SERVER_NAME="${DOMAIN_BASE}"
    fi

    echo -e "${CYAN}Local Testing Configuration:${NC}"
    echo -e "  Matrix API:  https://${MATRIX_DOMAIN}"
    echo -e "  Element Web: https://${ELEMENT_DOMAIN}"
    echo -e "  MAS Auth:    https://${AUTH_DOMAIN}"
    echo -e "  Authelia:    https://${AUTHELIA_DOMAIN}"
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        echo -e "  Element Call: https://${CALL_DOMAIN}"
        echo -e "  LiveKit RTC:  https://${RTC_DOMAIN}"
    fi
    echo ""
    HOSTS_DOMAINS="${MATRIX_DOMAIN} ${ELEMENT_DOMAIN} ${AUTH_DOMAIN} ${AUTHELIA_DOMAIN}"
    if [[ "$SERVER_NAME" != "$MATRIX_DOMAIN" ]]; then
        HOSTS_DOMAINS="${SERVER_NAME} ${HOSTS_DOMAINS}"
    fi
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        HOSTS_DOMAINS="${HOSTS_DOMAINS} ${RTC_DOMAIN} ${CALL_DOMAIN}"
    fi
    echo -e "${YELLOW}⚠ Remember to add these to /etc/hosts:${NC}"
    echo -e "  127.0.0.1  ${HOSTS_DOMAINS}"
    echo -e "  ::1        ${HOSTS_DOMAINS}"
    echo ""
    echo -e "${BLUE}ℹ Note: IPv6 entry (::1) required to prevent DNS lookups bypassing /etc/hosts${NC}"
    echo ""
    read -p "Press Enter to continue..."
    echo ""

else
    # Production deployment (single-server or distributed)
    echo -e "${CYAN}Production Deployment Configuration${NC}"
    echo ""

    # Base domain
    read -p "Enter your base domain (e.g., example.com): " DOMAIN_BASE
    AUTHELIA_COOKIE_DOMAIN="${DOMAIN_BASE}"

    # Matrix subdomain
    read -p "Enter Matrix subdomain [default: matrix]: " MATRIX_SUBDOMAIN
    MATRIX_SUBDOMAIN=${MATRIX_SUBDOMAIN:-matrix}
    MATRIX_DOMAIN="${MATRIX_SUBDOMAIN}.${DOMAIN_BASE}"

    # Element subdomain
    read -p "Enter Element subdomain [default: element]: " ELEMENT_SUBDOMAIN
    ELEMENT_SUBDOMAIN=${ELEMENT_SUBDOMAIN:-element}
    ELEMENT_DOMAIN="${ELEMENT_SUBDOMAIN}.${DOMAIN_BASE}"

    # Ketesa subdomain
    read -p "Enter Ketesa (admin panel) subdomain [default: admin]: " ADMIN_SUBDOMAIN
    ADMIN_SUBDOMAIN=${ADMIN_SUBDOMAIN:-admin}
    ADMIN_DOMAIN="${ADMIN_SUBDOMAIN}.${DOMAIN_BASE}"

    # FluffyChat subdomain
    if [[ "$USE_FLUFFYCHAT" == true ]]; then
        read -p "Enter FluffyChat subdomain [default: chat]: " FLUFFYCHAT_SUBDOMAIN
        FLUFFYCHAT_SUBDOMAIN=${FLUFFYCHAT_SUBDOMAIN:-chat}
        FLUFFYCHAT_DOMAIN="${FLUFFYCHAT_SUBDOMAIN}.${DOMAIN_BASE}"
    fi

    # Monitoring subdomain
    if [[ "$USE_MONITORING" == true ]]; then
        read -p "Enter Grafana subdomain [default: monitoring]: " MONITORING_SUBDOMAIN
        MONITORING_SUBDOMAIN=${MONITORING_SUBDOMAIN:-monitoring}
        MONITORING_DOMAIN="${MONITORING_SUBDOMAIN}.${DOMAIN_BASE}"
    fi

    # Hookshot subdomain
    if [[ "$USE_HOOKSHOT" == true ]]; then
        read -p "Enter hookshot webhook subdomain [default: hooks]: " HOOKSHOT_SUBDOMAIN
        HOOKSHOT_SUBDOMAIN=${HOOKSHOT_SUBDOMAIN:-hooks}
        HOOKSHOT_DOMAIN="${HOOKSHOT_SUBDOMAIN}.${DOMAIN_BASE}"
    fi

    # MAS subdomain
    read -p "Enter MAS/Auth subdomain [default: auth]: " AUTH_SUBDOMAIN
    AUTH_SUBDOMAIN=${AUTH_SUBDOMAIN:-auth}
    AUTH_DOMAIN="${AUTH_SUBDOMAIN}.${DOMAIN_BASE}"

    # Authelia subdomain
    read -p "Enter Authelia subdomain [default: authelia]: " AUTHELIA_SUBDOMAIN
    AUTHELIA_SUBDOMAIN=${AUTHELIA_SUBDOMAIN:-authelia}
    AUTHELIA_DOMAIN="${AUTHELIA_SUBDOMAIN}.${DOMAIN_BASE}"

    # RTC subdomain (LiveKit signaling) + Call subdomain (Element Call frontend)
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        read -p "Enter RTC subdomain for LiveKit [default: rtc]: " RTC_SUBDOMAIN
        RTC_SUBDOMAIN=${RTC_SUBDOMAIN:-rtc}
        RTC_DOMAIN="${RTC_SUBDOMAIN}.${DOMAIN_BASE}"
        read -p "Enter subdomain for Element Call frontend [default: call]: " CALL_SUBDOMAIN
        CALL_SUBDOMAIN=${CALL_SUBDOMAIN:-call}
        CALL_DOMAIN="${CALL_SUBDOMAIN}.${DOMAIN_BASE}"
    fi

    # Matrix server name (MXID identity domain)
    echo ""
    echo -e "${CYAN}Matrix User ID format:${NC}"
    echo -e "  [1] Short:     @user:${DOMAIN_BASE}  ← recommended"
    echo -e "  [2] Subdomain: @user:${MATRIX_DOMAIN}"
    read -p "Choose [1/2, default: 1]: " _sn_choice
    if [[ "$_sn_choice" == "2" ]]; then
        SERVER_NAME="${MATRIX_DOMAIN}"
    else
        SERVER_NAME="${DOMAIN_BASE}"
    fi

    if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
        echo ""
        echo -e "${CYAN}Backend Server Addresses (for Caddyfile):${NC}"
        echo -e "  ${YELLOW}Enter IP addresses or hostnames${NC}"
        echo ""

        # Matrix server address (IP or hostname)
        read -p "Matrix server address (IP or hostname): " MATRIX_SERVER_IP
        MATRIX_SERVER_IP=${MATRIX_SERVER_IP:-10.0.1.10}

        # Authelia server address (IP or hostname)
        read -p "Authelia server address (IP or hostname): " AUTHELIA_SERVER_IP
        AUTHELIA_SERVER_IP=${AUTHELIA_SERVER_IP:-10.0.1.20}
    fi

    # Email for Let's Encrypt (both production modes)
    read -p "Email for Let's Encrypt [default: admin@${DOMAIN_BASE}]: " LETSENCRYPT_EMAIL
    LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL:-admin@${DOMAIN_BASE}}

    echo ""
    echo -e "${GREEN}✓${NC} Configuration Summary:"
    echo -e "  Base Domain:  ${DOMAIN_BASE}"
    echo -e "  Server Name:  ${SERVER_NAME}  (@user:${SERVER_NAME})"
    echo -e "  Matrix:       https://${MATRIX_DOMAIN}"
    echo -e "  Element:      https://${ELEMENT_DOMAIN}"
    echo -e "  MAS:          https://${AUTH_DOMAIN}"
    if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
        echo -e "  Authelia:     https://${AUTHELIA_DOMAIN}"
    fi
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        echo -e "  Element Call: https://${CALL_DOMAIN}"
        echo -e "  LiveKit RTC:  https://${RTC_DOMAIN}"
    fi
    if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
        echo -e "  Matrix Backend:   ${MATRIX_SERVER_IP}"
        echo -e "  Authelia Backend: ${AUTHELIA_SERVER_IP}"
        print_info "Note: Generated Caddyfile will use these backend addresses"
        print_info "      Copy generated configs from authelia/config/ to your Authelia server"
    fi
    echo ""
fi

# Ensure FLUFFYCHAT_DOMAIN is always set (needed for MAS client entry even when service is disabled)
FLUFFYCHAT_DOMAIN="${FLUFFYCHAT_DOMAIN:-chat.${DOMAIN_BASE}}"

# Step 1: Check prerequisites
echo -e "${BLUE}[1/13] Checking prerequisites...${NC}"
if ! command -v openssl &> /dev/null; then
    print_error "openssl is not installed"
    exit 1
fi
if [[ "${SKIP_START:-false}" != "true" ]] && ! $DOCKER_CMD --version &> /dev/null; then
    print_error "Docker is not accessible"
    exit 1
fi
if [[ "${SKIP_START:-false}" != "true" ]] && command -v curl &> /dev/null; then
    print_info "Checking container registry connectivity..."
    # An HTTP response (even 401 — anonymous /v2/ probes are unauthorized by
    # design) means the registry is reachable. Only "000" (curl couldn't
    # complete the request at all: DNS/TCP/TLS/timeout failure) means it isn't.
    _registry_code=$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' https://registry-1.docker.io/v2/ 2>/dev/null); _registry_code="${_registry_code:-000}"
    _ghcr_code=$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' https://ghcr.io/v2/ 2>/dev/null); _ghcr_code="${_ghcr_code:-000}"
    if [[ "$_registry_code" == "000" ]] && [[ "$_ghcr_code" == "000" ]]; then
        print_error "Cannot reach Docker Hub (registry-1.docker.io) or GitHub Container Registry (ghcr.io)."
        print_error "This deployment needs to pull several container images. Check your network"
        print_error "connection, firewall, or proxy settings (e.g. /etc/environment and the Docker"
        print_error "daemon's proxy config) before re-running this script."
        exit 1
    fi
fi
print_status "Prerequisites OK"
echo ""

# Step 1.5: Create directory structure
echo -e "${BLUE}[1.5/13] Creating directory structure...${NC}"
mkdir -p authelia/config
mkdir -p mas/config mas/data mas/certs
mkdir -p element/config
mkdir -p synapse/data
mkdir -p postgres/data
mkdir -p caddy/data caddy/config
mkdir -p bridges/{telegram,whatsapp,signal,discord,slack}/config
mkdir -p appservices
mkdir -p prometheus/rules
mkdir -p grafana/provisioning/{datasources,dashboards,dashboards/json}
mkdir -p hookshot
print_status "Directory structure created"
echo ""

# Step 1.5 (cont.): Ensure livekit directory exists with correct ownership
mkdir -p livekit
sudo chown "$(id -u):$(id -g)" livekit 2>/dev/null || true

# Step 2: Generate secure secrets
echo -e "${BLUE}[2/12] Generating secure secrets...${NC}"
POSTGRES_PASSWORD=$(generate_secret)
AUTHELIA_JWT_SECRET=$(generate_secret)
AUTHELIA_SESSION_SECRET=$(generate_secret)
AUTHELIA_STORAGE_ENCRYPTION_KEY=$(generate_secret)
MAS_SECRET_KEY=$(generate_hex_secret)  # MAS requires hex format
SYNAPSE_SHARED_SECRET=$(generate_secret)
DOUBLEPUPPET_AS_TOKEN=$(generate_hex_secret)
DOUBLEPUPPET_HS_TOKEN=$(generate_hex_secret)
if [[ "$USE_ELEMENT_CALL" == true ]]; then
    LIVEKIT_SECRET=$(generate_hex_secret)
fi
print_status "Secrets generated"
echo ""

# Step 3: Update .env file
echo -e "${BLUE}[3/13] Updating .env file with generated secrets...${NC}"
cat > .env << EOF
# Matrix Stack Environment Variables
# Auto-generated by deploy.sh on $(date)
# Deployment Mode: ${DEPLOYMENT_MODE}

# Domain Configuration
DOMAIN_BASE=${DOMAIN_BASE}
MATRIX_DOMAIN=${MATRIX_DOMAIN}
ELEMENT_DOMAIN=${ELEMENT_DOMAIN}
ADMIN_DOMAIN=${ADMIN_DOMAIN}
AUTH_DOMAIN=${AUTH_DOMAIN}
AUTHELIA_DOMAIN=${AUTHELIA_DOMAIN}
FLUFFYCHAT_DOMAIN=${FLUFFYCHAT_DOMAIN:-}
MONITORING_DOMAIN=${MONITORING_DOMAIN:-}
HOOKSHOT_DOMAIN=${HOOKSHOT_DOMAIN:-}
SERVER_NAME=${SERVER_NAME}
USE_FLUFFYCHAT=${USE_FLUFFYCHAT}
USE_MONITORING=${USE_MONITORING}
USE_HOOKSHOT=${USE_HOOKSHOT}

# PostgreSQL
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Synapse
SYNAPSE_REPORT_STATS=no
SYNAPSE_SHARED_SECRET=${SYNAPSE_SHARED_SECRET}

# Authelia
AUTHELIA_JWT_SECRET=${AUTHELIA_JWT_SECRET}
AUTHELIA_SESSION_SECRET=${AUTHELIA_SESSION_SECRET}
AUTHELIA_STORAGE_ENCRYPTION_KEY=${AUTHELIA_STORAGE_ENCRYPTION_KEY}
AUTHELIA_POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# MAS
MAS_DATABASE_URL=postgresql://synapse:${POSTGRES_PASSWORD}@postgres/mas
MAS_SECRET_KEY=${MAS_SECRET_KEY}

# Timezone
TZ=${TZ:-Europe/Berlin}

# Docker images
POSTGRES_IMAGE=${POSTGRES_IMAGE}
SYNAPSE_IMAGE=${SYNAPSE_IMAGE}
ELEMENT_IMAGE=${ELEMENT_IMAGE}
FLUFFYCHAT_IMAGE=${FLUFFYCHAT_IMAGE}
KETESA_IMAGE=${KETESA_IMAGE}
REDIS_IMAGE=${REDIS_IMAGE}
MAS_IMAGE=${MAS_IMAGE}
TELEGRAM_IMAGE=${TELEGRAM_IMAGE}
WHATSAPP_IMAGE=${WHATSAPP_IMAGE}
SIGNAL_IMAGE=${SIGNAL_IMAGE}
DISCORD_IMAGE=${DISCORD_IMAGE}
SLACK_IMAGE=${SLACK_IMAGE}
HOOKSHOT_IMAGE=${HOOKSHOT_IMAGE}
PROMETHEUS_IMAGE=${PROMETHEUS_IMAGE}
GRAFANA_IMAGE=${GRAFANA_IMAGE}
LIVEKIT_IMAGE=${LIVEKIT_IMAGE}
LK_JWT_IMAGE=${LK_JWT_IMAGE}
ELEMENT_CALL_IMAGE=${ELEMENT_CALL_IMAGE}
AUTHELIA_IMAGE=${AUTHELIA_IMAGE}
CADDY_IMAGE=${CADDY_IMAGE}
EOF

# Add production-specific variables
if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
    cat >> .env << EOF

# Production Configuration (Backend addresses for Caddyfile generation)
# These are used in the generated caddy/Caddyfile.production template
MATRIX_SERVER_IP=${MATRIX_SERVER_IP}
AUTHELIA_SERVER_IP=${AUTHELIA_SERVER_IP}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
EOF
fi

# Add Element Call variables
if [[ "$USE_ELEMENT_CALL" == true ]]; then
    cat >> .env << EOF

# Element Call (LiveKit + self-hosted frontend)
RTC_DOMAIN=${RTC_DOMAIN}
CALL_DOMAIN=${CALL_DOMAIN}
LIVEKIT_SECRET=${LIVEKIT_SECRET}
EOF
fi

# Add custom OIDC variables
if [[ "$USE_CUSTOM_OIDC" == true ]]; then
    cat >> .env << EOF

# Custom OIDC provider (configured via deploy.sh)
OIDC_ISSUER_URL=${OIDC_ISSUER_URL}
OIDC_CLIENT_ID=${OIDC_CLIENT_ID}
OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}
EOF
fi

# Telegram bridge credentials placeholder (obtain from https://my.telegram.org)
if ! grep -q "TELEGRAM_API_ID" .env 2>/dev/null; then
    cat >> .env << 'ENVEOF'

# Telegram Bridge — obtain API credentials at https://my.telegram.org (Apps tab)
# Uncomment and fill in before running setup-bridges.sh to enable Telegram
# TELEGRAM_API_ID=your_api_id
# TELEGRAM_API_HASH=your_api_hash
ENVEOF
fi

print_status ".env file updated"
echo ""

# Conditional: Authelia configuration (Steps 4-8)
if [[ "$USE_AUTHELIA" == true ]]; then
    # Step 4: Generate RSA key for Authelia
    echo -e "${BLUE}[4/13] Generating RSA key for Authelia OIDC...${NC}"
    openssl genrsa -out authelia_private.pem 4096 2>/dev/null
    AUTHELIA_RSA_KEY=$(cat authelia_private.pem)
    print_status "Authelia RSA key generated"
    echo ""

    # Step 5: Generate or reuse client secret for Authelia
    echo -e "${BLUE}[5/13] Configuring Authelia client secret...${NC}"
    if [[ -n "$PRESERVED_CLIENT_SECRET" ]]; then
        # Reuse preserved secret to maintain Authelia integration
        CLIENT_SECRET_PLAIN="$PRESERVED_CLIENT_SECRET"
        CLIENT_SECRET_HASH=$($DOCKER_CMD run --rm authelia/authelia:latest authelia crypto hash generate pbkdf2 --variant sha512 --password "${CLIENT_SECRET_PLAIN}" 2>/dev/null | grep "Digest:" | awk '{print $2}')
        print_status "Reusing preserved client secret (Authelia integration maintained)"
    else
        # Generate new secret
        CLIENT_SECRET_PLAIN=$(generate_secret)
        CLIENT_SECRET_HASH=$($DOCKER_CMD run --rm authelia/authelia:latest authelia crypto hash generate pbkdf2 --variant sha512 --password "${CLIENT_SECRET_PLAIN}" 2>/dev/null | grep "Digest:" | awk '{print $2}')
        print_status "Client secret generated"
    fi
    echo ""

    # Step 6: Generate password hash for default admin user
    echo -e "${BLUE}[6/13] Generating default admin user...${NC}"
    ADMIN_PASSWORD=$(generate_secret)  # Generate secure random password
    ADMIN_PASSWORD_HASH=$($DOCKER_CMD run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password "${ADMIN_PASSWORD}" 2>/dev/null | grep "Digest:" | awk '{print $2}')
    print_status "Admin user password hash generated"
    print_warning "Default admin password: ${ADMIN_PASSWORD} (SAVE THIS - you'll need it to log in!)"
    echo ""

    # Step 7: Update Authelia configuration
echo -e "${BLUE}[7/12] Configuring Authelia...${NC}"
cat > authelia/config/configuration.yml << EOF
---
# Authelia Configuration for Matrix Stack

theme: auto

server:
  address: 'tcp://0.0.0.0:9091'

log:
  level: 'info'
  format: 'text'

authentication_backend:
  file:
    path: '/config/users_database.yml'
    password:
      algorithm: 'argon2'
      argon2:
        variant: 'argon2id'
        iterations: 3
        memory: 65536
        parallelism: 4
        key_length: 32
        salt_length: 16

session:
  secret: '${AUTHELIA_SESSION_SECRET}'
  cookies:
    - domain: '${AUTHELIA_COOKIE_DOMAIN}'
      authelia_url: 'https://${AUTHELIA_DOMAIN}'
      default_redirection_url: 'https://${ELEMENT_DOMAIN}'

  redis:
    host: 'redis'
    port: 6379

storage:
  encryption_key: '${AUTHELIA_STORAGE_ENCRYPTION_KEY}'
  postgres:
    address: 'tcp://postgres:5432'
    database: 'authelia'
    username: 'synapse'
    password: '${POSTGRES_PASSWORD}'

notifier:
  filesystem:
    filename: '/config/notification.txt'

identity_validation:
  reset_password:
    jwt_secret: '${AUTHELIA_JWT_SECRET}'

access_control:
  default_policy: 'deny'
  rules:
    - domain:
        - 'matrix.localhost'
      policy: 'two_factor'
    - domain:
        - 'element.matrix.localhost'
      policy: 'two_factor'

identity_providers:
  oidc:
    hmac_secret: '${AUTHELIA_JWT_SECRET}'
    jwks:
      - key_id: 'main'
        algorithm: 'RS256'
        use: 'sig'
        key: |
EOF

# Add the RSA key with proper indentation
echo "$AUTHELIA_RSA_KEY" | sed 's/^/          /' >> authelia/config/configuration.yml

# Continue with the rest of the config
cat >> authelia/config/configuration.yml << EOF
    clients:
      - client_id: 'mas-client'
        client_name: 'Matrix Authentication Service'
        client_secret: '${CLIENT_SECRET_HASH}'
        public: false
        authorization_policy: 'one_factor'    # Change to two_factor in production!
        redirect_uris:
          - 'https://${AUTH_DOMAIN}/callback'
          - 'https://${AUTH_DOMAIN}/oauth2/callback'
          - 'https://${AUTH_DOMAIN}/upstream/callback/01HQW90Z35CMXFJWQPHC3BGZGQ'  # MAS upstream callback
        scopes:
          - 'openid'
          - 'profile'
          - 'email'
          - 'offline_access'
        grant_types:
          - 'authorization_code'
          - 'refresh_token'
        response_types:
          - 'code'
        token_endpoint_auth_method: 'client_secret_basic'
EOF

print_status "Authelia configuration updated"
echo ""

    # Step 8: Create Authelia users database
    echo -e "${BLUE}[8/13] Creating Authelia users database...${NC}"
    cat > authelia/config/users_database.yml << EOF
---
# Authelia Users Database

users:
  admin:
    displayname: "Admin User"
    password: "${ADMIN_PASSWORD_HASH}"
    email: admin@${MATRIX_DOMAIN}
    groups:
      - admins
      - users
EOF

    print_status "Authelia users database created"
    echo ""
else
    print_info "Skipping Authelia configuration (not included in deployment)"
    echo ""
fi

# Step 9: Generate MAS signing key and Synapse client secret
echo -e "${BLUE}[9/12] Generating MAS signing key and Synapse client secret...${NC}"
openssl genrsa 4096 2>/dev/null | openssl pkcs8 -topk8 -nocrypt > mas-signing.key 2>/dev/null
MAS_SIGNING_KEY=$(cat mas-signing.key)
SYNAPSE_CLIENT_SECRET=$(generate_secret)
print_status "MAS signing key and Synapse client secret generated"
echo ""

# Step 10: Configure MAS
echo -e "${BLUE}[10/12] Configuring MAS...${NC}"
cat > mas/config/config.yaml << EOF
---
# Matrix Authentication Service (MAS) Configuration

http:
  listeners:
    - name: web
      resources:
        - name: discovery
        - name: human
        - name: oauth
        - name: compat
        - name: graphql
          playground: true
        - name: assets    # Required for CSS/JS files
        - name: adminapi
      binds:
        - address: '[::]:8080'
    - name: internal
      resources:
        - name: health
      binds:
        - address: '127.0.0.1:8081'

  public_base: 'https://${AUTH_DOMAIN}/'
  issuer: 'https://${AUTH_DOMAIN}/'

database:
  uri: 'postgresql://synapse:${POSTGRES_PASSWORD}@postgres/mas'
  auto_migrate: true

secrets:
  encryption: '${MAS_SECRET_KEY}'
  keys:
    - kid: 'key-1'
      algorithm: rs256
      key: |
EOF

# Add the MAS signing key with proper indentation
echo "$MAS_SIGNING_KEY" | sed 's/^/        /' >> mas/config/config.yaml

# Continue with the rest of the MAS config - conditional based on Authelia usage
if [[ "$USE_AUTHELIA" == true ]]; then
    # With Authelia: Use upstream OAuth2 provider
    # Set discovery URL based on deployment mode
    if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
        AUTHELIA_DISCOVERY_URL="https://${AUTHELIA_DOMAIN}/.well-known/openid-configuration"
    else
        # Local: Use internal HTTP to avoid self-signed cert issues between containers
        AUTHELIA_DISCOVERY_URL="http://authelia:9091/.well-known/openid-configuration"
    fi

    cat >> mas/config/config.yaml << EOF

upstream_oauth2:
  providers:
    - id: '01HQW90Z35CMXFJWQPHC3BGZGQ'
      issuer: 'https://${AUTHELIA_DOMAIN}'
      discovery_url: '${AUTHELIA_DISCOVERY_URL}'
      client_id: 'mas-client'
      client_secret: '${CLIENT_SECRET_PLAIN}'
      scope: 'openid profile email offline_access'
      token_endpoint_auth_method: 'client_secret_basic'
      fetch_userinfo: true    # Critical: Must fetch userinfo for Authelia claims
      claims_imports:
        localpart:
          action: force
          template: '{{ user.preferred_username }}'  # Works with Authelia
        displayname:
          action: suggest
          template: '{{ user.preferred_username }}'  # Authelia provides preferred_username, not name
        email:
          action: force
          template: '{{ user.email }}'
          set_email_verification: always

matrix:
  homeserver: '${SERVER_NAME}'
  endpoint: 'http://synapse:8008'
  secret: '${SYNAPSE_SHARED_SECRET}'

passwords:
  enabled: false

account:
  password_registration_enabled: false
  password_change_allowed: true
  password_recovery_enabled: false
  account_deactivation_allowed: true
EOF
elif [[ "$USE_CUSTOM_OIDC" == true ]]; then
    # With custom OIDC: Use external upstream OAuth2 provider
    cat >> mas/config/config.yaml << EOF

upstream_oauth2:
  providers:
    - id: '01HQW90Z35CMXFJWQPHC3BGZGQ'
      issuer: '${OIDC_ISSUER_URL}'
      client_id: '${OIDC_CLIENT_ID}'
      client_secret: '${OIDC_CLIENT_SECRET}'
      scope: 'openid profile email offline_access'
      token_endpoint_auth_method: 'client_secret_basic'
      fetch_userinfo: true
      claims_imports:
        localpart:
          action: force
          template: '{{ user.preferred_username }}'
        displayname:
          action: suggest
          template: '{{ user.name | default(user.preferred_username) }}'
        email:
          action: force
          template: '{{ user.email }}'
          set_email_verification: always

matrix:
  homeserver: '${SERVER_NAME}'
  endpoint: 'http://synapse:8008'
  secret: '${SYNAPSE_SHARED_SECRET}'

passwords:
  enabled: false

account:
  password_registration_enabled: false
  password_change_allowed: true
  password_recovery_enabled: false
  account_deactivation_allowed: true
EOF
else
    # Without SSO: MAS handles authentication directly
    cat >> mas/config/config.yaml << EOF

matrix:
  homeserver: '${SERVER_NAME}'
  endpoint: 'http://synapse:8008'
  secret: '${SYNAPSE_SHARED_SECRET}'

passwords:
  enabled: true
  minimum_complexity: 3
  schemes:
    - version: 1
      algorithm: argon2id

account:
  password_registration_enabled: ${OPEN_REGISTRATION}
  password_registration_email_required: false
  password_change_allowed: true
  password_recovery_enabled: false
  account_deactivation_allowed: true
EOF
fi

# Common configuration continues (email, branding, policy, clients)
cat >> mas/config/config.yaml << EOF

email:
  from: '"Matrix Authentication Service" <noreply@matrix.localhost>'
  reply_to: '"Matrix Support" <support@matrix.localhost>'
  transport: smtp
  hostname: 'localhost'
  port: 25
  mode: plain

branding:
  service_name: 'Matrix'
  policy_uri: 'https://${AUTH_DOMAIN}/privacy'
  tos_uri: 'https://${AUTH_DOMAIN}/terms'

policy:
  data:
    registration:
      enabled: ${OPEN_REGISTRATION}

clients:
  # Element Web client (public)
  - client_id: '01HQW90Z35CMXFJWQPHC3BGZGQ'
    client_auth_method: none
    redirect_uris:
      - 'https://${ELEMENT_DOMAIN}'
      - 'https://${ELEMENT_DOMAIN}/mobile_guide/'
      - 'io.element.app:/callback'
      - 'http://localhost'
      - 'http://127.0.0.1'

  # FluffyChat (public client — web + native apps)
  - client_id: '01FFCHAT00000000000000FC00'
    client_auth_method: none
    redirect_uris:
      - 'https://${FLUFFYCHAT_DOMAIN}'
      - 'https://${FLUFFYCHAT_DOMAIN}/'
      - 'im.fluffychat://login'

  # Synapse client (confidential - for backend integration)
  - client_id: '0000000000000000000SYNAPSE'
    client_auth_method: client_secret_basic
    client_secret: '${SYNAPSE_CLIENT_SECRET}'
EOF

if [[ "$USE_AUTHELIA" == true ]]; then
    print_status "MAS configuration created (with Authelia upstream provider)"
elif [[ "$USE_CUSTOM_OIDC" == true ]]; then
    print_status "MAS configuration created (with custom OIDC provider: ${OIDC_ISSUER_URL})"
else
    print_status "MAS configuration created (password authentication enabled)"
fi
echo ""

# Step 11: Create Element Web configuration
echo -e "${BLUE}[11/13] Creating Element Web configuration...${NC}"

# Build Element Call block if enabled
if [[ "$USE_ELEMENT_CALL" == true ]]; then
    ELEMENT_CALL_FEATURES=',
        "feature_element_call_video_rooms": true'
    ELEMENT_CALL_BLOCK=',
    "element_call": {
        "url": "https://'"${CALL_DOMAIN}"'",
        "brand": "Element Call"
    }'
else
    ELEMENT_CALL_FEATURES=''
    ELEMENT_CALL_BLOCK=''
fi

cat > element/config/config.json << EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://${MATRIX_DOMAIN}",
            "server_name": "${SERVER_NAME}"
        }
    },
    "brand": "Element",
    "integrations_ui_url": "https://scalar.vector.im/",
    "integrations_rest_url": "https://scalar.vector.im/api",
    "integrations_widgets_urls": [
        "https://scalar.vector.im/_matrix/integrations/v1",
        "https://scalar.vector.im/api"
    ],
    "show_labs_settings": true,
    "piwik": false,
    "room_directory": {
        "servers": [
            "matrix.org",
            "${MATRIX_DOMAIN}"
        ]
    },
    "features": {
        "feature_oidc_aware_navigation": true${ELEMENT_CALL_FEATURES}
    },
    "default_server_name": "${SERVER_NAME}",
    "disable_custom_urls": false,
    "disable_guests": true${ELEMENT_CALL_BLOCK}
}
EOF
print_status "Element Web configuration created"
echo ""

# Step 11.1: Create FluffyChat config (if enabled)
if [[ "$USE_FLUFFYCHAT" == true ]]; then
    echo -e "${BLUE}[11.1/13] Creating FluffyChat configuration...${NC}"
    mkdir -p fluffychat
    cat > fluffychat/config.json << EOF
{
    "default_homeserver": "${SERVER_NAME}",
    "homeserver_list": [
        {
            "name": "${SERVER_NAME}",
            "server_url": "https://${MATRIX_DOMAIN}",
            "isDefault": true
        }
    ]
}
EOF
    print_status "FluffyChat configuration created"
    echo ""
fi

# Step 11.2: Create Prometheus + Grafana config (if monitoring enabled)
if [[ "$USE_MONITORING" == true ]]; then
    echo -e "${BLUE}[11.2/13] Creating Prometheus + Grafana configuration...${NC}"

    cat > prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: synapse
    static_configs:
      - targets: ['synapse:9000']
EOF

    # Download Synapse recording rules (required for the official Grafana dashboard)
    if curl -sf --max-time 10 \
        "https://raw.githubusercontent.com/element-hq/synapse/develop/contrib/grafana/synapse.rules.yml" \
        -o prometheus/rules/synapse.rules.yml 2>/dev/null; then
        print_status "Synapse recording rules downloaded"
    else
        print_warning "Could not download Synapse recording rules — some Grafana panels may be empty"
        print_info "  Download manually from: https://github.com/element-hq/synapse/blob/develop/contrib/grafana/synapse.rules.yml"
    fi

    cat > grafana/provisioning/datasources/prometheus.yaml << EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
EOF

    cat > grafana/provisioning/dashboards/dashboard.yaml << EOF
apiVersion: 1
providers:
  - name: Synapse
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards/json
EOF

    # Download official Synapse Grafana dashboard (ID 10046)
    if curl -sf --max-time 15 \
        "https://grafana.com/api/dashboards/10046/revisions/latest/download" \
        -o grafana/provisioning/dashboards/json/synapse.json 2>/dev/null; then
        print_status "Synapse Grafana dashboard downloaded (ID 10046)"
    else
        print_warning "Could not download Synapse Grafana dashboard"
        print_info "  Import manually in Grafana: Dashboards → Import → ID 10046"
    fi

    print_status "Prometheus + Grafana configuration created"
    echo ""
fi

# Step 11.3: Create hookshot config (if hookshot enabled)
if [[ "$USE_HOOKSHOT" == true ]]; then
    echo -e "${BLUE}[11.3/13] Creating hookshot configuration...${NC}"

    HOOKSHOT_AS_TOKEN=$(generate_hex_secret)
    HOOKSHOT_HS_TOKEN=$(generate_hex_secret)

    cat > hookshot/config.yaml << EOF
# matrix-hookshot configuration
# Full docs: https://matrix-org.github.io/matrix-hookshot/
#
# After starting, use the Hookshot bot in a Matrix room:
#   !hookshot setup webhook <name>   (generic webhook)
#   !hookshot github project ...     (GitHub — add OAuth app credentials below first)

bridge:
  domain: ${SERVER_NAME}
  url: http://synapse:8008
  mediaUrl: https://${MATRIX_DOMAIN}
  port: 9993
  bindAddress: 0.0.0.0

logging:
  level: info
  colorize: true
  json: false
  timestampFormat: HH:mm:ss:SSS

permissions:
  - actor: "${SERVER_NAME}"
    services:
      - service: "*"
        level: admin

generic:
  enabled: true
  urlPrefix: https://${HOOKSHOT_DOMAIN}/
  userIdPrefix: _webhooks_
  allowJsTransformationFunctions: false
  waitForComplete: false
  showHttpBody: false

metrics:
  enabled: true

listeners:
  - port: 9000
    bindAddress: 0.0.0.0
    resources:
      - webhooks
      - metrics

# ── Optional integrations ──────────────────────────────────────────────────
# Uncomment and fill in to enable GitHub/GitLab/JIRA/RSS integrations.

# github:
#   auth:
#     id: YOUR_GITHUB_APP_ID
#     privateKeyFile: /data/github-key.pem
#   webhook:
#     secret: GENERATE_A_RANDOM_SECRET
#   oauth:
#     client_id: YOUR_GITHUB_OAUTH_CLIENT_ID
#     client_secret: YOUR_GITHUB_OAUTH_CLIENT_SECRET
#     redirect_uri: https://${HOOKSHOT_DOMAIN}/oauth

# gitlab:
#   instances:
#     gitlab.com:
#       url: https://gitlab.com

# feeds:
#   enabled: true
#   pollIntervalSeconds: 600

# jira:
#   webhook:
#     secret: GENERATE_A_RANDOM_SECRET
EOF
    chmod 644 hookshot/config.yaml

    cat > hookshot/registration.yaml << EOF
id: hookshot
url: http://hookshot:9993
as_token: ${HOOKSHOT_AS_TOKEN}
hs_token: ${HOOKSHOT_HS_TOKEN}
sender_localpart: hookshot
rate_limited: false
de.sorunome.msc2409.push_ephemeral: true
push_ephemeral: true
namespaces:
  users:
    - regex: "@_webhooks_.*:${SERVER_NAME}"
      exclusive: true
  aliases: []
  rooms: []
EOF
    cp hookshot/registration.yaml appservices/hookshot.yaml
    print_status "Hookshot configuration created (hookshot/config.yaml)"
    print_info "  Add GitHub/GitLab tokens to hookshot/config.yaml before using those integrations"
    echo ""
fi

# Step 11.5: Create LiveKit config (if Element Call enabled)
if [[ "$USE_ELEMENT_CALL" == true ]]; then
    echo -e "${BLUE}[11.5/13] Creating LiveKit configuration...${NC}"
    cat > livekit/livekit.yaml << EOF
port: 7880

rtc:
  tcp_port: 7881
  port_range_start: 50100
  port_range_end: 50200
  use_external_ip: true

room:
  auto_create: false

keys:
  livekit-key: ${LIVEKIT_SECRET}
EOF
    print_status "LiveKit configuration created"
    echo ""
fi

# Step 12: Generate Synapse configuration
echo -e "${BLUE}[12/13] Generating Synapse configuration...${NC}"

# Generate homeserver.yaml if it doesn't exist
if [ ! -f "synapse/data/homeserver.yaml" ]; then
    if [[ "${SKIP_START:-false}" == "true" ]]; then
        print_info "Generating minimal homeserver.yaml (config-only mode)..."
        cat > synapse/data/homeserver.yaml << EOF
server_name: "${SERVER_NAME}"
pid_file: /data/homeserver.pid
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    resources:
      - names: [client, federation]
        compress: false
log_config: "/data/${SERVER_NAME}.log.config"
media_store_path: /data/media_store
report_stats: false
EOF
    else
        print_info "Generating new homeserver.yaml..."
        $DOCKER_CMD run --rm \
            -v $(pwd)/synapse/data:/data \
            -e SYNAPSE_SERVER_NAME=${SERVER_NAME} \
            -e SYNAPSE_REPORT_STATS=no \
            matrixdotorg/synapse:latest generate
        # Fix ownership: synapse runs as uid 991 inside Docker; reclaim files for current user
        sudo chown -R "$(id -u):$(id -g)" synapse/data/
        # Synapse's generated config binds the client/federation listener to
        # loopback only, which is unreachable from other containers (Caddy,
        # MAS) on the Docker network. Rebind to all interfaces.
        sed -i "s/bind_addresses: \['::1', '127.0.0.1'\]/bind_addresses: ['0.0.0.0']/" synapse/data/homeserver.yaml
    fi
    print_status "Synapse configuration generated"
else
    print_info "Existing homeserver.yaml found - preserving custom configurations"
fi

# Always update database section (to match new .env password)
print_info "Updating database configuration..."

# Backup before modifying
cp synapse/data/homeserver.yaml synapse/data/homeserver.yaml.bak 2>/dev/null || true

# Remove old database configuration (both SQLite and PostgreSQL)
sed -i '/^database:/,/^[^ ]/{ /^database:/d; /^[^ ]/!d }' synapse/data/homeserver.yaml

# Remove old MAS integration sections (msc3861 removed in Synapse 1.137+)
sed -i '/^# MAS Integration/,/^[^ ]/{ /^# MAS Integration/d; /^[^ ]/!d }' synapse/data/homeserver.yaml
sed -i '/^experimental_features:/,/^[^ ]/{ /^experimental_features:/d; /^[^ ]/!d }' synapse/data/homeserver.yaml
# Remove old stable MAS config block (so we can re-add with correct secret)
sed -i '/^matrix_authentication_service:/,/^[^ ]/{ /^matrix_authentication_service:/d; /^[^ ]/!d }' synapse/data/homeserver.yaml
# Remove stale MAS-related comment lines
sed -i '/^# Matrix Authentication Service (MAS) integration/d' synapse/data/homeserver.yaml
sed -i '/^# Replaces deprecated experimental_features/d' synapse/data/homeserver.yaml
sed -i '/^# Experimental features$/d' synapse/data/homeserver.yaml

# Remove old enable_registration if present
sed -i '/^# Enable registration/d' synapse/data/homeserver.yaml
sed -i '/^enable_registration:/d' synapse/data/homeserver.yaml

# Remove old public room settings if present (re-added explicitly below)
sed -i '/^allow_public_rooms_without_auth:/d' synapse/data/homeserver.yaml
sed -i '/^allow_public_rooms_over_federation:/d' synapse/data/homeserver.yaml

# Remove old double-puppeting appservice registration if present (prevents duplication on re-run)
sed -i '/^# Double-puppeting appservice/d' synapse/data/homeserver.yaml
sed -i '/^app_service_config_files:/,/^[^ ]/{ /^app_service_config_files:/d; /^[^ ]/!d }' synapse/data/homeserver.yaml

# Remove old Element Call rate limit config if present (prevents duplication on re-run)
sed -i '/^# Element Call: delayed event rate limiting/d' synapse/data/homeserver.yaml
sed -i '/^max_event_delay_duration:/d' synapse/data/homeserver.yaml
sed -i '/^rc_delayed_event_mgmt:/,/^[^ ]/{ /^rc_delayed_event_mgmt:/d; /^[^ ]/!d }' synapse/data/homeserver.yaml

# Add PostgreSQL and MAS config (always with current passwords)
cat >> synapse/data/homeserver.yaml << EOF

# PostgreSQL Database Configuration (added/updated by deploy.sh)
database:
  name: psycopg2
  args:
    user: synapse
    password: ${POSTGRES_PASSWORD}
    database: synapse
    host: postgres
    port: 5432
    cp_min: 5
    cp_max: 10

# Enable registration (disabled when using MAS/OAuth delegation)
enable_registration: false
allow_guest_access: false
allow_public_rooms_without_auth: false
allow_public_rooms_over_federation: false
enable_authenticated_media: true

# MAS Integration (Synapse 1.136+ stable config — replaces deprecated experimental_features.msc3861)
matrix_authentication_service:
  enabled: true
  endpoint: 'http://mas:8080'
  secret: '${SYNAPSE_SHARED_SECRET}'
EOF

# Add Element Call MSC features if enabled (separate from MAS config)
if [[ "$USE_ELEMENT_CALL" == true ]]; then
    cat >> synapse/data/homeserver.yaml << EOF

# Element Call MSC features
experimental_features:
  msc3266_enabled: true
  msc4222_enabled: true
  msc4140_enabled: true

# Element Call: delayed event rate limiting
max_event_delay_duration: 24h

rc_delayed_event_mgmt:
  per_second: 1
  burst_count: 20
EOF
fi

# Generate double-puppeting appservice registration
cat > appservices/doublepuppet.yaml << EOF
id: doublepuppet
url: null
as_token: "${DOUBLEPUPPET_AS_TOKEN}"
hs_token: "${DOUBLEPUPPET_HS_TOKEN}"
sender_localpart: doublepuppet
rate_limited: false

namespaces:
  users:
    - regex: "@.*:${SERVER_NAME}"
      exclusive: false
EOF

# Build the appservice file list (always doublepuppet + hookshot if enabled)
APPSERVICE_FILES="  - /appservices/doublepuppet.yaml"
if [[ "$USE_HOOKSHOT" == true ]]; then
    APPSERVICE_FILES="${APPSERVICE_FILES}
  - /appservices/hookshot.yaml"
fi

cat >> synapse/data/homeserver.yaml << EOF

# Double-puppeting + optional appservices
app_service_config_files:
${APPSERVICE_FILES}
EOF

# Add Prometheus metrics: enable_metrics lives in its own file (loaded
# alongside homeserver.yaml via SYNAPSE_CONFIG_PATH=/data), but the metrics
# *listener* must be merged into homeserver.yaml's own `listeners:` list.
# Synapse's multi-file config merge replaces top-level keys wholesale rather
# than merging lists, so a second top-level `listeners:` key in metrics.yaml
# would silently clobber the client/federation listener from homeserver.yaml
# and take down port 8008 (issue #32).

# Remove any previously injected metrics listener entry first, so re-running
# with monitoring toggled off/on doesn't duplicate or strand stale entries.
sed -i '/# ess-deploy:metrics-listener/,/^  - \|^[^ ]/{ /# ess-deploy:metrics-listener/d; /^  - \|^[^ ]/!d }' synapse/data/homeserver.yaml
rm -f synapse/data/metrics.yaml

if [[ "$USE_MONITORING" == true ]]; then
    sed -i '/^        compress: false/a\
\
  - type: metrics   # ess-deploy:metrics-listener\
    port: 9000\
    bind_addresses: ['"'"'0.0.0.0'"'"']\
    resources: []' synapse/data/homeserver.yaml

    cat > synapse/data/metrics.yaml << EOF
# Synapse Prometheus metrics — loaded alongside homeserver.yaml
enable_metrics: true
EOF
    print_status "Synapse metrics listener merged into homeserver.yaml (port 9000)"
fi

# Restore ownership to container UIDs so containers can read/write their data
if [[ "${SKIP_START:-false}" != "true" ]]; then
    sudo chown -R 991:991 synapse/data/
    sudo chmod 640 synapse/data/*.signing.key 2>/dev/null || true
    sudo chown -R 65532:65532 mas/data/
fi
print_status "Database configuration updated with current credentials"
echo ""

# Step 12.5: Generate local Caddyfile (only for local mode)
if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
    echo -e "${BLUE}[12.5/13] Generating local Caddyfile...${NC}"

    # Pre-build JSON blobs for the local Caddyfile (single-line, no literal \n)
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        LOCAL_WELLKNOWN_JSON="{\"m.homeserver\":{\"base_url\":\"https://${MATRIX_DOMAIN}\"},\"m.authentication\":{\"issuer\":\"https://${AUTH_DOMAIN}/\"},\"org.matrix.msc4143.rtc_foci\":[{\"type\":\"livekit\",\"livekit_service_url\":\"https://${RTC_DOMAIN}/livekit/jwt\"}]}"
        LOCAL_ELEMENT_CFG_JSON="{\"default_server_config\":{\"m.homeserver\":{\"base_url\":\"https://${MATRIX_DOMAIN}\",\"server_name\":\"${SERVER_NAME}\"}},\"default_server_name\":\"${SERVER_NAME}\",\"disable_custom_urls\":false,\"disable_guests\":true,\"features\":{\"feature_oidc_aware_navigation\":true,\"feature_element_call_video_rooms\":true},\"element_call\":{\"url\":\"https://${CALL_DOMAIN}\",\"brand\":\"Element Call\"}}"
    else
        LOCAL_WELLKNOWN_JSON="{\"m.homeserver\":{\"base_url\":\"https://${MATRIX_DOMAIN}\"},\"m.authentication\":{\"issuer\":\"https://${AUTH_DOMAIN}/\"}}"
        LOCAL_ELEMENT_CFG_JSON="{\"default_server_config\":{\"m.homeserver\":{\"base_url\":\"https://${MATRIX_DOMAIN}\",\"server_name\":\"${SERVER_NAME}\"}},\"default_server_name\":\"${SERVER_NAME}\",\"disable_custom_urls\":false,\"disable_guests\":true,\"features\":{\"feature_oidc_aware_navigation\":true}}"
    fi

    cat > caddy/Caddyfile << 'CADDYEOF'
# Local Development Caddyfile for Matrix Stack
# Uses self-signed certificates for local HTTPS testing
# Auto-generated by deploy.sh — do not edit manually

{
    # Use local CA for self-signed certificates
    local_certs
    # Enable admin API (localhost only)
    admin localhost:2019
}
CADDYEOF

    # Append Matrix homeserver block (variables expanded)
    cat >> caddy/Caddyfile << EOF

# =========================
# Matrix Homeserver (Synapse)
# =========================
${MATRIX_DOMAIN}:443 {
    # TLS with self-signed cert
    tls internal

    # Well-known client endpoint
    @wk path /.well-known/matrix/client
    handle @wk {
        header Content-Type application/json
        header Access-Control-Allow-Origin "*"
        respond \`${LOCAL_WELLKNOWN_JSON}\` 200
    }

    # Well-known server endpoint (federation)
    @wk_server path /.well-known/matrix/server
    handle @wk_server {
        header Content-Type application/json
        respond \`{"m.server":"${MATRIX_DOMAIN}:443"}\` 200
    }

    # Rendezvous endpoints for QR code login (MSC4108)
    @rendezvous path_regexp rendezvous ^/_matrix/client/(unstable|v1)/org\.matrix\.(msc3886|msc4108)/rendezvous.*\$
    handle @rendezvous {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept, If-Match, If-None-Match"
        header Vary "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
        encode {
        }
        reverse_proxy synapse:8008 {
            header_down -Access-Control-Allow-Origin
            header_down -Access-Control-Allow-Methods
            header_down -Access-Control-Allow-Headers
            header_down -Vary
        }
    }

    # Client versions endpoint with CORS
    @versions path /_matrix/client/versions
    handle @versions {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        header Vary "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
        reverse_proxy synapse:8008 {
            header_down -Access-Control-Allow-Origin
            header_down -Access-Control-Allow-Methods
            header_down -Access-Control-Allow-Headers
            header_down -Vary
        }
    }

    # CORS preflight for auth metadata
    @auth_preflight {
        method OPTIONS
        path /_matrix/client/unstable/org.matrix.msc2965/auth_metadata
    }
    handle @auth_preflight {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        header Access-Control-Max-Age "86400"
        respond 204
    }

    # CORS preflight for all Matrix API
    @preflight {
        method OPTIONS
        path_regexp matrix ^/_matrix/.*\$
    }
    handle @preflight {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        header Access-Control-Max-Age "86400"
        respond 204
    }

    # MAS compat endpoints (login/logout/refresh/register) with CORS
    @compat path \\
        /_matrix/client/v3/login* \\
        /_matrix/client/v3/logout* \\
        /_matrix/client/v3/refresh* \\
        /_matrix/client/v3/register* \\
        /_matrix/client/r0/login* \\
        /_matrix/client/r0/logout* \\
        /_matrix/client/r0/refresh* \\
        /_matrix/client/r0/register*
    handle @compat {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        header Vary "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
        reverse_proxy mas:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
            header_down -Access-Control-Allow-Origin
            header_down -Access-Control-Allow-Methods
            header_down -Access-Control-Allow-Headers
            header_down -Vary
        }
    }

    # Everything else under /_matrix → Synapse with CORS
    @matrix_rest path_regexp matrix ^/_matrix/.*\$
    handle @matrix_rest {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        header Vary "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
        reverse_proxy synapse:8008 {
            header_down -Access-Control-Allow-Origin
            header_down -Access-Control-Allow-Methods
            header_down -Access-Control-Allow-Headers
            header_down -Vary
        }
    }

    # Synapse admin API — CORS for Ketesa
    handle /_synapse/admin* {
        header Access-Control-Allow-Origin "https://${ADMIN_DOMAIN}"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        @admin_preflight method OPTIONS
        respond @admin_preflight "" 204
        reverse_proxy synapse:8008 {
            header_down -Access-Control-Allow-Origin
        }
    }

    # Default: everything else → Synapse
    handle {
        reverse_proxy synapse:8008
    }
}

# =========================
# Matrix Authentication Service (MAS)
# =========================
${AUTH_DOMAIN}:443 {
    tls internal

    # OIDC Discovery
    @disco path /.well-known/openid-configuration
    handle @disco {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "GET, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        reverse_proxy mas:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    # Dynamic Client Registration: CORS preflight
    @reg_opts {
        method OPTIONS
        path /oauth2/registration
    }
    handle @reg_opts {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "POST, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        respond 204
    }

    # Dynamic Client Registration (POST)
    @reg path /oauth2/registration
    route @reg {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "POST, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        reverse_proxy mas:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    # JWKS preflight
    @jwks_opts {
        method OPTIONS
        path /oauth2/keys.json
    }
    handle @jwks_opts {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "GET, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        respond 204
    }

    # Map keys.json → /oauth2/jwks (MAS naming)
    @jwksjson path /oauth2/keys.json
    route @jwksjson {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "GET, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        uri replace /oauth2/keys.json /oauth2/jwks
        reverse_proxy mas:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    # Generic OAuth2 endpoints
    @oauth path /oauth2/*
    route @oauth {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "GET, OPTIONS, POST"
        header ?Access-Control-Allow-Headers "*"
        reverse_proxy mas:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    # Account portal (handle, not handle_path — preserves /account/ prefix for MAS SPA routing)
    handle /account/* {
        reverse_proxy mas:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    # Authelia endpoints (proxy to authelia)
    handle_path /authelia/* {
        reverse_proxy authelia:9091
    }

    # Fallback: everything else to MAS
    handle {
        reverse_proxy mas:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    # Add CORS on error responses
    handle_errors {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Headers "*"
        header ?Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
    }
}

# =========================
# Authelia SSO
# =========================
${AUTHELIA_DOMAIN}:443 {
    tls internal

    reverse_proxy authelia:9091
}

# =========================
# Element Web Client
# =========================
${ELEMENT_DOMAIN}:443 {
    tls internal

    # Serve config.json with proper settings
    @cfg path /config.json /config.${ELEMENT_DOMAIN}.json
    handle @cfg {
        header Content-Type application/json
        header Cache-Control no-store
        respond \`${LOCAL_ELEMENT_CFG_JSON}\` 200
    }

    # Everything else to Element container
    handle {
        reverse_proxy element:80
    }
}

# =========================
# Ketesa
# =========================
${ADMIN_DOMAIN}:443 {
    tls internal

    handle {
        reverse_proxy ketesa:8080
    }
}
EOF

    # Append FluffyChat block if enabled
    if [[ "$USE_FLUFFYCHAT" == true ]]; then
        cat >> caddy/Caddyfile << EOF

# =========================
# FluffyChat
# =========================
${FLUFFYCHAT_DOMAIN}:443 {
    tls internal

    handle {
        reverse_proxy fluffychat:80
    }
}
EOF
    fi

    # Append identity domain well-known block if SERVER_NAME differs from MATRIX_DOMAIN
    if [[ "$SERVER_NAME" != "$MATRIX_DOMAIN" ]]; then
        cat >> caddy/Caddyfile << EOF

# =========================
# Identity Domain (well-known delegation)
# =========================
${SERVER_NAME}:443 {
    tls internal

    @wk path /.well-known/matrix/client
    handle @wk {
        header Content-Type application/json
        header Access-Control-Allow-Origin "*"
        respond \`${LOCAL_WELLKNOWN_JSON}\` 200
    }

    @wk_server path /.well-known/matrix/server
    handle @wk_server {
        header Content-Type application/json
        respond \`{"m.server":"${MATRIX_DOMAIN}:443"}\` 200
    }
}
EOF
    fi

    # Append monitoring block if enabled
    if [[ "$USE_MONITORING" == true ]]; then
        cat >> caddy/Caddyfile << EOF

# =========================
# Grafana (Monitoring)
# =========================
${MONITORING_DOMAIN}:443 {
    tls internal

    handle {
        reverse_proxy grafana:3000
    }
}
EOF
    fi

    # Append hookshot block if enabled
    if [[ "$USE_HOOKSHOT" == true ]]; then
        cat >> caddy/Caddyfile << EOF

# =========================
# Hookshot (Webhooks)
# =========================
${HOOKSHOT_DOMAIN}:443 {
    tls internal

    handle {
        reverse_proxy hookshot:9000
    }
}
EOF
    fi

    # Append Element Call blocks if enabled
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        cat >> caddy/Caddyfile << EOF

# =========================
# Element Call (LiveKit)
# =========================
${RTC_DOMAIN}:443 {
    tls internal

    handle_path /livekit/jwt* {
        reverse_proxy lk-jwt-service:8080
    }

    handle_path /livekit/sfu* {
        reverse_proxy livekit:7880
    }
}

# =========================
# Element Call Frontend
# =========================
${CALL_DOMAIN}:443 {
    tls internal

    reverse_proxy element-call:8080
}
EOF
    fi

    print_status "Local Caddyfile generated: caddy/Caddyfile"
    echo ""
fi

# Step 12.6: Generate single-server Caddyfile (production-single mode only)
if [[ "$DEPLOYMENT_MODE" == "production-single" ]]; then
    echo -e "${BLUE}[12.6/13] Generating single-server Caddyfile...${NC}"

    # Pre-build JSON blobs
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        SINGLE_WELLKNOWN_JSON="{\"m.homeserver\":{\"base_url\":\"https://${MATRIX_DOMAIN}\"},\"m.authentication\":{\"issuer\":\"https://${AUTH_DOMAIN}/\"},\"org.matrix.msc4143.rtc_foci\":[{\"type\":\"livekit\",\"livekit_service_url\":\"https://${RTC_DOMAIN}/livekit/jwt\"}]}"
        SINGLE_ELEMENT_CFG_JSON="{\"default_server_config\":{\"m.homeserver\":{\"base_url\":\"https://${MATRIX_DOMAIN}\",\"server_name\":\"${SERVER_NAME}\"}},\"default_server_name\":\"${SERVER_NAME}\",\"disable_custom_urls\":false,\"disable_guests\":true,\"features\":{\"feature_oidc_aware_navigation\":true,\"feature_element_call_video_rooms\":true},\"element_call\":{\"url\":\"https://${CALL_DOMAIN}\",\"brand\":\"Element Call\"}}"
    else
        SINGLE_WELLKNOWN_JSON="{\"m.homeserver\":{\"base_url\":\"https://${MATRIX_DOMAIN}\"},\"m.authentication\":{\"issuer\":\"https://${AUTH_DOMAIN}/\"}}"
        SINGLE_ELEMENT_CFG_JSON="{\"default_server_config\":{\"m.homeserver\":{\"base_url\":\"https://${MATRIX_DOMAIN}\",\"server_name\":\"${SERVER_NAME}\"}},\"default_server_name\":\"${SERVER_NAME}\",\"disable_custom_urls\":false,\"disable_guests\":true,\"features\":{\"feature_oidc_aware_navigation\":true}}"
    fi

    cat > caddy/Caddyfile << 'CADDYEOF'
# Single-Server Production Caddyfile for Matrix Stack
# Let's Encrypt certificates — requires valid DNS pointing to this machine
# Auto-generated by deploy.sh — do not edit manually

{
    # Let's Encrypt email for certificate notifications
CADDYEOF
    echo "    email ${LETSENCRYPT_EMAIL}" >> caddy/Caddyfile
    cat >> caddy/Caddyfile << 'CADDYEOF'
    # Enable admin API (localhost only)
    admin localhost:2019
}
CADDYEOF

    cat >> caddy/Caddyfile << EOF

# =========================
# Matrix Homeserver
# =========================
${MATRIX_DOMAIN} {
    # Well-known client endpoint
    @wk path /.well-known/matrix/client
    handle @wk {
        header Content-Type application/json
        header Access-Control-Allow-Origin "*"
        respond \`${SINGLE_WELLKNOWN_JSON}\` 200
    }

    # Well-known server endpoint (federation)
    @wk_server path /.well-known/matrix/server
    handle @wk_server {
        header Content-Type application/json
        respond \`{"m.server":"${MATRIX_DOMAIN}:443"}\` 200
    }

    # CORS preflight
    @preflight {
        method OPTIONS
        path_regexp ^/_matrix/.*\$
    }
    handle @preflight {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        header Access-Control-Max-Age "86400"
        respond 204
    }

    # MAS compat endpoints (login/logout/refresh/register)
    @compat path /_matrix/client/v3/login* /_matrix/client/v3/logout* /_matrix/client/v3/refresh* /_matrix/client/v3/register* /_matrix/client/r0/login* /_matrix/client/r0/logout* /_matrix/client/r0/refresh* /_matrix/client/r0/register*
    handle @compat {
        header Access-Control-Allow-Origin "*"
        reverse_proxy mas:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
            header_down -Access-Control-Allow-Origin
        }
    }

    # Synapse admin API — CORS for Ketesa
    handle /_synapse/admin* {
        header Access-Control-Allow-Origin "https://${ADMIN_DOMAIN}"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        @admin_preflight method OPTIONS
        respond @admin_preflight "" 204
        reverse_proxy synapse:8008 {
            header_down -Access-Control-Allow-Origin
        }
    }

    # Everything else to Synapse
    @matrix path_regexp ^/_matrix/.*\$
    handle @matrix {
        header Access-Control-Allow-Origin "*"
        reverse_proxy synapse:8008 {
            header_down -Access-Control-Allow-Origin
        }
    }

    handle {
        reverse_proxy synapse:8008
    }
}

# =========================
# MAS (OIDC)
# =========================
${AUTH_DOMAIN} {
    # OIDC Discovery
    @disco path /.well-known/openid-configuration
    handle @disco {
        header ?Access-Control-Allow-Origin "*"
        reverse_proxy mas:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    # OAuth2 endpoints
    @oauth path /oauth2/*
    route @oauth {
        header ?Access-Control-Allow-Origin "*"
        reverse_proxy mas:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    # Account portal (handle, not handle_path — preserves /account/ prefix for MAS SPA routing)
    handle /account/* {
        reverse_proxy mas:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    handle {
        reverse_proxy mas:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    handle_errors {
        header ?Access-Control-Allow-Origin "*"
    }
}

# =========================
# Element Web Client
# =========================
${ELEMENT_DOMAIN} {
    @cfg path /config.json /config.${ELEMENT_DOMAIN}.json
    handle @cfg {
        header Content-Type application/json
        header Cache-Control no-store
        respond \`${SINGLE_ELEMENT_CFG_JSON}\` 200
    }

    handle {
        reverse_proxy element:80
    }
}

# =========================
# Ketesa
# =========================
${ADMIN_DOMAIN} {
    handle {
        reverse_proxy ketesa:8080
    }
}
EOF

    # Append FluffyChat block if enabled
    if [[ "$USE_FLUFFYCHAT" == true ]]; then
        cat >> caddy/Caddyfile << EOF

# =========================
# FluffyChat
# =========================
${FLUFFYCHAT_DOMAIN} {
    handle {
        reverse_proxy fluffychat:80
    }
}
EOF
    fi

    # Append monitoring block if enabled
    if [[ "$USE_MONITORING" == true ]]; then
        cat >> caddy/Caddyfile << EOF

# =========================
# Grafana (Monitoring)
# =========================
${MONITORING_DOMAIN} {
    handle {
        reverse_proxy grafana:3000
    }
}
EOF
    fi

    # Append hookshot block if enabled
    if [[ "$USE_HOOKSHOT" == true ]]; then
        cat >> caddy/Caddyfile << EOF

# =========================
# Hookshot (Webhooks)
# =========================
${HOOKSHOT_DOMAIN} {
    handle {
        reverse_proxy hookshot:9000
    }
}
EOF
    fi

    # Append identity domain well-known block if SERVER_NAME differs from MATRIX_DOMAIN
    if [[ "$SERVER_NAME" != "$MATRIX_DOMAIN" ]]; then
        cat >> caddy/Caddyfile << EOF

# =========================
# Identity Domain (well-known delegation)
# =========================
${SERVER_NAME} {
    @wk path /.well-known/matrix/client
    handle @wk {
        header Content-Type application/json
        header Access-Control-Allow-Origin "*"
        respond \`${SINGLE_WELLKNOWN_JSON}\` 200
    }

    @wk_server path /.well-known/matrix/server
    handle @wk_server {
        header Content-Type application/json
        respond \`{"m.server":"${MATRIX_DOMAIN}:443"}\` 200
    }
}
EOF
    fi

    # Append Element Call blocks if enabled
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        cat >> caddy/Caddyfile << EOF

# =========================
# Element Call (LiveKit)
# =========================
${RTC_DOMAIN} {
    handle_path /livekit/jwt* {
        reverse_proxy lk-jwt-service:8080
    }

    handle_path /livekit/sfu* {
        reverse_proxy livekit:7880
    }
}

# =========================
# Element Call Frontend
# =========================
${CALL_DOMAIN} {
    reverse_proxy element-call:8080
}
EOF
    fi

    print_status "Single-server Caddyfile generated: caddy/Caddyfile"
    echo ""
fi

# Step 13: Fix directory permissions
echo -e "${BLUE}[13/14] Fixing directory permissions...${NC}"
chmod 755 postgres/init postgres/config 2>/dev/null || true
chmod 644 postgres/init/*.sql 2>/dev/null || true
chmod 755 authelia/config element/config 2>/dev/null || true
# Secret files: owner-read only
chmod 755 mas/config 2>/dev/null || true
chmod 644 mas/config/config.yaml 2>/dev/null || true
chmod 600 .env 2>/dev/null || true
print_status "Permissions fixed"
echo ""

# Image summary
echo -e "${CYAN}Docker images configured:${NC}"
echo -e "  Synapse:       $SYNAPSE_IMAGE"
echo -e "  Postgres:      $POSTGRES_IMAGE"
echo -e "  Redis:         $REDIS_IMAGE"
echo -e "  MAS:           $MAS_IMAGE"
echo -e "  Element:       $ELEMENT_IMAGE"
if [[ "$USE_FLUFFYCHAT" == true ]]; then
    echo -e "  FluffyChat:    $FLUFFYCHAT_IMAGE"
fi
echo -e "  Ketesa:        $KETESA_IMAGE"
echo -e "  Discord Bridge: $DISCORD_IMAGE"
echo -e "  Slack Bridge:   $SLACK_IMAGE"
if [[ "$USE_MONITORING" == true ]]; then
    echo -e "  Prometheus:    $PROMETHEUS_IMAGE"
    echo -e "  Grafana:       $GRAFANA_IMAGE"
fi
if [[ "$USE_HOOKSHOT" == true ]]; then
    echo -e "  Hookshot:      $HOOKSHOT_IMAGE"
fi
echo -e "  Auto-Compressor: (built locally)"
echo -e "  Authelia:      $AUTHELIA_IMAGE"
echo -e "  Caddy:         $CADDY_IMAGE"
if [[ "$USE_ELEMENT_CALL" == true ]]; then
    echo -e "  LiveKit:       $LIVEKIT_IMAGE"
    echo -e "  LK JWT:        $LK_JWT_IMAGE"
    echo -e "  Element Call:  $ELEMENT_CALL_IMAGE"
fi
echo ""

# Step 14: Start the stack
echo -e "${BLUE}[14/14] Starting the Matrix stack...${NC}"

if [[ "${SKIP_START:-false}" == "true" ]]; then
    print_info "Skipping stack start (SKIP_START=true)"
else

print_info "Using compose file: ${COMPOSE_FILE}"
print_info "This may take a few minutes on first run..."
echo ""

# Start PostgreSQL first
print_info "Starting PostgreSQL..."
$DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} up -d postgres
sleep 10

# Wait for PostgreSQL to be ready
print_info "Waiting for PostgreSQL to be ready..."
for i in {1..60}; do
    if $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} exec -T postgres pg_isready -U synapse &> /dev/null; then
        print_status "PostgreSQL is ready"
        break
    fi
    if [ $i -eq 60 ]; then
        print_error "PostgreSQL failed to start in time"
        echo "Checking logs..."
        $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} logs postgres | tail -20
        exit 1
    fi
    sleep 2
done
echo ""

# Start Redis (only if using Authelia)
if [[ "$USE_AUTHELIA" == true ]]; then
    print_info "Starting Redis (for Authelia)..."
    $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} --profile authelia up -d redis
    sleep 3
    echo ""
fi

# Build compose profile flags
COMPOSE_PROFILES=""
if [[ "$DEPLOYMENT_MODE" == "production-single" ]]; then
    COMPOSE_PROFILES="${COMPOSE_PROFILES} --profile single-machine"
fi
if [[ "$USE_AUTHELIA" == true ]]; then
    COMPOSE_PROFILES="${COMPOSE_PROFILES} --profile authelia"
fi
if [[ "$USE_ELEMENT_CALL" == true ]]; then
    COMPOSE_PROFILES="${COMPOSE_PROFILES} --profile element-call"
fi
if [[ "$USE_FLUFFYCHAT" == true ]]; then
    COMPOSE_PROFILES="${COMPOSE_PROFILES} --profile fluffychat"
fi
if [[ "$USE_MONITORING" == true ]]; then
    COMPOSE_PROFILES="${COMPOSE_PROFILES} --profile monitoring"
fi
if [[ "$USE_HOOKSHOT" == true ]]; then
    COMPOSE_PROFILES="${COMPOSE_PROFILES} --profile hookshot"
fi

# Start remaining services (--remove-orphans cleans up containers from renamed/removed services)
if [[ -n "$COMPOSE_PROFILES" ]]; then
    print_info "Starting all services (profiles:${COMPOSE_PROFILES})..."
    $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} ${COMPOSE_PROFILES} up -d --remove-orphans
else
    print_info "Starting all services..."
    $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} up -d --remove-orphans
fi
echo ""

# Wait for services to be ready
print_info "Waiting for services to be ready..."
sleep 10
echo ""

# ============================================================================
# LOCAL: Extract Caddy CA Certificate for MAS
# ============================================================================
if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
    echo -e "${BLUE}[Post-Deployment] Extracting Caddy CA certificate for MAS...${NC}"

    # Create certs and caddy data directories
    mkdir -p mas/certs
    mkdir -p caddy/data/caddy  # Required for Caddy to save PKI certificates

    # Wait for Caddy to generate CA (retry loop — cert is created lazily on first HTTPS request)
    print_info "Waiting for Caddy to generate local CA certificate..."
    CADDY_CA_SRC="caddy/data/caddy/pki/authorities/local/root.crt"
    CA_READY=false
    for i in {1..24}; do
        # Trigger HTTPS request each iteration to prompt Caddy to generate certs
        curl -k https://${AUTH_DOMAIN} > /dev/null 2>&1 || true
        if sudo test -f "${CADDY_CA_SRC}"; then
            CA_READY=true
            break
        fi
        sleep 5
    done

    # Copy CA certificate from host path (Caddy data dir is root-owned via Docker)
    if [[ "$CA_READY" == true ]]; then
        sudo cp "${CADDY_CA_SRC}" mas/certs/caddy-ca.crt
        sudo chmod 644 mas/certs/caddy-ca.crt
        print_status "Caddy CA certificate copied to mas/certs/caddy-ca.crt"

        # Restart MAS to pick up the certificate
        print_info "Restarting MAS to load CA certificate..."
        $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} restart mas
        sleep 5
        print_status "MAS restarted with trusted CA certificate"
    else
        print_warning "Could not find Caddy CA certificate after 2 minutes"
        print_info "You may need to manually copy it after Caddy generates it"
        print_info "Run: sudo cp caddy/data/caddy/pki/authorities/local/root.crt mas/certs/caddy-ca.crt"
        print_info "Then restart MAS: $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} restart mas"
    fi
    echo ""
fi

fi  # end SKIP_START

# ============================================================================
# PRODUCTION: Generate Caddy and Authelia configs for separate machines
# ============================================================================
if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}Generating Production Deployment Configs...${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Generate production Caddyfile
    print_info "Generating Caddyfile for Caddy machine..."

    # Pre-build conditional JSON blobs for the Caddyfile
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        PROD_WELLKNOWN_JSON="{\"m.homeserver\":{\"base_url\":\"https://${MATRIX_DOMAIN}\"},\"m.authentication\":{\"issuer\":\"https://${AUTH_DOMAIN}/\"},\"org.matrix.msc4143.rtc_foci\":[{\"type\":\"livekit\",\"livekit_service_url\":\"https://${RTC_DOMAIN}/livekit/jwt\"}]}"
        PROD_ELEMENT_CFG_JSON="{\"default_server_config\":{\"m.homeserver\":{\"base_url\":\"https://${MATRIX_DOMAIN}\",\"server_name\":\"${SERVER_NAME}\"}},\"default_server_name\":\"${SERVER_NAME}\",\"disable_custom_urls\":false,\"disable_guests\":true,\"features\":{\"feature_oidc_aware_navigation\":true,\"feature_element_call_video_rooms\":true},\"element_call\":{\"url\":\"https://${CALL_DOMAIN}\",\"brand\":\"Element Call\"}}"
    else
        PROD_WELLKNOWN_JSON="{\"m.homeserver\":{\"base_url\":\"https://${MATRIX_DOMAIN}\"},\"m.authentication\":{\"issuer\":\"https://${AUTH_DOMAIN}/\"}}"
        PROD_ELEMENT_CFG_JSON="{\"default_server_config\":{\"m.homeserver\":{\"base_url\":\"https://${MATRIX_DOMAIN}\",\"server_name\":\"${SERVER_NAME}\"}},\"default_server_name\":\"${SERVER_NAME}\",\"disable_custom_urls\":false,\"disable_guests\":true,\"features\":{\"feature_oidc_aware_navigation\":true}}"
    fi

    cat > caddy/Caddyfile.production << EOF
# Production Caddyfile for Matrix Stack
# Deploy this on your SSL termination machine
# Email for Let's Encrypt: ${LETSENCRYPT_EMAIL}

{
    email ${LETSENCRYPT_EMAIL}
    # Enable admin API (localhost only)
    admin localhost:2019
}

# =========================
# Matrix Homeserver
# =========================
${MATRIX_DOMAIN} {
    # Well-known client endpoint
    @wk path /.well-known/matrix/client
    handle @wk {
        header Content-Type application/json
        header Access-Control-Allow-Origin "*"
        respond \`${PROD_WELLKNOWN_JSON}\` 200
    }

    # Well-known server endpoint (federation)
    @wk_server path /.well-known/matrix/server
    handle @wk_server {
        header Content-Type application/json
        respond \`{"m.server":"${MATRIX_DOMAIN}:443"}\` 200
    }

    # Client versions with CORS
    @versions path /_matrix/client/versions
    handle @versions {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        reverse_proxy ${MATRIX_SERVER_IP}:8008 {
            header_down -Access-Control-Allow-Origin
            header_down -Access-Control-Allow-Methods
            header_down -Access-Control-Allow-Headers
            header_down -Vary
        }
    }

    # CORS preflight
    @preflight {
        method OPTIONS
        path_regexp matrix ^/_matrix/.*$
    }
    handle @preflight {
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        header Access-Control-Max-Age "86400"
        respond 204
    }

    # MAS compat endpoints (login/logout/refresh/register)
    @compat path /_matrix/client/v3/login* /_matrix/client/v3/logout* /_matrix/client/v3/refresh* /_matrix/client/v3/register* /_matrix/client/r0/login* /_matrix/client/r0/logout* /_matrix/client/r0/refresh* /_matrix/client/r0/register*
    handle @compat {
        header Access-Control-Allow-Origin "*"
        reverse_proxy ${MATRIX_SERVER_IP}:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
            header_down -Access-Control-Allow-Origin
            header_down -Access-Control-Allow-Methods
            header_down -Access-Control-Allow-Headers
            header_down -Vary
        }
    }

    # Everything else to Synapse
    @matrix_rest path_regexp matrix ^/_matrix/.*$
    handle @matrix_rest {
        header Access-Control-Allow-Origin "*"
        reverse_proxy ${MATRIX_SERVER_IP}:8008 {
            header_down -Access-Control-Allow-Origin
            header_down -Access-Control-Allow-Methods
            header_down -Access-Control-Allow-Headers
            header_down -Vary
        }
    }

    # Synapse admin API — CORS for Ketesa
    handle /_synapse/admin* {
        header Access-Control-Allow-Origin "https://${ADMIN_DOMAIN}"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
        @admin_preflight method OPTIONS
        respond @admin_preflight "" 204
        reverse_proxy ${MATRIX_SERVER_IP}:8008 {
            header_down -Access-Control-Allow-Origin
        }
    }

    handle {
        reverse_proxy ${MATRIX_SERVER_IP}:8008
    }
}

# =========================
# MAS (OIDC)
# =========================
${AUTH_DOMAIN} {
    # OIDC Discovery
    @disco path /.well-known/openid-configuration
    handle @disco {
        header ?Access-Control-Allow-Origin "*"
        reverse_proxy ${MATRIX_SERVER_IP}:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    # OAuth2 endpoints
    @oauth path /oauth2/*
    route @oauth {
        header ?Access-Control-Allow-Origin "*"
        reverse_proxy ${MATRIX_SERVER_IP}:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    # Account portal (handle, not handle_path — preserves /account/ prefix for MAS SPA routing)
    handle /account/* {
        reverse_proxy ${MATRIX_SERVER_IP}:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    handle {
        reverse_proxy ${MATRIX_SERVER_IP}:8080 {
            header_up Host {http.request.host}
            header_up X-Forwarded-Host {http.request.host}
        }
    }

    handle_errors {
        header ?Access-Control-Allow-Origin "*"
    }
}

# =========================
# Authelia SSO
# =========================
${AUTHELIA_DOMAIN} {
    reverse_proxy ${AUTHELIA_SERVER_IP}:9091
}

# =========================
# Element Web
# =========================
${ELEMENT_DOMAIN} {
    # Serve config with proper settings
    @cfg path /config.json /config.${ELEMENT_DOMAIN}.json
    handle @cfg {
        header Content-Type application/json
        header Cache-Control no-store
        respond \`${PROD_ELEMENT_CFG_JSON}\` 200
    }

    handle {
        reverse_proxy ${MATRIX_SERVER_IP}:8090
    }
}

# =========================
# Ketesa
# =========================
${ADMIN_DOMAIN} {
    # Proxy to Ketesa
    handle {
        reverse_proxy ${MATRIX_SERVER_IP}:8091
    }
}
EOF

    # Append FluffyChat block if enabled
    if [[ "$USE_FLUFFYCHAT" == true ]]; then
        cat >> caddy/Caddyfile.production << EOF

# =========================
# FluffyChat
# =========================
${FLUFFYCHAT_DOMAIN} {
    handle {
        reverse_proxy ${MATRIX_SERVER_IP}:8092
    }
}
EOF
    fi

    # Append monitoring block if enabled
    if [[ "$USE_MONITORING" == true ]]; then
        cat >> caddy/Caddyfile.production << EOF

# =========================
# Grafana (Monitoring)
# =========================
${MONITORING_DOMAIN} {
    handle {
        reverse_proxy ${MATRIX_SERVER_IP}:3000
    }
}
EOF
    fi

    # Append hookshot block if enabled
    if [[ "$USE_HOOKSHOT" == true ]]; then
        cat >> caddy/Caddyfile.production << EOF

# =========================
# Hookshot (Webhooks)
# =========================
${HOOKSHOT_DOMAIN} {
    handle {
        reverse_proxy ${MATRIX_SERVER_IP}:9000
    }
}
EOF
    fi

    # Append identity domain well-known block if SERVER_NAME differs from MATRIX_DOMAIN
    if [[ "$SERVER_NAME" != "$MATRIX_DOMAIN" ]]; then
        cat >> caddy/Caddyfile.production << EOF

# =========================
# Identity Domain (well-known delegation)
# =========================
${SERVER_NAME} {
    @wk path /.well-known/matrix/client
    handle @wk {
        header Content-Type application/json
        header Access-Control-Allow-Origin "*"
        respond \`${PROD_WELLKNOWN_JSON}\` 200
    }

    @wk_server path /.well-known/matrix/server
    handle @wk_server {
        header Content-Type application/json
        respond \`{"m.server":"${MATRIX_DOMAIN}:443"}\` 200
    }
}
EOF
    fi

    # Append Element Call blocks to production Caddyfile if enabled
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        cat >> caddy/Caddyfile.production << EOF

# =========================
# Element Call (LiveKit)
# =========================
${RTC_DOMAIN} {
    handle_path /livekit/jwt* {
        reverse_proxy ${MATRIX_SERVER_IP}:8082
    }

    handle_path /livekit/sfu* {
        reverse_proxy ${MATRIX_SERVER_IP}:7880
    }
}

# =========================
# Element Call Frontend
# =========================
${CALL_DOMAIN} {
    reverse_proxy ${MATRIX_SERVER_IP}:8083
}
EOF
    fi

    print_status "Production Caddyfile created: caddy/Caddyfile.production"
    echo ""

    print_info "Production configs generated successfully!"
    print_status "Authelia config: authelia/config/configuration.yml"
    print_status "Authelia users: authelia/config/users_database.yml"
    print_status "Caddy config: caddy/Caddyfile.production"
    print_status "Caddy compose: docker-compose.caddy.yml"
    print_status "Authelia compose: docker-compose.authelia.yml"
    echo ""
fi

# Check service status
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Show service status
if [[ "${SKIP_START:-false}" != "true" ]]; then
    echo -e "${BLUE}Service Status:${NC}"
    $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} ps
    echo ""
fi

echo -e "${GREEN}✓ Matrix stack is now running!${NC}"
echo ""

if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
    echo -e "${BLUE}Access Points (HTTPS with self-signed certificates):${NC}"
    echo -e "  • Element Web:  https://${ELEMENT_DOMAIN}"
    if [[ "$USE_FLUFFYCHAT" == true ]]; then
        echo -e "  • FluffyChat:   https://${FLUFFYCHAT_DOMAIN}"
    fi
    echo -e "  • Matrix API:   https://${MATRIX_DOMAIN}"
    echo -e "  • MAS (Auth):   https://${AUTH_DOMAIN}"
    echo -e "  • Ketesa Admin: https://${ADMIN_DOMAIN}"
    if [[ "$USE_AUTHELIA" == true ]]; then
        echo -e "  • Authelia:     https://${AUTHELIA_DOMAIN}"
    fi
    if [[ "$USE_MONITORING" == true ]]; then
        echo -e "  • Grafana:      https://${MONITORING_DOMAIN}"
    fi
    if [[ "$USE_HOOKSHOT" == true ]]; then
        echo -e "  • Hookshot:     https://${HOOKSHOT_DOMAIN}"
    fi
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        echo -e "  • Element Call: https://${CALL_DOMAIN}"
        echo -e "  • LiveKit JWT:  https://${RTC_DOMAIN}/livekit/jwt"
    fi
    echo -e "  • Caddy Admin:  http://localhost:2019"
    echo ""
    echo -e "${YELLOW}⚠ Self-Signed Certificate Warning:${NC}"
    echo -e "  Your browser will show a security warning because we're using"
    echo -e "  self-signed certificates for local testing. This is expected!"
    echo -e "  Click 'Advanced' and 'Proceed to site' to continue."
    echo ""

    if [[ "$USE_AUTHELIA" == true ]]; then
        echo -e "${BLUE}Authelia Login Credentials:${NC}"
        echo -e "  • Username:     admin"
        echo -e "  • Password:     ${ADMIN_PASSWORD}"
        echo -e "  ${RED}⚠ SAVE THIS PASSWORD - you'll need it to log in!${NC}"
        echo ""
        echo -e "${BLUE}Next Steps:${NC}"
        echo -e "  1. Go to https://${ELEMENT_DOMAIN}"
        echo -e "  2. Accept the self-signed certificate warning"
        echo -e "  3. Click 'Sign In'"
        echo -e "  4. You'll be redirected through MAS → Authelia for SSO"
        echo -e "  5. Log in with the Authelia credentials above"
        echo -e "  6. Set up 2FA (Time-based OTP) for additional security"
        echo -e "  7. Complete registration and start chatting!"
        echo ""
    else
        echo -e "${BLUE}Next Steps:${NC}"
        echo -e "  1. Go to https://${ELEMENT_DOMAIN}"
        echo -e "  2. Accept the self-signed certificate warning"
        echo -e "  3. Click 'Sign In'"
        echo -e "  4. You'll be redirected to MAS for authentication"
        echo -e "  5. Register a new account with your email and password"
        echo -e "  6. Complete email verification if required"
        echo -e "  7. Start chatting!"
        echo ""
    fi
elif [[ "$DEPLOYMENT_MODE" == "production-single" ]]; then
    echo -e "${BLUE}Access Points (once DNS is live):${NC}"
    echo -e "  • Element Web:  https://${ELEMENT_DOMAIN}"
    if [[ "$USE_FLUFFYCHAT" == true ]]; then
        echo -e "  • FluffyChat:   https://${FLUFFYCHAT_DOMAIN}"
    fi
    echo -e "  • Matrix API:   https://${MATRIX_DOMAIN}"
    echo -e "  • MAS (Auth):   https://${AUTH_DOMAIN}"
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        echo -e "  • Element Call: https://${CALL_DOMAIN}"
    fi
    echo ""
    echo -e "${CYAN}DNS — point all domains to this server's IP:${NC}"
    echo -e "  • ${MATRIX_DOMAIN}"
    echo -e "  • ${ELEMENT_DOMAIN}"
    echo -e "  • ${ADMIN_DOMAIN}"
    echo -e "  • ${AUTH_DOMAIN}"
    if [[ "$USE_FLUFFYCHAT" == true ]]; then
        echo -e "  • ${FLUFFYCHAT_DOMAIN}"
    fi
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        echo -e "  • ${RTC_DOMAIN}"
        echo -e "  • ${CALL_DOMAIN}"
    fi
    if [[ "$SERVER_NAME" != "$MATRIX_DOMAIN" ]]; then
        echo -e "  • ${SERVER_NAME}  (identity domain)"
    fi
    echo ""
    echo -e "${CYAN}Firewall — ensure these ports are open:${NC}"
    echo -e "  • TCP 80 and 443  (HTTP + HTTPS, required for Let's Encrypt)"
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        echo -e "  • TCP 7881        (LiveKit WebRTC fallback)"
        echo -e "  • UDP 50100-50200 (LiveKit media)"
    fi
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "  1. Set DNS records above to point to this machine"
    echo -e "  2. Caddy will obtain Let's Encrypt certificates automatically on first request"
    echo -e "  3. Go to https://${ELEMENT_DOMAIN} and create your first account"
    echo ""
else
    # Production distributed mode
    echo -e "${BLUE}Matrix Server Deployed!${NC}"
    echo ""
    echo -e "${MAGENTA}Production Deployment - Next Steps:${NC}"
    echo ""
    echo -e "${CYAN}1. Deploy Caddy on your SSL termination machine:${NC}"
    echo -e "   Generated files:"
    echo -e "   • caddy/Caddyfile.production"
    echo -e "   • docker-compose.caddy.yml"
    echo -e "   • Copy these files to your Caddy machine"
    echo -e "   • Run: docker compose -f docker-compose.caddy.yml up -d"
    echo ""
    echo -e "${CYAN}2. Deploy Authelia on your SSO machine:${NC}"
    echo -e "   Generated files:"
    echo -e "   • authelia/config/configuration.yml"
    echo -e "   • authelia/config/users_database.yml"
    echo -e "   • docker-compose.authelia.yml"
    echo -e "   • Copy these files to your Authelia machine"
    echo -e "   • Run: docker compose -f docker-compose.authelia.yml up -d"
    echo ""
    echo -e "${CYAN}3. Configure DNS:${NC}"
    echo -e "   Point these domains to your Caddy machine (${MATRIX_SERVER_IP}):"
    echo -e "   • ${MATRIX_DOMAIN}"
    echo -e "   • ${ELEMENT_DOMAIN}"
    echo -e "   • ${AUTH_DOMAIN}"
    echo -e "   • ${AUTHELIA_DOMAIN}"
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        echo -e "   • ${RTC_DOMAIN}"
        echo -e "   • ${CALL_DOMAIN}"
    fi
    echo ""
    echo -e "${CYAN}4. Configure Firewall:${NC}"
    echo -e "   Matrix server (${MATRIX_SERVER_IP}): Allow from Caddy"
    echo -e "   Authelia server (${AUTHELIA_SERVER_IP}): Allow from Caddy and Matrix"
    echo -e "   Caddy: Allow ports 80/443 from internet"
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        echo -e "   Matrix server (${MATRIX_SERVER_IP}): Allow port 7881/TCP and 50100-50200/UDP from internet (WebRTC)"
    fi
    echo ""
    echo -e "${BLUE}Authelia Login Credentials:${NC}"
    echo -e "  • Username:     admin"
    echo -e "  • Password:     ${ADMIN_PASSWORD}"
    echo -e "  ${RED}⚠ SAVE THIS PASSWORD!${NC}"
    echo ""
    echo -e "${BLUE}Access URLs (after DNS and Caddy setup):${NC}"
    echo -e "  • Element Web:  https://${ELEMENT_DOMAIN}"
    if [[ "$USE_FLUFFYCHAT" == true ]]; then
        echo -e "  • FluffyChat:   https://${FLUFFYCHAT_DOMAIN}"
    fi
    echo -e "  • Matrix API:   https://${MATRIX_DOMAIN}"
    echo -e "  • MAS (Auth):   https://${AUTH_DOMAIN}"
    echo -e "  • Authelia:     https://${AUTHELIA_DOMAIN}"
    if [[ "$USE_ELEMENT_CALL" == true ]]; then
        echo -e "  • Element Call: https://${CALL_DOMAIN}"
        echo -e "  • LiveKit JWT:  https://${RTC_DOMAIN}/livekit/jwt"
    fi
    echo ""
fi
echo -e "${BLUE}Useful Commands:${NC}"
_CMD="$DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE}${COMPOSE_PROFILES}"
echo -e "  • View logs:        ${_CMD} logs -f"
echo -e "  • Stop stack:       ${_CMD} down"
echo -e "  • Restart service:  ${_CMD} restart <service>"
echo -e "  • View status:      ${_CMD} ps"
echo ""
echo -e "${BLUE}Generated Files:${NC}"
echo -e "  • .env                              - Environment variables"
if [[ "$USE_AUTHELIA" == true ]]; then
    echo -e "  • authelia_private.pem              - Authelia RSA key"
fi
echo -e "  • mas-signing.key                   - MAS signing key"
if [[ "$USE_AUTHELIA" == true ]]; then
    echo -e "  • authelia/config/configuration.yml - Authelia config"
    echo -e "  • authelia/config/users_database.yml - User accounts"
fi
echo -e "  • mas/config/config.yaml            - MAS config"
echo -e "  • synapse/data/homeserver.yaml      - Synapse config"
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo -e "  • Using example.test domains (not .localhost) to avoid public suffix list issues"
echo -e "  • All critical bugfixes have been applied (see BUGFIXES.md for details)"
echo -e "  • MAS configured with assets resource and internal discovery"
if [[ "$USE_AUTHELIA" == true ]]; then
    echo -e "  • Authelia upstream provider enabled with fetch_userinfo and preferred_username claim"
    echo -e "  • SSL certificate trust configured for local development"
else
    echo -e "  • MAS handling password authentication directly (no upstream provider)"
fi
echo ""
echo -e "${BLUE}Troubleshooting:${NC}"
echo -e "  • If CSS is missing: Check that MAS has 'assets' resource in config"
echo -e "  • If login fails with empty string error: Verify fetch_userinfo: true in MAS"
echo -e "  • If redirect URI error: Check Authelia client redirect_uris include upstream callback"
echo -e "  • If SSL errors: Ensure mas/certs/caddy-ca.crt exists and MAS was restarted"
echo -e "  • For detailed troubleshooting: See BUGFIXES.md"
echo ""
echo -e "${YELLOW}Security Note:${NC}"
echo -e "  This is a local testing deployment with self-signed certificates."
echo -e "  For production: Use Let's Encrypt, enable 2FA, and review all configs."
echo -e "  See PRODUCTION.md for the distributed deployment guide."
echo ""
