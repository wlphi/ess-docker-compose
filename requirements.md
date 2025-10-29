* matrix synapse with element web
* matrix authentication service (MAS) with SSO auth via Authelia
* Postgres DB
* Bridges for telegram, whatsapp, signal
* All running on a single machine with docker compose
* element-x as mobile client

Target deployment:
* authelia runs on a separate machine
* SSL termination via caddy on a separate machine
* We can run both locally for testing, but keep this in mind for the production setup