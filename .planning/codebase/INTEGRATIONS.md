# External Integrations

**Analysis Date:** 2026-03-10

## APIs & External Services

**LLM Services (via LiteLLM proxy):**
- OpenAI GPT models - gpt-4o, gpt-4o-mini, o3-mini, o1, gpt-4.1 variants
  - SDK/Client: LangChain-OpenAI
  - Auth: `OPENAI_API_KEY` env var
  - LiteLLM model names: `openai-gpt-4o`, `openai-gpt-4o-mini`, `openai-o3-mini`, `openai-o1`, `openai-o3`, `openai-gpt-4.1*`
  - Rate limits: Configured in `/deployment/k8s/values.yaml` (TPM/RPM per model)

- Anthropic Claude models - claude-3-7-sonnet, claude-sonnet-4, claude-sonnet-4-5
  - SDK/Client: LangChain (via LiteLLM)
  - Auth: `ANTHROPIC_API_KEY` env var
  - LiteLLM model names: `claude-3.7-sonnet`, `claude-4-sonnet`, `claude-4.5-sonnet`
  - TPM: 125000-400000 depending on model

- Azure OpenAI - gpt-4o, gpt-4o-mini, o3-mini, o1
  - SDK/Client: LangChain-OpenAI
  - Auth: `AZURE_API_BASE`, `AZURE_API_KEY` env vars
  - LiteLLM model names: `azure-gpt-4o`, `azure-gpt-4o-mini`, `azure-o3-mini`, `azure-o1`

- Google Gemini - gemini-pro, gemini-2.5-flash, gemini-2.5-flash-exp
  - SDK/Client: LangChain (via LiteLLM)
  - Auth: `GEMINI_API_KEY` env var
  - LiteLLM model names: `gemini-pro`, `gemini-2.5-flash-exp`, `gemini-2.5-flash`

**LiteLLM Service:**
- LLM API proxy at `litellm:4000` (in-cluster service)
- Configuration: `/litellm/litellm_config.yaml`
- Master key: `LITELLM_MASTER_KEY` env var
- Budget: `LITELLM_MAX_BUDGET` env var (daily spend limit)
- All component traffic routes through this proxy for unified rate limiting

**Competition API (External):**
- AIxCC Competition API - External task distribution
  - Location: `COMPETITION_API_URL` env var
  - Client SDK: Generated code at `/orchestrator/src/buttercup/orchestrator/competition_api_client/`
  - Authentication: `COMPETITION_API_KEY_ID` + `COMPETITION_API_KEY_TOKEN`
  - Generated via: OpenAPI/fastapi-codegen from external spec
  - Endpoints: `/v1/challenges/`, `/v1/patches/`, `/v1/vulnerabilities/`, `/v1/sarif/`

## Data Storage

**Databases:**
- Redis 7.x (Primary)
  - Connection: `REDIS_URL` env var (default: `redis://localhost:6379`)
  - Client: redis-py package
  - Usage: Task queues with consumer groups for reliable delivery
  - Persistence: AOF enabled, 8GB storage default
  - Authentication: Disabled by default in K8s config

- MongoDB 4.x+ (Optional)
  - Connection: PyMongo client
  - Usage: Document storage for supplementary data
  - Not a hard requirement for core functionality

- SQLite (LLM Cache)
  - Location: `.langchain.cache` in patcher working directory
  - Purpose: LangChain prompt/response caching to reduce LLM API calls
  - Managed by: `LangChain SQLiteCache` in `/patcher/src/buttercup/patcher/patcher.py`

- PostgreSQL 17.x (LiteLLM Database - Optional)
  - Connection: `postgresql://litellm_user:password@buttercup-litellm-postgresql:5432/litellm`
  - Purpose: Advanced LiteLLM features (usage tracking, model management)
  - Managed by: Helm PostgreSQL subchart (bitnamilegacy/postgresql:17.2.0)
  - Enabled in `/deployment/k8s/values.yaml` under `litellm-helm.postgresql`

**File Storage:**
- Node-local storage: `/node_data_storage` on K8s nodes
  - Host path mount for corpus and fuzzing artifacts
  - Persistent across pod restarts on same node
  - Mounted at `/node_data` inside containers

- Kubernetes Persistent Volumes:
  - `tasks_storage` - ReadWriteMany, 5Gi default
  - `crs_scratch` - ReadWriteMany, 10Gi default
  - `ui_db` - ReadWriteOnce, 1Gi default

**Caching:**
- Redis - Primary caching layer (included in redis-py integration)
- LLM response cache - SQLite (patcher component)

## Authentication & Identity

**Internal API Authentication:**
- Bearer token scheme with `AUTHORIZATION` header
- CRS credentials:
  - `CRS_KEY_ID`: UUID identifier
  - `CRS_KEY_TOKEN`: Base64-encoded secret
  - `CRS_KEY_TOKEN_HASH`: Argon2 hash for server-side verification
- Generated via: `/orchestrator/src/buttercup/orchestrator/task_server/auth_tool.py`
- Used by: Task server for validating client requests

**Competition API Authentication:**
- Separate credentials from internal CRS auth
- `COMPETITION_API_KEY_ID` + `COMPETITION_API_KEY_TOKEN`
- Used by: Downloader and scheduler to fetch external tasks

**Container Registry Authentication:**
- GHCR (GitHub Container Registry)
  - Secret name: `ghcr-auth` in K8s
  - Base64 encoded: `echo "USERNAME:$GHCR_PAT" | base64 --wrap=0`
  - PAT permissions: `package:read` minimum
- Docker Hub
  - Secret name: `docker-auth` in K8s
  - Credentials: `DOCKER_USERNAME`, `DOCKER_PAT`

**Password Hashing:**
- Argon2id - Used for CRS token hashing
- Library: `argon2-cffi ~=21.3.0`

## Monitoring & Observability

**Error Tracking & LLM Tracing:**
- Langfuse (Optional)
  - URL: `LANGFUSE_HOST` env var (defaults to `https://cloud.langfuse.com`)
  - Auth: `LANGFUSE_PUBLIC_KEY` + `LANGFUSE_SECRET_KEY`
  - Enabled: `LANGFUSE_ENABLED=true` env var
  - Configuration: `/deployment/k8s/values.yaml` under `global.langfuse`
  - Integrated via: `langfuse ~=2.59.2` package
  - Traces: All LLM calls from patcher, seed-gen, and orchestrator

**Distributed Tracing:**
- OpenTelemetry (Optional)
  - Endpoint: `OTEL_ENDPOINT` env var (protocol: gRPC or HTTP)
  - Token: `OTEL_TOKEN` env var (basic or bearer auth)
  - Protocol: `OTEL_PROTOCOL` env var (grpc default)
  - Used for: Application metrics and traces

**Observability Platforms:**
- SigNoz (Optional)
  - Deployment: `DEPLOY_SIGNOZ=false` by default
  - Uses OpenTelemetry for ingestion
  - Clickhouse backend in K8s chart

**Logs:**
- Stdout/stderr logging with Python logging module
- Structured logging in `buttercup.common.logging`
- Log line length configurable: `global.logMaxLineLength` in Helm (default: 10240 chars)

## CI/CD & Deployment

**Container Registry:**
- GHCR (ghcr.io/trailofbits/buttercup/*) - Primary image repository
  - Orchestrator: `ghcr.io/trailofbits/buttercup/buttercup-orchestrator`
  - Fuzzer: `ghcr.io/trailofbits/buttercup/buttercup-fuzzer`
  - Seed-Gen: `ghcr.io/trailofbits/buttercup/buttercup-seed-gen`
  - Patcher: `ghcr.io/trailofbits/buttercup/buttercup-patcher`
  - Program-Model: `ghcr.io/trailofbits/buttercup/buttercup-program-model`
  - Tags: `main`, version tags
  - Pull policy: `Always`

- Competition API image: `ghcr.io/tob-challenges/example-crs-architecture/competition-test-api:v1.4-rc1`

- Docker Hub fallback for public images (with optional auth)

**Hosting:**
- Kubernetes clusters:
  - Minikube - Local development
  - Azure AKS - Production deployment
  - Generic K8s 1.24+ - Self-hosted deployments
- Deployment: Helm charts in `/deployment/k8s/charts/`

**CI Pipeline:**
- GitHub Actions (inferred from `.github/` workflows)
- Dependabot for dependency updates (`.github/dependabot.yml`)
- Pre-commit hooks (`.pre-commit-config.yaml`)
- Build: Docker buildkit with layer caching

## Environment Configuration

**Required Environment Variables:**
```
# LiteLLM
LITELLM_MASTER_KEY
OPENAI_API_KEY or AZURE_API_BASE/AZURE_API_KEY or ANTHROPIC_API_KEY or GEMINI_API_KEY

# Redis
REDIS_URL (default: redis://localhost:6379)

# CRS (internal)
CRS_KEY_ID
CRS_KEY_TOKEN
CRS_KEY_TOKEN_HASH

# Competition API (if enabled)
COMPETITION_API_URL
COMPETITION_API_KEY_ID
COMPETITION_API_KEY_TOKEN
SCANTRON_GITHUB_PAT (for accessing competition server packages)
```

**Optional Environment Variables:**
```
# Langfuse
LANGFUSE_ENABLED
LANGFUSE_HOST
LANGFUSE_PUBLIC_KEY
LANGFUSE_SECRET_KEY

# OpenTelemetry
OTEL_ENDPOINT
OTEL_TOKEN
OTEL_PROTOCOL

# Docker Registry Auth
DOCKER_USERNAME
DOCKER_PAT
GHCR_AUTH (base64 encoded)

# Kubernetes Deployment
TAILSCALE_ENABLED (for VPN networking)
TS_CLIENT_ID, TS_CLIENT_SECRET, TS_OP_TAG (Tailscale config)
```

**Secrets Location:**
- Kubernetes Secrets: `buttercup-litellm-api-secrets`, `ghcr-auth`, `docker-auth`
- Environment file: `/deployment/env.template` (not committed, for local reference)
- Helm values-template files: `/deployment/k8s/values-*.template`

## Webhooks & Callbacks

**Incoming Webhooks:**
- `/webhook/trigger_task` - POST endpoint at `orchestrator:8000`
  - Receives Challenge objects from external competition API
  - Triggers task download and processing workflow

- `/webhook/sarif` - POST endpoint at `orchestrator:8000`
  - Receives SARIF format vulnerability reports
  - Triggers vulnerability submission workflow

- `/webhook/pov` - Inferred endpoint for proof-of-vulnerability submission
  - Receives test case data and trace information

**Outgoing HTTP Calls (not webhooks but external API calls):**
- Competition API calls:
  - GET `/v1/challenges/{task_id}` - Fetch task details
  - POST `/v1/vulnerabilities` - Submit found vulnerabilities
  - POST `/v1/patches` - Submit patches
  - POST `/v1/sarif` - Submit SARIF reports
  - GET `/v1/ping` - Health check
  - Implementation: `requests` library in `/orchestrator/src/buttercup/orchestrator/ui/competition_api/services/crs_client.py`

**Message Queue (Redis Consumer Groups):**
- Reliable task distribution using Redis consumer groups
- Queue patterns for different task types:
  - BUILD_REQUEST - Build tasks
  - CRASH_TASK - Fuzzer crash reports
  - PATCH_TASK - Patch validation
  - CONFIRMED_VULNERABILITIES_TASK - Vulnerability confirmation
  - INDEX_TASK - Code indexing tasks
  - TRACED_VULNERABILITIES_TASK - Traced vulnerability reports

---

*Integration audit: 2026-03-10*
