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
import logging
import os
import subprocess
import sys
import tempfile
import yaml
from pathlib import Path

# Configure logging for coverage helper
logging.basicConfig(
    level=logging.INFO,
    format='[COVERAGE] %(levelname)s: %(message)s',
    stream=sys.stderr
)
logger = logging.getLogger('coverage_helper')


def get_project_language(project_name: str) -> str:
    """Detect language from project.yaml, default to 'c'."""
    helper_dir = Path(__file__).parent.parent  # oss-fuzz/
    project_yaml = helper_dir / "projects" / project_name / "project.yaml"
    logger.info(f"Language detection: checking {project_yaml}")
    if project_yaml.exists():
        with open(project_yaml) as f:
            config = yaml.safe_load(f)
            language = config.get("language", "c").lower()
            logger.info(f"Detected language '{language}' for project '{project_name}'")
            return language
    logger.warning(f"No project.yaml found at {project_yaml}, defaulting to 'c'")
    return "c"


def run_java_coverage(project_name: str, fuzz_target: str, corpus_dir: str,
                      build_dir: Path, no_serve: bool = True) -> int:
    """Run Java coverage using JaCoCo agent and CLI."""
    harness_path = build_dir / fuzz_target
    corpus_path = Path(corpus_dir)

    if not corpus_path.exists() or not list(corpus_path.iterdir()):
        print(f"Warning: No corpus files in {corpus_dir}", file=sys.stderr)
        return 0

    dumps_dir = build_dir / "dumps"
    dumps_dir.mkdir(parents=True, exist_ok=True)

    # JaCoCo output paths
    exec_file = dumps_dir / f"{fuzz_target}.exec"
    class_dump_dir = dumps_dir / "classes"
    class_dump_dir.mkdir(parents=True, exist_ok=True)
    xml_report = dumps_dir / f"{fuzz_target}.xml"

    # JaCoCo agent arguments (imitate OSS-Fuzz pattern)
    jacoco_args = f"destfile={exec_file},classdumpdir={class_dump_dir},excludes=com.code_intelligence.jazzer.*"

    # Run Jazzer with JaCoCo agent against corpus
    # Use -merge=1 to process all corpus files in one run
    jazzer_cmd = [
        str(harness_path),
        "-merge=1",
        "-timeout=100",
        "--nohooks",
        f"--additional_jvm_args=-javaagent:/opt/jacoco-agent.jar={jacoco_args}",
        str(corpus_path),
    ]

    print(f"Running Jazzer with JaCoCo: {' '.join(jazzer_cmd)}", file=sys.stderr)
    result = subprocess.run(jazzer_cmd, capture_output=True, text=True)

    if not exec_file.exists():
        print(f"Error: JaCoCo exec file not created at {exec_file}", file=sys.stderr)
        return 1

    # Generate XML report using JaCoCo CLI
    cli_cmd = [
        "java", "-jar", "/opt/jacoco-cli.jar",
        "report", str(exec_file),
        "--xml", str(xml_report),
        "--classfiles", str(class_dump_dir),
    ]

    print(f"Generating XML report: {' '.join(cli_cmd)}", file=sys.stderr)
    result = subprocess.run(cli_cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"Error generating XML report: {result.stderr}", file=sys.stderr)
        return 1

    print(f"Coverage XML written to {xml_report}", file=sys.stderr)
    return 0


def run_coverage(project_name: str, fuzz_target: str, corpus_dir: str,
                 build_dir: Path, no_serve: bool = True) -> int:
    """Run coverage analysis on the given fuzz target."""
    # Detect language and dispatch to appropriate handler
    language = get_project_language(project_name)

    if language in ("java", "jvm"):
        logger.info(f"Dispatching to JAVA coverage path for '{fuzz_target}'")
        return run_java_coverage(project_name, fuzz_target, corpus_dir, build_dir, no_serve)

    logger.info(f"Dispatching to C/C++ LLVM coverage path for '{fuzz_target}'")
    # Existing C/C++ LLVM coverage logic follows
    logger.info(f"=== C/C++ Coverage Start ===")
    logger.info(f"  Project: {project_name}")
    logger.info(f"  Target:  {fuzz_target}")
    logger.info(f"  Corpus:  {corpus_dir}")
    logger.info(f"  Build:   {build_dir}")

    harness_path = build_dir / fuzz_target
    if not harness_path.exists():
        logger.error(f"Harness not found at {harness_path}")
        return 1
    logger.info(f"Harness found: {harness_path}")

    corpus_path = Path(corpus_dir)
    if not corpus_path.exists():
        logger.error(f"Corpus directory not found: {corpus_dir}")
        return 1

    corpus_files = list(corpus_path.iterdir())
    if not corpus_files:
        logger.warning(f"No corpus files in {corpus_dir}, creating empty profdata")
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

    logger.info(f"Processing {len(corpus_files)} corpus files")

    # Create dumps directory for profraw files
    dumps_dir = build_dir / "dumps"
    dumps_dir.mkdir(parents=True, exist_ok=True)

    # Run harness against each corpus file with coverage instrumentation
    profraw_dir = dumps_dir / "profraw"
    profraw_dir.mkdir(parents=True, exist_ok=True)

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
            logger.debug(f"  Timeout on {corpus_file.name}")
        except Exception as e:
            logger.debug(f"  Error on {corpus_file.name}: {e}")

        # Log progress every 100 files
        if (i + 1) % 100 == 0:
            logger.info(f"  Processed {i + 1}/{len(corpus_files)} corpus files")

    logger.info(f"Processed all {len(corpus_files)} corpus files")

    # Merge all profraw files into profdata
    profraw_files = list(profraw_dir.glob("*.profraw"))
    if not profraw_files:
        logger.error("No profraw files generated")
        return 1

    profdata_path = dumps_dir / "merged.profdata"
    logger.info(f"Merging {len(profraw_files)} profraw files to {profdata_path}")

    # Use local llvm-profdata from build dir if available (matches build LLVM version)
    local_profdata = build_dir / "llvm-profdata"
    profdata_cmd = str(local_profdata) if local_profdata.exists() else "llvm-profdata"

    merge_cmd = [profdata_cmd, "merge", "-sparse", "-o", str(profdata_path)]
    merge_cmd.extend(str(f) for f in profraw_files)

    result = subprocess.run(merge_cmd, capture_output=True, text=True)
    if result.returncode != 0:
        logger.error(f"llvm-profdata merge failed: {result.stderr}")
        return 1

    logger.info(f"Profdata created: {profdata_path} ({profdata_path.stat().st_size} bytes)")
    logger.info(f"=== C/C++ Coverage Complete ===")
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
