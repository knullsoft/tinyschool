FROM oven/bun:1.3.13 AS ui

ARG APP_VERSION=dev
ENV NUXT_PUBLIC_APP_VERSION=$APP_VERSION
ENV NUXT_PUBLIC_API_BASE=/api/v1

WORKDIR /ui
COPY tinyschool-ui/package.json tinyschool-ui/bun.lock ./
RUN bun install --no-save
COPY tinyschool-ui/ ./
RUN bun run generate

FROM golang:1.26-bookworm AS build

WORKDIR /src
COPY tinyschool-api/go.mod tinyschool-api/go.sum ./
RUN go mod download
COPY tinyschool-api/ ./
RUN rm -rf internal/staticui/dist
COPY --from=ui /ui/.output/public/ ./internal/staticui/dist/
RUN CGO_ENABLED=1 go build -trimpath -ldflags="-s -w" -o /out/tinyschool-api .

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir /data \
    && chown 65532:65532 /data
COPY --from=build /out/tinyschool-api /usr/local/bin/tinyschool-api

USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["tinyschool-api"]
