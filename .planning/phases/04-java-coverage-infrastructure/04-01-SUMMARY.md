---
phase: 04-java-coverage-infrastructure
plan: 01
subsystem: deployment
tags:
  - java-support
  - coverage
  - configuration
dependency_graph:
  requires: []
  provides:
    - java-language-support
    - jacoco-tooling
  affects:
    - crs-configuration
    - coverage-builder-image
tech_stack:
  added:
    - JaCoCo 0.8.11
  patterns:
    - docker-build-args
key_files:
  created: []
  modified:
    - oss-crs/crs.yaml
    - oss-crs/dockerfiles/builder-coverage.Dockerfile
decisions:
  - "Use JaCoCo 0.8.11 as stable coverage instrumentation for Java"
  - "Install both jacoco-agent.jar and jacoco-cli.jar to /opt/ directory"
  - "Add unzip and curl dependencies to builder-coverage image"
metrics:
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
  commits: 2
  duration: 49s
  completed_at: "2026-03-12T20:51:32Z"
---

# Phase 04 Plan 01: Java Language Configuration Summary

**One-liner:** Added Java/JVM language support to crs.yaml and installed JaCoCo 0.8.11 JARs in coverage builder image

## Overview

This plan enabled the Buttercup CRS to accept Java targets by declaring java/jvm as supported languages in the system configuration and providing JaCoCo coverage instrumentation tooling in the Docker build environment.

## Tasks Completed

### Task 1: Add java and jvm to crs.yaml supported languages
**Status:** Complete
**Commit:** 1e345c5
**Files:** oss-crs/crs.yaml

Added `java` and `jvm` entries to the `supported_target.language` list in crs.yaml, enabling the CRS to recognize and process Java-based targets alongside existing C/C++ support.

### Task 2: Install JaCoCo JARs in builder-coverage.Dockerfile
**Status:** Complete
**Commit:** e93ad89
**Files:** oss-crs/dockerfiles/builder-coverage.Dockerfile

Added JaCoCo 0.8.11 installation to the coverage builder image. Downloads the official JaCoCo distribution from Maven Central, extracts jacocoagent.jar and jacococli.jar to /opt/, and cleans up temporary files. Added unzip and curl as build dependencies.

## Deviations from Plan

None - plan executed exactly as written.

## Technical Implementation

### Configuration Changes

Updated `oss-crs/crs.yaml` to declare Java support:

```yaml
supported_target:
  language:
    - c
    - c++
    - java
    - jvm
```

### Docker Image Enhancement

Added JaCoCo installation layer to `builder-coverage.Dockerfile`:

- Downloads JaCoCo 0.8.11 from Maven Central (official repository)
- Extracts agent JAR for runtime instrumentation
- Extracts CLI JAR for XML report generation
- Renames to consistent naming: jacoco-agent.jar and jacoco-cli.jar
- Installs at /opt/ for system-wide availability
- Cleans apt cache to minimize image size

## Verification Results

All verification criteria passed:

- `grep -E "^\s+- (java|jvm)$" oss-crs/crs.yaml` returns both entries ✓
- `grep -i jacoco oss-crs/dockerfiles/builder-coverage.Dockerfile` shows installation ✓
- Both files modified and committed ✓

## Success Criteria

- [x] crs.yaml has java and jvm in supported_target.language list
- [x] builder-coverage.Dockerfile downloads and installs JaCoCo JARs to /opt/

## Dependencies

### Requirements Fulfilled

- **CFG-01:** Java/JVM language declared in crs.yaml
- **COV-04:** JaCoCo JARs available in coverage builder image

### Downstream Impact

This plan enables:
- **04-02:** Language detection and helper.py dispatching can now handle Java targets
- Coverage collection workflows can invoke JaCoCo agent and CLI
- libCRS can validate Java as a supported target language

## Commits

| Hash    | Message                                            |
| ------- | -------------------------------------------------- |
| 1e345c5 | feat(04-01): add java and jvm to supported languages |
| e93ad89 | feat(04-01): install JaCoCo JARs in coverage builder |

## Self-Check: PASSED

Verified all claimed files and commits exist:

```bash
# Files exist
FOUND: oss-crs/crs.yaml
FOUND: oss-crs/dockerfiles/builder-coverage.Dockerfile

# Commits exist
FOUND: 1e345c5
FOUND: e93ad89
```

All artifacts verified successfully.
