# syntax=docker/dockerfile:1.7

ARG GO_VERSION=1.26.4
ARG DOCKER_CLI_VERSION=28.3.3-cli

FROM docker:${DOCKER_CLI_VERSION} AS docker-cli

FROM golang:${GO_VERSION}-bookworm

ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        bc \
        build-essential \
        ca-certificates \
        curl \
        file \
        findutils \
        gcc-x86-64-linux-gnu \
        gawk \
        git \
        gosu \
        jq \
        libc6-dev-amd64-cross \
        make \
        netcat-openbsd \
        perl \
        pkg-config \
        procps \
        ripgrep \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/ /usr/local/libexec/docker/cli-plugins/

RUN mkdir -p /cache/gomod /cache/go-build /cache/devtools/home /cache/devtools/xdg /cache/devtools/tmp

RUN ln -sf /usr/local/go/bin/go /usr/local/bin/go \
    && ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

ENV GOMODCACHE=/cache/gomod
ENV GOCACHE=/cache/go-build
ENV GOPATH=/cache/devtools/go
ENV GOBIN=/cache/devtools/bin
ENV XDG_CACHE_HOME=/cache/devtools/xdg
ENV GOTMPDIR=/cache/devtools/tmp
ENV TMPDIR=/cache/devtools/tmp
ENV HOME=/cache/devtools/home
ENV PATH=/usr/local/go/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

RUN cat <<'EOF' >/usr/local/bin/kudora-devtools-entrypoint
#!/usr/bin/env bash

set -euo pipefail

host_uid="${LOCAL_UID:-1000}"
host_gid="${LOCAL_GID:-1000}"
home_dir="${KUDORA_DEVTOOLS_HOME:-/cache/devtools/home}"
docker_config_dir="${DOCKER_CONFIG:-${home_dir}/.docker}"
docker_sock_gid="${DOCKER_SOCKET_GID:-}"

mkdir -p \
  "${home_dir}" \
  "${docker_config_dir}" \
  "${GOPATH:-/cache/devtools/go}" \
  "${GOBIN:-/cache/devtools/bin}" \
  "${GOMODCACHE:-/cache/gomod}" \
  "${GOCACHE:-/cache/go-build}" \
  "${XDG_CACHE_HOME:-/cache/devtools/xdg}" \
  "${GOTMPDIR:-/cache/devtools/tmp}" \
  "${TMPDIR:-/cache/devtools/tmp}"

if [[ "$(id -u)" == "0" ]]; then
  if [[ "${host_uid}" == "0" ]]; then
    exec env \
      PATH="${PATH:-/usr/local/go/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin}" \
      HOME="${home_dir}" \
      DOCKER_CONFIG="${docker_config_dir}" \
      GOPATH="${GOPATH:-/cache/devtools/go}" \
      GOBIN="${GOBIN:-/cache/devtools/bin}" \
      GOMODCACHE="${GOMODCACHE:-/cache/gomod}" \
      GOCACHE="${GOCACHE:-/cache/go-build}" \
      XDG_CACHE_HOME="${XDG_CACHE_HOME:-/cache/devtools/xdg}" \
      GOTMPDIR="${GOTMPDIR:-/cache/devtools/tmp}" \
      TMPDIR="${TMPDIR:-/cache/devtools/tmp}" \
      "$@"
  fi

  if ! getent group "${host_gid}" >/dev/null 2>&1; then
    groupadd --gid "${host_gid}" kudora-host >/dev/null 2>&1
  fi

  if getent passwd "${host_uid}" >/dev/null 2>&1; then
    username="$(getent passwd "${host_uid}" | cut -d: -f1)"
  else
    username="kudora"
    if getent passwd "${username}" >/dev/null 2>&1; then
      username="kudora-host"
    fi
    useradd \
      --uid "${host_uid}" \
      --gid "${host_gid}" \
      --home-dir "${home_dir}" \
      --create-home \
      --shell /bin/bash \
      "${username}" >/dev/null 2>&1
  fi

  if [[ -n "${docker_sock_gid}" && "${docker_sock_gid}" != "${host_gid}" ]]; then
    if ! getent group "${docker_sock_gid}" >/dev/null 2>&1; then
      groupadd --gid "${docker_sock_gid}" kudora-docker >/dev/null 2>&1
    fi

    docker_group="$(getent group "${docker_sock_gid}" | cut -d: -f1)"
    usermod -a -G "${docker_group}" "${username}" >/dev/null 2>&1 || true
  fi

  chown -R "${host_uid}:${host_gid}" \
    "${home_dir}" \
    "${docker_config_dir}" \
    "${GOPATH:-/cache/devtools/go}" \
    "${GOBIN:-/cache/devtools/bin}" \
    "${GOMODCACHE:-/cache/gomod}" \
    "${GOCACHE:-/cache/go-build}" \
    "${XDG_CACHE_HOME:-/cache/devtools/xdg}" \
    "${GOTMPDIR:-/cache/devtools/tmp}" \
    "${TMPDIR:-/cache/devtools/tmp}"

  exec gosu "${username}" env \
    PATH="${PATH:-/usr/local/go/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin}" \
    HOME="${home_dir}" \
    USER="${username}" \
    LOGNAME="${username}" \
    DOCKER_CONFIG="${docker_config_dir}" \
    GOPATH="${GOPATH:-/cache/devtools/go}" \
    GOBIN="${GOBIN:-/cache/devtools/bin}" \
    GOMODCACHE="${GOMODCACHE:-/cache/gomod}" \
    GOCACHE="${GOCACHE:-/cache/go-build}" \
    XDG_CACHE_HOME="${XDG_CACHE_HOME:-/cache/devtools/xdg}" \
    GOTMPDIR="${GOTMPDIR:-/cache/devtools/tmp}" \
    TMPDIR="${TMPDIR:-/cache/devtools/tmp}" \
    "$@"
fi

exec "$@"
EOF

RUN chmod 0755 /usr/local/bin/kudora-devtools-entrypoint

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/kudora-devtools-entrypoint"]
CMD ["bash"]
