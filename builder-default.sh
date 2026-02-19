#!/bin/bash
# Build with ASan (default sanitizer) and create ChallengeTask-compatible structure
#
# Creates:
#   /artifacts/task/                   # Task root directory
#   /artifacts/task/task_meta.json     # TaskMeta file
#   /artifacts/task/src/               # Source code snapshot
#   /artifacts/task/fuzz-tooling/      # OSS-Fuzz tooling
#   /artifacts/task/fuzz-tooling/build/infra/helper.py  # Stub helper
#   /artifacts/task/fuzz-tooling/build/out/{project}/  # Build outputs
#
# Environment variables:
#   PROJECT_NAME - OSS-Fuzz project name (required)
#   SRC          - Source directory (default: /src)
#   OUT          - Build output directory (default: /out)

set -e

PROJECT_NAME="${PROJECT_NAME:-$(basename $SRC)}"
SRC_DIR="${SRC:-/src}"
OUT_DIR="${OUT:-/out}"
TASK_ID="${TASK_ID:-oss-crs-task}"

echo "[builder-default] Starting ASan build..."
echo "[builder-default] PROJECT_NAME=$PROJECT_NAME"
echo "[builder-default] SRC_DIR=$SRC_DIR"
echo "[builder-default] OUT_DIR=$OUT_DIR"

# Run OSS-Fuzz compile (uses default SANITIZER=address)
compile

# Create ChallengeTask-compatible directory structure
TASK_DIR="/artifacts/task"
mkdir -p "$TASK_DIR"

# 1. Create task_meta.json
cat > "$TASK_DIR/task_meta.json" << EOF
{
  "project_name": "$PROJECT_NAME",
  "focus": "",
  "task_id": "$TASK_ID",
  "metadata": {
    "sanitizer": "address",
    "engine": "libfuzzer",
    "source": "oss-crs"
  }
}
EOF
echo "[builder-default] Created task_meta.json"

# 2. Snapshot source code
if [ -d "$SRC_DIR" ]; then
    mkdir -p "$TASK_DIR/src"
    cp -r "$SRC_DIR"/* "$TASK_DIR/src/" 2>/dev/null || true
    echo "[builder-default] Snapshotted source from $SRC_DIR"
else
    echo "[builder-default] WARNING: Source directory $SRC_DIR not found"
    mkdir -p "$TASK_DIR/src"
fi

# 3. Create fuzz-tooling structure with build outputs
# ChallengeTask expects:
#   fuzz-tooling/{oss-fuzz-subdir}/build/out/{project}/
#   fuzz-tooling/{oss-fuzz-subdir}/infra/helper.py
#   fuzz-tooling/{oss-fuzz-subdir}/projects/{project}/project.yaml
# where get_oss_fuzz_subpath() returns the first subdir under fuzz-tooling/ (oss-crs)
# and get_build_dir() returns get_oss_fuzz_path() / "build" / "out" / project_name
FUZZ_TOOLING="$TASK_DIR/fuzz-tooling"
OSS_FUZZ_SUBDIR="$FUZZ_TOOLING/oss-crs"
BUILD_OUT="$OSS_FUZZ_SUBDIR/build/out/$PROJECT_NAME"
mkdir -p "$BUILD_OUT"
mkdir -p "$OSS_FUZZ_SUBDIR/infra"

# 4. Create stub helper.py (ChallengeTask requires this file to exist)
cat > "$OSS_FUZZ_SUBDIR/infra/helper.py" << 'EOF'
#!/usr/bin/env python3
"""Stub OSS-Fuzz helper for OSS-CRS.

This is a minimal stub that satisfies ChallengeTask's requirement
for infra/helper.py to exist. Full helper functionality is not
needed in OSS-CRS context since builds are pre-compiled.
"""

import sys

def main():
    print("OSS-CRS stub helper - builds are pre-compiled", file=sys.stderr)
    return 0

if __name__ == "__main__":
    sys.exit(main())
EOF
chmod +x "$OSS_FUZZ_SUBDIR/infra/helper.py"
echo "[builder-default] Created stub helper.py"

# 5. Copy OSS-Fuzz project directory to the expected location
PROJ_DEST="$OSS_FUZZ_SUBDIR/projects/$PROJECT_NAME"
mkdir -p "$PROJ_DEST"

# This is typically at /src/oss-fuzz/projects/$PROJECT_NAME or similar
for proj_path in "/src/oss-fuzz/projects/$PROJECT_NAME" "/oss-fuzz/projects/$PROJECT_NAME"; do
    if [ -d "$proj_path" ]; then
        # Copy project files (Dockerfile, build.sh, project.yaml, etc.)
        cp -r "$proj_path"/* "$PROJ_DEST/" 2>/dev/null || true
        echo "[builder-default] Copied project files from $proj_path to $PROJ_DEST"
        break
    fi
done

# If project.yaml doesn't exist, create a minimal one
if [ ! -f "$PROJ_DEST/project.yaml" ]; then
    cat > "$PROJ_DEST/project.yaml" << PROJYAML
homepage: "https://github.com/example"
language: c
primary_contact: "oss-crs@example.com"
PROJYAML
    echo "[builder-default] Created minimal project.yaml"
fi

# 6. Copy build outputs (excluding src/ directory which contains source code from OSS-Fuzz builds)
# This prevents get_fuzz_targets from picking up spurious files from AFL++, etc.
for item in "$OUT_DIR"/*; do
    if [ -d "$item" ] && [ "$(basename "$item")" = "src" ]; then
        echo "[builder-default] Skipping $item (source directory)"
        continue
    fi
    cp -r "$item" "$BUILD_OUT/" 2>/dev/null || true
done
echo "[builder-default] Copied build outputs to $BUILD_OUT"

# 7. Ensure fuzz targets are executable (for cross-filesystem copies)
find "$BUILD_OUT" -maxdepth 1 -type f ! -name "*.a" ! -name "*.o" ! -name "*.so" ! -name "*.options" ! -name "*.dict" -exec chmod +x {} \;
echo "[builder-default] Set execute permissions on fuzz targets"

# Also copy to /artifacts/default for backwards compatibility
mkdir -p /artifacts/default
for item in "$OUT_DIR"/*; do
    if [ -d "$item" ] && [ "$(basename "$item")" = "src" ]; then
        continue
    fi
    cp -r "$item" /artifacts/default/ 2>/dev/null || true
done

echo "[builder-default] ASan build complete."
echo "[builder-default] Task directory structure:"
find "$TASK_DIR" -type f | head -20
