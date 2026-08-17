# Building a Self-Hosted Homelab with Docker and Ubuntu

A step-by-step guide to deploying, configuring, and maintaining a self-hosted homelab stack for cloud storage, ad blocking, local web development, and secure remote networking.

---

## Overview & Architecture

This guide walks through setting up a modular Docker-based homelab on an Ubuntu Server. By using Docker Compose and an external proxy network, services can securely communicate with each other while exposing only the necessary endpoints to your local network or VPN.

```text
                                 ┌────────────────────────┐
                                 │   Nginx Proxy Manager  │
                                 │      (:80, :443)       │
                                 └───────────┬────────────┘
                                             │
                                ┌────────────┴────────────┐
                                │   proxy-tier Network    │
                                └────────────┬────────────┘
                                             │
      ┌──────────────────┬───────────────────┼───────────────────┬──────────────────┐
      │                  │                   │                   │                  │
┌─────┴──────┐     ┌─────┴──────┐     ┌──────┴─────┐     ┌───────┴──────┐    ┌──────┴─────┐
│ Nextcloud  │     │  Pi-hole   │     │ LAMP Stack │     │  phpMyAdmin  │    │ Tailscale  │
│ Cloud Store│     │ DNS Filter │     │ Apache/PHP │     │ Database UI  │    │ Mesh VPN   │
└────────────┘     └────────────┘     └────────────┘     └──────────────┘    └────────────┘
```

---

## Prerequisites

Before starting, ensure your host machine meets the following requirements:

* **Operating System:** Ubuntu Server (or Linux equivalent)
* **Software:**
  * Docker Engine v24.0+
  * Docker Compose v2 (`docker compose`)
  * Git & `rsync`
* **User Permissions:** A user account with `sudo` privileges and standard UID/GID `1000`.

---

## Step 1: Network & Directory Preparation

Create a shared external Docker network named `proxy-tier`. This network allows Nginx Proxy Manager, Cloudflare Tunnel, and other front-end services to route traffic to internal applications by container name.

```bash
# Create external Docker network
docker network create proxy-tier

# Create application data directory structure
sudo mkdir -p /var/lib/docker/appdata
```

---

## Step 2: Repository Installation

Clone the `homelab` repository to your host system:

```bash
# Clone repository
git clone https://github.com/SPAC3MANSP1FF/homelab.git ~/homelab

# Navigate to the compose directory
cd ~/homelab/docker-apps
```

---

## Step 3: Environment Configuration

Copy the template environment file and restrict its permissions so sensitive credentials remain private:

```bash
# Copy template environment file
cp .env.example .env

# Restrict permissions
chmod 600 .env
```

Open `.env` in your preferred text editor (e.g., `nano .env`) and update all placeholder variables:

* **`PATH_APPDATA`**: Base host path for persistent volumes (default: `/var/lib/docker/appdata`).
* **`TZ`**: Your local timezone (e.g., `America/Los_Angeles`).
* **Database Credentials:** Secure passwords for MariaDB instances (`lamp-db` and `nextcloud-db`).

---

## Step 4: Validating and Launching Services

Before starting the containers, validate the rendered Docker Compose configuration to ensure all environment variables expand correctly:

```bash
# Validate compose file
docker compose config
```

If no errors are displayed, start the container stack in detached mode:

```bash
# Launch containers in background
docker compose up -d

# Check status of running containers
docker compose ps
```

---

## Step 5: Automated Maintenance & Backups

To keep system packages, Git repositories, and Docker images up to date, configure the automated scripts in `scripts/`:

```bash
cd ~/homelab/scripts
cp .config/update.env.example .config/update.env
cp .config/backup.env.example .config/backup.env
chmod 600 .config/*.env
```

### Dry-Run Testing
Test update and backup workflows safely without making changes to disk:

```bash
# Test update script
sudo ./update.sh --dry-run

# Test offsite rsync backup
sudo ./backup.sh --dry-run
```

---

## Service Reference & Ports

Once deployed, access local administrative dashboards using your host's LAN IP address:

| Service | Local URL / Access | Description |
| :--- | :--- | :--- |
| **Nginx Proxy Manager** | `http://<host-ip>:81` | Reverse proxy and SSL certificate management |
| **LAMP Web App** | `http://<host-ip>:8080` | Local Apache/PHP development environment |
| **phpMyAdmin** | `http://<host-ip>:8081` | Database UI for MySQL / MariaDB |
| **Pi-hole** | `http://<host-ip>/admin` | Network-wide ad blocking and local DNS |
| **Nextcloud** | Via Proxy / Tunnel | Cloud file storage and synchronization |
