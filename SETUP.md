# Matrix Stack Setup Guide

This guide will help you set up a complete Matrix communication stack with:
- Matrix Synapse homeserver
- Element Web client
- Matrix Authentication Service (MAS) with SSO via Authelia
- PostgreSQL database
- Bridges for Telegram, WhatsApp, and Signal

## Prerequisites

- Docker and Docker Compose installed
- At least 4GB RAM available
- Ports 8008, 8080, 8081, 8082, 8448, 9091 available

## Quick Start

### 1. Configure Environment Variables

Edit the `.env` file and change all passwords and secrets:

```bash
nano .env
```

**Important:** Change these values:
- `POSTGRES_PASSWORD` - PostgreSQL password
- `AUTHELIA_JWT_SECRET` - At least 32 characters
- `AUTHELIA_SESSION_SECRET` - At least 32 characters
- `AUTHELIA_STORAGE_ENCRYPTION_KEY` - At least 32 characters
- `MAS_SECRET_KEY` - At least 32 characters
- `DOMAIN` and `SERVER_NAME` - Your domain (use `matrix.localhost` for local testing)

You can generate secure secrets with:
```bash
openssl rand -base64 32
```

### 2. Generate Synapse Configuration

Run the setup script to generate the initial Synapse configuration:

```bash
./setup-synapse.sh
```

This will create `./synapse/data/homeserver.yaml`.

### 3. Configure Synapse for PostgreSQL and MAS

Edit `./synapse/data/homeserver.yaml`:

#### Database Configuration
Find the `database:` section and replace it with:

```yaml
database:
  name: psycopg2
  args:
    user: synapse
    password: changeme  # Use your POSTGRES_PASSWORD from .env
    database: synapse
    host: postgres
    port: 5432
    cp_min: 5
    cp_max: 10
```

#### Enable Registration (Optional)
Find `enable_registration:` and set it to `true` if you want to allow registration:

```yaml
enable_registration: true
enable_registration_without_verification: false
```

#### Configure MAS Integration
Add this section to enable Matrix Authentication Service:

```yaml
# Experimental features for MAS
experimental_features:
  # Enable support for MAS issuing OIDC-based access tokens
  msc3861:
    enabled: true
    issuer: http://mas:8080/
    client_id: 01HQW90Z35CMXFJWQPHC3BGZGQ
    client_auth_method: none
    admin_token: changeme_admin_token
```

### 4. Setup Authelia Users

Generate a password hash for your admin user:

```bash
docker run authelia/authelia:latest authelia crypto hash generate argon2 --password 'yourpassword'
```

Edit `./authelia/config/users_database.yml` and replace the password hash.

### 5. Generate Authelia Secrets

#### Generate RSA key for OIDC:
```bash
openssl genrsa -out authelia_private.pem 4096
cat authelia_private.pem
```

Copy the key content and paste it into `./authelia/config/configuration.yml` under `identity_providers.oidc.issuer_private_key`.

#### Generate client secret hash:
```bash
docker run authelia/authelia:latest authelia crypto hash generate pbkdf2 --variant sha512 --random --random.length 72 --random.charset rfc3986
```

Copy the hash and update `./authelia/config/configuration.yml` under `identity_providers.oidc.clients[0].client_secret`.

Also update the plain text secret in `./mas/config/config.yaml` under `upstream_oauth2.providers[0].client_secret`.

### 6. Generate MAS Signing Key

Generate an RSA key for MAS:

```bash
openssl genrsa 4096 | openssl pkcs8 -topk8 -nocrypt > mas-signing.key
cat mas-signing.key
```

Copy the content and paste it into `./mas/config/config.yaml` under `secrets.keys[0].data`.

### 7. Update MAS Database Password

Edit `./mas/config/config.yaml` and update the database URI:

```yaml
database:
  uri: 'postgresql://synapse:YOUR_POSTGRES_PASSWORD@postgres/mas'
```

Replace `YOUR_POSTGRES_PASSWORD` with the value from your `.env` file.

### 8. Start the Stack

Start PostgreSQL and wait for it to initialize:

```bash
docker compose up -d postgres
docker compose logs -f postgres
```

Wait until you see "database system is ready to accept connections", then press Ctrl+C.

Start the remaining services:

```bash
docker compose up -d
```

Check that everything is running:

```bash
docker compose ps
```

### 9. Access the Services

- **Element Web**: http://localhost:8080
- **Synapse**: http://localhost:8008
- **MAS**: http://localhost:8081
- **Authelia**: http://localhost:9091

### 10. Create Your First User

Since we're using SSO via Authelia, you first need to create a user in Authelia (see step 4), then:

1. Go to Element Web at http://localhost:8080
2. Click "Sign In"
3. You should be redirected to MAS
4. MAS will redirect you to Authelia
5. Log in with your Authelia credentials
6. Complete 2FA setup if required
7. You'll be redirected back to Element Web

## Setting Up Bridges

### Generate Bridge Configurations

Run the bridge setup script:

```bash
./setup-bridges.sh
```

This will generate configuration files for all three bridges.

### Configure Each Bridge

For each bridge (telegram, whatsapp, signal):

1. Edit the config file at `./bridges/{bridge}/config/config.yaml`
2. Set the homeserver address to `http://synapse:8008`
3. Set the domain to `matrix.localhost` (or your domain)
4. Note the `as_token` and `hs_token` values

### Register Bridges with Synapse

Each bridge generates a registration file. Copy them to Synapse:

```bash
cp ./bridges/telegram/config/registration.yaml ./synapse/data/telegram-registration.yaml
cp ./bridges/whatsapp/config/registration.yaml ./synapse/data/whatsapp-registration.yaml
cp ./bridges/signal/config/registration.yaml ./synapse/data/signal-registration.yaml
```

Edit `./synapse/data/homeserver.yaml` and add:

```yaml
app_service_config_files:
  - /data/telegram-registration.yaml
  - /data/whatsapp-registration.yaml
  - /data/signal-registration.yaml
```

Restart Synapse:

```bash
docker compose restart synapse
```

### Using the Bridges

#### Telegram Bridge
1. Start a chat with `@telegrambot:matrix.localhost`
2. Send `login`
3. Follow the authentication steps

#### WhatsApp Bridge
1. Start a chat with `@whatsappbot:matrix.localhost`
2. Send `login`
3. Scan the QR code with your phone

#### Signal Bridge
1. Start a chat with `@signalbot:matrix.localhost`
2. Send `link`
3. Scan the QR code or link your device

## Mobile Client (Element-X)

Element-X is available for iOS and Android. Configure it with:

- **Homeserver URL**: http://your-server-ip:8008 (or your public domain if accessible)
- Use your Authelia credentials to log in via SSO

## Troubleshooting

### Check Service Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f synapse
docker compose logs -f mas
docker compose logs -f authelia
```

### Service Not Starting

Check the logs for errors:
```bash
docker compose logs service-name
```

### Database Connection Issues

Ensure PostgreSQL is running and healthy:
```bash
docker compose exec postgres pg_isready -U synapse
```

### Port Conflicts

If ports are already in use, edit `docker-compose.yml` and change the port mappings:
```yaml
ports:
  - "8008:8008"  # Change left side to available port
```

### Reset Everything

To start fresh:
```bash
docker compose down -v
rm -rf postgres/data synapse/data mas/data bridges/*/config
```

Then start from step 2.

## Security Notes

⚠️ **For Production Use:**

1. Use strong, unique passwords and secrets
2. Set up proper TLS/SSL certificates (use Caddy or nginx reverse proxy)
3. Use a real domain name
4. Configure firewall rules
5. Regular backups of PostgreSQL data
6. Keep all containers updated
7. Review and harden all configuration files
8. Consider using Docker secrets instead of environment variables

## Backup

Important directories to backup:
- `./postgres/data` - All database data
- `./synapse/data` - Synapse configuration and media
- `./mas/data` - MAS data
- `./authelia/config` - Authelia configuration
- `./bridges/*/config` - Bridge configurations

## Next Steps

1. Configure reverse proxy (Caddy/nginx) for HTTPS
2. Set up proper domain names
3. Configure email for Authelia notifications
4. Customize Element Web branding
5. Set up media repository size limits
6. Configure backup automation

## Resources

- [Matrix Synapse Documentation](https://matrix-org.github.io/synapse/latest/)
- [Element Documentation](https://element.io/help)
- [MAS Documentation](https://element-hq.github.io/matrix-authentication-service/)
- [Authelia Documentation](https://www.authelia.com/)
- [mautrix bridges Documentation](https://docs.mau.fi/)
