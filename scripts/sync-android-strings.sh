#!/usr/bin/env bash
# Copies the Android parent app's strings into NozirKit/l10n/android and
# regenerates L10n.generated.swift. Run after the Android strings change.
# Usage: ./scripts/sync-android-strings.sh [path/to/NozirParent]
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="${1:-$HOME/AndroidStudioProjects/NozirParent}/app/src/main/res"
for folder in values values-en values-ru; do
  mkdir -p "NozirKit/l10n/android/$folder"
  cp "$SOURCE/$folder/strings.xml" "NozirKit/l10n/android/$folder/strings.xml"
done
python3 scripts/gen_l10n.py
