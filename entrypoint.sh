#!/bin/sh
set -u

echo "========================================"
echo " SonicMind LiveKit Server — Starting"
echo "========================================"
echo " PORT               = ${PORT:-NOT_SET}"
echo " LIVEKIT_API_KEY    = ${LIVEKIT_API_KEY:+SET}"
echo " LIVEKIT_API_SECRET = ${LIVEKIT_API_SECRET:+SET}"
echo " REDIS_URL          = ${REDIS_URL:+SET}"
echo "========================================"

# Verify livekit-server binary
LIVEKIT_BIN="/livekit-server"
if [ ! -x "$LIVEKIT_BIN" ]; then
  echo "FATAL: /livekit-server not found or not executable"
  exit 1
fi
echo "Binary OK: $LIVEKIT_BIN"

# --- Required env var checks ---
if [ -z "${LIVEKIT_API_KEY:-}" ]; then
  echo "FATAL: LIVEKIT_API_KEY is not set in Railway Variables"
  exit 1
fi
if [ -z "${LIVEKIT_API_SECRET:-}" ]; then
  echo "FATAL: LIVEKIT_API_SECRET is not set in Railway Variables"
  exit 1
fi

SIGNAL_PORT="${PORT:-8080}"
echo "Signal port: $SIGNAL_PORT"

# --- Generate config ---
mkdir -p /etc
cat > /etc/livekit.yaml <<EOF
port: ${SIGNAL_PORT}

bind_addresses:
  - "0.0.0.0"

log_level: debug

rtc:
  tcp_port: 7881
  use_external_ip: true

keys:
  ${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}

room:
  auto_create: true

turn:
  enabled: false
EOF

echo "=== /etc/livekit.yaml ==="
cat /etc/livekit.yaml
echo "========================="
echo ""
echo "Launching livekit-server ..."

"$LIVEKIT_BIN" --config /etc/livekit.yaml
EXIT_CODE=$?

echo ""
echo "!!! livekit-server EXITED with code $EXIT_CODE !!!"
echo "Sleeping 120s for log capture..."
sleep 120
exit "$EXIT_CODE"
