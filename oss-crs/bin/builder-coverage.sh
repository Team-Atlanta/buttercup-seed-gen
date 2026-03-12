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
OSS_FUZZ_SUBDIR="$FUZZ_TOOLING/oss-fuzz"
BUILD_OUT="$OSS_FUZZ_SUBDIR/build/out/$PROJECT_NAME"
mkdir -p "$BUILD_OUT"
mkdir -p "$OSS_FUZZ_SUBDIR/infra"

# Create functional coverage helper.py
# This helper runs coverage analysis by executing harness against corpus files
cat > "$OSS_FUZZ_SUBDIR/infra/helper.py" << 'HELPER_EOF'
#!/usr/bin/env python3
"""OSS-CRS coverage helper - runs coverage analysis on pre-built fuzzers."""
import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def run_coverage(project_name: str, fuzz_target: str, corpus_dir: str,
                 build_dir: Path, no_serve: bool = True) -> int:
    """Run coverage analysis on the given fuzz target."""
    harness_path = build_dir / fuzz_target
    if not harness_path.exists():
        print(f"Error: Harness not found at {harness_path}", file=sys.stderr)
        return 1

    corpus_path = Path(corpus_dir)
    if not corpus_path.exists():
        print(f"Error: Corpus directory not found: {corpus_dir}", file=sys.stderr)
        return 1

    corpus_files = list(corpus_path.iterdir())
    if not corpus_files:
        print(f"Warning: No corpus files in {corpus_dir}", file=sys.stderr)
        # Still create empty profdata for consistency
        dumps_dir = build_dir / "dumps"
        dumps_dir.mkdir(parents=True, exist_ok=True)
        profdata_path = dumps_dir / "merged.profdata"
        # Use local llvm-profdata if available
        local_profdata = build_dir / "llvm-profdata"
        profdata_cmd = str(local_profdata) if local_profdata.exists() else "llvm-profdata"
        subprocess.run([profdata_cmd, "merge", "-o", str(profdata_path)],
                       check=False, capture_output=True)
        return 0

    # Create dumps directory for profraw files
    dumps_dir = build_dir / "dumps"
    dumps_dir.mkdir(parents=True, exist_ok=True)

    # Run harness against each corpus file with coverage instrumentation
    profraw_dir = dumps_dir / "profraw"
    profraw_dir.mkdir(parents=True, exist_ok=True)

    print(f"Running coverage on {len(corpus_files)} corpus files...", file=sys.stderr)

    for i, corpus_file in enumerate(corpus_files):
        if not corpus_file.is_file():
            continue

        # Set profile output path for this run
        profraw_path = profraw_dir / f"{i}.profraw"
        env = os.environ.copy()
        env["LLVM_PROFILE_FILE"] = str(profraw_path)

        # Run harness with corpus file as input
        try:
            result = subprocess.run(
                [str(harness_path), str(corpus_file)],
                env=env,
                timeout=10,  # 10 second timeout per file
                capture_output=True,
            )
        except subprocess.TimeoutExpired:
            print(f"  Timeout on {corpus_file.name}", file=sys.stderr)
        except Exception as e:
            print(f"  Error on {corpus_file.name}: {e}", file=sys.stderr)

    # Merge all profraw files into profdata
    profraw_files = list(profraw_dir.glob("*.profraw"))
    if not profraw_files:
        print("Warning: No profraw files generated", file=sys.stderr)
        return 1

    profdata_path = dumps_dir / "merged.profdata"
    print(f"Merging {len(profraw_files)} profraw files...", file=sys.stderr)

    # Use local llvm-profdata from build dir if available (matches build LLVM version)
    local_profdata = build_dir / "llvm-profdata"
    profdata_cmd = str(local_profdata) if local_profdata.exists() else "llvm-profdata"

    merge_cmd = [profdata_cmd, "merge", "-sparse", "-o", str(profdata_path)]
    merge_cmd.extend(str(f) for f in profraw_files)

    result = subprocess.run(merge_cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error merging profraw files: {result.stderr}", file=sys.stderr)
        return 1

    print(f"Coverage profdata written to {profdata_path}", file=sys.stderr)
    return 0


def main():
    parser = argparse.ArgumentParser(description="OSS-CRS coverage helper")
    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # Coverage command
    cov_parser = subparsers.add_parser("coverage", help="Run coverage analysis")
    cov_parser.add_argument("project_name", help="Project name")
    cov_parser.add_argument("--corpus-dir", required=True, help="Corpus directory")
    cov_parser.add_argument("--fuzz-target", required=True, help="Fuzz target name")
    cov_parser.add_argument("--no-serve", action="store_true", help="Don't serve results")
    cov_parser.add_argument("--architecture", default="x86_64", help="Architecture")
    cov_parser.add_argument("-e", action="append", help="Environment variables")

    args = parser.parse_args()

    if args.command == "coverage":
        # Find build directory relative to helper location
        helper_dir = Path(__file__).parent.parent  # Go from infra/ to oss-fuzz/
        build_dir = helper_dir / "build" / "out" / args.project_name

        if not build_dir.exists():
            print(f"Error: Build directory not found: {build_dir}", file=sys.stderr)
            return 1

        return run_coverage(
            args.project_name,
            args.fuzz_target,
            args.corpus_dir,
            build_dir,
            args.no_serve,
        )
    else:
        print(f"Unknown command: {args.command}", file=sys.stderr)
        return 1


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

# Copy LLVM tools needed for coverage analysis into BUILD_OUT
# These need to be in the build output so the coverage helper can use them
# (version must match what was used to build the coverage-instrumented binaries)
# OSS-Fuzz base images have these in /usr/local/bin/
for llvm_tool in llvm-profdata llvm-cov; do
    if [ -f "/usr/local/bin/$llvm_tool" ]; then
        cp "/usr/local/bin/$llvm_tool" "$BUILD_OUT/"
        echo "[builder-coverage] Copied $llvm_tool from /usr/local/bin"
    elif [ -f "/usr/bin/$llvm_tool" ]; then
        cp "/usr/bin/$llvm_tool" "$BUILD_OUT/"
        echo "[builder-coverage] Copied $llvm_tool from /usr/bin"
    elif command -v "$llvm_tool" >/dev/null 2>&1; then
        cp "$(command -v $llvm_tool)" "$BUILD_OUT/"
        echo "[builder-coverage] Copied $llvm_tool from PATH"
    else
        echo "[builder-coverage] WARNING: $llvm_tool not found"
    fi
done

echo "[builder-coverage] Coverage build complete."
echo "[builder-coverage] Artifacts in /artifacts/coverage/"
ls -la /artifacts/coverage/ | head -20

# Submit coverage build output via libCRS
libCRS submit-build-output "$TASK_DIR" task-coverage

echo "[builder-coverage] Coverage build submitted via libCRS"
