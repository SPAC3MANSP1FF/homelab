# Homelab

Docker-based homelab configuration for a self-hosted cloud, networking, and utility server. The main application stack lives in [`docker-apps/compose.yaml`](docker-apps/compose.yaml); the shell scripts in [`scripts/`](scripts/) handle maintenance, backups, and Plex migration.

This repository contains configuration and operational documentation, not application data. Secrets, database files, media libraries, and persistent container data should remain outside Git.

The stack was developed and tested on an Ubuntu Server `26.04` host, with this repository checked out in my home directory. The Compose stack itself is not tied to that checkout location: clone it elsewhere, run Compose from `docker-apps/`, and update the absolute host paths in `.env`. The maintenance scripts also require their configured `DOCKER_DIR` and `REPO_DIR` values to point to the new locations.

The default examples use `/var/lib/docker/appdata` for persistent application data. This is a convention rather than a requirement, except for the hard-coded ownership cleanup path in `scripts/plex_migrate.sh`; change that script if Plex app data is stored elsewhere.

## Services

The Compose stack currently includes:

| Service | Purpose | Local port |
| --- | --- | ---: |
| Pi-hole | DNS filtering and local DNS | `53/tcp`, `53/udp` |
| Nginx Proxy Manager | Reverse proxy and TLS management | `80`, `81`, `443` |
| LAMP web/database | PHP/Apache and MariaDB application stack | `8080`, `3306` |
| phpMyAdmin | MariaDB administration | `8081` |
| Nextcloud | Personal cloud storage | Through the proxy |
| Cloudflare Tunnel | Outbound tunnel access | None |
| Tailscale | VPN and subnet routing | None |
| MagicMirror | Server-rendered dashboard | `8090` |

Most services share the external Docker network `proxy-tier`, allowing Nginx Proxy Manager, Cloudflare Tunnel, and other services to reach them by container name.

## Requirements

- Linux host with Docker Engine and the Docker Compose plugin
- Git
- Sufficient storage for application data and media libraries
- A Docker host user with UID/GID `1000` for the LinuxServer.io containers, or corresponding updates to the Compose file
- An existing network named `proxy-tier`

Create the shared network once:

```bash
docker network create proxy-tier
```

## Initial Setup

Clone the repository and enter the Compose directory:

```bash
git clone <repository-url> homelab
cd homelab/docker-apps
```

Create the environment file from the template:

```bash
cp .env.example .env
chmod 600 .env
```

Edit `.env` and set all values marked as placeholders. Configure the time zone, credentials, host paths, media paths, container paths, Nextcloud usernames, and MagicMirror wallpaper directory.

The path variables are split into host paths (`PATH_*`) and container paths (`CONT_*`). Keep both sides consistent with the applications that consume them.

### Environment Files

Docker Compose automatically reads `docker-apps/.env` when Compose is run from this directory. It uses that file for variable substitution in `compose.yaml`; it is not mounted into any container.

Keep the Compose environment file separate from the script configuration files:

| Template | Copy to | Used by |
| --- | --- | --- |
| `docker-apps/.env.example` | `docker-apps/.env` | Docker Compose |
| `scripts/.config/update.env.example` | `scripts/.config/update.env` | `scripts/update.sh` |
| `scripts/.config/backup.env.example` | `scripts/.config/backup.env` | `scripts/backup.sh` |
| `scripts/.config/plex_migrate.env.example` | `scripts/.config/plex_migrate.env` | `scripts/plex_migrate.sh` |

The script configuration files are sourced as Bash files, so use shell-compatible assignments such as `KEY=value` or `KEY="value with spaces"`. The Compose `.env` file is a Docker environment file and should contain the variable values expected by `compose.yaml`. Do not add secrets to the example templates.

After editing the Compose environment file, inspect the resolved configuration:

```bash
docker compose config
```

This command expands variables and can reveal missing values or incorrect paths before containers are started. Environment files are ignored by Git, but continue to treat them as secrets and keep their permissions restrictive:

```bash
chmod 600 .env
chmod 600 ../scripts/.config/*.env
```

Validate the rendered Compose configuration before starting anything:

```bash
docker compose config
```

Start the stack in the background:

```bash
docker compose up -d
```

Check service state and logs:

```bash
docker compose ps
docker compose logs -f <service>
```

The full maintenance workflow is available in [`scripts/update.sh`](scripts/update.sh). It updates Ubuntu packages, pulls Docker images, recreates the stack, prunes dangling images, and pulls the Git repository. Configure it first with [`scripts/.config/update.env.example`](scripts/.config/update.env.example), then copy and edit the file as `scripts/.config/update.env`.

```bash
cd scripts
cp .config/update.env.example .config/update.env
chmod 600 .config/update.env
sudo ./update.sh
```

## Backups

[`scripts/backup.sh`](scripts/backup.sh) uses SSH and `rsync` to back up selected home folders, media folders, and Docker application data to a remote host. It briefly stops the Compose stack before copying application data so databases are in a consistent state, then starts the stack again.

Configure it with:

```bash
cd scripts
cp .config/backup.env.example .config/backup.env
chmod 600 .config/backup.env
```

Set the remote host and user, SSH key, source and destination paths, media folder list, Docker app-data path, and Compose file path. Test the transfer without changing files:

```bash
./backup.sh --dry-run
```

Run a real backup only after reviewing the dry-run output:

```bash
./backup.sh
```

Logs are written to `/var/log/homelab`. The backup script must be able to create that directory and write to it.

## Plex Migration

[`scripts/plex_migrate.sh`](scripts/plex_migrate.sh) copies an existing Plex library from another server into the configured Docker app-data directory. It excludes caches, logs, indexes, diagnostics, and other regenerable files.

Configure the source SSH user, source server address, old Plex library path, and local destination in `.config/plex_migrate.env`:

```bash
cd scripts
cp .config/plex_migrate.env.example .config/plex_migrate.env
chmod 600 .config/plex_migrate.env
sudo ./plex_migrate.sh
```

Review the paths and SSH permissions before running the migration. The script uses `sudo` locally and expects the remote account to be able to run `rsync` with `sudo`.

## MagicMirror Kiosk

MagicMirror runs in server mode on port `8090`. A Raspberry Pi Zero 2W can act as a thin-client kiosk that opens the dashboard in Chromium. The complete setup is documented in [`docker-apps/magicmirror-pi-tutorial.md`](docker-apps/magicmirror-pi-tutorial.md).

The Pi does not need the MagicMirror source or modules. Its browser connects to the Docker host, while configuration and third-party modules remain in the paths configured by `PATH_MAGICMIRROR_CONFIG` and `PATH_MAGICMIRROR_MODULES`.

## Security Notes

- Never commit `.env`, script configuration files, SSH keys, tunnel tokens, claim tokens, or database passwords.
- Restrict permissions on local environment files with `chmod 600`.
- Do not expose database ports such as `3306` to the public internet.
- Review Nginx Proxy Manager and Cloudflare Tunnel routes before making services internet-accessible.
- Pi-hole, qBittorrent, phpMyAdmin, and other administrative interfaces should be limited to trusted networks or protected by authentication and VPN access.
- The Compose file currently uses several `latest` image tags. Pin versions when reproducible upgrades are important, and test updates before relying on them in production.
- The Compose file expects the external `proxy-tier` network to exist before startup.

## Repository Layout

```text
.
├── docker-apps/
│   ├── compose.yaml
│   ├── .env.example
│   └── magicmirror-pi-tutorial.md
├── scripts/
│   ├── backup.sh
│   ├── plex_migrate.sh
│   ├── update.sh
│   └── .config/*.env.example
├── LICENSE
└── README.md
```

Persistent data directories under `docker-apps/` are intentionally ignored by Git. Back up the configured host paths, not just this repository.

## License

This project is licensed under the GNU General Public License v3.0. See [`LICENSE`](LICENSE) for the full text.

## Common Access Points

These are the direct LAN endpoints when the host firewall allows them:

```text
http://<host>:81       Nginx Proxy Manager
http://<host>:8080     LAMP web application
http://<host>:8081     phpMyAdmin
http://<host>:8090     MagicMirror
```

Nextcloud is not directly published by the current Compose file and should be exposed through the reverse proxy or Cloudflare Tunnel.

## Operations

Run commands from `docker-apps/` unless a command says otherwise:

```bash
# Apply changes to Compose configuration
docker compose up -d

# Pull images and recreate services
docker compose pull
docker compose up -d

# Stop the stack
docker compose down

# Restart one service
docker compose restart <service>

# Follow logs
docker compose logs -f <service>
```
