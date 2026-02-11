#!/bin/bash
# Build codequery indexes for seed-gen
#
# Expects builder-default.sh to have run first (creates /artifacts/task)
# Creates codequery indexes in /artifacts/task/container_src_dir/
#
# This allows seed-gen to skip the docker-based source extraction step.

set -e

PROJECT_NAME="${PROJECT_NAME:-$(basename $SRC)}"
TASK_DIR="/artifacts/task"

echo "[builder-codequery] Starting codequery index build..."
echo "[builder-codequery] PROJECT_NAME=$PROJECT_NAME"

# Download task from libCRS (created by builder-default.sh in previous phase)
echo "[builder-codequery] Downloading task from libCRS..."
libCRS download-build-output task "$TASK_DIR" || {
    echo "[builder-codequery] WARNING: Could not download task from libCRS, checking if exists locally..."
}

# Check that task directory exists
if [ ! -d "$TASK_DIR" ]; then
    echo "[builder-codequery] ERROR: Task directory $TASK_DIR does not exist"
    echo "[builder-codequery] Run build phase first"
    exit 1
fi

# Create container_src_dir structure (matches CodeQuery expectations)
CONTAINER_SRC_DIR="$TASK_DIR/container_src_dir"
mkdir -p "$CONTAINER_SRC_DIR"

# Copy source from task/src to container_src_dir/src
# This mirrors what _copy_src_from_container does with docker cp
if [ -d "$TASK_DIR/src" ]; then
    echo "[builder-codequery] Copying source to container_src_dir..."
    cp -r "$TASK_DIR/src" "$CONTAINER_SRC_DIR/"
else
    echo "[builder-codequery] WARNING: No source directory at $TASK_DIR/src"
    # Try to use /src directly
    if [ -d "/src" ]; then
        echo "[builder-codequery] Using /src as source"
        cp -r /src "$CONTAINER_SRC_DIR/"
    else
        echo "[builder-codequery] ERROR: No source directory found"
        exit 1
    fi
fi

# Change to container_src_dir for index building
cd "$CONTAINER_SRC_DIR"

# Detect language from project.yaml if available
LANG="c"
PROJECT_YAML="$TASK_DIR/fuzz-tooling/oss-fuzz/projects/$PROJECT_NAME/project.yaml"
if [ -f "$PROJECT_YAML" ]; then
    DETECTED_LANG=$(grep -E "^language:" "$PROJECT_YAML" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    if [ -n "$DETECTED_LANG" ]; then
        LANG="$DETECTED_LANG"
        echo "[builder-codequery] Detected language: $LANG"
    fi
fi

# Generate cscope.files based on language
echo "[builder-codequery] Generating cscope.files for language: $LANG"
> cscope.files

case "$LANG" in
    c|c++|cpp)
        # C/C++ extensions
        find . -type f \( \
            -name "*.c" -o -name "*.cpp" -o -name "*.cxx" -o -name "*.cc" -o \
            -name "*.C" -o -name "*.c++" -o -name "*.h" -o -name "*.hpp" -o \
            -name "*.hxx" -o -name "*.hh" -o -name "*.H" -o -name "*.h++" -o \
            -name "*.inc" -o -name "*.inl" -o -name "*.ipp" -o -name "*.tpp" -o \
            -name "*.y" -o -name "*.yy" -o -name "*.l" -o -name "*.ll" -o \
            -name "*.lex" -o -name "*.yacc" -o -name "*.in" -o \
            -name "*.m" -o -name "*.mm" -o -name "*.cu" -o -name "*.cuh" \
        \) >> cscope.files
        ;;
    java|jvm)
        # Java extensions
        find . -type f \( \
            -name "*.java" -o -name "*.jsp" -o -name "*.jspx" -o \
            -name "*.tag" -o -name "*.jspf" -o -name "*.properties" -o \
            -name "*.gradle" -o -name "*.kt" -o -name "*.scala" -o \
            -name "*.groovy" -o -name "*.aj" \
        \) >> cscope.files
        ;;
    *)
        echo "[builder-codequery] WARNING: Unknown language $LANG, using C/C++ extensions"
        find . -type f \( \
            -name "*.c" -o -name "*.cpp" -o -name "*.h" -o -name "*.hpp" \
        \) >> cscope.files
        ;;
esac

FILE_COUNT=$(wc -l < cscope.files)
echo "[builder-codequery] Found $FILE_COUNT source files"

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "[builder-codequery] WARNING: No source files found, skipping index build"
    # Create empty index files to satisfy _is_already_indexed check
    touch cscope.out tags codequery.db
    exit 0
fi

# Build cscope index
# -b: build only, -k: kernel mode (no /usr/include), -c: compress (required by cqmakedb)
echo "[builder-codequery] Building cscope index..."
cscope -bkc 2>/dev/null || echo "[builder-codequery] cscope completed with warnings"

if [ ! -f "cscope.out" ]; then
    echo "[builder-codequery] ERROR: Failed to create cscope.out"
    exit 1
fi

# Build ctags index
echo "[builder-codequery] Building ctags index..."
ctags --fields=+i -n -L cscope.files 2>/dev/null || echo "[builder-codequery] ctags completed with warnings"

if [ ! -f "tags" ]; then
    echo "[builder-codequery] ERROR: Failed to create tags"
    exit 1
fi

# Build codequery database
echo "[builder-codequery] Building codequery database..."
cqmakedb -s codequery.db -c cscope.out -t tags -p 2>/dev/null || echo "[builder-codequery] cqmakedb completed with warnings"

if [ ! -f "codequery.db" ]; then
    echo "[builder-codequery] ERROR: Failed to create codequery.db"
    exit 1
fi

echo "[builder-codequery] Codequery index build complete."
echo "[builder-codequery] Index files:"
ls -la cscope.files cscope.out tags codequery.db 2>/dev/null || true

# Create cqdb output directory with tarball for seed-gen
# The tarball contains the container_src_dir with codequery indexes
TASK_ID="${TASK_ID:-oss-crs-task}"
CQDB_OUTPUT="/cqdb_output"
mkdir -p "$CQDB_OUTPUT"

CQDB_TARBALL="$CQDB_OUTPUT/${TASK_ID}.cqdb.tgz"
echo "[builder-codequery] Creating cqdb tarball at $CQDB_TARBALL..."
cd "$TASK_DIR"
tar -czf "$CQDB_TARBALL" container_src_dir/

# Submit cqdb output via libCRS
libCRS submit-build-output "$CQDB_OUTPUT" cqdb

echo "[builder-codequery] Codequery tarball created and submitted"
echo "[builder-codequery] Cqdb tarball: $CQDB_TARBALL"
