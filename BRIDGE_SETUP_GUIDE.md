# Matrix Bridge Setup Guide

**IMPORTANT**: This setup uses Matrix Authentication Service (MAS) for authentication. As of Synapse 1.140.0, **bridge encryption is NOT compatible with MAS** due to missing appservice login support. All bridge configurations in this guide have encryption disabled.

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

  # Bridge encryption disabled - incompatible with MAS
  # See "Known Issue: Encrypted Bridges with MAS" section below
  encryption:
    allow: false
    default: false
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

  # Bridge encryption disabled - incompatible with MAS
  # See "Known Issue: Encrypted Bridges with MAS" section below
  encryption:
    allow: false
    default: false
```

**Signal (`bridges/signal/config/config.yaml`):**
```yaml
homeserver:
  address: http://synapse:8008
  domain: matrix.example.test

appservice:
  address: http://mautrix-signal:29319

database:
  uri: postgres://synapse:PASSWORD@postgres/signal?sslmode=disable

bridge:
  permissions:
    "matrix.example.test": admin

  # Bridge encryption disabled - incompatible with MAS
  # See "Known Issue: Encrypted Bridges with MAS" section below
  encryption:
    allow: false
    default: false
```

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

**Note about registration.yaml:** The generated files should work as-is. Do not add MSC4190/MSC3202 flags since encryption is disabled in this MAS-based setup.

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

## Known Issue: Encrypted Bridges with MAS

**CRITICAL**: As of Synapse 1.140.0, there is a known compatibility issue between encrypted bridges and Matrix Authentication Service (MAS).

### The Problem
- Encrypted bridges require **appservice login** authentication for MSC4190 device masquerading
- When MAS is enabled, it takes over authentication from Synapse
- MAS does not currently support appservice login authentication
- **Result**: Encrypted bridges fail with `"homeserver does not support appservice login"` error

### Symptoms
- Bridge crashes during startup when encryption is enabled
- Error message: `"failed to start Matrix connector: homeserver does not support appservice login"`
- WhatsApp/Telegram may work (if not using encryption)
- Signal bridge typically fails (often defaults to encryption)

### Workaround Options

**Option 1: Disable encryption in affected bridges**
```yaml
# In bridge config.yaml
encryption:
  allow: false
  default: false
  # Remove or comment out msc4190: true
```

**Option 2: Wait for MAS appservice login support**
This is actively being developed. Check:
- https://github.com/element-hq/matrix-authentication-service/issues/3206
- Recent Synapse/MAS release notes

**Option 3: Disable MAS temporarily**
If encrypted bridges are critical, you may need to use Synapse's built-in authentication instead of MAS until this is resolved.

## Solution: Double Puppet and Unencrypted Rooms

While bridge encryption is incompatible with MAS, you can still achieve good message attribution using **double puppet** with unencrypted Matrix rooms. This is the recommended production-ready workaround.

### What is Double Puppet?

Double puppet allows bridges to send messages **as if they came from your actual Matrix user**, rather than from a bot account. This provides:
- Better message attribution (messages appear from you, not a bot)
- Improved user experience
- Works reliably without encryption issues

### Setting Up Double Puppet (Stable Solution)

#### Step 1: Generate Secure Tokens

```bash
# Generate tokens for the double puppet appservice
AS_TOKEN=$(openssl rand -hex 32)
HS_TOKEN=$(openssl rand -hex 32)

# Save these for later use
echo "AS_TOKEN: $AS_TOKEN"
echo "HS_TOKEN: $HS_TOKEN"
```

#### Step 2: Create Double Puppet Appservice

Create `appservices/doublepuppet.yaml`:

```yaml
id: doublepuppet
url: ""
as_token: "YOUR_AS_TOKEN_HERE"
hs_token: "YOUR_HS_TOKEN_HERE"
sender_localpart: doublepuppet
rate_limited: false

namespaces:
  users:
    - regex: "@.*:YOUR-DOMAIN.COM"
      exclusive: false
```

Replace:
- `YOUR_AS_TOKEN_HERE` with the AS_TOKEN you generated
- `YOUR_HS_TOKEN_HERE` with the HS_TOKEN you generated
- `YOUR-DOMAIN.COM` with your actual Matrix domain

Set permissions:
```bash
chmod 644 appservices/doublepuppet.yaml
```

#### Step 3: Register Double Puppet in Synapse

Edit `synapse/data/homeserver.yaml` and add:

```yaml
app_service_config_files:
  - /appservices/doublepuppet.yaml
  - /bridges/whatsapp/config/registration.yaml
  - /bridges/signal/config/registration.yaml
  - /bridges/telegram/config/registration.yaml
```

Ensure the appservices directory is mounted in your Synapse container:

```yaml
synapse:
  volumes:
    - ./synapse/data:/data
    - ./bridges:/bridges:ro
    - ./appservices:/appservices:ro  # Add this line
```

#### Step 4: Configure Bridges with Double Puppet

**WhatsApp** (`bridges/whatsapp/config/config.yaml`):
```yaml
bridge:
  double_puppet:
    secrets:
      your-domain.com: as_token:YOUR_AS_TOKEN_HERE

  # Disable encryption (not compatible with MAS)
  encryption:
    allow: false
    default: false
    msc4190: false
    self_sign: false
    allow_key_sharing: true
```

**Signal** (`bridges/signal/config/config.yaml`):
```yaml
bridge:
  double_puppet:
    secrets:
      your-domain.com: as_token:YOUR_AS_TOKEN_HERE

  # Disable encryption (not compatible with MAS)
  encryption:
    allow: false
    default: false
    msc4190: false
    self_sign: false
    allow_key_sharing: true
```

**Telegram** (`bridges/telegram/config/config.yaml`):
```yaml
bridge:
  login_shared_secret_map:
    your-domain.com: as_token:YOUR_AS_TOKEN_HERE

  # Disable encryption (not compatible with MAS)
  encryption:
    allow: false
    default: false
```

Replace:
- `your-domain.com` with your Matrix domain
- `YOUR_AS_TOKEN_HERE` with your AS_TOKEN

#### Step 5: Update Bridge Registration Files (For Future)

While encryption is disabled, you can add MSC4190 flags to registration files for future compatibility:

For each `bridges/*/config/registration.yaml`, ensure these lines exist:
```yaml
de.sorunome.msc2409.push_ephemeral: true
receive_ephemeral: true
io.element.msc4190: true  # For future encryption support
```

#### Step 6: Restart Services

```bash
# Restart Synapse to load double puppet appservice
docker restart matrix-synapse
sleep 15

# Restart all bridges
docker restart matrix-bridge-whatsapp matrix-bridge-signal matrix-bridge-telegram
sleep 10
```

#### Step 7: Clear Portal Database (Forces Room Recreatio)

To ensure bridges create new unencrypted rooms with double puppet:

```bash
# Clear WhatsApp portals
docker exec matrix-postgres psql -U synapse -d whatsapp -c "DELETE FROM portal;"
docker restart matrix-bridge-whatsapp

# Clear Signal portals (if needed)
docker exec matrix-postgres psql -U synapse -d signal -c "DELETE FROM portal;"
docker restart matrix-bridge-signal

# Clear Telegram portals (if needed)
docker exec matrix-postgres psql -U synapse -d telegram -c "DELETE FROM portal;"
docker restart matrix-bridge-telegram
```

**Note**: This will cause bridges to create new Matrix rooms for existing chats. Old rooms will remain but won't receive new messages.

### What You Get

✅ **Working**:
- Bridge connected to WhatsApp/Signal/Telegram
- Double puppet configured (better message attribution)
- Messages work in **unencrypted** Matrix rooms (both directions)
- Messages appear from your actual user, not bot

❌ **Not Working** (Known Issue):
- Encrypted Matrix rooms → Synapse NotImplementedError with MAS + MSC4190

### Future: When Synapse Fixes MSC4190 + MAS

When Synapse fixes the MSC4190 + MAS compatibility issue:

1. Update bridge configs:
   ```yaml
   encryption:
     allow: true
     default: false  # Or true if you want encryption by default
     msc4190: true
     self_sign: true
   ```

2. Restart bridges:
   ```bash
   docker restart matrix-bridge-whatsapp matrix-bridge-signal matrix-bridge-telegram
   ```

3. Encrypted rooms will work automatically

### Troubleshooting Double Puppet

**Bridge logs show "double puppet not enabled"**:
- Verify AS_TOKEN matches in both `appservices/doublepuppet.yaml` and bridge config
- Ensure Synapse loaded the appservice (check Synapse logs for "Registered application service")
- Verify appservices directory is mounted in Synapse container

**Messages still come from bot instead of my user**:
- Double puppet may not be enabled yet
- Try sending `login-matrix` command to the bridge bot
- Check bridge logs for double puppet status

**Encryption errors in logs**:
- Ensure `encryption.allow: false` in all bridge configs
- Clear portal database and restart bridges to force room recreation

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
