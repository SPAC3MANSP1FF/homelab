# Homelab

Docker-based homelab configuration for a self-hosted cloud, networking, and utility server. The primary application stack lives in [`docker-apps/compose.yaml`](docker-apps/compose.yaml); maintenance and offsite backup automation scripts live in [`scripts/`](scripts/).

This repository contains operational configuration and documentation only. Secrets, database files, media libraries, and persistent container data remain outside Git.

The stack was developed and tested on an Ubuntu Server host, with this repository checked out in the user's home directory (`~/homelab`). The Compose stack itself is not strictly tied to that checkout location: clone it elsewhere, run Compose from `docker-apps/`, and update the absolute host paths in `.env`.

The default setup uses `/var/lib/docker/appdata` for persistent application data. This is a convention rather than a strict requirement.

---

## Services

| Service | Container Name | Purpose | Local Port / Access |
| :--- | :--- | :--- | ---: |
| **Pi-hole** | `pihole` | DNS filtering and local DNS resolution | `53/tcp`, `53/udp` |
| **Nginx Proxy Manager** | `nginx-proxy-manager` | Reverse proxy and automated TLS management | `80`, `81`, `443` |
| **LAMP Web Server** | `lamp-web` | Apache/PHP (`php:8.4-apache`) application stack | `8080` |
| **LAMP Database** | `lamp-db` | MariaDB database instance (`10.11`) | `3306` |
| **phpMyAdmin** | `phpmyadmin` | MariaDB administration UI | `8081` |
| **Nextcloud** | `nextcloud-app` | Self-hosted personal cloud & photo storage | Via Reverse Proxy |
| **Nextcloud Database** | `nextcloud-db` | Dedicated MariaDB backend (`11.4`) | Internal |
| **Cloudflare Tunnel** | `cloudflared` | Outbound tunnel access for external web ingress | None |
| **Tailscale** | `tailscale` | Secure VPN overlay network & subnet routing | None |
| **MagicMirror²** | `magicmirror` | Server-rendered display dashboard | `8090` |

Most web-facing services join the external Docker network `proxy-tier`, allowing Nginx Proxy Manager, Cloudflare Tunnel, and internal containers to route traffic by container name.

---

## Requirements

- Linux host with Docker Engine and Docker Compose v2 (`docker compose`)
- Git & `rsync`
- A Docker host user with UID/GID `1000` for LinuxServer.io containers
- An existing external Docker network named `proxy-tier`

Create the shared Docker network once prior to initial startup:

```bash
docker network create proxy-tier