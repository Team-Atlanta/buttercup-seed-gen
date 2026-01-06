# Runner Dockerfile for Buttercup Bug-Finding CRS
# Based on seed-gen Dockerfile with full LLM seed generation support

ARG BASE_IMAGE=gcr.io/oss-fuzz-base/base-runner

# ============================================================
# Stage 1: Python base with uv
# ============================================================
FROM $BASE_IMAGE AS base-image

COPY --from=ghcr.io/astral-sh/uv:0.5.20 /uv /uvx /bin/

ENV UV_LINK_MODE=copy
ENV UV_COMPILE_BYTECODE=0
ENV UV_PYTHON_DOWNLOADS=manual

RUN uv python install python3.12

# Install system dependencies
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        curl \
        git \
        redis-server \
        codequery \
        sqlite3 \
        ripgrep \
        rsync \
        autoconf \
        gcc \
        make \
        bison \
        flex \
        libncurses-dev \
    && rm -rf /var/lib/apt/lists/*

# Download Python WASM for sandbox execution
RUN curl -fsSLO https://github.com/vmware-labs/webassembly-language-runtimes/releases/download/python%2F3.12.0%2B20231211-040d5a6/python-3.12.0.wasm

# ============================================================
# Stage 2: Build cscope from buttercup fork
# ============================================================
FROM base-image AS cscope-builder

COPY external/buttercup-cscope /cscope
RUN cd /cscope && autoreconf -i -s && ./configure && make && make install

# ============================================================
# Stage 3: Build Python dependencies
# ============================================================
FROM base-image AS builder

WORKDIR /app

# Copy all dependency files
COPY common/uv.lock common/uv.lock
COPY common/pyproject.toml common/pyproject.toml
COPY common/README.md common/README.md

COPY program-model/uv.lock program-model/uv.lock
COPY program-model/pyproject.toml program-model/pyproject.toml
COPY program-model/README.md program-model/README.md

COPY seed-gen/uv.lock seed-gen/uv.lock
COPY seed-gen/pyproject.toml seed-gen/pyproject.toml
COPY seed-gen/README.md seed-gen/README.md

COPY fuzzer_runner/uv.lock fuzzer_runner/uv.lock
COPY fuzzer_runner/pyproject.toml fuzzer_runner/pyproject.toml

# Install dependencies
RUN --mount=type=cache,target=/root/.cache/uv \
    cd seed-gen && uv sync --frozen --no-install-project --no-editable

# Copy source code
COPY common /app/common
COPY program-model /app/program-model
COPY seed-gen /app/seed-gen
COPY fuzzer_runner /app/fuzzer_runner

# Install projects
RUN --mount=type=cache,target=/root/.cache/uv \
    cd seed-gen && uv sync --frozen --no-editable

# ============================================================
# Stage 4: Runtime
# ============================================================
FROM base-image AS runtime

WORKDIR /app

# Copy cscope
COPY --from=cscope-builder /usr/local/bin/cscope /usr/local/bin/cscope

# Copy Python WASM
COPY --from=base-image /python-3.12.0.wasm /python-3.12.0.wasm

# Copy built virtual environment
COPY --from=builder /app/seed-gen/.venv /app/seed-gen/.venv

# Copy wrapper scripts
COPY oss-crs/scripts/ /app/scripts/

# Make scripts executable
RUN chmod +x /app/scripts/*.sh /app/scripts/*.py

# Environment variables
ENV PATH=/app/seed-gen/.venv/bin:$PATH
ENV PYTHON_WASM_BUILD_PATH="/python-3.12.0.wasm"
ENV NODE_DATA_DIR=/tmp/buttercup
ENV BUTTERCUP_SEED_GEN_WDIR=/tmp/seedgen
ENV BUTTERCUP_SEED_GEN_LOG_LEVEL=INFO

ENTRYPOINT ["/app/scripts/entrypoint.sh"]
