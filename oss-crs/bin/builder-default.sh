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
# Use deterministic task_id from target name (builds run in parallel, can't share state)
TASK_ID="${OSS_CRS_TARGET:-$PROJECT_NAME}"

echo "[builder-default] Starting ASan build..."
echo "[builder-default] TASK_ID=$TASK_ID"
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
# where get_oss_fuzz_subpath() returns the first subdir under fuzz-tooling/ (oss-fuzz)
# and get_build_dir() returns get_oss_fuzz_path() / "build" / "out" / project_name
FUZZ_TOOLING="$TASK_DIR/fuzz-tooling"
OSS_FUZZ_SUBDIR="$FUZZ_TOOLING/oss-fuzz"
BUILD_OUT="$OSS_FUZZ_SUBDIR/build/out/$PROJECT_NAME"
mkdir -p "$BUILD_OUT"
mkdir -p "$OSS_FUZZ_SUBDIR/infra"

# 4. Create stub helper.py (ChallengeTask requires this file to exist)
# This implements 'reproduce' and 'coverage' commands for tracer-bot and coverage-bot
cat > "$OSS_FUZZ_SUBDIR/infra/helper.py" << 'HELPEREOF'
#!/usr/bin/env python3
"""OSS-CRS helper.py - minimal implementation for reproduce and coverage.

This stub implements:
- 'reproduce' command for tracer-bot crash validation
- 'coverage' command for coverage-bot analysis
Other commands are no-ops since builds are pre-compiled.
"""

import glob
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def get_build_out(project: str) -> Path:
    """Get the build output directory."""
    script_dir = Path(__file__).parent
    # Try project subdirectory first
    build_out = script_dir.parent / "build" / "out" / project
    if build_out.exists():
        return build_out
    # Fall back to flat structure
    return script_dir.parent / "build" / "out"


def find_harness(project: str, fuzzer: str) -> Path | None:
    """Find the harness binary in the build output directory."""
    build_out = get_build_out(project)
    harness_path = build_out / fuzzer
    if harness_path.exists() and harness_path.is_file():
        return harness_path
    # Also check flat structure (harness directly in build/out/)
    script_dir = Path(__file__).parent
    harness_path = script_dir.parent / "build" / "out" / fuzzer
    if harness_path.exists() and harness_path.is_file():
        return harness_path
    return None


def coverage(project: str, fuzz_target: str, corpus_dir: str) -> int:
    """Run coverage collection on corpus files.

    This runs the coverage-instrumented harness with each corpus file,
    generates profraw files, and merges them into merged.profdata.
    """
    harness = find_harness(project, fuzz_target)
    if harness is None:
        print(f"ERROR: Could not find harness {fuzz_target} for project {project}", file=sys.stderr)
        return 1

    if not os.path.isdir(corpus_dir):
        print(f"ERROR: Corpus directory not found: {corpus_dir}", file=sys.stderr)
        return 1

    build_out = get_build_out(project)
    dumps_dir = build_out / "dumps"
    dumps_dir.mkdir(parents=True, exist_ok=True)

    # Find all corpus files
    corpus_files = []
    for item in Path(corpus_dir).iterdir():
        if item.is_file():
            corpus_files.append(item)

    if not corpus_files:
        print(f"WARNING: No corpus files found in {corpus_dir}", file=sys.stderr)
        # Create empty profdata so coverage_runner doesn't fail
        merged_profdata = dumps_dir / "merged.profdata"
        merged_profdata.touch()
        return 0

    print(f"Running coverage on {len(corpus_files)} corpus files...", file=sys.stderr)

    # Create temp directory for profraw files
    with tempfile.TemporaryDirectory() as profraw_dir:
        profraw_files = []

        # Run harness with each corpus file
        for i, corpus_file in enumerate(corpus_files):
            profraw_path = Path(profraw_dir) / f"corpus_{i}.profraw"
            env = os.environ.copy()
            env["LLVM_PROFILE_FILE"] = str(profraw_path)

            try:
                # Run with timeout, ignore crashes (we just want coverage)
                result = subprocess.run(
                    [str(harness), str(corpus_file)],
                    env=env,
                    timeout=30,
                    capture_output=True,
                )
                if profraw_path.exists():
                    profraw_files.append(profraw_path)
            except subprocess.TimeoutExpired:
                # Timeout is fine, check if profraw was generated
                if profraw_path.exists():
                    profraw_files.append(profraw_path)
            except Exception as e:
                print(f"WARNING: Error running corpus file {corpus_file}: {e}", file=sys.stderr)

        if not profraw_files:
            print("WARNING: No profraw files generated", file=sys.stderr)
            # Create empty profdata
            merged_profdata = dumps_dir / "merged.profdata"
            merged_profdata.touch()
            return 0

        print(f"Generated {len(profraw_files)} profraw files, merging...", file=sys.stderr)

        # Merge profraw files into profdata
        merged_profdata = dumps_dir / "merged.profdata"

        # Try to find llvm-profdata: first in build_out, then in PATH
        llvm_profdata_local = build_out / "llvm-profdata"
        if llvm_profdata_local.exists():
            llvm_profdata = str(llvm_profdata_local)
        else:
            llvm_profdata = "llvm-profdata"

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


def reproduce(project: str, fuzzer: str, testcase: str, timeout: int = 120) -> int:
    """Reproduce a crash by running the harness with the testcase."""
    harness = find_harness(project, fuzzer)
    if harness is None:
        print(f"ERROR: Could not find harness {fuzzer} for project {project}", file=sys.stderr)
        return 1

    if not os.path.exists(testcase):
        print(f"ERROR: Testcase not found: {testcase}", file=sys.stderr)
        return 1

    # Set up environment for ASAN
    env = os.environ.copy()
    env.setdefault("ASAN_OPTIONS", "detect_leaks=0:symbolize=1:detect_odr_violation=0")

    # Run the harness with the testcase
    # libfuzzer harnesses accept testcase as argument
    cmd = [str(harness), testcase]

    print(f"Running: {' '.join(cmd)}", file=sys.stderr)
    # Print fake seed info so did_run() returns True
    print("INFO: Seed: 0", file=sys.stdout)
    sys.stdout.flush()

    try:
        result = subprocess.run(
            cmd,
            env=env,
            timeout=timeout,
            capture_output=False,  # Let output go to stdout/stderr
        )
        return result.returncode
    except subprocess.TimeoutExpired:
        print(f"TIMEOUT after {timeout}s", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"ERROR running harness: {e}", file=sys.stderr)
        return 1


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: helper.py <command> [args...]", file=sys.stderr)
        return 1

    command = sys.argv[1]

    if command == "reproduce":
        # reproduce [options] <project> <fuzzer> <testcase>
        # Options: --architecture, -e (env), --timeout, --propagate_exit_code, --err_result
        # Parse arguments - skip options (--flag and their values)
        args = sys.argv[2:]
        positional = []
        timeout = 120
        i = 0
        while i < len(args):
            arg = args[i]
            if arg == "--timeout" and i + 1 < len(args):
                try:
                    timeout = int(args[i + 1])
                except ValueError:
                    pass
                i += 2
            elif arg in ("--architecture", "-e", "--err_result"):
                # Skip flag and its value
                i += 2
            elif arg in ("--propagate_exit_code",):
                # Skip boolean flag (no value)
                i += 1
            elif arg.startswith("-"):
                # Unknown flag, skip
                i += 1
            else:
                positional.append(arg)
                i += 1

        if len(positional) < 3:
            print(f"Usage: helper.py reproduce [options] <project> <fuzzer> <testcase>", file=sys.stderr)
            print(f"Got positional args: {positional}", file=sys.stderr)
            return 1

        project = positional[0]
        fuzzer = positional[1]
        testcase = positional[2]

        return reproduce(project, fuzzer, testcase, timeout)

    elif command == "coverage":
        # coverage [options] <project>
        # Options: --corpus-dir, --fuzz-target, --no-serve, --architecture, -e
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
                # Skip flag and its value
                i += 2
            elif arg in ("--no-serve",):
                # Skip boolean flag
                i += 1
            elif arg.startswith("-"):
                # Unknown flag, skip
                i += 1
            else:
                # Positional argument (project name)
                project = arg
                i += 1

        if not all([project, fuzz_target, corpus_dir]):
            print(f"Usage: helper.py coverage --fuzz-target <target> --corpus-dir <dir> <project>", file=sys.stderr)
            print(f"Got: project={project}, fuzz_target={fuzz_target}, corpus_dir={corpus_dir}", file=sys.stderr)
            return 1

        return coverage(project, fuzz_target, corpus_dir)

    else:
        # Other commands are no-ops (build, etc. are pre-compiled)
        print(f"OSS-CRS stub helper - command '{command}' is a no-op (builds are pre-compiled)", file=sys.stderr)
        return 0


if __name__ == "__main__":
    sys.exit(main())
HELPEREOF
chmod +x "$OSS_FUZZ_SUBDIR/infra/helper.py"
echo "[builder-default] Created helper.py with reproduce support"

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

# Submit build output via libCRS
libCRS submit-build-output "$TASK_DIR" build

echo "[builder-default] Build submitted via libCRS"
