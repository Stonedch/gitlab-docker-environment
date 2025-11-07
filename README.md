# GitLab Docker Compose Environment

Ready-to-use Docker Compose setup for GitLab with all necessary services for a complete development environment.

## Features

- GitLab CE/EE with full functionality
- PostgreSQL database for GitLab
- Redis for caching and background jobs
- Integrated Container Registry
- Pre-configured Docker environment
- Backup and restore utilities
- Custom domain and port configuration

## Table of Contents

1. [Requirements](#requirements)
2. [Quick Start](#quick-start)
3. [Detailed Setup](#detailed-setup)
4. [Services](#services)
5. [Administration](#administration)
6. [Backup & Restore](#backup--restore)
7. [Configuration](#configuration)
8. [Contacts](#contacts)

## Requirements

- Docker
- Docker Compose
- Minimum 4GB RAM (8GB recommended)
- 4+ CPU cores recommended
- At least 10GB free disk space
- Domain name pointing to your server (for proper GitLab functionality)

## Quick Start

1. Clone this repository:
```bash
git clone https://github.com/your-username/gitlab-docker-compose.git
cd gitlab-docker-compose
```
2. Configure your domain and ports in environment file:
```bash
cp .env.example .env
# Edit .env and set your domain:
# EXTERNAL_URL=http://komsalabs.ru
# HTTP_PORT=80
# HTTPS_PORT=443
# SSH_PORT=22
```
3. Start the containers:
```bash
docker-compose up -d --build
```
4. Wait for GitLab to initialize (may take several minutes) and access the web interface.

## Detailed Setup

1. Prepare environment files:
```bash
cp .env.example .env
# Edit .env according to your domain and requirements
```
2. Ensure directory structure:
```bash
# GITLAB_HOME=. will create directories in current folder
mkdir -p gitlab/config gitlab/data gitlab/logs
```
3. Build and start containers:
```bash
docker-compose up -d --build
```
4. Monitor initialization progress:
```bash
docker-compose logs -f gitlab
```
5. Access GitLab at your configured domain: http://komsalabs.ru

## Services

* GitLab: http://komsalabs.ru:80
    * Default admin user: root
    * Initial password: see Administration section
* SSH Access: port 22 (for Git operations)
* HTTPS: port 443 (if SSL configured)
* PostgreSQL: port 5432 (internal)
* Redis: port 6379 (internal)
* Container Registry: available on same domain

## Administration

### Get Root Password

After initial setup, retrieve the root password:

```bash
docker-compose exec -t gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

### Reset Root Password

If you've lost access, reset the root password:

```bash
docker-compose exec -t gitlab gitlab-rake "gitlab:password:reset"
```

### Check Service Status

```bash
docker-compose exec gitlab gitlab-ctl status
```

### View Configuration

```bash
docker-compose exec gitlab cat /etc/gitlab/gitlab.rb
```

## Backup & Restore

### Create Backup

Create a complete GitLab backup:

```bash
docker-compose exec -t gitlab gitlab-backup create
```

Backups are stored in /var/opt/gitlab/backups/ inside the container, which maps to ./gitlab/data/backups on host.

### Restore Backup

1. Ensure backup file is in the backups directory
2. Set proper ownership:
```bash
docker-compose exec -t gitlab chown git:git /var/opt/gitlab/backups/1762504061_2025_11_07_18.3.5-ee_gitlab_backup.tar
```
3. Restore the backup:
```bash
docker-compose exec -t gitlab gitlab-backup restore BACKUP=1762504061_2025_11_07_18.3.5-ee
```

> Important: Your gitlab.rb and gitlab-secrets.json files contain sensitive data and are not included in the backup. You will need to restore these files manually.

### Manual Configuration Backup

Backup configuration files separately:

```bash
# Backup from container
docker-compose exec gitlab tar czf /var/opt/gitlab/backups/$(date +%s)_gitlab_config.tar.gz /etc/gitlab/gitlab.rb /etc/gitlab/gitlab-secrets.json

# Or backup from host
cp ./gitlab/config/gitlab.rb ./gitlab/config/gitlab.rb.backup
cp ./gitlab/config/gitlab-secrets.json ./gitlab/config/gitlab-secrets.json.backup
```

## Configuration

### Environment Variables

Based on your .env configuration:

```bash
EXTERNAL_URL=http://komsalabs.ru
HTTP_PORT=80
HTTPS_PORT=443
SSH_PORT=22
GITLAB_HOME=.
```

### Port Mapping

The following ports are exposed on your host:

* 80 → GitLab HTTP
* 443 → GitLab HTTPS (if configured)
* 22 → GitLab SSH (for Git operations)

### Important Notes

1. SSH Port Conflict: If you have an existing SSH server on port 22, you may need to:
    * Change your system SSH to a different port
    * Or use a different SSH port for GitLab in .env
2. Domain Configuration: Ensure komsalabs.ru DNS points to your server's IP address.
3. SSL Certificate: For HTTPS, you'll need to configure SSL certificates in GitLab configuration.

### Custom Configuration

To add custom GitLab configuration, edit ./gitlab/config/gitlab.rb and run:

```bash
docker-compose exec gitlab gitlab-ctl reconfigure
```

## Troubleshooting

### Check Logs

```bash
docker-compose logs gitlab
docker-compose exec gitlab tail -f /var/log/gitlab/gitlab-rails/production.log
```

### Port Conflicts

If ports are already in use:

```bash
# Check what's using the ports
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :22

# Stop conflicting services or change ports in .env
```

### Permission Issues

Fix file permissions if needed:

```bash
sudo chown -R 1000:1000 ./gitlab/data
sudo chown -R 1000:1000 ./gitlab/logs
```

### Restart Services

```bash
docker-compose restart gitlab
# or
docker-compose exec gitlab gitlab-ctl restart
```

## Contacts

Created by @stonedch
