#!/bin/bash
set -eu

# Buttercup Bug-Finding CRS Entrypoint
# Starts Redis and runs the full Buttercup fuzzing pipeline

echo "=== Buttercup Bug-Finding CRS ==="
echo "Starting services..."

# Create required directories
mkdir -p /tmp/buttercup/scratch
mkdir -p /tmp/seedgen
mkdir -p /artifacts/povs
mkdir -p /artifacts/corpus

# Start Redis in background
echo "Starting Redis..."
redis-server --daemonize yes --dir /tmp

# Wait for Redis to be ready
until redis-cli ping > /dev/null 2>&1; do
    sleep 0.1
done
echo "Redis is ready"

# Export Redis URL for Buttercup components
export REDIS_URL="redis://127.0.0.1:6379"
export BUTTERCUP_SEED_GEN_SERVER__REDIS_URL="$REDIS_URL"
export BUTTERCUP_FUZZER_REDIS_URL="$REDIS_URL"

# Run the main Python orchestrator
exec python3 /app/scripts/run_buttercup.py "$@"
