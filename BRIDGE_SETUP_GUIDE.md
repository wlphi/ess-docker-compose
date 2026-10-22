# Matrix Bridge Setup Guide

**IMPORTANT**: This setup uses Matrix Authentication Service (MAS) for authentication. Bridge encryption is **not** compatible with MAS yet (no appservice login / MSC4190 support), so every bridge is configured with encryption disabled. See [Known Issue: Encrypted Bridges with MAS](#known-issue-encrypted-bridges-with-mas).

## Bridges in this stack

| Bridge | Image (default) | Config format | Port | Bot |
|--------|-----------------|---------------|------|-----|
| WhatsApp | `dock.mau.dev/mautrix/whatsapp:v26.10` | Go megabridge (bridgev2) | 29318 | `@whatsappbot` |
| Signal | `dock.mau.dev/mautrix/signal:v26.10` | Go megabridge (bridgev2) | 29328 | `@signalbot` |
| Telegram | `dock.mau.dev/mautrix/telegram:v26.10` | Go megabridge (bridgev2) | 29317 | `@telegrambot` |
| Slack | `dock.mau.dev/mautrix/slack:v26.10` | Go megabridge (bridgev2) | 29335 | `@slackbot` |
| Discord | `dock.mau.dev/mautrix/discord:v0.7.7` | Legacy mautrix-go (not bridgev2 yet) | 29334 | `@discordbot` |

The images are pinned to release tags because mautrix's `:latest` tag follows the development branch. Override any of them with `TELEGRAM_IMAGE`, `WHATSAPP_IMAGE`, `SIGNAL_IMAGE`, `SLACK_IMAGE` or `DISCORD_IMAGE` in `.env`.

Bridge user IDs use your **server name** — the part after the colon in your Matrix ID (`SERVER_NAME` in `.env`, e.g. `@whatsappbot:example.com`), which is not necessarily the Matrix API host.

## The Bridge Registration Problem

Mautrix bridges have a **chicken-and-egg problem** during initial setup:

1. **Bridges generate registration.yaml files** on first successful startup
2. **Synapse needs registration.yaml files** to load appservice configuration
3. **If Synapse tries to load non-existent registrations**, it fails to start
4. **A failed Synapse prevents bridges from starting** → registration files never get created

So the setup must run in this order:

```
1. Bridges generate default config.yaml → configure them
   ↓
2. Bridges generate registration.yaml
   ↓
3. Register the files in Synapse's homeserver.yaml
   ↓
4. Restart Synapse, then start the bridges
```

## Automated Bridge Setup Script

Run `setup-bridges.sh` from the project root **after** the stack is deployed:

```bash
./setup-bridges.sh
```

### What the Script Does

1. Generates a double puppet appservice token pair (`appservices/doublepuppet.yaml`)
2. Starts all five bridges to generate default configs, then stops them
3. Configures each bridge: homeserver address and server name, bridge address, database, permissions, double puppet secret, encryption off
4. Sets `hostname: 0.0.0.0` (megabridges) so Synapse can reach bridges across Docker containers
5. Starts the bridges to generate `registration.yaml` files, then stops them
6. Sets file permissions so Synapse can read the registration files
7. Creates one PostgreSQL database per bridge
8. Registers all appservices in `synapse/data/homeserver.yaml` (keeps hookshot's registration when hookshot is enabled)
9. Restarts Synapse, then starts the bridges

Re-running the script is safe: it regenerates bridge configs and the double puppet tokens, and rewrites the appservice list in `homeserver.yaml`. Existing bridge databases (logins, portals) are kept.

**Telegram** requires API credentials from [my.telegram.org](https://my.telegram.org). Add them to `.env` before running the script, otherwise Telegram is skipped:
```
TELEGRAM_API_ID=your_api_id
TELEGRAM_API_HASH=your_api_hash
```

### Upgrading from the Python Telegram bridge

mautrix-telegram was rewritten in Go (v26.04). The Go bridge migrates a Python bridge database in place, but **v26.10 removed that migration**, so an existing Python install must pass through v26.04–v26.09 first. The old relaybot is not migrated.

`setup-bridges.sh` detects a Python-format Telegram config (top-level `telegram:` section) and skips Telegram with instructions instead of overwriting it. To migrate:

1. Set `TELEGRAM_IMAGE=dock.mau.dev/mautrix/telegram:v26.09` in `.env`
2. Run `TELEGRAM_LEGACY_ACK=true ./setup-bridges.sh` and check `docker compose logs mautrix-telegram` for a completed migration
3. Set `TELEGRAM_IMAGE=dock.mau.dev/mautrix/telegram:v26.10` in `.env` and run `docker compose up -d mautrix-telegram`

To start fresh instead, drop the old database (`docker exec matrix-postgres psql -U synapse -c "DROP DATABASE telegram;"`) and run `TELEGRAM_LEGACY_ACK=true ./setup-bridges.sh`.

## Manual Bridge Setup (If the Script Fails)

The steps below mirror what the script does for one bridge. Replace `example.com` with your server name and `PASSWORD` with `POSTGRES_PASSWORD` from `.env`.

### Step 1: Generate the default config

```bash
sudo rm -rf bridges/whatsapp/config/*
docker compose up -d mautrix-whatsapp   # writes bridges/whatsapp/config/config.yaml and exits
docker compose stop mautrix-whatsapp
```

### Step 2: Configure the bridge

**Megabridges** (WhatsApp, Signal, Telegram, Slack) use top-level sections with 4-space fields. Use the bridge's own name and port from the table above:

```yaml
network:
    # Telegram only: API credentials from my.telegram.org
    api_id: 12345
    api_hash: your_api_hash

bridge:
    permissions:
        "example.com": admin

database:
    uri: postgres://synapse:PASSWORD@postgres/whatsapp?sslmode=disable

homeserver:
    address: http://synapse:8008
    domain: example.com

appservice:
    address: http://mautrix-whatsapp:29318
    hostname: 0.0.0.0

double_puppet:
    secrets:
        example.com: as_token:YOUR_DOUBLEPUPPET_AS_TOKEN

encryption:
    allow: false
    default: false
    msc4190: false
```

**Discord** still uses the legacy layout — database, double puppet and encryption live under `appservice:` and `bridge:`:

```yaml
homeserver:
    address: http://synapse:8008
    domain: example.com

appservice:
    address: http://mautrix-discord:29334
    hostname: 0.0.0.0
    database:
        uri: postgres://synapse:PASSWORD@postgres/discord?sslmode=disable

bridge:
    login_shared_secret_map:
        example.com: as_token:YOUR_DOUBLEPUPPET_AS_TOKEN
    encryption:
        allow: false
        default: false
        msc4190: false
    permissions:
        "example.com": admin
```

### Step 3: Create the database and generate the registration

```bash
docker exec matrix-postgres psql -U synapse -c "CREATE DATABASE whatsapp;"
docker compose up -d mautrix-whatsapp   # writes registration.yaml
sleep 15
docker compose stop mautrix-whatsapp
sudo chmod 644 bridges/whatsapp/config/registration.yaml
```

### Step 4: Register with Synapse

Add the registration to `synapse/data/homeserver.yaml` (the `./bridges` and `./appservices` directories are already mounted into the Synapse container):

```yaml
app_service_config_files:
  - /appservices/doublepuppet.yaml
  - /bridges/whatsapp/config/registration.yaml
```

Then restart Synapse and start the bridge:

```bash
docker compose restart synapse
docker compose up -d mautrix-whatsapp
```

The generated registration files work as-is. Do not add MSC4190/MSC3202 flags while encryption is disabled.

## Verification

### Check Services Running

```bash
docker compose ps | grep bridge
# All bridges should show "Up" status
```

### Check Logs

```bash
docker compose logs mautrix-whatsapp --tail 20
docker compose logs mautrix-signal --tail 20
docker compose logs mautrix-telegram --tail 20
docker compose logs mautrix-slack --tail 20
docker compose logs mautrix-discord --tail 20
```

**Common errors and fixes:**
- `homeserver.address not configured` → Fix homeserver.address in config.yaml
- `homeserver.domain not configured` → Set homeserver.domain to your server name
- `database not configured` → Fix the database URI and password
- `as_token was not accepted` → Registration not loaded in Synapse yet (check `app_service_config_files`, restart Synapse)
- `homeserver does not support appservice login` → Encryption is enabled; disable it (see below)

## Using the Bridges

Start a DM with the bridge bot (`@<bridge>bot:<server name>`, e.g. `@whatsappbot:example.com`) in Element and send `help`. Send `login` to link your account — the bot lists the available login methods (QR code, phone number, token, …) and walks you through them.

- **WhatsApp / Signal**: scan the QR code from the app's *Linked devices* screen
- **Telegram**: log in with your phone number and the code Telegram sends you
- **Slack**: log in with a token or your workspace credentials
- **Discord**: scan the QR code with the Discord mobile app

Full command references: [docs.mau.fi/bridges](https://docs.mau.fi/bridges/)

## Troubleshooting

### Bridge Keeps Restarting

Check logs for the specific error:
```bash
docker compose logs mautrix-whatsapp --tail 50
```

Common causes:
1. **Config not generated yet** — run `setup-bridges.sh`; until then the bridges have no config and restart repeatedly
2. **Database error** — ensure the database exists and the password is correct
3. **Synapse not reachable** — check `homeserver.address` points to `http://synapse:8008`
4. **Registration mismatch** — the as_token in registration.yaml must be the one Synapse loaded

### Messages Not Bridging

1. **Check bridge is running**: `docker compose ps`
2. **Check you're logged into the bridge**: send `help` to the bridge bot and use its login status command
3. **Check Synapse logs**: `docker compose logs synapse | grep -i appservice`
4. **Use unencrypted rooms**: encrypted portals cannot be bridged in this setup

### Permission Denied

The `permissions` section must give your server name `admin` (or at least `user`):

```yaml
    permissions:
        "example.com": admin           # Everyone on your server
        "@you:example.com": admin      # Or a specific user
```

## Known Issue: Encrypted Bridges with MAS

### The Problem
- Encrypted bridges require **appservice login** for MSC4190 device management
- With MAS enabled, MAS handles authentication and does not support appservice login yet
- **Result**: encrypted bridges fail with `homeserver does not support appservice login`

### What to do
Keep encryption disabled in every bridge config (the script does this):

```yaml
encryption:            # megabridges: top level; Discord: under bridge:
    allow: false
    default: false
    msc4190: false
```

Track MAS support at https://github.com/element-hq/matrix-authentication-service/issues/3206. When it lands, re-enable encryption in the bridge configs and restart the bridges.

## Double Puppet

Double puppeting makes bridges send messages **from your actual Matrix user** rather than a ghost user. It uses a dedicated appservice (`appservices/doublepuppet.yaml`, `url: null`) whose `as_token` the bridges use to act on behalf of local users.

`setup-bridges.sh` sets it up automatically. To do it manually:

1. Generate a token pair:
   ```bash
   AS_TOKEN=$(openssl rand -hex 32)
   HS_TOKEN=$(openssl rand -hex 32)
   ```
2. Create `appservices/doublepuppet.yaml` (`chmod 644`):
   ```yaml
   id: doublepuppet
   url: null
   as_token: "YOUR_AS_TOKEN"
   hs_token: "YOUR_HS_TOKEN"
   sender_localpart: doublepuppet
   rate_limited: false

   namespaces:
     users:
       - regex: "@.*:example.com"
         exclusive: false
   ```
3. Add `/appservices/doublepuppet.yaml` to `app_service_config_files` in `homeserver.yaml`
4. Put `example.com: as_token:YOUR_AS_TOKEN` into each bridge config — `double_puppet.secrets` for megabridges, `bridge.login_shared_secret_map` for Discord
5. Restart Synapse, then the bridges

### Recreating portal rooms

To make bridges create fresh (unencrypted, double-puppeted) rooms for existing chats:

```bash
docker exec matrix-postgres psql -U synapse -d whatsapp -c "DELETE FROM portal;"
docker restart matrix-bridge-whatsapp
```

The old rooms remain but stop receiving messages.

### Troubleshooting Double Puppet

**Messages still come from a ghost user instead of you**:
- Verify the AS_TOKEN in the bridge config matches `appservices/doublepuppet.yaml`
- Check the Synapse logs for the doublepuppet appservice being loaded
- Ensure the secret is keyed by your **server name**, not the Matrix API host

---

## Discord Bridge Notes

mautrix-discord has no bridgev2 release yet (latest: v0.7.7), so its config keeps the legacy layout shown above. When a bridgev2 release ships, `setup-bridges.sh` will need the megabridge configuration instead.

- **`failed to connect to homeserver`** — verify `homeserver.address` is `http://synapse:8008`
- **Login QR code expired** — send `login` again; Discord QR codes expire quickly
- **Servers not bridging** — servers (guilds) must be bridged explicitly; send `help` to the bot for the guild commands

## Slack Bridge Notes

- **`as_token was not accepted`** — the registration isn't loaded; check `homeserver.yaml` lists `/bridges/slack/config/registration.yaml`
- **Missing channels** — only channels your Slack account is a member of are bridged

---

## matrix-hookshot (GitHub / GitLab / JIRA / RSS / Webhooks)

Hookshot is an appservice bridge that connects Matrix rooms to external services. Enable it during `deploy.sh` setup (`--profile hookshot`).

### What hookshot can do

- **Generic webhooks** — receive any HTTP POST and post it to a Matrix room (enabled by default)
- **GitHub** — issues, PRs, CI status, releases (requires OAuth app)
- **GitLab** — merge requests, pipelines, issues (requires access token)
- **JIRA** — issues, comments (requires JIRA OAuth app)
- **RSS/Atom feeds** — poll any feed and post updates to a room

### After deploy.sh

`deploy.sh` generates `hookshot/config.yaml` with generic webhooks enabled and GitHub/GitLab/JIRA commented out, plus the appservice registration (`hookshot/registration.yaml`, copied to `appservices/hookshot.yaml`). The registration uses `receive_ephemeral: true`, which hookshot 7.4.3+ requires in place of the legacy `push_ephemeral` flags. Edit the config to enable integrations:

```yaml
# hookshot/config.yaml — add your credentials

github:
  auth:
    id: YOUR_GITHUB_APP_ID
    privateKeyFile: /data/github-key.pem
  oauth:
    client_id: YOUR_CLIENT_ID
    client_secret: YOUR_CLIENT_SECRET
    redirect_uri: https://hooks.yourdomain.com/oauth/

gitlab:
  instances:
    gitlab.com:
      url: https://gitlab.com
```

After editing, restart hookshot:

```bash
docker compose --profile hookshot restart hookshot
docker compose --profile hookshot logs --tail=30 hookshot
```

### Using generic webhooks

1. In a Matrix room, invite `@hookshot:yourdomain.com`
2. Send `!hookshot webhook <name>` — hookshot replies with a unique webhook URL
3. POST JSON to that URL from any service (GitHub Actions, CI scripts, monitoring alerts, etc.)

```bash
curl -X POST https://hooks.yourdomain.com/webhook/YOUR_TOKEN \
  -H "Content-Type: application/json" \
  -d '{"text": "Deployment complete!"}'
```

### Troubleshooting hookshot

- **`Unrecognised token`** — the `as_token` in `hookshot/registration.yaml` doesn't match `appservices/hookshot.yaml`; re-run `deploy.sh` or regenerate manually
- **`Connection refused` on webhook URL** — verify the `hookshot` profile is active and the Caddyfile has a `hooks.yourdomain.com` block
- **GitHub webhooks not firing** — check that the GitHub App webhook URL points to `https://hooks.yourdomain.com/` and is active
- **Existing deployments**: if `appservices/hookshot.yaml` still has `push_ephemeral`, replace those lines with `receive_ephemeral: true` and restart Synapse and hookshot
