#!/usr/bin/env bash
# Runs the NozirKit test suite on an iOS simulator and prints the tail of the log.
# Usage: ./scripts/test.sh [TestTarget]   e.g. ./scripts/test.sh NozirNetworkingTests
set -euo pipefail
cd "$(dirname "$0")/../NozirKit"
SCHEME="${NOZIR_SCHEME:-NozirKit}"
DESTINATION="${NOZIR_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
ONLY=()
if [[ $# -gt 0 ]]; then ONLY=(-only-testing:"$1"); fi
# ${ONLY[@]+...}: macOS ships bash 3.2, where an empty array under `set -u` is an error.
xcodebuild test -scheme "$SCHEME" -destination "$DESTINATION" ${ONLY[@]+"${ONLY[@]}"} 2>&1 | tail -60
