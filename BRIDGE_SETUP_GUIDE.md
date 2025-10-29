# Matrix Bridge Setup Guide

## The Bridge Registration Problem (CRITICAL)

### Chicken-and-Egg Issue

Mautrix bridges have a **chicken-and-egg problem** during initial setup:

1. **Bridges generate registration.yaml files** on first successful startup
2. **Synapse needs registration.yaml files** to load appservice configuration
3. **Bridges depend on Synapse** being healthy to start (docker-compose dependency)
4. **If Synapse tries to load non-existent registrations**, it crashes
5. **Crashed Synapse prevents bridges from starting** → registration files never get created

### Correct Setup Sequence

The bridges MUST be set up in this specific order:

```
1. Start bridges WITHOUT Synapse loading them
   ↓
2. Bridges generate registration.yaml files
   ↓
3. Configure Synapse to load registration files
   ↓
4. Restart Synapse with appservice support
   ↓
5. Bridges can now communicate with Synapse
```

## Automated Bridge Setup Script

Use the provided `setup-bridges.sh` script which handles the correct sequence:

```bash
#!/bin/bash
# This script must be run AFTER initial deployment

./setup-bridges.sh
```

### What the Script Does

1. **Removes** docker-compose dependency on Synapse health
2. **Starts each bridge** independently to generate configs and registrations
3. **Configures** all bridge settings (homeserver address, database, permissions)
4. **Waits** for registration.yaml files to be created
5. **Adds** registration paths to Synapse homeserver.yaml
6. **Mounts** bridge directory in Synapse container
7. **Restarts** Synapse to load appservice registrations
8. **Starts** all bridges with proper Synapse integration

## Manual Bridge Setup (If Script Fails)

### Step 1: Prepare Synapse

Remove any existing bridge registration references:

```bash
# Edit synapse/data/homeserver.yaml
# Remove or comment out:
# app_service_config_files:
#   - /bridges/whatsapp/config/registration.yaml
#   - /bridges/signal/config/registration.yaml

# Restart Synapse
sudo docker compose -f docker-compose.local.yml restart synapse
```

### Step 2: Temporarily Remove Dependencies

Edit `docker-compose.local.yml` and remove `depends_on: synapse` from bridges:

```yaml
mautrix-telegram:
  # ... other config ...
  # TEMPORARILY COMMENT OUT:
  # depends_on:
  #   synapse:
  #     condition: service_healthy
```

### Step 3: Start Bridges to Generate Configs

```bash
# Start each bridge independently
sudo docker compose -f docker-compose.local.yml up -d mautrix-telegram
sleep 15  # Wait for config generation

sudo docker compose -f docker-compose.local.yml up -d mautrix-whatsapp
sleep 15

sudo docker compose -f docker-compose.local.yml up -d mautrix-signal
sleep 15
```

### Step 4: Configure Bridges

For each bridge, edit the config file:

**Telegram (`bridges/telegram/config/config.yaml`):**
```yaml
homeserver:
  address: http://synapse:8008
  domain: matrix.example.test

appservice:
  address: http://mautrix-telegram:29317
  database: postgres://synapse:PASSWORD@postgres/telegram

bridge:
  permissions:
    'matrix.example.test': admin
```

**WhatsApp (`bridges/whatsapp/config/config.yaml`):**
```yaml
homeserver:
  address: http://synapse:8008
  domain: matrix.example.test  # Make sure this line has a value!

appservice:
  address: http://mautrix-whatsapp:29318

database:
  uri: postgres://synapse:PASSWORD@postgres/whatsapp?sslmode=disable

bridge:
  permissions:
    "matrix.example.test": admin
```

**Signal (similar structure)**

###

 Step 5: Create Bridge Databases

```bash
sudo docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE telegram;"
sudo docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE whatsapp;"
sudo docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE signal;"
```

### Step 6: Restart Bridges

```bash
sudo docker compose -f docker-compose.local.yml restart mautrix-telegram mautrix-whatsapp mautrix-signal
sleep 20
```

### Step 7: Verify Registration Files Created

```bash
ls -la bridges/*/config/registration.yaml

# You should see:
# bridges/whatsapp/config/registration.yaml
# bridges/signal/config/registration.yaml
# NOTE: Telegram may not generate registration.yaml - that's OK
```

### Step 8: Configure Synapse

Edit `synapse/data/homeserver.yaml` and add:

```yaml
# At the end of the file
app_service_config_files:
  - /bridges/whatsapp/config/registration.yaml
  - /bridges/signal/config/registration.yaml
```

Ensure bridge directory is mounted in `docker-compose.local.yml`:

```yaml
synapse:
  volumes:
    - ./synapse/data:/data
    - ./bridges:/bridges:ro  # Add this line
```

### Step 9: Restart Everything

```bash
# Recreate Synapse with new volume mount
sudo docker compose -f docker-compose.local.yml up -d synapse

# Restore dependencies in docker-compose.local.yml
# Then restart bridges
sudo docker compose -f docker-compose.local.yml restart mautrix-telegram mautrix-whatsapp mautrix-signal
```

## Verification

### Check Services Running

```bash
sudo docker compose -f docker-compose.local.yml ps | grep bridge

# All bridges should show "Up" status
```

### Check Logs

```bash
# Telegram
sudo docker compose -f docker-compose.local.yml logs mautrix-telegram --tail 20

# WhatsApp
sudo docker compose -f docker-compose.local.yml logs mautrix-whatsapp --tail 20

# Signal
sudo docker compose -f docker-compose.local.yml logs mautrix-signal --tail 20
```

### Expected Log Messages

**Successful startup:**
```
INFO - Starting bridge
INFO - Bridge started successfully
INFO - Listening on port 29318
```

**Common errors and fixes:**
- `homeserver.address not configured` → Fix homeserver.address in config.yaml
- `homeserver.domain not configured` → Fix homeserver.domain (must have value, not empty)
- `database not configured` → Fix database URI with correct password
- `permissions not configured` → Add domain to bridge.permissions
- `as_token was not accepted` → Registration not loaded in Synapse yet

## Using the Bridges

### Link Accounts

Once bridges are running:

1. Open Element Web: `https://element.example.test`
2. Start a chat with the bridge bot:
   - Telegram: `@telegrambot:matrix.example.test`
   - WhatsApp: `@whatsappbot:matrix.example.test`
   - Signal: `@signalbot:matrix.example.test`
3. Follow the bot's instructions to link your account

### Telegram Bridge

```
!tg help        # Show commands
!tg login       # Start login process
```

### WhatsApp Bridge

```
help                    # Show commands
login                   # Show QR code
```

### Signal Bridge

```
help                    # Show commands
link                    # Start linking process
```

## Troubleshooting

### Bridge Keeps Restarting

Check logs for specific error:
```bash
sudo docker compose logs mautrix-whatsapp --tail 50
```

Common causes:
1. **Config error** - Review config.yaml for typos or missing values
2. **Database error** - Ensure database exists and password is correct
3. **Synapse not reachable** - Check `homeserver.address` points to `http://synapse:8008`
4. **Registration mismatch** - as_token in registration.yaml must match Synapse config

### Messages Not Bridging

1. **Check bridge is running**: `docker compose ps`
2. **Check you're logged into bridge**: Send `status` command to bridge bot
3. **Check Synapse logs**: `docker compose logs synapse | grep appservice`
4. **Verify registration loaded**: Check Synapse startup logs for "Registered application service"

### Permission Denied

Bridge bot needs admin permissions. In bridge config:

```yaml
bridge:
  permissions:
    "your-domain.com": admin  # Domain-wide admin
    "@you:your-domain.com": admin  # Or specific user
```

## Why This Is So Complex

Mautrix bridges were designed for manual setup with these assumptions:

1. Admin manually creates and edits config files
2. Admin runs bridge once to generate registration
3. Admin manually copies registration to Synapse
4. Admin manually configures Synapse to load registration
5. Admin restarts both services

Our automated approach must handle all these steps programmatically, which creates the chicken-and-egg dependency problem.

## Future Improvements

To make this fully automatic in deploy.sh:

1. Start bridges WITHOUT docker-compose dependencies
2. Use docker-compose `restart: "no"` for initial generation
3. Wait for registration files (with timeout)
4. Configure Synapse dynamically
5. Switch bridges to `restart: unless-stopped`
6. Final restart of all services

This requires more sophisticated orchestration than docker-compose dependencies provide.
