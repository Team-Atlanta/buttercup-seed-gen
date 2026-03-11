# Buttercup Runner - Combined image for all buttercup services
# Services are selected via RUN_TYPE environment variable

ARG BASE_IMAGE=gcr.io/oss-fuzz-base/base-runner

# hadolint ignore=DL3006
FROM $BASE_IMAGE AS base-image

COPY --from=ghcr.io/astral-sh/uv:0.5.20 /uv /uvx /bin/

ENV UV_LINK_MODE=copy
ENV UV_COMPILE_BYTECODE=0
ENV UV_PYTHON_DOWNLOADS=manual

RUN uv python install python3.12

# Install Docker
FROM base-image AS runner-base
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       ca-certificates curl git rsync inotify-tools ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=SC1091
RUN echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Build stage for seed-gen components
FROM base-image AS seedgen-builder

WORKDIR /app

# hadolint ignore=DL3003
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=common/uv.lock,target=common/uv.lock \
    --mount=type=bind,source=common/pyproject.toml,target=common/pyproject.toml \
    --mount=type=bind,source=common/README.md,target=common/README.md \
    --mount=type=bind,source=program-model/uv.lock,target=program-model/uv.lock \
    --mount=type=bind,source=program-model/pyproject.toml,target=program-model/pyproject.toml \
    --mount=type=bind,source=program-model/README.md,target=program-model/README.md \
    --mount=type=bind,source=seed-gen/uv.lock,target=seed-gen/uv.lock \
    --mount=type=bind,source=seed-gen/pyproject.toml,target=seed-gen/pyproject.toml \
    cd seed-gen && uv sync --frozen --no-install-project --no-editable

COPY common /app/common
COPY program-model /app/program-model
COPY seed-gen /app/seed-gen

# hadolint ignore=DL3003
RUN --mount=type=cache,target=/root/.cache/uv \
    cd seed-gen && uv sync --frozen --no-editable

# Build stage for fuzzer components (coverage-bot)
FROM base-image AS fuzzer-builder

WORKDIR /app

# hadolint ignore=DL3003
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=common/uv.lock,target=common/uv.lock \
    --mount=type=bind,source=common/pyproject.toml,target=common/pyproject.toml \
    --mount=type=bind,source=common/README.md,target=common/README.md \
    --mount=type=bind,source=fuzzer/uv.lock,target=fuzzer/uv.lock \
    --mount=type=bind,source=fuzzer/pyproject.toml,target=fuzzer/pyproject.toml \
    cd fuzzer && uv sync --frozen --no-install-project --no-editable

COPY common /app/common
COPY fuzzer /app/fuzzer

# hadolint ignore=DL3003
RUN --mount=type=cache,target=/root/.cache/uv \
    cd fuzzer && uv sync --frozen --no-editable

# Build cscope for seed-gen
FROM runner-base AS cscope-builder
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       autoconf automake gcc make bison flex libncurses-dev \
    && rm -rf /var/lib/apt/lists/*
COPY external/buttercup-cscope /cscope
# hadolint ignore=DL3003
RUN cd /cscope && autoreconf -i -s && ./configure && make && make install

# Base target for docker-bake.hcl prepare phase
FROM runner-base AS base

# Final runtime stage
FROM runner-base AS runtime

# Install libCRS
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Install codequery toolchain for seed-gen
# cscope is custom-built, others from apt
COPY --from=cscope-builder /usr/local/bin/cscope /usr/local/bin/cscope
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       exuberant-ctags codequery \
    && rm -rf /var/lib/apt/lists/*

# Copy built Python environments
COPY --from=seedgen-builder /app/seed-gen/.venv /app/seed-gen/.venv
COPY --from=fuzzer-builder /app/fuzzer/.venv /app/fuzzer/.venv

# Download Python WASM build for seed-gen sandbox
RUN curl -fsSL -o /opt/python-3.12.0.wasm \
    "https://github.com/vmware-labs/webassembly-language-runtimes/releases/download/python%2F3.12.0%2B20231211-040d5a6/python-3.12.0.wasm"
ENV PYTHON_WASM_BUILD_PATH=/opt/python-3.12.0.wasm

# Copy oss-crs specific files
COPY oss-crs/orchestrator.py /crs/orchestrator.py
COPY oss-crs/bin /crs/bin

# Set up PATH to include seed-gen and fuzzer venvs
ENV PATH=/app/seed-gen/.venv/bin:/app/fuzzer/.venv/bin:$PATH

# Copy entrypoint
COPY oss-crs/bin/buttercup_entrypoint /usr/local/bin/buttercup_entrypoint
RUN chmod +x /usr/local/bin/buttercup_entrypoint

ENTRYPOINT ["/usr/local/bin/buttercup_entrypoint"]
