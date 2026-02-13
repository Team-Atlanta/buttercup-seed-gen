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
# Use deterministic task_id from target name (must match builder-default.sh)
TASK_ID="${OSS_CRS_TARGET:-$PROJECT_NAME}"

echo "[builder-coverage] Starting coverage build..."
echo "[builder-coverage] TASK_ID=$TASK_ID"
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
OSS_FUZZ_SUBDIR="$FUZZ_TOOLING/oss-fuzz"
BUILD_OUT="$OSS_FUZZ_SUBDIR/build/out/$PROJECT_NAME"
mkdir -p "$BUILD_OUT"
mkdir -p "$OSS_FUZZ_SUBDIR/infra"

# Create helper.py with coverage support
cat > "$OSS_FUZZ_SUBDIR/infra/helper.py" << 'HELPER_EOF'
#!/usr/bin/env python3
"""OSS-CRS helper.py - coverage command implementation."""

import os
import subprocess
import sys
import tempfile
from pathlib import Path


def get_build_out(project: str) -> Path:
    """Get the build output directory."""
    script_dir = Path(__file__).parent
    build_out = script_dir.parent / "build" / "out" / project
    if build_out.exists():
        return build_out
    return script_dir.parent / "build" / "out"


def find_harness(project: str, fuzzer: str) -> Path | None:
    """Find the harness binary in the build output directory."""
    build_out = get_build_out(project)
    harness_path = build_out / fuzzer
    if harness_path.exists() and harness_path.is_file():
        return harness_path
    script_dir = Path(__file__).parent
    harness_path = script_dir.parent / "build" / "out" / fuzzer
    if harness_path.exists() and harness_path.is_file():
        return harness_path
    return None


def coverage(project: str, fuzz_target: str, corpus_dir: str) -> int:
    """Run coverage collection on corpus files."""
    print(f"DEBUG: coverage called with project={project}, fuzz_target={fuzz_target}, corpus_dir={corpus_dir}", file=sys.stderr)

    harness = find_harness(project, fuzz_target)
    print(f"DEBUG: find_harness returned: {harness}", file=sys.stderr)
    if harness is None:
        print(f"ERROR: Could not find harness {fuzz_target} for project {project}", file=sys.stderr)
        return 1

    if not os.path.isdir(corpus_dir):
        print(f"ERROR: Corpus directory not found: {corpus_dir}", file=sys.stderr)
        return 1

    build_out = get_build_out(project)
    print(f"DEBUG: build_out={build_out}", file=sys.stderr)
    dumps_dir = build_out / "dumps"
    dumps_dir.mkdir(parents=True, exist_ok=True)

    corpus_files = [item for item in Path(corpus_dir).iterdir() if item.is_file()]
    print(f"DEBUG: Found {len(corpus_files)} corpus files in {corpus_dir}", file=sys.stderr)

    if not corpus_files:
        print(f"WARNING: No corpus files found in {corpus_dir}", file=sys.stderr)
        merged_profdata = dumps_dir / "merged.profdata"
        merged_profdata.touch()
        return 0

    print(f"Running coverage on {len(corpus_files)} corpus files...", file=sys.stderr)

    with tempfile.TemporaryDirectory() as profraw_dir:
        profraw_files = []

        for i, corpus_file in enumerate(corpus_files):
            profraw_path = Path(profraw_dir) / f"corpus_{i}.profraw"
            env = os.environ.copy()
            env["LLVM_PROFILE_FILE"] = str(profraw_path)

            try:
                subprocess.run(
                    [str(harness), str(corpus_file)],
                    env=env,
                    timeout=30,
                    capture_output=True,
                )
                if profraw_path.exists():
                    profraw_files.append(profraw_path)
            except subprocess.TimeoutExpired:
                if profraw_path.exists():
                    profraw_files.append(profraw_path)
            except Exception as e:
                print(f"WARNING: Error running corpus file {corpus_file}: {e}", file=sys.stderr)

        if not profraw_files:
            print("WARNING: No profraw files generated", file=sys.stderr)
            merged_profdata = dumps_dir / "merged.profdata"
            merged_profdata.touch()
            return 0

        print(f"Generated {len(profraw_files)} profraw files, merging...", file=sys.stderr)

        merged_profdata = dumps_dir / "merged.profdata"

        # Try to find llvm-profdata: first in build_out, then in PATH
        llvm_profdata_local = build_out / "llvm-profdata"
        if llvm_profdata_local.exists():
            llvm_profdata = str(llvm_profdata_local)
            print(f"DEBUG: Using local llvm-profdata: {llvm_profdata}", file=sys.stderr)
        else:
            llvm_profdata = "llvm-profdata"
            print(f"DEBUG: Using system llvm-profdata", file=sys.stderr)

        merge_cmd = [llvm_profdata, "merge", "-sparse", "-o", str(merged_profdata)]
        merge_cmd.extend(str(p) for p in profraw_files)

        try:
            result = subprocess.run(merge_cmd, capture_output=True)
            if result.returncode != 0:
                print(f"ERROR: llvm-profdata merge failed: {result.stderr.decode()}", file=sys.stderr)
                return 1
        except FileNotFoundError:
            print(f"ERROR: llvm-profdata not found (tried {llvm_profdata})", file=sys.stderr)
            return 1

    print(f"Coverage data written to {merged_profdata}", file=sys.stderr)
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: helper.py <command> [args...]", file=sys.stderr)
        return 1

    command = sys.argv[1]

    if command == "coverage":
        args = sys.argv[2:]
        corpus_dir = None
        fuzz_target = None
        project = None
        i = 0
        while i < len(args):
            arg = args[i]
            if arg == "--corpus-dir" and i + 1 < len(args):
                corpus_dir = args[i + 1]
                i += 2
            elif arg == "--fuzz-target" and i + 1 < len(args):
                fuzz_target = args[i + 1]
                i += 2
            elif arg in ("--architecture", "-e"):
                i += 2
            elif arg in ("--no-serve",):
                i += 1
            elif arg.startswith("-"):
                i += 1
            else:
                project = arg
                i += 1

        if not all([project, fuzz_target, corpus_dir]):
            print(f"Usage: helper.py coverage --fuzz-target <target> --corpus-dir <dir> <project>", file=sys.stderr)
            return 1

        return coverage(project, fuzz_target, corpus_dir)

    else:
        print(f"OSS-CRS stub helper - command '{command}' is a no-op", file=sys.stderr)
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

# Copy LLVM tools to BUILD_OUT so helper.py can find them
# Note: LLVM tools are in /usr/local/bin in OSS-Fuzz base images
if [ -f /usr/local/bin/llvm-profdata ]; then
    cp /usr/local/bin/llvm-profdata "$BUILD_OUT/"
    echo "[builder-coverage] Copied llvm-profdata from /usr/local/bin"
elif [ -f /usr/bin/llvm-profdata ]; then
    cp /usr/bin/llvm-profdata "$BUILD_OUT/"
    echo "[builder-coverage] Copied llvm-profdata from /usr/bin"
else
    echo "[builder-coverage] WARNING: llvm-profdata not found"
fi

if [ -f /usr/local/bin/llvm-cov ]; then
    cp /usr/local/bin/llvm-cov "$BUILD_OUT/"
    echo "[builder-coverage] Copied llvm-cov from /usr/local/bin"
elif [ -f /usr/bin/llvm-cov ]; then
    cp /usr/bin/llvm-cov "$BUILD_OUT/"
    echo "[builder-coverage] Copied llvm-cov from /usr/bin"
else
    echo "[builder-coverage] WARNING: llvm-cov not found"
fi

# Ensure fuzz targets are executable (for cross-filesystem copies)
find "$BUILD_OUT" -maxdepth 1 -type f ! -name "*.a" ! -name "*.o" ! -name "*.so" ! -name "*.options" ! -name "*.dict" -exec chmod +x {} \;
echo "[builder-coverage] Set execute permissions on fuzz targets"

echo "[builder-coverage] Coverage build complete."
echo "[builder-coverage] Artifacts in /artifacts/coverage/"
ls -la /artifacts/coverage/ | head -20

# Submit coverage build output via libCRS
libCRS submit-build-output "$TASK_DIR" task-coverage

echo "[builder-coverage] Coverage build submitted via libCRS"
