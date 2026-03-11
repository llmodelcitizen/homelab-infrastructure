FROM alpine:latest AS extract
ADD https://github.com/quaintops/Prowlarr/releases/download/v2.3.0.5236-flaresolverr-fix/Prowlarr.develop.2.3.0.5236.linux-musl-x64.tar.gz /tmp/prowlarr.tar.gz
RUN mkdir /build && tar xzf /tmp/prowlarr.tar.gz -C /build/ && rm /tmp/prowlarr.tar.gz

FROM lscr.io/linuxserver/prowlarr:latest
COPY --from=extract /build/Prowlarr.Common.dll /build/Prowlarr.Core.dll \
    /build/Prowlarr.dll /build/Prowlarr.Host.dll /build/Prowlarr.Http.dll \
    /build/Prowlarr.Mono.dll /build/Prowlarr.Api.V1.dll \
    /build/Prowlarr.SignalR.dll /build/Prowlarr.Windows.dll \
    /build/Prowlarr /app/prowlarr/bin/
RUN ln -s /app/prowlarr/bin/UI /app/prowlarr/UI
