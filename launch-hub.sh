#!/bin/bash
# Research Hub — launchd wrapper
# Stays in foreground (launchd monitors the PID).
# Spawns all 3 services and restarts any that die.

set -e

TR_DIR="/Users/melawigide/TrendRadar"
CA_DIR="/Users/melawigide/Downloads/chokepoint-atlas"
PYTHON="/Users/melawigide/TrendRadar/.venv/bin/python"
LOG_DIR="$TR_DIR/logs"

mkdir -p "$LOG_DIR"

# Start a service and track its PID
start_service() {
    local name="$1"
    local pid_var="${2}"
    shift 2
    "$@" >> "$LOG_DIR/${name}.log" 2>&1 &
    eval "$pid_var=$!"
    echo "started $name (PID $!)"
}

echo "=== Research Hub launchd wrapper starting ==="
echo "$(date)"

# Check CA is already running (from separate launchd or dev session)
CA_ALIVE=0
curl -s -o /dev/null http://localhost:3000 2>/dev/null && CA_ALIVE=1

if [ "$CA_ALIVE" -eq 0 ]; then
    cd "$CA_DIR" && npx next dev --port 3000 &
    CA_PID=$!
    echo "started chokepoint-atlas (PID $CA_PID)"
else
    echo "chokepoint-atlas already running"
    CA_PID=0
fi

cd "$TR_DIR"
source .venv/bin/activate

# Start TrendRadar server
"$PYTHON" server.py &
TR_PID=$!
echo "started trendradar (PID $TR_PID)"

# Start Hub server
"$PYTHON" hub_server.py &
HUB_PID=$!
echo "started hub (PID $HUB_PID)"

echo "=== All services started ==="
echo "Hub: :9000 | TrendRadar: :8080 | Chokepoint: :3000"
echo "Logs: $LOG_DIR"

# Monitor — restart any that die, loop forever (launchd watches this PID)
while true; do
    sleep 15

    if ! kill -0 "$TR_PID" 2>/dev/null; then
        echo "$(date) TrendRadar died, restarting..."
        cd "$TR_DIR" && source .venv/bin/activate && "$PYTHON" server.py &
        TR_PID=$!
        echo "restarted trendradar (PID $TR_PID)"
    fi

    if ! kill -0 "$HUB_PID" 2>/dev/null; then
        echo "$(date) Hub died, restarting..."
        cd "$TR_DIR" && source .venv/bin/activate && "$PYTHON" hub_server.py &
        HUB_PID=$!
        echo "restarted hub (PID $HUB_PID)"
    fi
done
