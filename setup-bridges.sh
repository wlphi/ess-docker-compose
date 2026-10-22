#!/bin/bash
set -e

# Complete Bridge Setup Script with Double Puppet and Encryption Fix
#
# Configures all five mautrix bridges:
#   - WhatsApp, Signal, Telegram, Slack: Go megabridge (bridgev2) config format
#   - Discord: legacy mautrix-go config format (no bridgev2 release yet)
#
# The configure_* functions only edit the config file they are given, so
# test_deploy.sh can source this script and run them against default configs.

# Use sudo for files the bridge containers create as root; tests set SUDO="".
SUDO=${SUDO-sudo}

# Domain used in Matrix IDs (@user:<server name>). deploy.sh writes SERVER_NAME
# to .env; quickstart.sh always uses the Matrix subdomain as the server name.
bridge_server_name() {
    echo "${SERVER_NAME:-$MATRIX_DOMAIN}"
}

# configure_megabridge <config.yaml> <name> <port>
# Shared settings for bridgev2 bridges (4-space field indentation).
configure_megabridge() {
    local cfg=$1 name=$2 port=$3
    local server_name
    server_name=$(bridge_server_name)

    # Homeserver endpoint (megabridge default: http://example.localhost:8008)
    $SUDO sed -i "s|    address: http://example.localhost:8008|    address: http://synapse:8008|" "$cfg"
    # Homeserver domain (server name, not the Matrix API host)
    $SUDO sed -i "s|    domain: example.com|    domain: ${server_name}|" "$cfg"
    # Bridge's own address
    $SUDO sed -i "s|    address: http://localhost:${port}|    address: http://mautrix-${name}:${port}|" "$cfg"
    # Database
    $SUDO sed -i "s|    uri: postgres://user:password@host/database?sslmode=disable|    uri: postgres://synapse:${POSTGRES_PASSWORD}@postgres/${name}?sslmode=disable|" "$cfg"
    # Listen on all interfaces (required for Docker: Synapse is on a different container)
    $SUDO sed -i "s|    hostname: 127.0.0.1|    hostname: 0.0.0.0|" "$cfg"
    # Permissions: remove placeholder entries (8-space indent), add domain admin
    $SUDO sed -i '/        "example.com": user/d' "$cfg"
    $SUDO sed -i '/        "@admin:example.com": admin/d' "$cfg"
    $SUDO sed -i "/^    permissions:/a\\        \"${server_name}\": admin" "$cfg"
    # Double puppet: replace placeholder in double_puppet.secrets (8-space indent)
    $SUDO sed -i "s|        example.com: as_token:foobar|        ${server_name}: as_token:${DOUBLEPUPPET_AS_TOKEN}|" "$cfg"
    # Encryption: already false by default; set explicitly for safety (4-space fields under top-level encryption:)
    $SUDO sed -i "s/^    allow: true$/    allow: false/" "$cfg"
    $SUDO sed -i "s/^    default: true$/    default: false/" "$cfg"
    $SUDO sed -i "s/^    msc4190: true$/    msc4190: false/" "$cfg"
}

# configure_telegram <config.yaml> — megabridge settings plus API credentials
configure_telegram() {
    local cfg=$1
    configure_megabridge "$cfg" telegram 29317
    # Telegram API credentials (required — obtained from my.telegram.org), under network:
    $SUDO sed -i "s|    api_id: 12345|    api_id: ${TELEGRAM_API_ID}|" "$cfg"
    $SUDO sed -i "s|    api_hash: tjyd5yge35lbodk1xwzw2jstp90k55qz|    api_hash: ${TELEGRAM_API_HASH}|" "$cfg"
}

# configure_discord <config.yaml> — legacy mautrix-go format: settings nested
# under appservice:/bridge: with 8-space fields
configure_discord() {
    local cfg=$1
    local server_name
    server_name=$(bridge_server_name)

    # Homeserver endpoint and domain (legacy default: https://matrix.example.com)
    $SUDO sed -i "s|    address: https://matrix.example.com|    address: http://synapse:8008|" "$cfg"
    $SUDO sed -i "s|    domain: example.com|    domain: ${server_name}|" "$cfg"
    # Bridge's own address (hostname already defaults to 0.0.0.0)
    $SUDO sed -i "s|    address: http://localhost:29334|    address: http://mautrix-discord:29334|" "$cfg"
    # Database (nested under appservice.database)
    $SUDO sed -i "s|        uri: postgres://user:password@host/database?sslmode=disable|        uri: postgres://synapse:${POSTGRES_PASSWORD}@postgres/discord?sslmode=disable|" "$cfg"
    # Permissions: remove placeholder entries (8-space indent), add domain admin
    $SUDO sed -i '/        "example.com": user/d' "$cfg"
    $SUDO sed -i '/        "@admin:example.com": admin/d' "$cfg"
    $SUDO sed -i "/^    permissions:/a\\        \"${server_name}\": admin" "$cfg"
    # Double puppet: drop placeholder server map entry, set shared secret (as_token: form)
    $SUDO sed -i "/        example.com: https:\/\/example.com/d" "$cfg"
    $SUDO sed -i "s|        example.com: foobar|        ${server_name}: as_token:${DOUBLEPUPPET_AS_TOKEN}|" "$cfg"
    # Encryption: already false by default; set explicitly for safety (8-space fields under bridge.encryption:)
    $SUDO sed -i "s/^        allow: true$/        allow: false/" "$cfg"
    $SUDO sed -i "s/^        default: true$/        default: false/" "$cfg"
    $SUDO sed -i "s/^        msc4190: true$/        msc4190: false/" "$cfg"
}

# A config written by the legacy Python mautrix-telegram has a top-level
# telegram: section; the Go bridge uses network: instead.
is_legacy_telegram_config() {
    $SUDO grep -q '^telegram:' "$1" 2>/dev/null
}

main() {
    source .env

    local server_name
    server_name=$(bridge_server_name)
    local ALL_BRIDGES=(mautrix-telegram mautrix-whatsapp mautrix-signal mautrix-discord mautrix-slack)

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
    - regex: "@.*:${server_name}"
      exclusive: false
EOF

    chmod 644 appservices/doublepuppet.yaml
    echo "✓ Double puppet appservice created"

    # Telegram requires API credentials from my.telegram.org
    if [ -z "${TELEGRAM_API_ID:-}" ] || [ -z "${TELEGRAM_API_HASH:-}" ]; then
        echo ""
        echo "⚠  TELEGRAM_API_ID and TELEGRAM_API_HASH are not set in .env"
        echo "   Obtain them at https://my.telegram.org"
        echo "   Add to .env and re-run this script to enable the Telegram bridge."
        echo "   Skipping Telegram configuration."
        echo ""
        SKIP_TELEGRAM=true
    elif is_legacy_telegram_config bridges/telegram/config/config.yaml && [ "${TELEGRAM_LEGACY_ACK:-}" != "true" ]; then
        # The Go rewrite (v26.04+) migrates a Python bridge database in place,
        # but v26.10 removed that migration: an existing Python install must
        # pass through v26.04–v26.09 first.
        echo ""
        echo "⚠  Existing Telegram bridge uses the legacy Python config format."
        echo "   mautrix-telegram v26.10+ can no longer migrate a Python bridge database."
        echo "   To keep your existing Telegram portals:"
        echo "     1. Set TELEGRAM_IMAGE=dock.mau.dev/mautrix/telegram:v26.09 in .env"
        echo "     2. Re-run this script with TELEGRAM_LEGACY_ACK=true and check the bridge logs"
        echo "     3. Then remove TELEGRAM_IMAGE from .env (back to the pinned default)"
        echo "   To start fresh instead: drop the 'telegram' database and re-run with TELEGRAM_LEGACY_ACK=true."
        echo "   Skipping Telegram configuration."
        echo ""
        SKIP_TELEGRAM=true
    else
        SKIP_TELEGRAM=false
    fi

    # Stop bridges
    docker compose stop "${ALL_BRIDGES[@]}" 2>/dev/null || true

    # Clean old configs (keep a skipped legacy Telegram config so the warning persists)
    if [ "$SKIP_TELEGRAM" = "false" ]; then
        $SUDO rm -rf bridges/telegram/config/*
    fi
    $SUDO rm -rf bridges/whatsapp/config/* bridges/signal/config/* bridges/discord/config/* bridges/slack/config/*

    # Start the bridges simultaneously to generate default configs, then stop.
    # A skipped Telegram bridge is left alone (a legacy config must not be touched).
    local GEN_BRIDGES=(mautrix-whatsapp mautrix-signal mautrix-discord mautrix-slack)
    [ "$SKIP_TELEGRAM" = "false" ] && GEN_BRIDGES=(mautrix-telegram "${GEN_BRIDGES[@]}")
    echo "Generating default bridge configs..."
    docker compose up -d "${GEN_BRIDGES[@]}" 2>&1
    sleep 20
    docker compose stop "${GEN_BRIDGES[@]}" 2>&1

    # -----------------------------------------------------------------------
    # Configure bridges
    # -----------------------------------------------------------------------
    if [ "$SKIP_TELEGRAM" = "false" ]; then
        echo "Configuring Telegram bridge..."
        configure_telegram bridges/telegram/config/config.yaml
        echo "✓ Telegram configured"
    fi

    echo "Configuring WhatsApp bridge..."
    configure_megabridge bridges/whatsapp/config/config.yaml whatsapp 29318
    echo "✓ WhatsApp configured"

    echo "Configuring Signal bridge..."
    configure_megabridge bridges/signal/config/config.yaml signal 29328
    echo "✓ Signal configured"

    echo "Configuring Slack bridge..."
    configure_megabridge bridges/slack/config/config.yaml slack 29335
    echo "✓ Slack configured"

    echo "Configuring Discord bridge..."
    configure_discord bridges/discord/config/config.yaml
    echo "✓ Discord configured"

    # Bridges that will be registered and started
    local ACTIVE=(whatsapp signal discord slack)
    [ "$SKIP_TELEGRAM" = "false" ] && ACTIVE=(telegram "${ACTIVE[@]}")
    local ACTIVE_SERVICES=("${ACTIVE[@]/#/mautrix-}")

    # -----------------------------------------------------------------------
    # Start bridges with valid configs so they generate registration.yaml
    # -----------------------------------------------------------------------
    echo "Starting bridges to generate registration files..."
    docker compose up -d "${ACTIVE_SERVICES[@]}" 2>&1

    echo "Waiting for registration files (up to 60s)..."
    local i b status missing
    for i in $(seq 1 12); do
        sleep 5
        status=""
        missing=0
        for b in "${ACTIVE[@]}"; do
            if [ -f "bridges/$b/config/registration.yaml" ]; then
                status="$status $b=1"
            else
                status="$status $b=0"
                missing=1
            fi
        done
        if [ "$missing" = "0" ]; then
            echo "✓ All registration files generated"
            break
        fi
        echo "  attempt $i/12:$status"
    done

    # Make registration files readable by Synapse container user (bridge containers create them as root:root 600)
    for b in "${ACTIVE[@]}"; do
        $SUDO chmod 644 "bridges/$b/config/registration.yaml" || true
    done

    # Stop bridges while we register them with Synapse
    docker compose stop "${ACTIVE_SERVICES[@]}" 2>&1

    # -----------------------------------------------------------------------
    # Create databases
    # -----------------------------------------------------------------------
    for b in "${ACTIVE[@]}"; do
        docker exec matrix-postgres psql -U synapse -tc "SELECT 1 FROM pg_database WHERE datname = '$b'" | grep -q 1 \
            || docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE $b;"
    done

    # -----------------------------------------------------------------------
    # Register all appservices with Synapse
    # -----------------------------------------------------------------------
    echo "Registering appservices with Synapse..."
    # Remove previous section completely (idempotent — handles all partial states)
    $SUDO sed -i '/^  - \/bridges\//d' synapse/data/homeserver.yaml
    $SUDO sed -i '/^  - \/appservices\//d' synapse/data/homeserver.yaml
    $SUDO sed -i '/^app_service_config_files:/d' synapse/data/homeserver.yaml
    $SUDO sed -i '/^# Appservice registrations (bridges and double puppet)$/d' synapse/data/homeserver.yaml

    # Write a fresh complete section (hookshot keeps its registration when its profile is enabled)
    {
        printf '\n# Appservice registrations (bridges and double puppet)\n'
        printf 'app_service_config_files:\n'
        printf '  - /appservices/doublepuppet.yaml\n'
        [ "${USE_HOOKSHOT:-false}" = "true" ] && [ -f appservices/hookshot.yaml ] && printf '  - /appservices/hookshot.yaml\n' || true
        for b in "${ACTIVE[@]}"; do
            printf '  - /bridges/%s/config/registration.yaml\n' "$b"
        done
    } | $SUDO tee -a synapse/data/homeserver.yaml > /dev/null

    echo "✓ Appservice registrations added to homeserver.yaml"

    # -----------------------------------------------------------------------
    # Restart Synapse to load registrations, then start bridges
    # -----------------------------------------------------------------------
    echo "Restarting Synapse..."
    docker compose restart synapse
    sleep 20

    echo "Starting bridges..."
    docker compose up -d "${ACTIVE_SERVICES[@]}"
    sleep 15

    echo ""
    echo "=== Bridge setup complete! ==="
    echo ""
    echo "✓ Double puppet appservice: url=null (no Synapse transaction retries)"
    echo "✓ All bridges configured with encryption disabled (MAS/MSC4190 incompatibility)"
    echo "✓ All bridges configured with double puppet support"
    echo ""
    echo "Bridge status:"
    docker compose ps | grep -E "bridge" || true
    echo ""
    echo "Next steps:"
    echo "  1. Check bridge logs: docker compose logs mautrix-whatsapp"
    echo "  2. Start a DM with a bridge bot (e.g. @whatsappbot:${server_name}) and send 'login'"
    echo "  3. Use unencrypted rooms for bridged messages"
    echo ""
    echo "To clear portal database and force room recreation (optional):"
    echo "  docker exec matrix-postgres psql -U synapse -d whatsapp -c \"DELETE FROM portal;\""
    echo "  docker restart matrix-bridge-whatsapp"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
