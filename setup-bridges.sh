#!/bin/bash
# Setup script for Matrix bridges

set -e

echo "Setting up Matrix bridges..."
echo ""

# Function to setup a bridge
setup_bridge() {
    local bridge_name=$1
    local bridge_image=$2
    local config_dir=$3

    echo "Setting up $bridge_name bridge..."

    # Generate config if it doesn't exist
    if [ ! -f "$config_dir/config.yaml" ]; then
        echo "  Generating config for $bridge_name..."
        docker run --rm \
            -v $(pwd)/$config_dir:/data \
            $bridge_image

        echo "  ✓ Config generated at $config_dir/config.yaml"
        echo "  ! Please edit the config file before starting the bridge"
        echo ""
    else
        echo "  Config already exists at $config_dir/config.yaml"
        echo ""
    fi
}

# Check if Synapse is configured
if [ ! -f "./synapse/data/homeserver.yaml" ]; then
    echo "Error: Synapse must be configured first. Run ./setup-synapse.sh"
    exit 1
fi

# Setup each bridge
echo "=== Setting up Telegram Bridge ==="
setup_bridge "Telegram" "dock.mau.dev/mautrix/telegram:latest" "bridges/telegram/config"

echo "=== Setting up WhatsApp Bridge ==="
setup_bridge "WhatsApp" "dock.mau.dev/mautrix/whatsapp:latest" "bridges/whatsapp/config"

echo "=== Setting up Signal Bridge ==="
setup_bridge "Signal" "dock.mau.dev/mautrix/signal:latest" "bridges/signal/config"

echo ""
echo "Bridge setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit each bridge config file to set:"
echo "   - homeserver address: http://synapse:8008"
echo "   - homeserver domain: matrix.localhost"
echo "   - as_token and hs_token (generated in configs)"
echo "2. Copy the registration YAML files to synapse/data/"
echo "3. Add them to synapse homeserver.yaml app_service_config_files section"
echo "4. Restart the stack"
echo ""
