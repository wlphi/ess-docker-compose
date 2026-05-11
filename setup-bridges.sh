#!/bin/bash
set -e

# Complete Bridge Setup Script with Double Puppet and Encryption Fix
source .env

echo "=== Setting up Mautrix Bridges with Double Puppet ==="

# Generate double puppet tokens
echo "Generating double puppet tokens..."
DOUBLEPUPPET_AS_TOKEN=$(openssl rand -hex 32)
DOUBLEPUPPET_HS_TOKEN=$(openssl rand -hex 32)

echo "  AS_TOKEN: $DOUBLEPUPPET_AS_TOKEN"
echo "  HS_TOKEN: $DOUBLEPUPPET_HS_TOKEN"

# Create appservices directory
mkdir -p appservices

# Create doublepuppet.yaml
echo "Creating doublepuppet appservice configuration..."
cat > appservices/doublepuppet.yaml << EOF
id: doublepuppet
url: null
as_token: "$DOUBLEPUPPET_AS_TOKEN"
hs_token: "$DOUBLEPUPPET_HS_TOKEN"
sender_localpart: doublepuppet
rate_limited: false

namespaces:
  users:
    - regex: "@.*:${MATRIX_DOMAIN}"
      exclusive: false
EOF

chmod 644 appservices/doublepuppet.yaml
echo "✓ Double puppet appservice created"

# Stop bridges
docker compose stop mautrix-telegram mautrix-whatsapp mautrix-signal 2>/dev/null || true

# Clean old configs
sudo rm -rf bridges/telegram/config/* bridges/whatsapp/config/* bridges/signal/config/*

# Start all bridges simultaneously to generate default configs, then stop
echo "Generating default bridge configs..."
docker compose up -d mautrix-telegram mautrix-whatsapp mautrix-signal 2>&1
sleep 20
docker compose stop mautrix-telegram mautrix-whatsapp mautrix-signal 2>&1

# -----------------------------------------------------------------------
# Configure Telegram bridge
# -----------------------------------------------------------------------
echo "Configuring Telegram bridge..."

# Telegram requires API credentials from my.telegram.org
if [ -z "${TELEGRAM_API_ID:-}" ] || [ -z "${TELEGRAM_API_HASH:-}" ]; then
    echo ""
    echo "⚠  TELEGRAM_API_ID and TELEGRAM_API_HASH are not set in .env"
    echo "   Obtain them at https://my.telegram.org"
    echo "   Add to .env and re-run this script to enable the Telegram bridge."
    echo "   Skipping Telegram configuration."
    echo ""
    SKIP_TELEGRAM=true
else
    SKIP_TELEGRAM=false
fi

# Homeserver endpoint (Telegram default: https://example.com, 4-space indent)
if [ "$SKIP_TELEGRAM" = "false" ]; then
sudo sed -i "s|    address: https://example.com|    address: http://synapse:8008|" bridges/telegram/config/config.yaml
# Homeserver domain
sudo sed -i "s|    domain: example.com|    domain: ${MATRIX_DOMAIN}|" bridges/telegram/config/config.yaml
# Bridge's own address
sudo sed -i "s|    address: http://localhost:29317|    address: http://mautrix-telegram:29317|" bridges/telegram/config/config.yaml
# Database
sudo sed -i "s|    uri: postgres://username:password@hostname/dbname?sslmode=disable|    uri: postgres://synapse:${POSTGRES_PASSWORD}@postgres/telegram?sslmode=disable|" bridges/telegram/config/config.yaml
# Permissions: remove all placeholder entries (sentinel for "not configured"), add domain admin
sudo sed -i "/'@admin:example.com': admin/d" bridges/telegram/config/config.yaml
sudo sed -i "/        example.com: full/d" bridges/telegram/config/config.yaml
sudo sed -i "/        public.example.com: user/d" bridges/telegram/config/config.yaml
sudo sed -i "/permissions:/a\\        '${MATRIX_DOMAIN}': admin" bridges/telegram/config/config.yaml
# Double puppet: replace placeholder in login_shared_secret_map (8-space entry)
sudo sed -i "s|        example.com: foobar|        ${MATRIX_DOMAIN}: as_token:${DOUBLEPUPPET_AS_TOKEN}|" bridges/telegram/config/config.yaml
# Telegram API credentials (required — obtained from my.telegram.org)
sudo sed -i "s|    api_id: 12345|    api_id: ${TELEGRAM_API_ID}|" bridges/telegram/config/config.yaml
sudo sed -i "s|    api_hash: tjyd5yge35lbodk1xwzw2jstp90k55qz|    api_hash: ${TELEGRAM_API_HASH}|" bridges/telegram/config/config.yaml
# Encryption: already false by default; set explicitly for safety (8-space fields inside bridge:)
sudo sed -i "s/^        allow: true$/        allow: false/" bridges/telegram/config/config.yaml
sudo sed -i "s/^        default: true$/        default: false/" bridges/telegram/config/config.yaml
sudo sed -i "s/^        msc4190: true$/        msc4190: false/" bridges/telegram/config/config.yaml

echo "✓ Telegram configured"
fi  # end SKIP_TELEGRAM

# -----------------------------------------------------------------------
# Configure WhatsApp bridge (megabridge format: 4-space field indentation)
# -----------------------------------------------------------------------
echo "Configuring WhatsApp bridge..."

# Homeserver endpoint (megabridge default: http://example.localhost:8008, 4-space indent)
sudo sed -i "s|    address: http://example.localhost:8008|    address: http://synapse:8008|" bridges/whatsapp/config/config.yaml
# Homeserver domain (4-space indent in megabridge format — NOT 2-space)
sudo sed -i "s|    domain: example.com|    domain: ${MATRIX_DOMAIN}|" bridges/whatsapp/config/config.yaml
# Bridge's own address
sudo sed -i "s|    address: http://localhost:29318|    address: http://mautrix-whatsapp:29318|" bridges/whatsapp/config/config.yaml
# Database
sudo sed -i "s|    uri: postgres://user:password@host/database?sslmode=disable|    uri: postgres://synapse:${POSTGRES_PASSWORD}@postgres/whatsapp?sslmode=disable|" bridges/whatsapp/config/config.yaml
# Listen on all interfaces (required for Docker: Synapse is on a different container)
sudo sed -i "s|    hostname: 127.0.0.1|    hostname: 0.0.0.0|" bridges/whatsapp/config/config.yaml
# Permissions: remove placeholder entries (8-space indent), add domain admin
sudo sed -i '/        "example.com": user/d' bridges/whatsapp/config/config.yaml
sudo sed -i '/        "@admin:example.com": admin/d' bridges/whatsapp/config/config.yaml
sudo sed -i "/permissions:/a\\        \"${MATRIX_DOMAIN}\": admin" bridges/whatsapp/config/config.yaml
# Double puppet: replace placeholder in secrets (already present in default config, 8-space indent)
sudo sed -i "s|        example.com: as_token:foobar|        ${MATRIX_DOMAIN}: as_token:${DOUBLEPUPPET_AS_TOKEN}|" bridges/whatsapp/config/config.yaml
# Encryption: already false by default; set explicitly for safety (4-space fields under top-level encryption:)
sudo sed -i "s/^    allow: true$/    allow: false/" bridges/whatsapp/config/config.yaml
sudo sed -i "s/^    default: true$/    default: false/" bridges/whatsapp/config/config.yaml
sudo sed -i "s/^    msc4190: true$/    msc4190: false/" bridges/whatsapp/config/config.yaml

echo "✓ WhatsApp configured"

# -----------------------------------------------------------------------
# Configure Signal bridge (megabridge format: 4-space field indentation)
# -----------------------------------------------------------------------
echo "Configuring Signal bridge..."

# Homeserver endpoint (megabridge default: http://example.localhost:8008, 4-space indent)
sudo sed -i "s|    address: http://example.localhost:8008|    address: http://synapse:8008|" bridges/signal/config/config.yaml
# Homeserver domain (4-space indent in megabridge format — NOT 2-space)
sudo sed -i "s|    domain: example.com|    domain: ${MATRIX_DOMAIN}|" bridges/signal/config/config.yaml
# Bridge's own address
sudo sed -i "s|    address: http://localhost:29328|    address: http://mautrix-signal:29328|" bridges/signal/config/config.yaml
# Database
sudo sed -i "s|    uri: postgres://user:password@host/database?sslmode=disable|    uri: postgres://synapse:${POSTGRES_PASSWORD}@postgres/signal?sslmode=disable|" bridges/signal/config/config.yaml
# Listen on all interfaces (required for Docker: Synapse is on a different container)
sudo sed -i "s|    hostname: 127.0.0.1|    hostname: 0.0.0.0|" bridges/signal/config/config.yaml
# Permissions: remove placeholder entries (8-space indent), add domain admin
sudo sed -i '/        "example.com": user/d' bridges/signal/config/config.yaml
sudo sed -i '/        "@admin:example.com": admin/d' bridges/signal/config/config.yaml
sudo sed -i "/permissions:/a\\        \"${MATRIX_DOMAIN}\": admin" bridges/signal/config/config.yaml
# Double puppet: replace placeholder in secrets (already present in default config, 8-space indent)
sudo sed -i "s|        example.com: as_token:foobar|        ${MATRIX_DOMAIN}: as_token:${DOUBLEPUPPET_AS_TOKEN}|" bridges/signal/config/config.yaml
# Encryption: already false by default; set explicitly for safety (4-space fields under top-level encryption:)
sudo sed -i "s/^    allow: true$/    allow: false/" bridges/signal/config/config.yaml
sudo sed -i "s/^    default: true$/    default: false/" bridges/signal/config/config.yaml
sudo sed -i "s/^    msc4190: true$/    msc4190: false/" bridges/signal/config/config.yaml

echo "✓ Signal configured"

# -----------------------------------------------------------------------
# Start bridges with valid configs so they generate registration.yaml
# -----------------------------------------------------------------------
echo "Starting bridges to generate registration files..."
docker compose up -d mautrix-telegram mautrix-whatsapp mautrix-signal 2>&1

echo "Waiting for registration files (up to 60s)..."
for i in $(seq 1 12); do
    sleep 5
    [ -f bridges/whatsapp/config/registration.yaml ] && WA_REG=1 || WA_REG=0
    [ -f bridges/signal/config/registration.yaml ]   && SIG_REG=1 || SIG_REG=0
    [ "$SKIP_TELEGRAM" = "true" ] && TG_REG=1 || { [ -f bridges/telegram/config/registration.yaml ] && TG_REG=1 || TG_REG=0; }
    if [ "$TG_REG" = "1" ] && [ "$WA_REG" = "1" ] && [ "$SIG_REG" = "1" ]; then
        echo "✓ All registration files generated"
        break
    fi
    echo "  attempt $i/12: telegram=$TG_REG whatsapp=$WA_REG signal=$SIG_REG"
done

# Make registration files readable by Synapse container user (bridge containers create them as root:root 600)
sudo chmod 644 bridges/whatsapp/config/registration.yaml bridges/signal/config/registration.yaml
[ "$SKIP_TELEGRAM" = "false" ] && sudo chmod 644 bridges/telegram/config/registration.yaml || true

# Stop bridges while we register them with Synapse
docker compose stop mautrix-telegram mautrix-whatsapp mautrix-signal 2>&1

# -----------------------------------------------------------------------
# Create databases
# -----------------------------------------------------------------------
docker exec matrix-postgres psql -U synapse -tc "SELECT 1 FROM pg_database WHERE datname = 'telegram'" | grep -q 1 || docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE telegram;"
docker exec matrix-postgres psql -U synapse -tc "SELECT 1 FROM pg_database WHERE datname = 'whatsapp'" | grep -q 1 || docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE whatsapp;"
docker exec matrix-postgres psql -U synapse -tc "SELECT 1 FROM pg_database WHERE datname = 'signal'" | grep -q 1 || docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE signal;"

# -----------------------------------------------------------------------
# Register all appservices with Synapse
# -----------------------------------------------------------------------
echo "Registering appservices with Synapse..."
# Remove previous section completely (idempotent — handles all partial states)
sudo sed -i '/^  - \/bridges\//d' synapse/data/homeserver.yaml
sudo sed -i '/^  - \/appservices\//d' synapse/data/homeserver.yaml
sudo sed -i '/^app_service_config_files:/d' synapse/data/homeserver.yaml
sudo sed -i '/^# Appservice registrations (bridges and double puppet)$/d' synapse/data/homeserver.yaml

# Write a fresh complete section
{
    printf '\n# Appservice registrations (bridges and double puppet)\n'
    printf 'app_service_config_files:\n'
    printf '  - /appservices/doublepuppet.yaml\n'
    [ "$SKIP_TELEGRAM" = "false" ] && printf '  - /bridges/telegram/config/registration.yaml\n' || true
    printf '  - /bridges/whatsapp/config/registration.yaml\n'
    printf '  - /bridges/signal/config/registration.yaml\n'
} | sudo tee -a synapse/data/homeserver.yaml > /dev/null

echo "✓ Appservice registrations added to homeserver.yaml"

# -----------------------------------------------------------------------
# Restart Synapse to load registrations, then start bridges
# -----------------------------------------------------------------------
echo "Restarting Synapse..."
docker compose restart synapse
sleep 20

echo "Starting bridges..."
if [ "$SKIP_TELEGRAM" = "false" ]; then
    docker compose up -d mautrix-telegram mautrix-whatsapp mautrix-signal
else
    docker compose up -d mautrix-whatsapp mautrix-signal
fi
sleep 15

echo ""
echo "=== Bridge setup complete! ==="
echo ""
echo "✓ Double puppet appservice: url=null (no Synapse transaction retries)"
echo "✓ All bridges configured with encryption disabled (MAS/MSC4190 incompatibility)"
echo "✓ All bridges configured with double puppet support"
echo ""
echo "Bridge status:"
docker compose ps | grep -E "bridge|signal|whatsapp|telegram"
echo ""
echo "Next steps:"
echo "  1. Check bridge logs: docker compose logs mautrix-whatsapp"
echo "  2. Invite bridge bots to a room and link your accounts"
echo "  3. Use unencrypted rooms for bridged messages"
echo ""
echo "To clear portal database and force room recreation (optional):"
echo "  docker exec matrix-postgres psql -U synapse -d whatsapp -c \"DELETE FROM portal;\""
echo "  docker restart matrix-bridge-whatsapp"
