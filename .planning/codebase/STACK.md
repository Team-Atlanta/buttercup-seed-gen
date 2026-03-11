# Technology Stack

**Analysis Date:** 2026-03-10

## Languages

**Primary:**
- Python 3.12 - Core implementation language across all components
- Python 3.11+ - Supported for common and fuzzer_runner components

**Secondary:**
- C/C++/Java - Analyzed by program model but not written in primary codebase
- Protobuf - Message serialization format for inter-service communication

## Runtime

**Environment:**
- Python 3.12.x (required for most components)
- Docker containers (all components containerized)
- Kubernetes microservices orchestration
- DinD (Docker-in-Docker) for isolated build execution

**Package Manager:**
- `uv` - Fast Python package manager (modern replacement for pip)
- Lockfiles: `uv.lock` present in each component
- Virtual environments: `.venv` per component

## Frameworks

**Core Application:**
- FastAPI ~0.115.6 - REST API framework in orchestrator
- Uvicorn ~0.34.0 - ASGI web server for FastAPI

**LLM & AI:**
- LangChain ~0.3.27 - LLM orchestration framework
- LangChain-OpenAI ~0.3.30 - OpenAI integration
- LangChain-Community ~0.3.27 - Additional integrations
- LanggGraph ~0.6.6 - Agentic workflow framework (patcher, seed-gen)
- LiteLLM - Unified LLM API proxy for multi-model routing

**Code Analysis:**
- Tree-Sitter ~0.24.0 - AST parsing for C/C++/Java
- Tree-Sitter-Language-Pack ~0.9.0 - Language support
- RapidFuzz ~3.12.2 - String fuzzy matching for code search

**Fuzzing & Analysis:**
- ClusterFuzz 2.6.0 - Google's fuzzing infrastructure (fuzzer_runner)
- BeautifulSoup4 ~4.13.3 - HTML/XML parsing (fuzzer)
- lxml ~5.3.1 - Fast XML processing
- cxxfilt>=0.3.0 - C++ symbol demangling

**Data & Serialization:**
- Pydantic ~2.11.0 - Data validation and settings
- Pydantic-Settings ~2.7.1 - Environment-based configuration
- ProtoBuf >=5.0 - Message serialization
- PyYAML ~6.0.1 - YAML configuration parsing
- Unidiff ~0.7.5 - Unified diff parsing (patcher)

**Testing:**
- pytest ~8.3.4 - Test framework across all components
- pytest-asyncio ~0.25.2 - Async test support
- pytest-cov ~6.0.0 - Coverage reporting
- pytest-xdist ~3.6.1 - Parallel test execution
- dirty-equals ~0.9.0 - Flexible test assertions
- responses ~=0.25.6 - HTTP mocking for tests

**Linting & Type Checking:**
- ruff ~0.14.0 - Fast linter and formatter
- ty - Astral type checker (replaces mypy)
- mypy-compatible type stubs for external libraries

**Utility Libraries:**
- requests ~=2.32.3 - HTTP client (orchestrator)
- requests-file ~=2.1.0 - File:// URL support
- urllib3 ~=2.6.0 - HTTP connection pooling
- python-dateutil ~=2.9.0 - Date/time utilities
- typing-extensions ~=4.12.2 - Backported typing features
- argon2-cffi ~=21.3.0 - Password hashing (auth)
- rich ~=13.9.4 - Terminal UI and formatting
- six ~=1.17.0 - Python 2/3 compatibility layer
- NumPy ~=2.2.3 - Numerical operations (seed-gen)

**Database & Caching:**
- Redis ~=5.2.1 - Message queue and cache
- Redis consumer groups - Reliable message processing
- SQLAlchemy ~=2.0.0 - ORM for UI database
- PyMongo ~=4.10.1 - MongoDB client (common)

**Observability & Monitoring:**
- Langfuse ~=2.59.2 - LLM tracing and observability
- OpenLit >=1.36.0,<1.36.6 - Instrumentation framework
- OpenTelemetry - Distributed tracing support

**WASM Runtime:**
- Wasmtime ~=29.0.0 - WebAssembly runtime (seed-gen sandbox execution)

## Build & Deployment

**Build System:**
- Hatchling - Python package build backend
- Docker - Container images for all components
- BuildKit - Docker build acceleration

**Container Base Images:**
- `python:3.12-slim-bookworm` - Minimal Python runtime
- `gcr.io/oss-fuzz-base/base-runner` - OSS-Fuzz base image (fuzzer)

**Orchestration:**
- Kubernetes - Container orchestration
- Helm - K8s package manager (`/deployment/k8s/charts/`)
- Minikube - Local K8s development
- Azure AKS - Production deployment target

**Container Registry:**
- GHCR (GitHub Container Registry) - Image storage
- Docker Hub - Public image pulls (with auth support)

## Configuration

**Environment Variables (from `/deployment/env.template`):**
- `REDIS_URL` - Redis connection string
- `LITELLM_MASTER_KEY` - LiteLLM authentication
- `OPENAI_API_KEY` - OpenAI API credentials
- `ANTHROPIC_API_KEY` - Anthropic API credentials
- `GEMINI_API_KEY` - Google Gemini API credentials
- `AZURE_API_BASE`, `AZURE_API_KEY` - Azure OpenAI deployment
- `LANGFUSE_HOST`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY` - LLM observability
- `OTEL_ENDPOINT`, `OTEL_TOKEN` - OpenTelemetry configuration
- `COMPETITION_API_URL`, `COMPETITION_API_KEY_ID`, `COMPETITION_API_KEY_TOKEN` - External competition API
- `CRS_KEY_ID`, `CRS_KEY_TOKEN` - Internal CRS authentication

**Build Configuration:**
- `ruff.toml` in each component - Linting rules (120 char line length)
- `pyproject.toml` - Package metadata and tool config
- `.prettierrc` - Code formatting (if used)

**Deployment Configuration:**
- `/deployment/k8s/values.yaml` - Helm global values
- `/litellm/litellm_config.yaml` - LiteLLM model and rate limit config
- Kubernetes secrets for API keys and credentials
- Docker registry auth secrets (ghcr-auth, docker-auth)

## Platform Requirements

**Development:**
- Python 3.12
- Docker & Docker Desktop (with minimum 8GB RAM for Minikube)
- kubectl for K8s interaction
- git & git-lfs for large file support
- uv package manager

**Production:**
- Kubernetes 1.24+ cluster
- Persistent storage support (ReadWriteMany volumes)
- External Redis instance
- LLM API access (OpenAI, Anthropic, Azure, or Gemini)
- Container registry (GHCR or Docker Hub)

## Database & Storage

**Primary Message Broker:**
- Redis 7.x - Consumer groups for reliable task delivery
- Persistence: AOF (append-only file) enabled in `/deployment/k8s/values.yaml`

**Optional Databases:**
- MongoDB 4.x+ - Document storage (via pymongo)
- SQLite - LLM cache (LangChain SQLiteCache in patcher)
- PostgreSQL 17.x - LiteLLM database (optional, for advanced features)

**Storage Volumes:**
- `/node_data_storage` - Node-local corpus and artifacts
- Kubernetes PVCs for shared storage (tasks_storage, crs_scratch)

---

*Stack analysis: 2026-03-10*
