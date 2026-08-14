# syntax=docker/dockerfile:1.7

ARG RELEASE_IMAGE=kudora/kudorad:latest-rc

FROM ${RELEASE_IMAGE}

ARG COSMOVISOR_VERSION
ARG RELEASE_VERSION=candidate
ARG GIT_COMMIT=unknown

LABEL org.opencontainers.image.title="kudorad-cosmovisor" \
      org.opencontainers.image.description="Kudora candidate cosmovisor runtime" \
      org.opencontainers.image.version="${RELEASE_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      io.kudora.release_track="candidate" \
      io.kudora.mainnet_launch_ready="false" \
      io.kudora.cosmovisor_version="${COSMOVISOR_VERSION}"

COPY --from=prebuilt /usr/local/bin/cosmovisor /usr/local/bin/cosmovisor

ENV DAEMON_NAME=kudorad \
    DAEMON_HOME=/home/nonroot/.kudora \
    DAEMON_RESTART_AFTER_UPGRADE=true \
    DAEMON_ALLOW_DOWNLOAD_BINARIES=false \
    UNSAFE_SKIP_BACKUP=false

WORKDIR /home/nonroot

EXPOSE 26656 26657 1317 9090 8545 8546

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/cosmovisor","run","start"]
