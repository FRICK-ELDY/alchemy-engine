# Pin Elixir/Alpine versions so the release runtime matches the build image's libc/OpenSSL.
ARG ELIXIR_IMAGE=elixir:1.19-otp-28-alpine
ARG ALPINE_VERSION=3.23

# Development image for alchemy-auth (hot reload via bind mount).
FROM ${ELIXIR_IMAGE} AS dev

RUN apk add --no-cache build-base git

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

# Warm dependency cache when building the image (source is bind-mounted at runtime).
COPY mix.exs mix.lock ./
RUN mix deps.get

COPY config config
COPY lib lib
COPY priv priv
COPY test test
COPY .formatter.exs ./
COPY AGENTS.md ./

RUN mix compile

EXPOSE 4002

CMD ["mix", "phx.server"]

# Production release build.
FROM ${ELIXIR_IMAGE} AS build

RUN apk add --no-cache build-base git

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config config
COPY lib lib
COPY priv priv
COPY .formatter.exs ./

RUN mix compile
RUN mix release

# Production runtime (mix release).
FROM alpine:${ALPINE_VERSION} AS release

RUN apk add --no-cache libstdc++ openssl ncurses-libs ca-certificates

WORKDIR /app

RUN adduser -D -h /app auth && chown auth:auth /app

COPY --from=build --chown=auth:auth /app/_build/prod/rel/auth ./

USER auth

ENV PHX_SERVER=true
ENV PORT=4002

EXPOSE 4002

CMD ["bin/auth", "start"]
