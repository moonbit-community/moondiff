# syntax=docker/dockerfile:1

FROM node:22-bookworm-slim AS build

ARG MOONBIT_VERSION=latest
ENV MOON_HOME=/opt/moon
ENV PATH="${MOON_HOME}/bin:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://cli.moonbitlang.com/install/unix.sh -o /tmp/moon-install.sh \
    && bash /tmp/moon-install.sh "${MOONBIT_VERSION}" \
    && rm /tmp/moon-install.sh

# The frontend imports the root MoonBit module through moon.work.
WORKDIR /src
COPY . .
# The release builder uses only Node.js built-ins, so npm dependencies are unnecessary.
RUN moon update && npm run build

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 moondiff \
    && useradd --uid 10001 --gid moondiff --no-create-home \
        --home-dir /var/lib/moondiff --shell /usr/sbin/nologin moondiff \
    && install -d -m 0700 -o moondiff -g moondiff /var/lib/moondiff

COPY --from=build /opt/moon/bin/moonrun /usr/local/bin/moonrun
WORKDIR /app
COPY --from=build /src/playground/dist/moondiff-server.wasm ./moondiff-server.wasm
COPY --from=build /src/playground/dist/static/ ./static/

ENV MOONDIFF_LISTEN=0.0.0.0:4173 \
    MOONDIFF_STATIC_DIR=/app/static \
    MOONDIFF_DATABASE=/var/lib/moondiff/moondiff.sqlite3

USER 10001:10001
EXPOSE 4173
VOLUME ["/var/lib/moondiff"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["sh", "-c", \
        "curl --noproxy '*' --fail --silent --show-error --max-time 3 \"http://localhost:${MOONDIFF_LISTEN##*:}/healthz\" || exit 1"]

ENTRYPOINT ["moonrun"]
CMD ["/app/moondiff-server.wasm"]
