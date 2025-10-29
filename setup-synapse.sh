#!/bin/bash
# Generate initial Synapse configuration

set -e

echo "Generating Matrix Synapse configuration..."

# Source environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Generate config using Docker
docker run -it --rm \
    -v $(pwd)/synapse/data:/data \
    -e SYNAPSE_SERVER_NAME=${SERVER_NAME:-matrix.localhost} \
    -e SYNAPSE_REPORT_STATS=${SYNAPSE_REPORT_STATS:-no} \
    matrixdotorg/synapse:latest generate

echo ""
echo "Synapse configuration generated in ./synapse/data/"
echo "You now need to edit ./synapse/data/homeserver.yaml to:"
echo "  1. Configure PostgreSQL database connection"
echo "  2. Enable registration (if desired)"
echo "  3. Configure MAS integration"
echo ""
