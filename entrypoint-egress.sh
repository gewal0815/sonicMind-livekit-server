#!/bin/bash
set -euo pipefail

echo "========================================"
echo " SonicMind LiveKit Egress - Starting"
echo "========================================"
echo " PORT                         = ${PORT:-NOT_SET}"
echo " LIVEKIT_URL                  = ${LIVEKIT_URL:+SET}"
echo " LIVEKIT_WS_URL               = ${LIVEKIT_WS_URL:+SET}"
echo " LIVEKIT_API_KEY              = ${LIVEKIT_API_KEY:+SET}"
echo " LIVEKIT_API_SECRET           = ${LIVEKIT_API_SECRET:+SET}"
echo " REDIS_URL                    = ${REDIS_URL:+SET}"
echo " LIVEKIT_EGRESS_HEALTH_PORT   = ${LIVEKIT_EGRESS_HEALTH_PORT:-NOT_SET}"
echo "========================================"

if [ -z "${LIVEKIT_API_KEY:-}" ]; then
  echo "FATAL: LIVEKIT_API_KEY is not set in Railway Variables"
  exit 1
fi

if [ -z "${LIVEKIT_API_SECRET:-}" ]; then
  echo "FATAL: LIVEKIT_API_SECRET is not set in Railway Variables"
  exit 1
fi

if [ -z "${REDIS_URL:-}" ]; then
  echo "FATAL: REDIS_URL is required. Egress must use the same Redis as livekit-server."
  exit 1
fi

WS_URL="${LIVEKIT_WS_URL:-${LIVEKIT_URL:-}}"
if [ -z "$WS_URL" ]; then
  echo "FATAL: LIVEKIT_WS_URL or LIVEKIT_URL is required"
  exit 1
fi

REDIS_USE_TLS="false"
if [[ "$REDIS_URL" == rediss://* ]]; then
  REDIS_USE_TLS="true"
fi
REDIS_NO_SCHEME="${REDIS_URL#redis://}"
REDIS_NO_SCHEME="${REDIS_NO_SCHEME#rediss://}"
REDIS_AUTH=""
REDIS_HOST_PORT="$REDIS_NO_SCHEME"
if [[ "$REDIS_NO_SCHEME" == *"@"* ]]; then
  REDIS_AUTH="${REDIS_NO_SCHEME%%@*}"
  REDIS_HOST_PORT="${REDIS_NO_SCHEME#*@}"
fi

REDIS_USERNAME=""
REDIS_PASSWORD=""
if [ -n "$REDIS_AUTH" ]; then
  if [[ "$REDIS_AUTH" == *":"* ]]; then
    REDIS_USERNAME="${REDIS_AUTH%%:*}"
    REDIS_PASSWORD="${REDIS_AUTH#*:}"
  else
    REDIS_PASSWORD="$REDIS_AUTH"
  fi
fi

if [ -z "$REDIS_HOST_PORT" ]; then
  echo "FATAL: Could not parse REDIS_URL"
  exit 1
fi

HEALTH_PORT="${LIVEKIT_EGRESS_HEALTH_PORT:-${PORT:-8080}}"
LOG_LEVEL="${LIVEKIT_EGRESS_LOG_LEVEL:-info}"
ENABLE_CHROME_SANDBOX="${LIVEKIT_EGRESS_ENABLE_CHROME_SANDBOX:-false}"

CONFIG_FILE="/home/egress/livekit-egress.yaml"

cat > "$CONFIG_FILE" <<EOF
log_level: ${LOG_LEVEL}
api_key: ${LIVEKIT_API_KEY}
api_secret: ${LIVEKIT_API_SECRET}
ws_url: ${WS_URL}
health_port: ${HEALTH_PORT}
enable_chrome_sandbox: ${ENABLE_CHROME_SANDBOX}

redis:
  address: ${REDIS_HOST_PORT}
EOF

if [ "$REDIS_USE_TLS" = "true" ]; then
  cat >> "$CONFIG_FILE" <<EOF
  use_tls: true
EOF
fi

if [ -n "$REDIS_USERNAME" ]; then
  cat >> "$CONFIG_FILE" <<EOF
  username: ${REDIS_USERNAME}
EOF
fi

if [ -n "$REDIS_PASSWORD" ]; then
  cat >> "$CONFIG_FILE" <<EOF
  password: ${REDIS_PASSWORD}
EOF
fi

if [ -n "${LIVEKIT_EGRESS_S3_BUCKET:-}" ] && [ -n "${LIVEKIT_EGRESS_S3_ACCESS_KEY_ID:-}" ] && [ -n "${LIVEKIT_EGRESS_S3_SECRET_ACCESS_KEY:-}" ]; then
  cat >> "$CONFIG_FILE" <<EOF

s3:
  access_key: ${LIVEKIT_EGRESS_S3_ACCESS_KEY_ID}
  secret: ${LIVEKIT_EGRESS_S3_SECRET_ACCESS_KEY}
  region: ${LIVEKIT_EGRESS_S3_REGION:-us-east-1}
  bucket: ${LIVEKIT_EGRESS_S3_BUCKET}
EOF
  if [ -n "${LIVEKIT_EGRESS_S3_ENDPOINT:-}" ]; then
    cat >> "$CONFIG_FILE" <<EOF
  endpoint: ${LIVEKIT_EGRESS_S3_ENDPOINT}
EOF
  fi
fi

echo ""
echo "=== LiveKit egress runtime summary ==="
echo "ws_url: ${WS_URL}"
echo "health_port: ${HEALTH_PORT}"
echo "log_level: ${LOG_LEVEL}"
echo "redis: enabled"
echo "redis_tls: ${REDIS_USE_TLS}"
echo "s3 defaults: $([ -n "${LIVEKIT_EGRESS_S3_BUCKET:-}" ] && echo enabled || echo per-request-only)"
echo "chrome_sandbox: ${ENABLE_CHROME_SANDBOX}"
echo "======================================"
echo ""

exec egress --config "$CONFIG_FILE"
