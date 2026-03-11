# Requirements: Buttercup Seed-Gen Standalone

**Defined:** 2026-03-10
**Core Value:** Generate quality seeds and submit them to the competition API without fuzzing overhead

## v1 Requirements

Requirements for slimmed-down oss-crs seed generator.

### Service Configuration

- [x] **SVC-01**: Remove fuzzer-bot service from crs.yaml
- [x] **SVC-02**: Keep redis service for inter-service communication
- [x] **SVC-03**: Keep orchestrator service for Redis population from build artifacts
- [x] **SVC-04**: Keep coverage-bot service for coverage metrics
- [x] **SVC-05**: Keep seed-gen service with modified task selection

### Code Changes

- [x] **CODE-01**: Remove vuln-discovery task type from seedgen task probability distribution
- [x] **CODE-02**: Remove fuzzer case from buttercup_entrypoint script
- [x] **CODE-03**: Remove crash queue consumer references from seedgen
- [x] **CODE-04**: Remove POV submission path logic (no longer needed)
- [ ] **CODE-05**: Verify libCRS seed submission continues working (already implemented)

### Cleanup

- [x] **CLN-01**: Remove fuzzer build stages from Dockerfile (dead code)
- [x] **CLN-02**: Remove orphaned Redis crash queue setup if present

### Validation

- [ ] **VAL-01**: Services deploy successfully with slimmed configuration
- [ ] **VAL-02**: Seedgen generates and submits seeds via libCRS
- [ ] **VAL-03**: Coverage-bot runs without fuzzer-bot dependency

## v2 Requirements

Deferred to future work.

### Optimization

- **OPT-01**: Further slim Docker image by removing unused Python dependencies
- **OPT-02**: Add seed quality metrics/dashboard

## Out of Scope

| Feature | Reason |
|---------|--------|
| Fuzzing capability | Deliberately removed — this is a seed-gen-only tool |
| POV/vulnerability discovery | Removed per scope decision — pure seed generation |
| Patcher integration | No vulnerabilities to patch without fuzzer |
| Full Buttercup CRS features | This is oss-crs only, not full deployment |
| Protobuf enum cleanup | BuildType.FUZZER must remain (seedgen references it for build lookup) |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SVC-01 | Phase 1 | Complete |
| SVC-02 | Phase 1 | Complete |
| SVC-03 | Phase 1 | Complete |
| SVC-04 | Phase 1 | Complete |
| SVC-05 | Phase 1 | Complete |
| CODE-01 | Phase 2 | Complete |
| CODE-02 | Phase 1 | Complete |
| CODE-03 | Phase 2 | Complete |
| CODE-04 | Phase 2 | Complete |
| CODE-05 | Phase 3 | Pending |
| CLN-01 | Phase 1 | Complete |
| CLN-02 | Phase 2 | Complete |
| VAL-01 | Phase 3 | Pending |
| VAL-02 | Phase 3 | Pending |
| VAL-03 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

---
*Requirements defined: 2026-03-10*
*Last updated: 2026-03-10 with phase mappings*
