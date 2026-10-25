FROM ghcr.io/cirruslabs/flutter:3.38.1 AS build
WORKDIR /workspace
COPY . .
RUN flutter pub get && dart compile exe apps/api/bin/server.dart -o /server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libsqlite3-0 python3 && rm -rf /var/lib/apt/lists/* && useradd --system --uid 10001 app && mkdir -p /data /backups && chown app:app /data /backups
COPY --from=build /server /app/server
COPY --from=build /workspace/apps/mobile/assets/fonts /app/fonts
COPY --from=build /workspace/apps/mobile/assets/images /app/demo-images
COPY tool/backup.py /app/backup.py
USER app
WORKDIR /app
ENV HOST=0.0.0.0 PORT=8080 DATABASE_PATH=/data/marketplace.sqlite BILLING_FONT_PATH=/app/fonts/InterVariable.ttf
HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD ["/app/server", "--healthcheck"]
EXPOSE 8080
VOLUME ["/data"]
ENTRYPOINT ["/app/server"]
