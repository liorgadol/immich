# Fail2ban Configuration for Immich

This directory contains fail2ban configuration to protect your Immich instance from brute force attacks and abuse.

## How It Works

Fail2ban monitors nginx logs and automatically bans IP addresses that show malicious behavior by adding iptables firewall rules.

### Two Protection Layers

1. **nginx-immich-auth**: Monitors failed authentication attempts
   - Bans after 5 failed login attempts within 5 minutes
   - Ban duration: 1 hour
   - Watches: `/api/auth/` and `/api/oauth/` endpoints for 401/403 responses

2. **nginx-immich-limit**: Monitors rate limit violations
   - Bans after 10 rate limit violations within 1 minute
   - Ban duration: 10 minutes
   - Watches: nginx error log for rate limit messages

## Commands

### Check fail2ban status
```bash
docker exec immich_fail2ban fail2ban-client status
```

### Check specific jail status
```bash
docker exec immich_fail2ban fail2ban-client status nginx-immich-auth
docker exec immich_fail2ban fail2ban-client status nginx-immich-limit
```

### View banned IPs
```bash
docker exec immich_fail2ban fail2ban-client banned
```

### Unban an IP address
```bash
docker exec immich_fail2ban fail2ban-client set nginx-immich-auth unbanip <IP_ADDRESS>
docker exec immich_fail2ban fail2ban-client set nginx-immich-limit unbanip <IP_ADDRESS>
```

### View fail2ban logs
```bash
docker logs immich_fail2ban
```

## Configuration Files

- `jail.d/immich.conf`: Defines the jails (when to ban and for how long)
- `filter.d/nginx-immich-auth.conf`: Filter for authentication failures
- `filter.d/nginx-immich-limit.conf`: Filter for rate limit violations

## Customization

Edit `jail.d/immich.conf` to adjust:
- `maxretry`: Number of failures before ban
- `findtime`: Time window in seconds to count failures
- `bantime`: How long to ban (in seconds)

## Troubleshooting

If IPs aren't being banned:
1. Check fail2ban logs: `docker logs immich_fail2ban`
2. Test the filter manually:
   ```bash
   docker exec immich_fail2ban fail2ban-regex /var/log/nginx/access.log /data/filter.d/nginx-immich-auth.conf
   ```
3. Verify nginx logs exist: `docker exec immich_nginx_proxy ls -la /var/log/nginx/`
