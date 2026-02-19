ARG BASE_IMAGE=gcr.io/oss-fuzz-base/base-runner

# hadolint ignore=DL3006
FROM $BASE_IMAGE AS base-image

COPY --from=ghcr.io/astral-sh/uv:0.5.20 /uv /uvx /bin/

ENV UV_LINK_MODE=copy
ENV UV_COMPILE_BYTECODE=1
ENV UV_PYTHON_DOWNLOADS=manual

RUN uv python install python3.12

FROM base-image AS runner-base

# Install Docker CLI for container operations
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl \
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
       docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
       ripgrep codequery git rsync libncurses6 \
    && rm -rf /var/lib/apt/lists/*

# Download Python WASM for seed-gen
RUN curl -fsSLO https://github.com/vmware-labs/webassembly-language-runtimes/releases/download/python%2F3.12.0%2B20231211-040d5a6/python-3.12.0.wasm

FROM base-image AS builder

WORKDIR /app

# Install dependencies for all packages
# hadolint ignore=DL3003
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=common/uv.lock,target=common/uv.lock \
    --mount=type=bind,source=common/pyproject.toml,target=common/pyproject.toml \
    --mount=type=bind,source=common/README.md,target=common/README.md \
    --mount=type=bind,source=fuzzer/uv.lock,target=fuzzer/uv.lock \
    --mount=type=bind,source=fuzzer/pyproject.toml,target=fuzzer/pyproject.toml \
    --mount=type=bind,source=fuzzer_runner/uv.lock,target=fuzzer_runner/uv.lock \
    --mount=type=bind,source=fuzzer_runner/pyproject.toml,target=fuzzer_runner/pyproject.toml \
    --mount=type=bind,source=program-model/uv.lock,target=program-model/uv.lock \
    --mount=type=bind,source=program-model/pyproject.toml,target=program-model/pyproject.toml \
    --mount=type=bind,source=program-model/README.md,target=program-model/README.md \
    --mount=type=bind,source=seed-gen/uv.lock,target=seed-gen/uv.lock \
    --mount=type=bind,source=seed-gen/pyproject.toml,target=seed-gen/pyproject.toml \
    cd fuzzer && uv sync --frozen --no-install-project --no-editable && cd .. \
    && cd fuzzer_runner && uv sync --frozen --no-install-project --no-editable && cd .. \
    && cd seed-gen && uv sync --frozen --no-install-project --no-editable

COPY common /app/common
COPY fuzzer /app/fuzzer
COPY fuzzer_runner /app/fuzzer_runner
COPY program-model /app/program-model
COPY seed-gen /app/seed-gen

# Build all packages
# hadolint ignore=DL3003
RUN --mount=type=cache,target=/root/.cache/uv \
    cd fuzzer && uv sync --frozen --no-editable
# hadolint ignore=DL3003
RUN --mount=type=cache,target=/root/.cache/uv \
    cd fuzzer_runner && uv sync --frozen --no-editable
# hadolint ignore=DL3003
RUN --mount=type=cache,target=/root/.cache/uv \
    cd seed-gen && uv sync --frozen --no-editable

FROM runner-base AS cscope-builder
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       autoconf automake gcc make bison flex libncurses-dev \
    && rm -rf /var/lib/apt/lists/*
COPY external/buttercup-cscope /cscope
# hadolint ignore=DL3003
RUN cd /cscope && autoreconf -i -s && ./configure && make && make install

FROM runner-base AS runtime

# Copy cscope for code analysis
COPY --from=cscope-builder /usr/local/bin/cscope /usr/local/bin/cscope

# Copy all venvs from builder
COPY --from=builder --chown=app:app /app/fuzzer/.venv /app/fuzzer/.venv
COPY --from=builder --chown=app:app /app/fuzzer_runner/.venv /app/fuzzer_runner/.venv
COPY --from=builder --chown=app:app /app/seed-gen/.venv /app/seed-gen/.venv

# Copy scripts
COPY common/container-entrypoint.sh /container-entrypoint.sh
COPY fuzzer_runner/runner.sh /app/fuzzer_runner/runner.sh

# Copy OSS-CRS orchestrator (populates Redis from disk artifacts)
COPY oss-crs/orchestrator.py /crs/orchestrator.py

# Copy existing OSS-CRS interface (for backwards compatibility)
COPY oss-crs/run_fuzzer.py /crs/run_fuzzer.py
COPY oss-crs/src/ /crs/src/

# Environment setup
ENV PATH=/app/fuzzer/.venv/bin:/app/seed-gen/.venv/bin:$PATH
ENV PYTHON_WASM_BUILD_PATH="/python-3.12.0.wasm"
ENV NODE_DATA_DIR="/tmp/node_data"

WORKDIR /crs

ENTRYPOINT ["/container-entrypoint.sh"]
