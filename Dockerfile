FROM livekit/livekit-server:latest

COPY livekit.yaml /etc/livekit/livekit.yaml

EXPOSE 7880 7881 3478/udp 5349

ENTRYPOINT ["/livekit-server"]
CMD ["--config", "/etc/livekit/livekit.yaml"]
