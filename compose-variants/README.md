# Compose File Variants

This folder contains alternative Docker Compose configurations that are not used in the main deployment.

## Files

- **docker-compose.old.yml** - Original compose configuration (legacy)
- **docker-compose.local.yml** - Local testing configuration with self-signed certificates
- **docker-compose.authelia.yml** - Standalone Authelia service
- **docker-compose.caddy.yml** - Standalone Caddy service

## Active Configuration

The active configuration is in the root directory as **docker-compose.yml** (production configuration).

## Usage

These variants can be used for:
- Local development and testing (docker-compose.local.yml)
- Reference for different deployment architectures
- Standalone service testing

To use a variant:
```bash
docker compose -f compose-variants/docker-compose.local.yml up -d
```
