#!/bin/bash
# Validation script to check if the setup is ready

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Matrix Stack Setup Validation ==="
echo ""

# Track overall status
ERRORS=0
WARNINGS=0

check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} $1 exists"
        return 0
    else
        echo -e "${RED}✗${NC} $1 missing"
        ERRORS=$((ERRORS+1))
        return 1
    fi
}

check_dir() {
    if [ -d "$1" ]; then
        echo -e "${GREEN}✓${NC} $1 exists"
        return 0
    else
        echo -e "${RED}✗${NC} $1 missing"
        ERRORS=$((ERRORS+1))
        return 1
    fi
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS+1))
}

# Check essential files
echo "Checking essential files..."
check_file ".env"
check_file "docker-compose.yml"
check_file "element/config/config.json"
check_file "authelia/config/configuration.yml"
check_file "authelia/config/users_database.yml"
check_file "mas/config/config.yaml"
check_file "postgres/init/01-init-databases.sql"
echo ""

# Check if Synapse is configured
echo "Checking Synapse configuration..."
if check_file "synapse/data/homeserver.yaml"; then
    # Check for PostgreSQL config
    if grep -q "psycopg2" synapse/data/homeserver.yaml; then
        echo -e "${GREEN}✓${NC} Synapse configured for PostgreSQL"
    else
        warn "Synapse may not be configured for PostgreSQL"
        echo "  Check database section in synapse/data/homeserver.yaml"
    fi

    # Check for MAS config
    if grep -q "msc3861" synapse/data/homeserver.yaml; then
        echo -e "${GREEN}✓${NC} Synapse configured for MAS"
    else
        warn "Synapse may not be configured for MAS"
        echo "  Add experimental_features.msc3861 to homeserver.yaml"
    fi
else
    echo -e "${YELLOW}⚠${NC} Run ./setup-synapse.sh to generate Synapse config"
fi
echo ""

# Check .env for default values
echo "Checking .env for default/insecure values..."
if [ -f ".env" ]; then
    if grep -q "changeme" .env; then
        warn "Found 'changeme' in .env - update with secure values"
    fi

    if grep -q "matrix.localhost" .env; then
        echo -e "${GREEN}ℹ${NC} Using matrix.localhost (OK for local testing)"
    fi
fi
echo ""

# Check Authelia users
echo "Checking Authelia users configuration..."
if [ -f "authelia/config/users_database.yml" ]; then
    if grep -q "..." authelia/config/users_database.yml; then
        warn "Authelia users database contains placeholder password hashes"
        echo "  Generate password hash with:"
        echo "  docker run authelia/authelia:latest authelia crypto hash generate argon2 --password 'yourpassword'"
    else
        echo -e "${GREEN}✓${NC} Authelia users appear to be configured"
    fi
fi
echo ""

# Check Authelia RSA key
echo "Checking Authelia OIDC configuration..."
if grep -q "BEGIN RSA PRIVATE KEY" authelia/config/configuration.yml; then
    if grep -q "# Generate with:" authelia/config/configuration.yml; then
        warn "Authelia OIDC key is placeholder - generate real RSA key"
        echo "  Generate with: openssl genrsa -out authelia_private.pem 4096"
    else
        echo -e "${GREEN}✓${NC} Authelia OIDC key appears to be configured"
    fi
else
    warn "Authelia OIDC key missing or invalid"
fi
echo ""

# Check MAS signing key
echo "Checking MAS signing key..."
if [ -f "mas/config/config.yaml" ]; then
    if grep -q "BEGIN PRIVATE KEY" mas/config/config.yaml; then
        if grep -q "# Generate your own" mas/config/config.yaml; then
            warn "MAS signing key is placeholder - generate real key"
            echo "  Generate with: openssl genrsa 4096 | openssl pkcs8 -topk8 -nocrypt"
        else
            echo -e "${GREEN}✓${NC} MAS signing key appears to be configured"
        fi
    else
        warn "MAS signing key missing or invalid"
    fi
fi
echo ""

# Check if Docker is running
echo "Checking Docker..."
if docker info > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Docker is running"
else
    echo -e "${RED}✗${NC} Docker is not running or not accessible"
    ERRORS=$((ERRORS+1))
fi
echo ""

# Check if containers are running
echo "Checking running containers..."
if docker compose ps > /dev/null 2>&1; then
    RUNNING=$(docker compose ps --services --filter "status=running" | wc -l)
    TOTAL=$(docker compose ps --services | wc -l)

    if [ $RUNNING -eq $TOTAL ] && [ $TOTAL -gt 0 ]; then
        echo -e "${GREEN}✓${NC} All containers are running ($RUNNING/$TOTAL)"
    elif [ $RUNNING -gt 0 ]; then
        warn "Some containers are not running ($RUNNING/$TOTAL)"
        echo "  Run: docker compose ps"
    else
        echo -e "${YELLOW}ℹ${NC} No containers running yet"
        echo "  Start with: docker compose up -d"
    fi
fi
echo ""

# Summary
echo "==================================="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Setup validation passed!${NC}"
    echo "You should be ready to start the stack."
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Setup has $WARNINGS warning(s)${NC}"
    echo "Review the warnings above before proceeding."
else
    echo -e "${RED}✗ Setup has $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo "Fix the errors above before starting the stack."
    exit 1
fi
echo ""

echo "Next steps:"
echo "1. Review CHECKLIST.md for detailed setup steps"
echo "2. Read SETUP.md for comprehensive instructions"
echo "3. Start the stack: docker compose up -d"
echo "4. Check logs: docker compose logs -f"
