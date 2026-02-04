# Nginx Reverse Proxy Setup

## Current Configuration

Your Immich server is now protected behind an Nginx reverse proxy.

- **HTTP Access**: Port 2283 (mapped to Nginx port 80)
- **HTTPS Access**: Port 2284 (ready for SSL - currently commented out)

## Security Features Enabled

- X-Frame-Options header (prevents clickjacking)
- X-Content-Type-Options header (prevents MIME type sniffing)
- X-XSS-Protection header
- Referrer-Policy header
- Large file upload support (10GB limit)
- WebSocket support for Immich features
- Proper timeout configurations

## Accessing Your Server

Access your Immich server at: `http://your-server-ip:2283`

## SSL/HTTPS Setup (Recommended for External Access)

### Option 1: Self-Signed Certificate (for testing)

```bash
cd nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout key.pem -out cert.pem \
  -subj "/CN=your-domain-or-ip"
```

### Option 2: Let's Encrypt Certificate (for production)

1. Install certbot on your host machine
2. Obtain certificates:
```bash
certbot certonly --standalone -d your-domain.com
```
3. Copy certificates to `nginx/ssl/`:
```bash
cp /etc/letsencrypt/live/your-domain.com/fullchain.pem nginx/ssl/cert.pem
cp /etc/letsencrypt/live/your-domain.com/privkey.pem nginx/ssl/key.pem
```

### Enable HTTPS

After placing your SSL certificates in `nginx/ssl/`:

1. Edit `nginx.conf`
2. Uncomment the HTTPS server block (lines starting with #)
3. Uncomment the HTTP to HTTPS redirect line
4. Restart the containers: `docker compose restart nginx-proxy`

Your server will then be accessible at: `https://your-server-ip:2284`

## Additional Security Recommendations

1. **Use SSL/HTTPS** for external access
2. **Set up a firewall** to allow only ports 2283/2284
3. **Use strong passwords** in your Immich configuration
4. **Consider using Cloudflare** or similar service for additional DDoS protection
5. **Regular backups** - use the backup script in `backup_script/`
6. **Keep images updated**: `docker compose pull && docker compose up -d`

## Troubleshooting

- Check nginx logs: `docker compose logs nginx-proxy`
- Test nginx config: `docker compose exec nginx-proxy nginx -t`
- Restart proxy: `docker compose restart nginx-proxy`
