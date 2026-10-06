FROM --platform=$BUILDPLATFORM node:22.17.0-alpine@sha256:fc3e945f920b7e3000cd1af86c4ae406ec70c72f328b667baf0f3a8910d69eed AS builder
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

FROM caddy:2.11.6-alpine@sha256:d44355d3c2149dc580ce2cac735955d1c08d3d00882c30489c241aa51a5c10d9
ARG GIT_COMMIT=unknown
ARG BUILD_VERSION=local
ARG SOURCE_URL=https://github.com/unknown/kube-deploy
LABEL org.opencontainers.image.source=$SOURCE_URL \
      org.opencontainers.image.revision=$GIT_COMMIT \
      org.opencontainers.image.version=$BUILD_VERSION
ENV XDG_CONFIG_HOME=/tmp/caddy-config XDG_DATA_HOME=/tmp/caddy-data
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /src/build/client /srv
# The upstream image grants cap_net_bind_service to Caddy for ports 80/443.
# This application listens on 8080, and Kubernetes correctly refuses to exec a
# file with capabilities when allowPrivilegeEscalation=false/no_new_privs is set.
RUN setcap -r /usr/bin/caddy
USER 10001:10001
EXPOSE 8080
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
