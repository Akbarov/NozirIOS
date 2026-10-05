#!/usr/bin/env bash
# Runs checks on request, so an assistant without Xcode can run the tests.
# Start once and leave it open:   ./scripts/test-watch.sh   (Ctrl+C stops it)
#
# A request is the file .superpowers/test-request containing "<what> <id>", where
# <what> is one of: all | app | <Name>Tests. Anything else is refused.
# The result goes to .superpowers/test-result.log (written whole, after the run);
# the full log streams to .superpowers/test-live.log while it runs.
# A run longer than NOZIR_RUN_LIMIT seconds (default 600) is killed and reported.
set -u
set -m   # background jobs get their own process group, so a hung run can be killed whole
cd "$(dirname "$0")/.."
REQUEST=.superpowers/test-request
RESULT=.superpowers/test-result.log
LIVE=.superpowers/test-live.log
LIMIT="${NOZIR_RUN_LIMIT:-600}"
mkdir -p .superpowers
echo "Watching $REQUEST — leave this window open (Ctrl+C to stop)."
while true; do
  if [[ -f "$REQUEST" ]]; then
    read -r what id < "$REQUEST" || true
    rm -f "$REQUEST"
    echo "$(date '+%H:%M:%S') running: ${what:-?} (${id:-no id})"
    : > "$LIVE"
    case "${what:-}" in
      all) cmd=(./scripts/test.sh) ;;
      app) cmd=(bash -c "xcodebuild build -project Nozir.xcodeproj -scheme Nozir -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | tee $LIVE | tail -40; exit \${PIPESTATUS[0]}") ;;
      *)   if [[ "${what:-}" =~ ^[A-Za-z]+Tests$ ]]; then cmd=(./scripts/test.sh "$what"); else cmd=(); fi ;;
    esac
    {
      echo "### request ${what:-?} ${id:-} started $(date '+%H:%M:%S')"
      if [[ ${#cmd[@]} -eq 0 ]]; then
        echo "refused: '${what:-}'"; status=2
      else
        NOZIR_FULL_LOG="$LIVE" "${cmd[@]}" &
        pid=$!; waited=0
        while kill -0 "$pid" 2>/dev/null && (( waited < LIMIT )); do sleep 2; waited=$((waited + 2)); done
        if kill -0 "$pid" 2>/dev/null; then
          kill -TERM -- "-$pid" 2>/dev/null; sleep 2; kill -KILL -- "-$pid" 2>/dev/null
          echo "TIMEOUT after ${LIMIT}s — last lines of the live log:"; tail -30 "$LIVE"
          status=124
        else
          wait "$pid"; status=$?
        fi
      fi
      echo "### done ${id:-} exit=$status"
    } > "$RESULT.tmp" 2>&1
    mv -f "$RESULT.tmp" "$RESULT"
    echo "$(date '+%H:%M:%S') done (exit $status)"
  fi
  sleep 2
done
