FROM busybox:1.37-musl AS busybox
FROM grafana/loki:latest
COPY --from=busybox /bin/busybox /usr/bin/busybox
