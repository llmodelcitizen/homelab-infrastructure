#!/bin/bash
# Configure qBittorrent for access behind Traefik + Authelia
# qBittorrent manages its own config file at runtime, so we patch it on every start

CONF="/config/qBittorrent/qBittorrent.conf"

if [ -f "$CONF" ]; then
    # Disable reverse proxy support so qBittorrent sees Traefik's direct IP
    # (172.18.0.x) instead of the real client IP from X-Forwarded-For. This
    # lets the auth subnet whitelist bypass qBittorrent's login for requests
    # arriving through Traefik (already authenticated by Authelia).
    sed -i 's/^WebUI\\ReverseProxySupportEnabled=.*/WebUI\\ReverseProxySupportEnabled=false/' "$CONF"
    sed -i '/^WebUI\\TrustedReverseProxiesList=/d' "$CONF"

    # Enable auth bypass for the traefik-public network
    sed -i 's/^WebUI\\AuthSubnetWhitelistEnabled=.*/WebUI\\AuthSubnetWhitelistEnabled=true/' "$CONF"
    sed -i 's|^WebUI\\AuthSubnetWhitelist=.*|WebUI\\AuthSubnetWhitelist=172.18.0.0/16|' "$CONF"

    # Disable CSRF protection -- Authelia handles authentication, and the
    # Origin/Referer headers don't match when routed through the SSO portal
    if ! grep -q "CSRFProtection" "$CONF"; then
        sed -i '/^\[Preferences\]/a WebUI\\CSRFProtection=false' "$CONF"
    fi
fi
