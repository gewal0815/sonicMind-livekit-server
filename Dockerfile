FROM livekit/livekit-server:latest

# The official image is debian:bookworm-slim based.
# Add tools needed for ICE TCP proxy fallback (haproxy) and DNS resolution.
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash haproxy iptables dnsutils \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
