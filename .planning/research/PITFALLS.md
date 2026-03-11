# Pitfalls Research

**Domain:** Microservices Extraction (Slimming oss-crs from fuzzing pipeline to seed-gen standalone)
**Researched:** 2026-03-10
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Orphaned Redis Queue Consumers

**What goes wrong:**
Seedgen continues reading from crash queues or POV queues that no longer have producers (fuzzer-bot removed). Messages pile up unprocessed, or worse, seedgen blocks waiting for messages that will never arrive. The crash_queue and crash_set infrastructure in seed_gen_bot.py expects fuzzer-bot to populate crash data for vuln-discovery tasks.

**Why it happens:**
When extracting components from a microservices system, developers focus on removing the service definition (crs.yaml entry) but miss the **runtime message flow dependencies**. The seedgen code contains explicit crash handling logic (CrashSubmit, crash_queue, crash_set) that was designed for integration with fuzzer-bot's crash detection.

**How to avoid:**
1. Map all Redis queue dependencies before removal (grep for QueueFactory, ReliableQueue, crash_queue across all retained services)
2. In seed_gen_bot.py, remove or conditionally disable crash submission logic:
   - Remove CrashSubmit initialization (lines 195-205)
   - Remove crash_queue and crash_set from __init__ (lines 56-57)
   - Disable vuln-discovery task option or strip crash handling from VulnDiscoveryFullTask/VulnDiscoveryDeltaTask
3. Add startup validation that fails fast if removed queues are referenced
4. Update task probability distribution if removing vuln-discovery entirely

**Warning signs:**
- Logs show "waiting for messages" indefinitely
- Redis LLEN shows growing queue depths for queues with no consumers
- Seedgen tasks hang during initialization
- Error messages about missing crash data or queue timeouts

**Phase to address:**
Phase 1 (Service Removal) - Must be removed alongside fuzzer-bot service definition, not deferred.

---

### Pitfall 2: Shared Protobuf Message Definitions with Stale Dependencies

**What goes wrong:**
Removed services (fuzzer-bot) are referenced in BuildType enum or BuildRequest/BuildOutput messages. Seedgen requires BuildType.FUZZER in required_builds() but the orchestrator continues to register it. If protobuf definitions are later updated to remove unused enums, seedgen breaks at runtime when deserializing messages.

**Why it happens:**
Protobuf definitions in common/protos/msg.proto are shared across all services. The **"safe" backward-compatible approach of never removing enum values** conflicts with the refactoring goal of slimming down dependencies. Developers assume removing fuzzer-bot means removing BuildType.FUZZER is safe, but seedgen still explicitly checks for it (seed_gen_bot.py line 65: `return [BuildType.FUZZER]`).

**How to avoid:**
1. Audit retained services for BuildType references BEFORE protobuf changes
2. In this specific case: seedgen STILL NEEDS BuildType.FUZZER because it processes fuzzer harnesses - the enum must stay
3. Document in msg.proto which enums are required by which services after extraction
4. Run protobuf compatibility check: compile old .proto with new seedgen code
5. Never remove protobuf field numbers (reserve them instead) - [protobuf best practices](https://oneuptime.com/blog/post/2026-01-24-protocol-buffer-evolution/view)

**Warning signs:**
- "Unknown enum value" errors in logs
- Protobuf deserialization failures at service startup
- Redis build map returns empty lists despite orchestrator registration
- Type errors when accessing BuildType in Python code

**Phase to address:**
Phase 2 (Dependency Cleanup) - Only after verifying all retained services' protobuf usage patterns.

---

### Pitfall 3: Environment Variable Configuration Drift

**What goes wrong:**
Fuzzer-bot specific environment variables (BUTTERCUP_FUZZER_RUNNER_PATH, BUTTERCUP_FUZZER_TIMEOUT) remain in deployment configs but are unused. Worse, seedgen assumes certain env vars are set by fuzzer-bot's entrypoint logic. When fuzzer-bot is removed from buttercup_entrypoint (lines 113-129), the shared corpus registration logic disappears, breaking seedgen's corpus directory access.

**Why it happens:**
The **single Dockerfile, multi-service pattern** (buttercup-runner.Dockerfile) with RUN_TYPE routing creates shared initialization logic. The entrypoint script (buttercup_entrypoint) has service-specific setup blocks that interdepend. Line 120 shows fuzzer-bot registers shared corpus directory - if seedgen needs this and fuzzer is removed, seedgen silently fails to access shared storage.

**How to avoid:**
1. Inventory ALL environment variables in buttercup_entrypoint per RUN_TYPE before removal
2. Check seedgen config.py for env var expectations (BUTTERCUP_SEED_GEN_SERVER__CORPUS_ROOT)
3. Move shared setup logic (corpus registration, download-build-output) from fuzzer-bot block to seedgen block
4. Create .env.example file documenting required vs. optional variables per service
5. Add startup validation in seedgen __init__ that checks for required env vars

**Warning signs:**
- "FileNotFoundError: corpus directory not found" in seedgen logs
- Environment variable references in code but undefined at runtime
- Inconsistent behavior between local dev and deployment (missing libCRS calls)
- Silent failures where seeds are generated but never submitted

**Phase to address:**
Phase 1 (Service Removal) - Must audit entrypoint script when modifying crs.yaml services.

---

### Pitfall 4: Docker Build Cache Contains Dead Code

**What goes wrong:**
After removing fuzzer-bot from crs.yaml, the buttercup-runner.Dockerfile still builds fuzzer dependencies (lines 38-65: fuzzer-builder stage). Docker layer cache masks the inefficiency, but the image contains ~200MB of unused Python packages and binaries. Worse, if fuzzer dependencies have security vulnerabilities, they persist in the slimmed image.

**Why it happens:**
The **multi-stage Dockerfile pattern** with separate builder stages (fuzzer-builder, seedgen-builder) means removing a service from crs.yaml doesn't automatically remove its build artifacts. The final runtime stage (line 105) copies from both builders (lines 121-123), even if fuzzer-bot isn't in the service list.

**How to avoid:**
1. Remove fuzzer-builder stage entirely from buttercup-runner.Dockerfile
2. Remove fuzzer COPY commands (lines 121-122, line 126)
3. Remove fuzzer from PATH environment variable (line 133: remove /app/fuzzer/.venv/bin)
4. Run `docker system prune --volumes` to clear orphaned build cache
5. Verify image size reduction: `docker images ghcr.io/trailofbits/buttercup` before/after
6. Update docker-bake.hcl if it references fuzzer targets

**Warning signs:**
- Image size doesn't decrease after removing fuzzer-bot
- `docker history` shows layers copying fuzzer code
- Security scans flag vulnerabilities in unused dependencies
- Build times remain the same despite removing a service

**Phase to address:**
Phase 1 (Service Removal) - Clean Dockerfile immediately when modifying crs.yaml, not later.

---

### Pitfall 5: Implicit Service Communication via Shared Corpus Directory

**What goes wrong:**
Fuzzer-bot writes discovered seeds to shared corpus via `libCRS register-shared-dir /shared-corpus corpus`. Seedgen reads from this shared corpus to improve seed quality. When fuzzer is removed, seedgen's corpus.py (line 33: `self.remote_path = node_local.remote_path(Path(self.path))`) expects a shared corpus that no longer exists. Seeds are generated but isolation degrades quality.

**Why it happens:**
The **shared filesystem pattern** creates implicit service coupling that's invisible in service graphs. Unlike Redis queues (explicit in code), shared volumes are configured in deployment manifests (crs.yaml, docker-compose, K8s volumes). The dependency is **data-flow coupling** not code coupling, so grep doesn't find it.

**How to avoid:**
1. Audit all `libCRS register-shared-dir` calls across services before removal
2. Check corpus.py for remote_path vs. local path logic (lines 32-34, 45-50)
3. If shared corpus is needed, move registration from fuzzer-bot to seedgen entrypoint
4. If not needed, remove remote_path logic from corpus.py entirely (simplify to local-only)
5. Document in PROJECT.md whether seed quality depends on cross-service corpus sharing

**Warning signs:**
- Seedgen corpus size doesn't grow over time (missing shared inputs)
- Logs show "failed to copy to remote corpus" errors
- Coverage-bot reports lower coverage than expected (missing fuzzer-discovered seeds)
- Performance degradation: seedgen re-discovers basic inputs that fuzzer would have shared

**Phase to address:**
Phase 1 (Service Removal) - Decide on corpus strategy when modifying entrypoint, not after deployment.

---

### Pitfall 6: POV Submission Path vs. Seed Submission Path Confusion

**What goes wrong:**
Seedgen currently submits both seeds AND POVs (proof-of-vulnerability crashes). The entrypoint registers two submit directories: `libCRS register-submit-dir pov` (line 116) and `libCRS register-submit-dir seed` (line 117 for fuzzer, line 143 for seedgen). When fuzzer is removed, developers forget seedgen ALSO generates POVs via vuln-discovery tasks. The POV path is removed from seedgen entrypoint, so vuln-discovery tasks write POVs that are never submitted.

**Why it happens:**
The **task probability distribution** in seed_gen_bot.py (lines 32-38) shows vuln-discovery has 35-45% probability. This task uses CrashSubmit to write POVs. Developers assume "no fuzzer = no POVs" but seedgen's vuln-discovery feature GENERATES ITS OWN POVs via LLM-created test cases. The confusion between "fuzzer-discovered crashes" vs. "seedgen-generated crashes" masks the dependency.

**How to avoid:**
1. Decide: Are POVs in scope for slimmed oss-crs? (PROJECT.md says "no vulnerabilities to patch" but vuln-discovery generates them)
2. If NO POVs: Remove VULN_DISCOVERY from task_distribution in seed_gen_bot.py sample_task()
3. If YES POVs: Keep `libCRS register-submit-dir pov` in seedgen entrypoint (line 143 equivalent)
4. Update PROJECT.md Active requirements to clarify POV scope decision
5. Remove crash_submit from VulnDiscoveryFullTask/DeltaTask if POVs are out of scope

**Warning signs:**
- POV files exist in /artifacts/povs but no submission logs
- Vuln-discovery tasks run but no competition API submissions appear
- CrashSubmit code executes but writes to unmonitored directories
- Task counter shows vuln-discovery ran 35% of time but no output

**Phase to address:**
Phase 0 (Requirements Clarification) - Resolve before any code changes. Critical scope decision.

---

### Pitfall 7: Coverage-Bot Dependency on Fuzzer Corpus

**What goes wrong:**
Coverage-bot measures code coverage by running harnesses with corpus inputs. In the full pipeline, fuzzer-bot populates the corpus, and coverage-bot consumes it. When fuzzer-bot is removed, coverage-bot runs harnesses against a sparse corpus (only seedgen outputs), reporting artificially low coverage metrics. The decision to "keep coverage-bot" (PROJECT.md line 65) assumes corpus population continues.

**Why it happens:**
**Temporal coupling**: coverage-bot depends on fuzzer-bot's side effects (corpus growth) rather than direct API calls. The services appear independent in crs.yaml, but runtime behavior creates a producer-consumer relationship. The orchestrator doesn't enforce this dependency - it just happens to work when both run.

**How to avoid:**
1. Verify coverage-bot corpus source in its code (where does it read inputs?)
2. If coverage-bot needs fuzzer corpus: Seedgen must write ALL generated seeds to corpus, not just high-quality ones
3. Adjust seedgen's copy_corpus logic (corpus.py lines 53-67) to be more permissive
4. Consider removing coverage-bot entirely if seed quality metrics aren't needed without fuzzer
5. Add metric: compare coverage before/after fuzzer removal (expect it to drop)

**Warning signs:**
- Coverage-bot reports remain static (0% or same as initial seeds)
- Coverage metrics drop significantly compared to fuzzer-enabled baseline
- Logs show "empty corpus" or "no inputs found" from coverage-bot
- Function selector in seedgen fails (needs coverage data to pick functions)

**Phase to address:**
Phase 1 (Service Removal) - Validate coverage-bot still provides value without fuzzer corpus.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Keep BuildType.FUZZER enum despite no fuzzer | No protobuf changes needed | Future developers confused why FUZZER enum exists in seed-only system | Acceptable - protobuf backward compat is critical |
| Leave POV submission code in seedgen but remove fuzzer POV path | Minimal code changes | Silent failures if vuln-discovery runs, dead code paths | Never - decide vuln-discovery scope upfront |
| Remove fuzzer-builder from Dockerfile but keep dependencies in pyproject.toml | Dockerfile simplified | Unused packages in lockfiles, security vulnerability surface | Phase 1 only, must clean in Phase 2 |
| Keep coverage-bot without verifying corpus source | Looks complete (all bots present) | Meaningless metrics, wasted compute | Only if corpus quality isn't a goal |
| Use conditional logic (if fuzzer-bot exists...) instead of removing dead code | Easy to test both modes | Complexity explosion, hard-to-test branches | Only during gradual migration, not final state |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Redis queue dependencies | Remove fuzzer-bot but leave crash_queue references in seedgen | Grep for ALL queue names across retained services, remove consumers without producers |
| libCRS submit directories | Assume one service per directory type (seed = seedgen, pov = fuzzer) | Map each service to ALL submit-dir calls it makes (seedgen does BOTH) |
| Shared Docker volumes | Remove volume from docker-compose but leave mount points in entrypoint | Audit entrypoint script for `register-shared-dir` before removing volumes |
| Protobuf enum usage | Remove service → remove its BuildType enum value | Audit all retained services for enum references FIRST (seedgen needs BuildType.FUZZER) |
| Environment variable scoping | Delete fuzzer-bot env vars from .env file | Check entrypoint shared setup - fuzzer block may set vars that seedgen needs |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Docker layer cache hides dead dependencies | No build time improvement after removal | `docker builder prune --all` after Dockerfile changes | First deployment to clean environment |
| Orphaned volumes accumulate seeds from old fuzzer runs | /artifacts fills disk over time | `docker volume prune` regularly, document in deployment README | After ~1000 task runs (weeks/months) |
| Redis memory growth from abandoned queues | Redis OOM errors, slow KEYS commands | Clear queues before removing producers: `redis-cli FLUSHDB` or selective delete | When fuzzer-produced millions of messages |
| Seedgen generates high-quality seeds that aren't corpus-copied | Corpus size static, coverage doesn't improve | Audit copy_corpus max_size limits, adjust for seed-only use case | Immediately visible in coverage metrics |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Unused fuzzer dependencies with CVEs remain in image | Container vulnerability scans fail, compliance issues | Remove fuzzer-builder stage, run `trivy image` before/after |
| Old fuzzer corpus contains sensitive data, orphaned volume persists | Data leak if volumes mounted to wrong container | Explicitly delete fuzzer corpus volumes during migration |
| Crash POVs written to unmonitored directory | Exploits exist on disk but aren't tracked | Remove vuln-discovery or ensure POV submit-dir registration |
| Shared corpus directory has overly broad permissions | Cross-service data contamination | Remove shared corpus if not needed, use explicit copy if needed |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Remove fuzzer but keep "fuzzer-bot" in logs/metrics | Confusing dashboards, support tickets | Rename services: "seedgen" not "fuzzer-bot mode=seedgen" |
| Coverage metrics drop but no explanation | Users think seedgen is broken | Document expected coverage delta in README, adjust baselines |
| Seeds generated but not submitted (missing libCRS call) | Silent failure, no competition API results | Add startup checks that verify submit-dir registration succeeded |
| Vuln-discovery tasks run but POVs disappear | Users think LLM failed, but submission path missing | Disable vuln-discovery OR add explicit POV submission logging |

## "Looks Done But Isn't" Checklist

- [ ] **Service removal:** Removed from crs.yaml AND Dockerfile builder stage AND entrypoint switch statement
- [ ] **Redis dependencies:** All queue consumers without producers identified and removed (not just commented)
- [ ] **Protobuf messages:** Retained services audited for removed service's BuildType/message references
- [ ] **Environment variables:** Entrypoint shared setup logic (libCRS calls, downloads) moved from removed service block
- [ ] **Docker volumes:** Shared volumes removed from compose AND entrypoint register-shared-dir calls updated
- [ ] **Submit directories:** Each retained service's libCRS register-submit-dir calls verified (seed AND pov)
- [ ] **Corpus flow:** Verified seedgen writes to corpus AND coverage-bot can read from same corpus
- [ ] **Build artifacts:** Downloaded artifacts (task, task-coverage, cqdb) verified for seedgen-only workflow
- [ ] **Dead code removal:** Removed service's code removed from source, not just disabled with conditionals
- [ ] **Integration test:** End-to-end test from task download → seedgen → submission → competition API

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Orphaned crash queue fills Redis | LOW | `redis-cli DEL queue:crash` or use QueueFactory.clear() in Python script |
| Seeds generated but not submitted (missing libCRS) | LOW | Add `libCRS register-submit-dir seed` to seedgen entrypoint, restart service |
| Protobuf enum removed, deserialization fails | HIGH | Restore enum to msg.proto, regenerate with protoc.sh, rebuild all images |
| Fuzzer corpus deleted, coverage-bot data gone | MEDIUM | Regenerate seeds with seedgen, wait for corpus to repopulate (hours/days) |
| Docker image contains CVE in unused fuzzer dep | MEDIUM | Rebuild image without fuzzer-builder stage, rescan with trivy |
| Coverage drops unexpectedly, seedgen blamed | LOW | Document baseline, educate users on expected delta without fuzzer |
| Shared corpus volume deleted | HIGH | Recreate volume, seedgen starts from scratch (corpus rebuilds over time) |
| POV submission path missing, vuln-discovery generates untracked exploits | MEDIUM | Disable vuln-discovery tasks OR add POV submit-dir to seedgen |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Orphaned Redis queue consumers | Phase 1 (Service Removal) | `redis-cli KEYS '*crash*'` returns empty after cleanup |
| Shared protobuf message definitions | Phase 2 (Dependency Cleanup) | Protobuf compatibility test passes with old/new .proto |
| Environment variable drift | Phase 1 (Service Removal) | Seedgen starts successfully with only seedgen-specific env vars |
| Docker build cache dead code | Phase 1 (Service Removal) | `docker images` shows 200+ MB size reduction |
| Implicit shared corpus communication | Phase 1 (Service Removal) | Seedgen corpus.py works without fuzzer's shared corpus registration |
| POV vs. seed submission confusion | Phase 0 (Requirements) | PROJECT.md explicitly states POV scope decision |
| Coverage-bot corpus dependency | Phase 1 (Service Removal) | Coverage metrics remain meaningful (>10% coverage) after fuzzer removal |

## Refactoring Patterns from Research

Based on industry research into microservices extraction, these patterns apply specifically to this project:

### Pattern: Dependency Mapping Before Removal
[Refactoring monoliths research](https://arxiv.org/html/2510.03050) emphasizes identifying dependencies at the code level before extraction. For oss-crs:
- **Application:** Map Redis queue consumers/producers (crash_queue, harness_weights) across all services
- **Tool:** `grep -r "QueueFactory\|crash_queue\|crash_set" seed-gen/ fuzzer/` to find coupling
- **Pitfall prevented:** Orphaned queue consumers (Pitfall 1)

### Pattern: Contract Testing for Removed Services
[Contract testing approaches](https://microservices.io/patterns/testing/service-integration-contract-test.html) define expectations between services. For oss-crs:
- **Application:** Define BuildType usage contract: seedgen expects BuildType.FUZZER even without fuzzer-bot
- **Tool:** Create test that verifies orchestrator provides BuildType.FUZZER builds for seedgen
- **Pitfall prevented:** Protobuf definition removal breaking seedgen (Pitfall 2)

### Pattern: Shared Infrastructure Failure Modes
[Redis microservices patterns](https://reintech.io/blog/redis-microservices-patterns-antipatterns) warn about cascading failures. For oss-crs:
- **Application:** When fuzzer-bot stops producing to crash_queue, seedgen shouldn't block
- **Tool:** Add timeout to queue.get() calls, fail gracefully if producer missing
- **Pitfall prevented:** Orphaned queue blocking (Pitfall 1)

### Pattern: Message Loss Detection in Queues
[Redis Streams reliability](https://oneuptime.com/blog/post/2026-01-21-redis-streams-message-queues/view) emphasizes consumer groups and acknowledgment. For oss-crs:
- **Application:** If removing fuzzer-bot leaves messages in crash_queue, detect and clear
- **Tool:** Startup check: `LLEN queue:crash` warns if >0 messages exist without producer
- **Pitfall prevented:** Stale crash data confusing seedgen (Pitfall 1)

### Pattern: Distributed Monolith Anti-Pattern Avoidance
[Monolith refactoring research](https://vfunction.com/blog/go-to-guide-to-refactoring-a-monolith-to-microservices/) warns about highly connected extracted services. For oss-crs:
- **Application:** Seedgen shouldn't require fuzzer-bot's corpus for basic functionality
- **Tool:** Test seedgen in isolation: can it generate seeds without ANY shared corpus?
- **Pitfall prevented:** Implicit corpus dependency degrading quality (Pitfall 5)

## Sources

Research for this pitfalls analysis drew from:

### Microservices Extraction
- [Refactoring Towards Microservices: Preparing the Ground for Service Extraction](https://arxiv.org/html/2510.03050) - Academic research on dependency identification before extraction
- [Refactoring a monolith to microservices](https://microservices.io/refactoring/) - Patterns for breaking down monoliths
- [How to break a Monolith into Microservices](https://martinfowler.com/articles/break-monolith-into-microservices.html) - Martin Fowler's guidance on dependency elimination
- [Go-to Guide to Refactoring a Monolith to Microservices](https://vfunction.com/blog/go-to-guide-to-refactoring-a-monolith-to-microservices/) - Distributed monolith anti-pattern warnings

### Service Dependencies and Breaking Changes
- [Managing Version Dependencies Between Microservices](https://medium.com/@denhox/managing-version-dependencies-between-microservices-648d1d8dd4ca) - Versioning strategies when removing services
- [5 Tips for Managing Service Dependencies in Microservice Architecture](https://www.linkedin.com/pulse/5-tips-managing-service-dependencies-microservice-architecture) - Dependency management best practices
- [Top 10 Microservices Architecture Best Practices for 2026](https://www.tekrecruiter.com/post/top-10-microservices-architecture-best-practices-for-2026) - Current industry standards

### Redis Queue Patterns
- [How to Use Redis Lists for Message Queues](https://oneuptime.com/blog/post/2026-01-25-redis-lists-message-queues/view) - Message loss patterns and reliable queues
- [How to Implement Reliable Message Queues with Redis Streams](https://oneuptime.com/blog/post/2026-01-21-redis-streams-message-queues/view) - Consumer groups and acknowledgment
- [Redis in Microservices Architecture: Patterns and Anti-Patterns](https://reintech.io/blog/redis-microservices-patterns-antipatterns) - Tight coupling avoidance
- [Redis Queue](https://redis.io/glossary/redis-queue/) - Official Redis queue documentation

### Docker and Infrastructure
- [How to Clean Up Orphaned Docker Volumes](https://oneuptime.com/blog/post/2026-02-08-how-to-clean-up-orphaned-docker-volumes/view) - Volume cleanup after service removal
- [How to Remove Docker Images, Containers, and Volumes: Complete Cleanup Guide (2025–2026)](https://www.progressiverobot.com/2026/02/05/remove-docker-images-containers-and-volumes/) - System prune best practices
- [Prune unused Docker objects | Docker Docs](https://docs.docker.com/engine/manage-resources/pruning/) - Official Docker pruning documentation

### Protobuf and Configuration
- [How to Handle Protocol Buffer Evolution](https://oneuptime.com/blog/post/2026-01-24-protocol-buffer-evolution/view) - Schema evolution without breaking changes
- [Proto-Break: Safeguarding Your Protobuf Evolution](https://medium.com/@tedious/proto-break-safeguarding-your-protobuf-evolution-7b8455f08796) - Field number reservation patterns
- [Environment Variable Management: Complete Best Practices Guide 2026](https://www.envsentinel.dev/blog/environment-variable-management-tips-best-practices) - Env var validation and documentation
- [How to Fix 'Configuration Management' Issues](https://oneuptime.com/blog/post/2026-01-24-configuration-management-issues/view) - Runtime configuration errors

### Testing Strategies
- [Microservices Pattern: Pattern: Service Integration Contract Test](https://microservices.io/patterns/testing/service-integration-contract-test.html) - Contract testing for removed services
- [Pact | Microservices testing made easy](https://pact.io/) - Consumer-driven contract testing
- [Top 10 Microservices Testing Tools In 2026](https://www.accelq.com/blog/microservices-testing-tools/) - Current testing tool landscape

---
*Pitfalls research for: Buttercup oss-crs seed-gen standalone extraction*
*Researched: 2026-03-10*
*Codebase analysis: seed-gen/, common/, oss-crs/ directories*
