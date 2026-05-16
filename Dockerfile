FROM livekit/livekit-server:latest AS livekit

FROM alpine:3.19
RUN apk add --no-cache bash haproxy iptables ca-certificates bind-tools

COPY --from=livekit /livekit-server /livekit-server
RUN chmod +x /livekit-server

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
