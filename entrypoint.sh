#!/bin/sh
set -u

echo "========================================"
echo " SonicMind LiveKit Server — Starting"
echo "========================================"
echo " PORT                   = ${PORT:-NOT_SET}"
echo " LIVEKIT_API_KEY        = ${LIVEKIT_API_KEY:+SET}"
echo " LIVEKIT_API_SECRET     = ${LIVEKIT_API_SECRET:+SET}"
echo " RAILWAY_TCP_APP_PORT   = ${RAILWAY_TCP_APPLICATION_PORT:-NOT_SET}"
echo " RAILWAY_TCP_PROXY_PORT = ${RAILWAY_TCP_PROXY_PORT:-NOT_SET}"
echo "========================================"

# Verify binary
LIVEKIT_BIN="/livekit-server"
if [ ! -x "$LIVEKIT_BIN" ]; then
  echo "FATAL: /livekit-server not found or not executable"
  exit 1
fi

# Required env vars
if [ -z "${LIVEKIT_API_KEY:-}" ]; then
  echo "FATAL: LIVEKIT_API_KEY is not set in Railway Variables"
  exit 1
fi
if [ -z "${LIVEKIT_API_SECRET:-}" ]; then
  echo "FATAL: LIVEKIT_API_SECRET is not set in Railway Variables"
  exit 1
fi

# HTTP signaling port — Railway's $PORT
SIGNAL_PORT="${PORT:-8080}"
echo "HTTP signaling port: $SIGNAL_PORT"

# ICE TCP port must not collide with the HTTP port.
# When Railway's TCP proxy is active it sets PORT = RAILWAY_TCP_APPLICATION_PORT,
# so $PORT is often 7881 — livekit's own default ICE TCP port.
# If they match, shift ICE TCP by one to avoid the bind conflict.
if [ "$SIGNAL_PORT" = "7881" ]; then
  ICE_TCP_PORT=7882
else
  ICE_TCP_PORT=7881
fi
echo "ICE TCP port: $ICE_TCP_PORT"

mkdir -p /etc
cat > /etc/livekit.yaml <<EOF
port: ${SIGNAL_PORT}

bind_addresses:
  - "0.0.0.0"

log_level: debug

keys:
  ${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}

room:
  auto_create: true

rtc:
  tcp_port: ${ICE_TCP_PORT}

turn:
  enabled: false
EOF

echo "=== /etc/livekit.yaml ==="
cat /etc/livekit.yaml
echo "========================="
echo ""
echo "Starting livekit-server on port $SIGNAL_PORT ..."
exec "$LIVEKIT_BIN" --config /etc/livekit.yaml
