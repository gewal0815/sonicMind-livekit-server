# SonicMind LiveKit Egress Worker

Self-hosted LiveKit does not include recording workers inside `livekit-server`.
Deploy this repo as a second Railway service using `Dockerfile.egress`.

Required Railway variables:

```text
LIVEKIT_URL=wss://sonicmind-livekit-server-production.up.railway.app
LIVEKIT_API_KEY=<same key as livekit-server>
LIVEKIT_API_SECRET=<same secret as livekit-server>
REDIS_URL=<same Redis URL as livekit-server>
```

Optional variables:

```text
LIVEKIT_EGRESS_LOG_LEVEL=info
LIVEKIT_EGRESS_HEALTH_PORT=8080
LIVEKIT_EGRESS_ENABLE_CHROME_SANDBOX=false
```

Storage credentials can be passed per egress request by the app. If defaults are
wanted on the worker too, set:

```text
LIVEKIT_EGRESS_S3_BUCKET=report-media
LIVEKIT_EGRESS_S3_ENDPOINT=https://fohqhbjtyjgfgjydfyvp.storage.supabase.co/storage/v1/s3
LIVEKIT_EGRESS_S3_REGION=ap-northeast-1
LIVEKIT_EGRESS_S3_ACCESS_KEY_ID=<supabase storage s3 key>
LIVEKIT_EGRESS_S3_SECRET_ACCESS_KEY=<supabase storage s3 secret>
```

Railway setup:

1. Create a new service from this repository.
2. Set the Dockerfile path to `Dockerfile.egress`.
3. Attach or reference the same Redis service used by the LiveKit server.
4. Use at least 4 CPU / 4 GB RAM for reliable room-composite egress.

