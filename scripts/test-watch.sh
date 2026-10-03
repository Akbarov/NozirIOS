#!/usr/bin/env bash
# Runs checks on request, so an assistant without Xcode can run the tests.
# Start once and leave it open:   ./scripts/test-watch.sh   (Ctrl+C stops it)
#
# A request is the file .superpowers/test-request containing "<what> <id>", where
# <what> is one of: all | app | <Name>Tests. Anything else is refused.
# The result goes to .superpowers/test-result.log (written whole, after the run).
set -u
cd "$(dirname "$0")/.."
REQUEST=.superpowers/test-request
RESULT=.superpowers/test-result.log
mkdir -p .superpowers
echo "Watching $REQUEST — leave this window open (Ctrl+C to stop)."
while true; do
  if [[ -f "$REQUEST" ]]; then
    read -r what id < "$REQUEST" || true
    rm -f "$REQUEST"
    echo "$(date '+%H:%M:%S') running: ${what:-?} (${id:-no id})"
    {
      echo "### request ${what:-?} ${id:-} started $(date '+%H:%M:%S')"
      status=0
      case "${what:-}" in
        all) ./scripts/test.sh || status=$? ;;
        app) xcodebuild build -project Nozir.xcodeproj -scheme Nozir \
               -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -40
             status=${PIPESTATUS[0]} ;;
        *)   if [[ "${what:-}" =~ ^[A-Za-z]+Tests$ ]]; then ./scripts/test.sh "$what" || status=$?
             else echo "refused: '${what:-}'"; status=2; fi ;;
      esac
      echo "### done ${id:-} exit=$status"
    } > "$RESULT.tmp" 2>&1
    mv -f "$RESULT.tmp" "$RESULT"
    echo "$(date '+%H:%M:%S') done (exit $status)"
  fi
  sleep 2
done
