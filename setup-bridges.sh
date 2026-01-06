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
url: ""
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

# Generate configs by starting briefly
docker compose up -d mautrix-telegram && sleep 15 && docker compose stop mautrix-telegram
docker compose up -d mautrix-whatsapp && sleep 15 && docker compose stop mautrix-whatsapp
docker compose up -d mautrix-signal && sleep 15 && docker compose stop mautrix-signal

# Configure Telegram
echo "Configuring Telegram bridge..."
sudo sed -i "s|address: https://example.com|address: http://synapse:8008|" bridges/telegram/config/config.yaml
sudo sed -i "s|domain: example.com|domain: ${MATRIX_DOMAIN}|" bridges/telegram/config/config.yaml
sudo sed -i "s|address: http://localhost:29317|address: http://mautrix-telegram:29317|" bridges/telegram/config/config.yaml
sudo sed -i "s|database: postgres://username:password@hostname/dbname|database: postgres://synapse:${POSTGRES_PASSWORD}@postgres/telegram|" bridges/telegram/config/config.yaml
sudo sed -i "/'@admin:example.com': admin/d" bridges/telegram/config/config.yaml
sudo sed -i "/permissions:/a\\        '${MATRIX_DOMAIN}': admin" bridges/telegram/config/config.yaml

# Add double puppet configuration for Telegram
if ! sudo grep -q "login_shared_secret_map:" bridges/telegram/config/config.yaml; then
    sudo sed -i "/permissions:/i\\  login_shared_secret_map:\n    ${MATRIX_DOMAIN}: as_token:${DOUBLEPUPPET_AS_TOKEN}" bridges/telegram/config/config.yaml
else
    sudo sed -i "s|login_shared_secret_map:.*|login_shared_secret_map:\n    ${MATRIX_DOMAIN}: as_token:${DOUBLEPUPPET_AS_TOKEN}|" bridges/telegram/config/config.yaml
fi

# Disable encryption for Telegram (not compatible with MAS)
if sudo grep -q "encryption:" bridges/telegram/config/config.yaml; then
    sudo sed -i "/encryption:/,/default:/ { s|allow:.*|allow: false|; s|default:.*|default: false| }" bridges/telegram/config/config.yaml
else
    echo "    encryption:" | sudo tee -a bridges/telegram/config/config.yaml > /dev/null
    echo "        allow: false" | sudo tee -a bridges/telegram/config/config.yaml > /dev/null
    echo "        default: false" | sudo tee -a bridges/telegram/config/config.yaml > /dev/null
fi

echo "✓ Telegram configured with double puppet and encryption disabled"

# Configure WhatsApp
echo "Configuring WhatsApp bridge..."
DOMAIN_LINE=$(sudo grep -n "^  domain:" bridges/whatsapp/config/config.yaml | cut -d: -f1)
[ -n "$DOMAIN_LINE" ] && sudo sed -i "${DOMAIN_LINE}s|.*|  domain: ${MATRIX_DOMAIN}|" bridges/whatsapp/config/config.yaml
sudo sed -i "s|address: http://localhost:29318|address: http://mautrix-whatsapp:29318|" bridges/whatsapp/config/config.yaml
sudo sed -i "s|uri: postgres://user:password@host/database?sslmode=disable|uri: postgres://synapse:${POSTGRES_PASSWORD}@postgres/whatsapp?sslmode=disable|" bridges/whatsapp/config/config.yaml
sudo sed -i "/\"@admin:example.com\": admin/d" bridges/whatsapp/config/config.yaml
sudo sed -i "/permissions:/a\\        \"${MATRIX_DOMAIN}\": admin" bridges/whatsapp/config/config.yaml
[ -f bridges/whatsapp/config/registration.yaml ] && sudo sed -i "s|url: http://localhost:29318|url: http://mautrix-whatsapp:29318|" bridges/whatsapp/config/registration.yaml

# Add double puppet configuration for WhatsApp
if ! sudo grep -q "double_puppet:" bridges/whatsapp/config/config.yaml; then
    sudo sed -i "/permissions:/i\\  double_puppet:\n    secrets:\n      ${MATRIX_DOMAIN}: as_token:${DOUBLEPUPPET_AS_TOKEN}" bridges/whatsapp/config/config.yaml
fi

# Disable encryption for WhatsApp (not compatible with MAS)
if sudo grep -q "encryption:" bridges/whatsapp/config/config.yaml; then
    sudo sed -i "/encryption:/,/allow_key_sharing:/ { s|allow:.*|allow: false|; s|default:.*|default: false|; s|msc4190:.*|msc4190: false|; s|self_sign:.*|self_sign: false|; s|allow_key_sharing:.*|allow_key_sharing: true| }" bridges/whatsapp/config/config.yaml
else
    echo "    encryption:" | sudo tee -a bridges/whatsapp/config/config.yaml > /dev/null
    echo "        allow: false" | sudo tee -a bridges/whatsapp/config/config.yaml > /dev/null
    echo "        default: false" | sudo tee -a bridges/whatsapp/config/config.yaml > /dev/null
    echo "        msc4190: false" | sudo tee -a bridges/whatsapp/config/config.yaml > /dev/null
    echo "        self_sign: false" | sudo tee -a bridges/whatsapp/config/config.yaml > /dev/null
    echo "        allow_key_sharing: true" | sudo tee -a bridges/whatsapp/config/config.yaml > /dev/null
fi

echo "✓ WhatsApp configured with double puppet and encryption disabled"

# Configure Signal
echo "Configuring Signal bridge..."
DOMAIN_LINE=$(sudo grep -n "^  domain:" bridges/signal/config/config.yaml | cut -d: -f1)
[ -n "$DOMAIN_LINE" ] && sudo sed -i "${DOMAIN_LINE}s|.*|  domain: ${MATRIX_DOMAIN}|" bridges/signal/config/config.yaml
sudo sed -i "s|address: http://localhost:29328|address: http://mautrix-signal:29328|" bridges/signal/config/config.yaml
sudo sed -i "s|uri: postgres://user:password@host/database?sslmode=disable|uri: postgres://synapse:${POSTGRES_PASSWORD}@postgres/signal?sslmode=disable|" bridges/signal/config/config.yaml
sudo sed -i "/\"@admin:example.com\": admin/d" bridges/signal/config/config.yaml
sudo sed -i "/permissions:/a\\        \"${MATRIX_DOMAIN}\": admin" bridges/signal/config/config.yaml
[ -f bridges/signal/config/registration.yaml ] && sudo sed -i "s|url: http://localhost:29328|url: http://mautrix-signal:29328|" bridges/signal/config/registration.yaml

# Add double puppet configuration for Signal
if ! sudo grep -q "double_puppet:" bridges/signal/config/config.yaml; then
    sudo sed -i "/permissions:/i\\  double_puppet:\n    secrets:\n      ${MATRIX_DOMAIN}: as_token:${DOUBLEPUPPET_AS_TOKEN}" bridges/signal/config/config.yaml
fi

# Disable encryption for Signal (not compatible with MAS)
if sudo grep -q "encryption:" bridges/signal/config/config.yaml; then
    sudo sed -i "/encryption:/,/allow_key_sharing:/ { s|allow:.*|allow: false|; s|default:.*|default: false|; s|msc4190:.*|msc4190: false|; s|self_sign:.*|self_sign: false|; s|allow_key_sharing:.*|allow_key_sharing: true| }" bridges/signal/config/config.yaml
else
    echo "    encryption:" | sudo tee -a bridges/signal/config/config.yaml > /dev/null
    echo "        allow: false" | sudo tee -a bridges/signal/config/config.yaml > /dev/null
    echo "        default: false" | sudo tee -a bridges/signal/config/config.yaml > /dev/null
    echo "        msc4190: false" | sudo tee -a bridges/signal/config/config.yaml > /dev/null
    echo "        self_sign: false" | sudo tee -a bridges/signal/config/config.yaml > /dev/null
    echo "        allow_key_sharing: true" | sudo tee -a bridges/signal/config/config.yaml > /dev/null
fi

echo "✓ Signal configured with double puppet and encryption disabled"

# Create databases
docker exec matrix-postgres psql -U synapse -tc "SELECT 1 FROM pg_database WHERE datname = 'telegram'" | grep -q 1 || docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE telegram;"
docker exec matrix-postgres psql -U synapse -tc "SELECT 1 FROM pg_database WHERE datname = 'whatsapp'" | grep -q 1 || docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE whatsapp;"
docker exec matrix-postgres psql -U synapse -tc "SELECT 1 FROM pg_database WHERE datname = 'signal'" | grep -q 1 || docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE signal;"

# Add registrations to Synapse (including double puppet)
echo "Registering appservices with Synapse..."
if ! grep -q "app_service_config_files:" synapse/data/homeserver.yaml; then
    echo -e "\n# Appservice registrations (bridges and double puppet)\napp_service_config_files:" | sudo tee -a synapse/data/homeserver.yaml > /dev/null
fi

# Remove old registrations
sudo sed -i '/^  - \/bridges\//d' synapse/data/homeserver.yaml
sudo sed -i '/^  - \/appservices\//d' synapse/data/homeserver.yaml

# Add new registrations
echo "  - /appservices/doublepuppet.yaml" | sudo tee -a synapse/data/homeserver.yaml > /dev/null
echo "  - /bridges/whatsapp/config/registration.yaml" | sudo tee -a synapse/data/homeserver.yaml > /dev/null
echo "  - /bridges/signal/config/registration.yaml" | sudo tee -a synapse/data/homeserver.yaml > /dev/null

echo "✓ Appservice registrations added to homeserver.yaml"

# Restart Synapse
docker compose restart synapse && sleep 10

# Start bridges
echo "Starting bridges..."
docker compose up -d mautrix-telegram mautrix-whatsapp mautrix-signal
sleep 15

echo ""
echo "=== Bridge setup complete with double puppet! ==="
echo ""
echo "✓ Double puppet appservice created and registered"
echo "✓ All bridges configured with encryption disabled (MAS compatibility)"
echo "✓ All bridges configured with double puppet support"
echo ""
echo "IMPORTANT: Ensure appservices directory is mounted in Synapse container!"
echo "Add to docker-compose.yml under synapse.volumes:"
echo "  - ./appservices:/appservices:ro"
echo ""
echo "Bridge status:"
docker compose ps | grep bridge
echo ""
echo "To clear portal database and force room recreation (optional):"
echo "  docker exec matrix-postgres psql -U synapse -d whatsapp -c \"DELETE FROM portal;\""
echo "  docker restart matrix-bridge-whatsapp"
