FROM --platform=$BUILDPLATFORM golang:1.27.1-alpine@sha256:8a5910f31396cd4d89662f56c68b3ae31d374308270a1c3bd96672ee5ed43414 AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -buildvcs=false -ldflags="-s -w" -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3
ARG GIT_COMMIT=unknown
ARG BUILD_VERSION=local
ARG SOURCE_URL=https://github.com/unknown/kube-deploy
LABEL org.opencontainers.image.source=$SOURCE_URL \
      org.opencontainers.image.revision=$GIT_COMMIT \
      org.opencontainers.image.version=$BUILD_VERSION
ENV PORT=8080 BUILD_VERSION=$BUILD_VERSION BUILD_COMMIT=$GIT_COMMIT
COPY --from=builder --chown=65532:65532 /out/server /server
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/server"]
