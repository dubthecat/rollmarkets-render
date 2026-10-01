#!/usr/bin/env bash
# AI vs AI, best of three, with whatever open-licensed characters the image carries (IKEMEN_ASSETS tarball URL).
set -uo pipefail
cd /opt/ikemen || { echo "RESULT {\"game\":\"ikemen\",\"ok\":false,\"error\":\"engine missing\"}"; exit 0; }
[ -n "${IKEMEN_ASSETS:-}" ] && curl -fsSL "$IKEMEN_ASSETS" | tar -xz -C /opt/ikemen || true
timeout 600 $RUN ./Ikemen_GO -p1.ai 8 -p2.ai 8 -rounds 3 -nosound 2>&1 | tee /work/logs/ikemen.log | tail -20
echo "RESULT {\"game\":\"ikemen\",\"ok\":false,\"error\":\"result parsing pending\"}"
