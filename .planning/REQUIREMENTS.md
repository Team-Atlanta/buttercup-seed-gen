# Requirements: Buttercup Seed-Gen Standalone

**Defined:** 2026-03-10
**Core Value:** Generate quality seeds and submit them to the competition API without fuzzing overhead

## v1.1 Requirements

Requirements for Java/Jazzer support with JaCoCo coverage integration.

### Configuration

- [ ] **CFG-01**: crs.yaml declares `java` and `jvm` in `supported_target.language`
- [ ] **CFG-02**: helper.py detects language from project.yaml

### Coverage Infrastructure

- [ ] **COV-01**: JaCoCo agent runs Jazzer target with `--additional_jvm_args=-javaagent:/opt/jacoco-agent.jar=...`
- [ ] **COV-02**: JaCoCo CLI generates XML report from .exec file via `java -jar /opt/jacoco-cli.jar report`
- [ ] **COV-03**: XML report placed at `<build_dir>/dumps/<harness>.xml` (CoverageRunner.run_java() expected path)
- [ ] **COV-04**: JaCoCo JARs (`jacoco-agent.jar`, `jacoco-cli.jar`) available in coverage builder image

### Integration

- [ ] **INT-01**: helper.py dispatches to Java coverage vs C coverage based on detected language
- [ ] **INT-02**: CoverageRunner.run_java() successfully parses generated JaCoCo XML

### Validation

- [ ] **VAL-04**: Java target coverage execution succeeds in oss-crs deployment
- [ ] **VAL-05**: coverage-bot populates CoverageMap for Java harness

## v1.0 Requirements (Complete)

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
- [x] **CODE-05**: Verify libCRS seed submission continues working (already implemented)

### Cleanup

- [x] **CLN-01**: Remove fuzzer build stages from Dockerfile (dead code)
- [x] **CLN-02**: Remove orphaned Redis crash queue setup if present

### Validation

- [x] **VAL-01**: Services deploy successfully with slimmed configuration
- [x] **VAL-02**: Seedgen generates and submits seeds via libCRS
- [x] **VAL-03**: Coverage-bot runs without fuzzer-bot dependency

## Future Requirements

Deferred to future work.

### Optimization

- **OPT-01**: Further slim Docker image by removing unused Python dependencies
- **OPT-02**: Add seed quality metrics/dashboard

### Additional Languages

- **LANG-01**: Go coverage support
- **LANG-02**: Python coverage support

## Out of Scope

| Feature | Reason |
|---------|--------|
| Fuzzing capability | Deliberately removed — this is a seed-gen-only tool |
| POV/vulnerability discovery | Removed per scope decision — pure seed generation |
| Patcher integration | No vulnerabilities to patch without fuzzer |
| Full Buttercup CRS features | This is oss-crs only, not full deployment |
| Protobuf enum cleanup | BuildType.FUZZER must remain (seedgen references it for build lookup) |
| Go/Python/JS coverage | Focus on C/C++ and Java only for OSS-CRS |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

### v1.1 Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CFG-01 | Phase 4 | Pending |
| CFG-02 | Phase 4 | Pending |
| COV-01 | Phase 4 | Pending |
| COV-02 | Phase 4 | Pending |
| COV-03 | Phase 4 | Pending |
| COV-04 | Phase 4 | Pending |
| INT-01 | Phase 5 | Pending |
| INT-02 | Phase 5 | Pending |
| VAL-04 | Phase 5 | Pending |
| VAL-05 | Phase 5 | Pending |

**v1.1 Coverage:**
- v1.1 requirements: 10 total
- Mapped to phases: 10
- Unmapped: 0

### v1.0 Traceability (Complete)

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
| CODE-05 | Phase 3 | Complete |
| CLN-01 | Phase 1 | Complete |
| CLN-02 | Phase 2 | Complete |
| VAL-01 | Phase 3 | Complete |
| VAL-02 | Phase 3 | Complete |
| VAL-03 | Phase 3 | Complete |

**v1.0 Coverage:**
- v1.0 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

---
*Requirements defined: 2026-03-10*
*Last updated: 2026-03-12 — v1.1 traceability updated*
