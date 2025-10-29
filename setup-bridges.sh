#!/bin/bash
set -e

# Complete Bridge Setup Script
source .env

echo "=== Setting up Mautrix Bridges ==="

# Stop bridges
docker compose -f docker-compose.local.yml stop mautrix-telegram mautrix-whatsapp mautrix-signal 2>/dev/null || true

# Clean old configs
sudo rm -rf bridges/telegram/config/* bridges/whatsapp/config/* bridges/signal/config/*

# Generate configs by starting briefly
docker compose -f docker-compose.local.yml up -d mautrix-telegram && sleep 15 && docker compose -f docker-compose.local.yml stop mautrix-telegram
docker compose -f docker-compose.local.yml up -d mautrix-whatsapp && sleep 15 && docker compose -f docker-compose.local.yml stop mautrix-whatsapp
docker compose -f docker-compose.local.yml up -d mautrix-signal && sleep 15 && docker compose -f docker-compose.local.yml stop mautrix-signal

# Configure Telegram
sudo sed -i "s|address: https://example.com|address: http://synapse:8008|" bridges/telegram/config/config.yaml
sudo sed -i "s|domain: example.com|domain: ${MATRIX_DOMAIN}|" bridges/telegram/config/config.yaml
sudo sed -i "s|address: http://localhost:29317|address: http://mautrix-telegram:29317|" bridges/telegram/config/config.yaml
sudo sed -i "s|database: postgres://username:password@hostname/dbname|database: postgres://synapse:${POSTGRES_PASSWORD}@postgres/telegram|" bridges/telegram/config/config.yaml
sudo sed -i "/'@admin:example.com': admin/d" bridges/telegram/config/config.yaml
sudo sed -i "/permissions:/a\\        '${MATRIX_DOMAIN}': admin" bridges/telegram/config/config.yaml

# Configure WhatsApp  
DOMAIN_LINE=$(sudo grep -n "^    domain:" bridges/whatsapp/config/config.yaml | cut -d: -f1)
[ -n "$DOMAIN_LINE" ] && sudo sed -i "${DOMAIN_LINE}s|.*|    domain: ${MATRIX_DOMAIN}|" bridges/whatsapp/config/config.yaml
sudo sed -i "s|address: http://localhost:29318|address: http://mautrix-whatsapp:29318|" bridges/whatsapp/config/config.yaml
sudo sed -i "s|uri: postgres://user:password@host/database?sslmode=disable|uri: postgres://synapse:${POSTGRES_PASSWORD}@postgres/whatsapp?sslmode=disable|" bridges/whatsapp/config/config.yaml
sudo sed -i "/\"@admin:example.com\": admin/d" bridges/whatsapp/config/config.yaml
sudo sed -i "/permissions:/a\\        \"${MATRIX_DOMAIN}\": admin" bridges/whatsapp/config/config.yaml
[ -f bridges/whatsapp/config/registration.yaml ] && sudo sed -i "s|url: http://localhost:29318|url: http://mautrix-whatsapp:29318|" bridges/whatsapp/config/registration.yaml

# Configure Signal
DOMAIN_LINE=$(sudo grep -n "^    domain:" bridges/signal/config/config.yaml | cut -d: -f1)
[ -n "$DOMAIN_LINE" ] && sudo sed -i "${DOMAIN_LINE}s|.*|    domain: ${MATRIX_DOMAIN}|" bridges/signal/config/config.yaml
sudo sed -i "s|address: http://localhost:29328|address: http://mautrix-signal:29328|" bridges/signal/config/config.yaml
sudo sed -i "s|uri: postgres://user:password@host/database?sslmode=disable|uri: postgres://synapse:${POSTGRES_PASSWORD}@postgres/signal?sslmode=disable|" bridges/signal/config/config.yaml
sudo sed -i "/\"@admin:example.com\": admin/d" bridges/signal/config/config.yaml
sudo sed -i "/permissions:/a\\        \"${MATRIX_DOMAIN}\": admin" bridges/signal/config/config.yaml
[ -f bridges/signal/config/registration.yaml ] && sudo sed -i "s|url: http://localhost:29328|url: http://mautrix-signal:29328|" bridges/signal/config/registration.yaml

# Create databases
docker exec matrix-postgres psql -U synapse -tc "SELECT 1 FROM pg_database WHERE datname = 'telegram'" | grep -q 1 || docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE telegram;"
docker exec matrix-postgres psql -U synapse -tc "SELECT 1 FROM pg_database WHERE datname = 'whatsapp'" | grep -q 1 || docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE whatsapp;"
docker exec matrix-postgres psql -U synapse -tc "SELECT 1 FROM pg_database WHERE datname = 'signal'" | grep -q 1 || docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE signal;"

# Add registrations to Synapse
if ! grep -q "app_service_config_files:" synapse/data/homeserver.yaml; then
    echo -e "\n# Bridge registrations\napp_service_config_files:" | sudo tee -a synapse/data/homeserver.yaml > /dev/null
fi
sudo sed -i '/^  - \/bridges\//d' synapse/data/homeserver.yaml
echo "  - /bridges/whatsapp/config/registration.yaml" | sudo tee -a synapse/data/homeserver.yaml > /dev/null
echo "  - /bridges/signal/config/registration.yaml" | sudo tee -a synapse/data/homeserver.yaml > /dev/null

# Restart Synapse
docker compose -f docker-compose.local.yml restart synapse && sleep 10

# Start bridges
docker compose -f docker-compose.local.yml up -d mautrix-telegram mautrix-whatsapp mautrix-signal
sleep 15

echo "=== Bridge setup complete ==="
docker compose -f docker-compose.local.yml ps | grep bridge
