#!/bin/bash
# scan.sh - Scan all container images with Trivy
# Uso: bash scan.sh [--server] [--summary]
set -euo pipefail

C='\033[0;36m'; Y='\033[1;33m'; R='\033[0;31m'; G='\033[0;32m'; N='\033[0m'
info() { echo -e "${C}[INFO]${N} $1"; }
pass() { echo -e "${G}[PASS]${N} $1"; }
warn() { echo -e "${Y}[WARN]${N} $1"; }
fail() { echo -e "${R}[FAIL]${N} $1"; }

SERVER_MODE=false
SUMMARY=false
for arg in "$@"; do
  [ "$arg" = "--server" ] && SERVER_MODE=true
  [ "$arg" = "--summary" ] && SUMMARY=true
done

IMAGES=$(grep '^\s*image:' docker-compose.yml | awk '{print $2}' | sort -u)
TOTAL=$(echo "$IMAGES" | wc -l)

info "Images to scan ($TOTAL):"
echo "$IMAGES" | sed 's/^/  - /'
echo ""

if $SERVER_MODE; then
  info "Starting Trivy server in background..."
  docker rm -f lab-trivy 2>/dev/null || true
  docker run -d --name lab-trivy \
    -p 9999:9999 \
    -v trivy_cache:/root/.cache/ \
    aquasec/trivy:latest server --listen 0.0.0.0:9999
  info "Trivy server running at http://localhost:9999"
  info "Run again without --server to scan using this cache."
  exit 0
fi

TRIVY_CMD="docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy_cache:/root/.cache/ aquasec/trivy:latest"
if $SUMMARY; then
  TRIVY_CMD="$TRIVY_CMD image --severity HIGH,CRITICAL --no-progress --exit-code 0"
else
  TRIVY_CMD="$TRIVY_CMD image --no-progress --exit-code 0"
fi

if curl -sf http://localhost:9999/health >/dev/null 2>&1; then
  info "Using Trivy server at http://localhost:9999 for caching..."
  TRIVY_CMD="$TRIVY_CMD --server http://localhost:9999"
fi

SCAN_LOG="/tmp/trivy-scan-$(date +%s).log"
HIGH=0
CRIT=0
FAILED=0

for IMG in $IMAGES; do
  echo -e "\n${C}────────────────────────────────────────────────${N}"
  info "Scanning: $IMG"
  echo -e "${C}────────────────────────────────────────────────${N}"
  if $TRIVY_CMD "$IMG" 2>&1 | tee -a "$SCAN_LOG" | grep -E "HIGH|CRITICAL|Total:" | sed 's/^/  /'; then
    COUNT_H=$(grep -c "HIGH" <<< "$(grep -A5 "Total:" "$SCAN_LOG" 2>/dev/null)" 2>/dev/null || echo 0)
    COUNT_C=$(grep -c "CRITICAL" <<< "$(grep -A5 "Total:" "$SCAN_LOG" 2>/dev/null)" 2>/dev/null || echo 0)
    HIGH=$((HIGH + COUNT_H))
    CRIT=$((CRIT + COUNT_C))
  else
    warn "Scan failed or no results for $IMG"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
info "Scan complete. Log: $SCAN_LOG"
if [ "$HIGH" -gt 0 ] || [ "$CRIT" -gt 0 ]; then
  warn "HIGH: $HIGH | CRITICAL: $CRIT"
else
  pass "No HIGH/CRITICAL vulnerabilities found."
fi
[ "$FAILED" -gt 0 ] && warn "Failed scans: $FAILED"
