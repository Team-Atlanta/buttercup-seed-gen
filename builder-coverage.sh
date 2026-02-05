#!/bin/bash
# Build with coverage instrumentation and add to ChallengeTask structure
#
# Expects builder-default.sh to have run first (creates /artifacts/task)
# Adds coverage build to the existing task structure.
#
# Creates:
#   /artifacts/coverage/               # Coverage build outputs (flat, for backwards compat)
#   /artifacts/task-coverage/          # Coverage task directory (if running standalone)

set -e

PROJECT_NAME="${PROJECT_NAME:-$(basename $SRC)}"
SRC_DIR="${SRC:-/src}"
OUT_DIR="${OUT:-/out}"
TASK_ID="${TASK_ID:-oss-crs-task}"

echo "[builder-coverage] Starting coverage build..."
echo "[builder-coverage] PROJECT_NAME=$PROJECT_NAME"

# Set coverage sanitizer and clean previous build artifacts
export SANITIZER=coverage
rm -rf /out/* /work/*

# Run OSS-Fuzz compile with coverage
compile

# Export artifacts to /artifacts/coverage (flat structure, excluding src/)
mkdir -p /artifacts/coverage
for item in "$OUT_DIR"/*; do
    if [ -d "$item" ] && [ "$(basename "$item")" = "src" ]; then
        continue
    fi
    cp -r "$item" /artifacts/coverage/ 2>/dev/null || true
done

# Copy LLVM tools needed for coverage analysis
cp /usr/bin/llvm-profdata /artifacts/coverage/ 2>/dev/null || echo "[builder-coverage] llvm-profdata not found"
cp /usr/bin/llvm-cov /artifacts/coverage/ 2>/dev/null || echo "[builder-coverage] llvm-cov not found"

# Always create /artifacts/task-coverage with proper ChallengeTask structure
# This is separate from /artifacts/task (ASan build) so coverage bot can use it
echo "[builder-coverage] Creating coverage task structure..."
TASK_DIR="/artifacts/task-coverage"
mkdir -p "$TASK_DIR"

# Create task_meta.json
cat > "$TASK_DIR/task_meta.json" << EOF
{
  "project_name": "$PROJECT_NAME",
  "focus": "",
  "task_id": "$TASK_ID",
  "metadata": {
    "sanitizer": "coverage",
    "engine": "libfuzzer",
    "source": "oss-crs"
  }
}
EOF

# Snapshot source
if [ -d "$SRC_DIR" ]; then
    mkdir -p "$TASK_DIR/src"
    cp -r "$SRC_DIR"/* "$TASK_DIR/src/" 2>/dev/null || true
fi

# Create fuzz-tooling structure (same as builder-default.sh)
FUZZ_TOOLING="$TASK_DIR/fuzz-tooling"
OSS_FUZZ_SUBDIR="$FUZZ_TOOLING/oss-crs"
BUILD_OUT="$OSS_FUZZ_SUBDIR/build/out/$PROJECT_NAME"
mkdir -p "$BUILD_OUT"
mkdir -p "$OSS_FUZZ_SUBDIR/infra"

# Create stub helper.py
cat > "$OSS_FUZZ_SUBDIR/infra/helper.py" << 'HELPER_EOF'
#!/usr/bin/env python3
"""Stub OSS-Fuzz helper for OSS-CRS."""
import sys
def main():
    print("OSS-CRS stub helper", file=sys.stderr)
    return 0
if __name__ == "__main__":
    sys.exit(main())
HELPER_EOF
chmod +x "$OSS_FUZZ_SUBDIR/infra/helper.py"

# Copy OSS-Fuzz project directory to the expected location
PROJ_DEST="$OSS_FUZZ_SUBDIR/projects/$PROJECT_NAME"
mkdir -p "$PROJ_DEST"
for proj_path in "/src/oss-fuzz/projects/$PROJECT_NAME" "/oss-fuzz/projects/$PROJECT_NAME"; do
    if [ -d "$proj_path" ]; then
        cp -r "$proj_path"/* "$PROJ_DEST/" 2>/dev/null || true
        break
    fi
done
# Create minimal project.yaml if missing
if [ ! -f "$PROJ_DEST/project.yaml" ]; then
    cat > "$PROJ_DEST/project.yaml" << PROJYAML
homepage: "https://github.com/example"
language: c
primary_contact: "oss-crs@example.com"
PROJYAML
fi

# Copy build outputs (excluding src/)
for item in "$OUT_DIR"/*; do
    if [ -d "$item" ] && [ "$(basename "$item")" = "src" ]; then
        continue
    fi
    cp -r "$item" "$BUILD_OUT/" 2>/dev/null || true
done

# Ensure fuzz targets are executable (for cross-filesystem copies)
find "$BUILD_OUT" -maxdepth 1 -type f ! -name "*.a" ! -name "*.o" ! -name "*.so" ! -name "*.options" ! -name "*.dict" -exec chmod +x {} \;
echo "[builder-coverage] Set execute permissions on fuzz targets"

echo "[builder-coverage] Coverage build complete."
echo "[builder-coverage] Artifacts in /artifacts/coverage/"
ls -la /artifacts/coverage/ | head -20
