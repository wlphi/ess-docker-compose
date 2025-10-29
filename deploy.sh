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

# Test docker access
if ! sudo docker ps &> /dev/null; then
    echo -e "${RED}Error: Cannot access Docker. Please ensure Docker is running.${NC}"
    exit 1
fi

clear
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
echo -e "  ${GREEN}1)${NC} Local Testing (All-in-One)"
echo -e "     → Everything on one machine with self-signed certificates"
echo -e "     → Uses *.localhost domains"
echo -e "     → Caddy + Authelia + Matrix stack together"
echo ""
echo -e "  ${GREEN}2)${NC} Production (Distributed)"
echo -e "     → Services on separate machines for security"
echo -e "     → Machine 1: Caddy (SSL termination)"
echo -e "     → Machine 2: Authelia (SSO)"
echo -e "     → Machine 3: Matrix stack (Synapse, Element, MAS, bridges)"
echo -e "     → Real domains with Let's Encrypt certificates"
echo ""
read -p "Enter choice [1 or 2]: " DEPLOYMENT_TYPE

if [[ "$DEPLOYMENT_TYPE" == "1" ]]; then
    DEPLOYMENT_MODE="local"
    COMPOSE_FILE="compose-variants/docker-compose.local.yml"
    echo -e "${GREEN}✓${NC} Selected: Local Testing Mode"
elif [[ "$DEPLOYMENT_TYPE" == "2" ]]; then
    DEPLOYMENT_MODE="production"
    COMPOSE_FILE="docker-compose.yml"
    echo -e "${GREEN}✓${NC} Selected: Production Mode"
else
    echo -e "${RED}✗${NC} Invalid choice. Exiting."
    exit 1
fi
echo ""

# ============================================================================
# DATA DIRECTORY CHECK
# ============================================================================
echo -e "${YELLOW}Checking for existing data directories...${NC}"

EXISTING_DATA=""
[[ -d "postgres/data" ]] && [[ "$(ls -A postgres/data 2>/dev/null)" ]] && EXISTING_DATA="${EXISTING_DATA}postgres/data "
[[ -d "synapse/data" ]] && [[ -f "synapse/data/homeserver.yaml" ]] && EXISTING_DATA="${EXISTING_DATA}synapse/data "
[[ -d "mas/data" ]] && [[ "$(ls -A mas/data 2>/dev/null)" ]] && EXISTING_DATA="${EXISTING_DATA}mas/data "

if [[ -n "$EXISTING_DATA" ]]; then
    echo -e "${RED}⚠ WARNING: Existing data directories found:${NC}"
    for dir in $EXISTING_DATA; do
        echo -e "  • $dir"
    done
    echo ""
    echo -e "${YELLOW}These directories contain data from a previous deployment.${NC}"
    echo -e "${YELLOW}If you continue, services may fail to start due to:${NC}"
    echo -e "  • Mismatched passwords (old DB password != new .env password)"
    echo -e "  • Stale configurations"
    echo -e "  • Database schema conflicts"
    echo ""
    echo -e "${CYAN}Recommended actions:${NC}"
    echo -e "  1) ${GREEN}Clean slate${NC} - Delete all data and start fresh (recommended for testing)"
    echo -e "  2) ${YELLOW}Keep data${NC}   - Continue with existing data (may cause errors)"
    echo -e "  3) ${RED}Abort${NC}       - Exit and manually backup/clean data"
    echo ""
    read -p "Choose [1/2/3]: " DATA_CHOICE

    case "$DATA_CHOICE" in
        1)
            echo -e "${YELLOW}Cleaning data directories...${NC}"
            sudo rm -rf postgres/data synapse/data mas/data mas/certs caddy/data caddy/config
            mkdir -p postgres/data synapse/data mas/data mas/certs caddy/data caddy/config
            echo -e "${GREEN}✓${NC} Data directories cleaned"
            echo ""
            ;;
        2)
            echo -e "${YELLOW}⚠ Continuing with existing data...${NC}"
            echo -e "${RED}Note: Deployment may fail due to password/config mismatches!${NC}"
            echo ""
            ;;
        3)
            echo -e "${BLUE}Exiting. Please backup or clean your data manually.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Exiting.${NC}"
            exit 1
            ;;
    esac
else
    echo -e "${GREEN}✓${NC} No existing data found - starting with clean slate"
    echo ""
fi

# ============================================================================
# AUTHELIA SSO SELECTION
# ============================================================================
echo -e "${CYAN}Include Authelia SSO?${NC}"
echo ""
echo -e "  ${GREEN}Yes)${NC} Use Authelia as upstream OAuth provider"
echo -e "       → Full SSO with 2FA support"
echo -e "       → Users authenticate through Authelia"
echo -e "       → Additional authentication layer"
echo ""
echo -e "  ${GREEN}No)${NC}  MAS handles authentication directly"
echo -e "       → Simpler setup, fewer moving parts"
echo -e "       → MAS manages users directly"
echo -e "       → Password-based authentication"
echo ""
read -p "Include Authelia? [y/N]: " INCLUDE_AUTHELIA

if [[ "$INCLUDE_AUTHELIA" =~ ^[Yy]$ ]]; then
    USE_AUTHELIA=true
    echo -e "${GREEN}✓${NC} Authelia SSO will be included"
else
    USE_AUTHELIA=false
    echo -e "${GREEN}✓${NC} MAS will handle authentication directly (no Authelia)"
fi
echo ""

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
    AUTH_DOMAIN="auth.example.test"
    AUTHELIA_DOMAIN="authelia.example.test"

    echo -e "${CYAN}Local Testing Configuration:${NC}"
    echo -e "  Matrix API:  https://${MATRIX_DOMAIN}"
    echo -e "  Element Web: https://${ELEMENT_DOMAIN}"
    echo -e "  MAS Auth:    https://${AUTH_DOMAIN}"
    echo -e "  Authelia:    https://${AUTHELIA_DOMAIN}"
    echo ""
    echo -e "${YELLOW}⚠ Remember to add these to /etc/hosts:${NC}"
    echo -e "  127.0.0.1  ${MATRIX_DOMAIN} ${ELEMENT_DOMAIN} ${AUTH_DOMAIN} ${AUTHELIA_DOMAIN}"
    echo -e "  ::1        ${MATRIX_DOMAIN} ${ELEMENT_DOMAIN} ${AUTH_DOMAIN} ${AUTHELIA_DOMAIN}"
    echo ""
    echo -e "${BLUE}ℹ Note: IPv6 entry (::1) required to prevent DNS lookups bypassing /etc/hosts${NC}"
    echo ""
    read -p "Press Enter to continue..."
    echo ""

else
    # Production deployment
    echo -e "${CYAN}Production Deployment Configuration${NC}"
    echo ""

    # Base domain
    read -p "Enter your base domain (e.g., example.com): " DOMAIN_BASE
    AUTHELIA_COOKIE_DOMAIN="${DOMAIN_BASE}"  # Production uses the base domain

    # Matrix subdomain
    read -p "Enter Matrix subdomain [default: matrix]: " MATRIX_SUBDOMAIN
    MATRIX_SUBDOMAIN=${MATRIX_SUBDOMAIN:-matrix}
    MATRIX_DOMAIN="${MATRIX_SUBDOMAIN}.${DOMAIN_BASE}"

    # Element subdomain
    read -p "Enter Element subdomain [default: element]: " ELEMENT_SUBDOMAIN
    ELEMENT_SUBDOMAIN=${ELEMENT_SUBDOMAIN:-element}
    ELEMENT_DOMAIN="${ELEMENT_SUBDOMAIN}.${DOMAIN_BASE}"

    # MAS subdomain
    read -p "Enter MAS/Auth subdomain [default: auth]: " AUTH_SUBDOMAIN
    AUTH_SUBDOMAIN=${AUTH_SUBDOMAIN:-auth}
    AUTH_DOMAIN="${AUTH_SUBDOMAIN}.${DOMAIN_BASE}"

    # Authelia subdomain
    read -p "Enter Authelia subdomain [default: authelia]: " AUTHELIA_SUBDOMAIN
    AUTHELIA_SUBDOMAIN=${AUTHELIA_SUBDOMAIN:-authelia}
    AUTHELIA_DOMAIN="${AUTHELIA_SUBDOMAIN}.${DOMAIN_BASE}"

    # Set placeholder values for multi-machine deployment
    # (These will be used in generated Caddyfile template - update manually on Caddy server)
    MATRIX_SERVER_IP="10.0.1.10"
    AUTHELIA_SERVER_IP="10.0.1.20"
    LETSENCRYPT_EMAIL="admin@${DOMAIN_BASE}"

    echo ""
    echo -e "${GREEN}✓${NC} Configuration Summary:"
    echo -e "  Base Domain:     ${DOMAIN_BASE}"
    echo -e "  Matrix:          https://${MATRIX_DOMAIN}"
    echo -e "  Element:         https://${ELEMENT_DOMAIN}"
    echo -e "  MAS:             https://${AUTH_DOMAIN}"
    echo -e "  Authelia:        https://${AUTHELIA_DOMAIN}"
    echo ""
    print_info "Note: For multi-machine deployment, use MULTI_MACHINE_CONFIG_SNIPPETS.md"
    print_info "      Copy generated configs from authelia/config/ to your Authelia server"
    echo ""
fi

# Step 1: Check prerequisites
echo -e "${BLUE}[1/13] Checking prerequisites...${NC}"
if ! command -v openssl &> /dev/null; then
    print_error "openssl is not installed"
    exit 1
fi
if ! $DOCKER_CMD --version &> /dev/null; then
    print_error "Docker is not accessible"
    exit 1
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
mkdir -p bridges/{telegram,whatsapp,signal}/config
print_status "Directory structure created"
echo ""

# Step 2: Generate secure secrets
echo -e "${BLUE}[2/12] Generating secure secrets...${NC}"
POSTGRES_PASSWORD=$(generate_secret)
AUTHELIA_JWT_SECRET=$(generate_secret)
AUTHELIA_SESSION_SECRET=$(generate_secret)
AUTHELIA_STORAGE_ENCRYPTION_KEY=$(generate_secret)
MAS_SECRET_KEY=$(generate_hex_secret)  # MAS requires hex format
SYNAPSE_SHARED_SECRET=$(generate_secret)
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
AUTH_DOMAIN=${AUTH_DOMAIN}
AUTHELIA_DOMAIN=${AUTHELIA_DOMAIN}
SERVER_NAME=${MATRIX_DOMAIN}

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
EOF

# Add production-specific variables
if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
    cat >> .env << EOF

# Production Configuration (Placeholder values for multi-machine deployment)
# For multi-machine: Update these on your Caddy server's Caddyfile
MATRIX_SERVER_IP=${MATRIX_SERVER_IP}
AUTHELIA_SERVER_IP=${AUTHELIA_SERVER_IP}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
EOF
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

    # Step 5: Generate client secret for Authelia
    echo -e "${BLUE}[5/13] Generating Authelia client secret...${NC}"
    CLIENT_SECRET_PLAIN=$(generate_secret)
    # Generate hash for Authelia config
    CLIENT_SECRET_HASH=$($DOCKER_CMD run --rm authelia/authelia:latest authelia crypto hash generate pbkdf2 --variant sha512 --password "${CLIENT_SECRET_PLAIN}" 2>/dev/null | grep "Digest:" | awk '{print $2}')
    print_status "Client secret generated"
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
  homeserver: '${MATRIX_DOMAIN}'
  endpoint: 'http://synapse:8008'
  secret: '${SYNAPSE_SHARED_SECRET}'

passwords:
  enabled: false  # Using Authelia SSO instead
EOF
else
    # Without Authelia: MAS handles authentication directly
    cat >> mas/config/config.yaml << EOF

matrix:
  homeserver: '${MATRIX_DOMAIN}'
  endpoint: 'http://synapse:8008'
  secret: '${SYNAPSE_SHARED_SECRET}'

passwords:
  enabled: true  # MAS handles password authentication directly
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
  registration:
    enabled: true
    require_email: true

clients:
  # Element Web client (public)
  - client_id: '01HQW90Z35CMXFJWQPHC3BGZGQ'
    client_auth_method: none
    redirect_uris:
      - 'https://${ELEMENT_DOMAIN}'
      - 'https://${ELEMENT_DOMAIN}/mobile_guide/'
      - 'io.element.app:/callback'

  # Synapse client (confidential - for backend integration)
  - client_id: '0000000000000000000SYNAPSE'
    client_auth_method: client_secret_basic
    client_secret: '${SYNAPSE_CLIENT_SECRET}'
EOF

if [[ "$USE_AUTHELIA" == true ]]; then
    print_status "MAS configuration created (with Authelia upstream provider)"
else
    print_status "MAS configuration created (password authentication enabled)"
fi
echo ""

# Step 11: Create Element Web configuration
echo -e "${BLUE}[11/13] Creating Element Web configuration...${NC}"
cat > element/config/config.json << EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://${MATRIX_DOMAIN}",
            "server_name": "${MATRIX_DOMAIN}"
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
        "feature_oidc_aware_navigation": true
    },
    "default_server_name": "${MATRIX_DOMAIN}",
    "disable_custom_urls": false,
    "disable_guests": true
}
EOF
print_status "Element Web configuration created"
echo ""

# Step 12: Generate Synapse configuration
echo -e "${BLUE}[12/13] Generating Synapse configuration...${NC}"
if [ ! -f "synapse/data/homeserver.yaml" ]; then
    $DOCKER_CMD run -it --rm \
        -v $(pwd)/synapse/data:/data \
        -e SYNAPSE_SERVER_NAME=${MATRIX_DOMAIN} \
        -e SYNAPSE_REPORT_STATS=no \
        matrixdotorg/synapse:latest generate

    # Update Synapse config for PostgreSQL
    print_info "Configuring Synapse for PostgreSQL..."

    # Backup original config
    cp synapse/data/homeserver.yaml synapse/data/homeserver.yaml.bak

    # Remove the default SQLite database configuration (4 lines)
    # database:
    #   name: sqlite3
    #   args:
    #     database: /data/homeserver.db
    sed -i '/^database:/,+3d' synapse/data/homeserver.yaml

    # Add PostgreSQL config
    cat >> synapse/data/homeserver.yaml << EOF

# PostgreSQL Database Configuration (added by deploy.sh)
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

# MAS Integration (MSC3861 - OAuth delegation)
experimental_features:
  msc3861:
    enabled: true
    issuer: https://${AUTH_DOMAIN}/
    client_id: 0000000000000000000SYNAPSE
    client_auth_method: client_secret_basic
    client_secret: ${SYNAPSE_CLIENT_SECRET}
    admin_token: ${SYNAPSE_SHARED_SECRET}
EOF

    print_status "Synapse configuration generated and updated"
else
    print_warning "Synapse config already exists, skipping generation"
fi
echo ""

# Step 13: Fix directory permissions
echo -e "${BLUE}[13/14] Fixing directory permissions...${NC}"
chmod 755 postgres/init postgres/config 2>/dev/null || true
chmod 644 postgres/init/*.sql 2>/dev/null || true
chmod 755 authelia/config mas/config element/config 2>/dev/null || true
print_status "Permissions fixed"
echo ""

# Step 14: Start the stack
echo -e "${BLUE}[14/14] Starting the Matrix stack...${NC}"
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

# Start remaining services
if [[ "$USE_AUTHELIA" == true ]]; then
    print_info "Starting all services (with Authelia)..."
    $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} --profile authelia up -d
else
    print_info "Starting all services (without Authelia)..."
    $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} up -d
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

    # Wait for Caddy to generate CA
    print_info "Waiting for Caddy to generate local CA..."
    sleep 5

    # Trigger HTTPS requests to force Caddy to generate certificates
    print_info "Triggering certificate generation..."
    curl -k https://${AUTH_DOMAIN} > /dev/null 2>&1 || true
    sleep 3

    # Copy CA certificate from host path (Caddy saves to volume)
    if [ -f "caddy/data/caddy/pki/authorities/local/root.crt" ]; then
        cp caddy/data/caddy/pki/authorities/local/root.crt mas/certs/caddy-ca.crt
        chmod 644 mas/certs/caddy-ca.crt
        print_status "Caddy CA certificate copied to mas/certs/caddy-ca.crt"

        # Restart MAS to pick up the certificate
        print_info "Restarting MAS to load CA certificate..."
        $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} restart mas
        sleep 5
        print_status "MAS restarted with trusted CA certificate"
    else
        print_warning "Could not find Caddy CA certificate at caddy/data/caddy/pki/authorities/local/root.crt"
        print_info "You may need to manually copy it after Caddy generates it"
        print_info "Run: cp caddy/data/caddy/pki/authorities/local/root.crt mas/certs/caddy-ca.crt"
        print_info "Then restart MAS: $DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} restart mas"
    fi
    echo ""
fi

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
    cat > caddy/Caddyfile.production << EOF
# Production Caddyfile for Matrix Stack
# Deploy this on your SSL termination machine
# Email for Let's Encrypt: ${LETSENCRYPT_EMAIL}

{
    email ${LETSENCRYPT_EMAIL}
    # Enable admin API (restrict access in firewall)
    admin 0.0.0.0:2019
}

# =========================
# Matrix Homeserver
# =========================
${MATRIX_DOMAIN} {
    # Well-known client endpoint
    @wk path /.well-known/matrix/client
    handle @wk {
        header Content-Type application/json
        respond \`{"m.homeserver":{"base_url":"https://${MATRIX_DOMAIN}"},"m.authentication":{"issuer":"https://${AUTH_DOMAIN}/"}}\` 200
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
        reverse_proxy ${MATRIX_SERVER_IP}:8008
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

    # MAS compat endpoints
    @compat path /_matrix/client/v3/login* /_matrix/client/v3/logout* /_matrix/client/v3/refresh* /_matrix/client/r0/login* /_matrix/client/r0/logout* /_matrix/client/r0/refresh*
    handle @compat {
        header Access-Control-Allow-Origin "*"
        reverse_proxy ${MATRIX_SERVER_IP}:8080
    }

    # Everything else to Synapse
    @matrix_rest path_regexp matrix ^/_matrix/.*$
    handle @matrix_rest {
        header Access-Control-Allow-Origin "*"
        reverse_proxy ${MATRIX_SERVER_IP}:8008
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
        reverse_proxy ${MATRIX_SERVER_IP}:8080
    }

    # OAuth2 endpoints
    @oauth path /oauth2/*
    route @oauth {
        header ?Access-Control-Allow-Origin "*"
        reverse_proxy ${MATRIX_SERVER_IP}:8080
    }

    # Account portal
    handle_path /account/* {
        reverse_proxy ${MATRIX_SERVER_IP}:8080
    }

    handle {
        reverse_proxy ${MATRIX_SERVER_IP}:8080
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
    @cfg path /config.json
    handle @cfg {
        header Content-Type application/json
        header Cache-Control no-store
        respond \`{"default_server_config":{"m.homeserver":{"base_url":"https://${MATRIX_DOMAIN}","server_name":"${MATRIX_DOMAIN}"}},"default_server_name":"${MATRIX_DOMAIN}","disable_custom_urls":false,"disable_guests":true,"features":{"feature_oidc_aware_navigation":true}}\` 200
    }

    handle {
        reverse_proxy ${MATRIX_SERVER_IP}:8090
    }
}
EOF

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
echo -e "${BLUE}Service Status:${NC}"
$DOCKER_COMPOSE_CMD -f ${COMPOSE_FILE} ps
echo ""

echo -e "${GREEN}✓ Matrix stack is now running!${NC}"
echo ""

if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
    echo -e "${BLUE}Access Points (HTTPS with self-signed certificates):${NC}"
    echo -e "  • Element Web:  https://${ELEMENT_DOMAIN}"
    echo -e "  • Matrix API:   https://${MATRIX_DOMAIN}"
    echo -e "  • MAS (Auth):   https://${AUTH_DOMAIN}"
    if [[ "$USE_AUTHELIA" == true ]]; then
        echo -e "  • Authelia:     https://${AUTHELIA_DOMAIN}"
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
else
    # Production mode
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
    echo ""
    echo -e "${CYAN}4. Configure Firewall:${NC}"
    echo -e "   Matrix server (${MATRIX_SERVER_IP}): Allow from Caddy"
    echo -e "   Authelia server (${AUTHELIA_SERVER_IP}): Allow from Caddy and Matrix"
    echo -e "   Caddy: Allow ports 80/443 from internet"
    echo ""
    echo -e "${BLUE}Authelia Login Credentials:${NC}"
    echo -e "  • Username:     admin"
    echo -e "  • Password:     ${ADMIN_PASSWORD}"
    echo -e "  ${RED}⚠ SAVE THIS PASSWORD!${NC}"
    echo ""
    echo -e "${BLUE}Access URLs (after DNS and Caddy setup):${NC}"
    echo -e "  • Element Web:  https://${ELEMENT_DOMAIN}"
    echo -e "  • Matrix API:   https://${MATRIX_DOMAIN}"
    echo -e "  • MAS (Auth):   https://${AUTH_DOMAIN}"
    echo -e "  • Authelia:     https://${AUTHELIA_DOMAIN}"
    echo ""
fi
echo -e "${BLUE}Useful Commands:${NC}"
if [[ "$USE_AUTHELIA" == true ]]; then
    echo -e "  • View logs:        $DOCKER_COMPOSE_CMD --profile authelia logs -f"
    echo -e "  • Stop stack:       $DOCKER_COMPOSE_CMD --profile authelia down"
    echo -e "  • Restart service:  $DOCKER_COMPOSE_CMD --profile authelia restart <service>"
    echo -e "  • View status:      $DOCKER_COMPOSE_CMD --profile authelia ps"
else
    echo -e "  • View logs:        $DOCKER_COMPOSE_CMD logs -f"
    echo -e "  • Stop stack:       $DOCKER_COMPOSE_CMD down"
    echo -e "  • Restart service:  $DOCKER_COMPOSE_CMD restart <service>"
    echo -e "  • View status:      $DOCKER_COMPOSE_CMD ps"
fi
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
