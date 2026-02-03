# Immich - Self-Hosted Photo and Video Management

A self-hosted photo and video management solution with automatic backup, machine learning-based photo recognition, and a modern web and mobile interface.

## 📋 Overview

This is a Docker Compose setup for running Immich, providing:

- **Photo & Video Storage**: Automatic upload and organization of your media files
- **Machine Learning**: Face recognition, object detection, and smart search
- **Web & Mobile Access**: Modern interface accessible from any device
- **Privacy First**: All data stays on your own server

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose
- At least 4GB RAM
- Sufficient storage for your media files

### Installation

1. **Clone or navigate to this directory**
   ```bash
   cd /Users/liorg/homedev/immich
   ```

2. **Configure environment variables**
   ```bash
   cp .env.example .env  # If not already created
   nano .env
   ```

   Key settings to configure:
   ```bash
   UPLOAD_LOCATION=./library          # Where your photos/videos are stored
   DB_DATA_LOCATION=./postgres        # Database storage location
   IMMICH_VERSION=release             # Immich version to use
   ```

3. **Start Immich**
   ```bash
   docker compose up -d
   ```

4. **Access Immich**
   
   Open your browser and navigate to:
   ```
   http://localhost:2283
   ```

5. **Create your admin account**
   
   Follow the on-screen instructions to set up your first user account.

## 📁 Directory Structure

```
immich/
├── docker-compose.yml       # Docker services configuration
├── .env                     # Environment variables (private)
├── library/                 # Your uploaded photos and videos
├── postgres/                # Database files
├── backup_script/           # Backup and restore scripts
└── README.md               # This file
```

## 🔧 Management

### Start Immich
```bash
docker compose up -d
```

### Stop Immich
```bash
docker compose down
```

### View Logs
```bash
docker compose logs -f
```

### Check Status
```bash
docker compose ps
```

### Update Immich
```bash
docker compose pull
docker compose down
docker compose up -d
```

## 💾 Backup & Restore

This installation includes comprehensive backup scripts in the `backup_script/` directory.

### Quick Backup

```bash
cd backup_script
./backup-immich.sh
```

This will backup:
- PostgreSQL database (compressed SQL dump)
- All media files (photos/videos)
- Configuration files

### Learn More

See the backup documentation:
- [Backup README](backup_script/README-BACKUP.md) - Full documentation
- [Quick Start Guide](backup_script/QUICKSTART-BACKUP.md) - Get started in 3 steps

## 🔍 Services

This installation runs the following Docker containers:

- **immich-server**: Main application server (port 2283)
- **immich-machine-learning**: ML service for face recognition and object detection
- **database**: PostgreSQL with vector search extensions
- **redis**: Caching and job queue

## ⚙️ Configuration

### Environment Variables

Key variables in `.env`:

```bash
# Immich
UPLOAD_LOCATION=./library
IMMICH_VERSION=release

# Database
DB_DATABASE_NAME=immich
DB_USERNAME=postgres
DB_PASSWORD=<your-secure-password>
DB_DATA_LOCATION=./postgres

# Ports
IMMICH_PORT=2283
```

### Hardware Acceleration

For faster video transcoding, edit `docker-compose.yml` and uncomment the hardware acceleration section:

```yaml
extends:
  file: hwaccel.transcoding.yml
  service: quicksync  # or nvenc, vaapi, etc.
```

## 🐛 Troubleshooting

### Immich won't start

Check the logs:
```bash
docker compose logs
```

### Database connection errors

Ensure the database container is running:
```bash
docker ps | grep postgres
```

### Storage is full

Check disk usage:
```bash
du -sh library/
du -sh postgres/
df -h
```

### Reset Immich

**⚠️ Warning: This will delete all your data!**

```bash
docker compose down -v
rm -rf library/ postgres/
docker compose up -d
```

## 📱 Mobile Apps

Immich has official mobile apps for automatic photo backup:

- **iOS**: Available on the App Store
- **Android**: Available on Google Play Store or F-Droid

Configure the app to point to your server:
```
Server URL: http://your-server-ip:2283
```

## 🔐 Security

### Recommended Security Measures

1. **Change default passwords** in `.env`
2. **Use HTTPS** with a reverse proxy (nginx, Caddy, Traefik)
3. **Enable firewall** rules to restrict access
4. **Regular backups** using the provided scripts
5. **Keep Immich updated** to the latest version

### Reverse Proxy Example (nginx)

```nginx
server {
    listen 443 ssl;
    server_name photos.yourdomain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:2283;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

## 📚 Resources

- **Official Documentation**: https://docs.immich.app
- **GitHub Repository**: https://github.com/immich-app/immich
- **Discord Community**: https://discord.gg/immich
- **Issues & Feature Requests**: https://github.com/immich-app/immich/issues

## 📝 Maintenance

### Regular Tasks

- **Weekly**: Check logs for errors
- **Monthly**: Update to latest version
- **Monthly**: Test backup restore process
- **Quarterly**: Review and clean up old backups

### Monitoring

Check Immich health:
```bash
curl http://localhost:2283/api/server/ping
```

## 🆘 Support

If you encounter issues:

1. Check the [Troubleshooting](#-troubleshooting) section
2. Review logs: `docker compose logs`
3. Search existing [GitHub issues](https://github.com/immich-app/immich/issues)
4. Join the [Discord community](https://discord.gg/immich)
5. Review the [official documentation](https://docs.immich.app)

## 📄 License

Immich is licensed under the AGPL-3.0 License.

This README and backup scripts are provided as-is for your personal use.

---

**Happy photo managing! 📸**
