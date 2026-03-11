---
phase: 1
slug: service-configuration-removal
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-10
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell validation commands (file content checks) |
| **Config file** | None — direct file assertions |
| **Quick run command** | `python -c "import yaml; yaml.safe_load(open('oss-crs/crs.yaml'))"` |
| **Full suite command** | `docker buildx bake -f oss-crs/docker-bake.hcl` |
| **Estimated runtime** | ~60 seconds (Docker build) |

---

## Sampling Rate

- **After every task commit:** Run YAML validation + grep checks
- **After every plan wave:** Run `docker buildx bake -f oss-crs/docker-bake.hcl`
- **Before `/gsd:verify-work`:** Full Docker build must succeed
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | SVC-01 | config | `python -c "import yaml; assert len(yaml.safe_load(open('oss-crs/crs.yaml'))['crs_run_phase']) == 4"` | ✅ | ⬜ pending |
| 1-01-02 | 01 | 1 | SVC-02 | config | `grep -q "redis:" oss-crs/crs.yaml` | ✅ | ⬜ pending |
| 1-01-03 | 01 | 1 | SVC-03 | config | `grep -q "orchestrator:" oss-crs/crs.yaml` | ✅ | ⬜ pending |
| 1-01-04 | 01 | 1 | SVC-04 | config | `grep -q "coverage-bot:" oss-crs/crs.yaml` | ✅ | ⬜ pending |
| 1-01-05 | 01 | 1 | SVC-05 | config | `grep -q "seed-gen:" oss-crs/crs.yaml` | ✅ | ⬜ pending |
| 1-01-06 | 01 | 1 | CODE-02 | config | `! grep -q "fuzzer)" oss-crs/bin/buttercup_entrypoint` | ✅ | ⬜ pending |
| 1-01-07 | 01 | 1 | CLN-01 | config | `! grep -q "fuzzer-builder" oss-crs/dockerfiles/buttercup-runner.Dockerfile` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements.*

All Phase 1 requirements are configuration file changes validated by shell commands. No test file stubs needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| libCRS submits seeds | SVC-05 | Requires competition API | Check /tmp/seed_submit.log in running container |
| Docker image size reduction | CLN-01 | Subjective threshold | Compare `docker images` before/after |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
