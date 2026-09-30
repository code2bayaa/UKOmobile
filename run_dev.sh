#!/usr/bin/env bash
# Run / build the Flutter port with the same env as the Expo app.
#
#   ./run_dev.sh                    -> flutter run
#   ./run_dev.sh build apk --debug  -> flutter build apk --debug
#   ENV_FILE=/path/to/.env ./run_dev.sh run -d <device>
#
# Reads ../mobile/.env, strips the EXPO_PUBLIC_ prefix and hands the variables
# to Flutter as dart-defines (read by lib/core/env.dart via String.fromEnvironment).
#
# Filtering:
#   * *_SECRET variables are ALWAYS skipped: secrets must never ship in a client.
#   * Only names that lib/core/env.dart actually declares are passed.
#   * Only the half matching ENVIRONMENT is passed: in "development" the plain
#     names, otherwise the *_LIVE names (Env/Api pick the same half at runtime).
#
# Why: Flutter forwards every define (base64) on the gradlew.bat command line;
# passing all ~157 .env entries exceeds cmd.exe's 8191-char limit on Windows
# ("The command line is too long."). The defines travel through a throwaway
# JSON file in the system temp dir (--dart-define-from-file), deleted on exit
# and never written inside the project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../mobile/.env}"
ENV_DART="$SCRIPT_DIR/lib/core/env.dart"
[[ -f "$ENV_FILE" ]] || { echo "env file not found: $ENV_FILE" >&2; exit 1; }

# names declared in env.dart
ALLOWED=" $(grep -o "fromEnvironment('[A-Z0-9_]*')" "$ENV_DART" | sed "s/fromEnvironment('//; s/')//" | tr '\n' ' ') "

# environment of the .env file
ENVIRONMENT="$(grep -E '^[[:space:]]*EXPO_PUBLIC_ENVIRONMENT=' "$ENV_FILE" | tail -1 | cut -d= -f2- | tr -d '\r"'"'" || true)"

TMP_DEFINES="$(mktemp "${TMPDIR:-/tmp}/uko_defines_XXXXXX.json")"
trap 'rm -f "$TMP_DEFINES"' EXIT

count=0
{
  echo "{"
  first=1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line// }" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"; value="${line#*=}"
    key="${key// /}"
    key="${key#EXPO_PUBLIC_}"
    [[ -z "$key" ]] && continue
    if [[ "$key" == *_SECRET ]]; then echo "skipping secret $key" >&2; continue; fi
    [[ "$ALLOWED" == *" $key "* ]] || continue
    if [[ "$key" != "ENVIRONMENT" ]]; then
      if [[ "$ENVIRONMENT" == "development" ]]; then
        [[ "$key" == *_LIVE ]] && continue
      else
        # live: drop X when X_LIVE exists
        [[ "$key" != *_LIVE && "$ALLOWED" == *" ${key}_LIVE "* ]] && continue
      fi
    fi
    if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then value="${BASH_REMATCH[1]}"; fi
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    [[ $first -eq 1 ]] || echo ","
    first=0
    printf '  "%s": "%s"' "$key" "$value"
  done < "$ENV_FILE"
  echo
  echo "}"
} > "$TMP_DEFINES"
count="$(grep -c '": "' "$TMP_DEFINES" || true)"

cd "$SCRIPT_DIR"
if [[ $# -eq 0 ]]; then set -- run; fi
echo "flutter $* --dart-define-from-file=<$count defines from $(basename "$ENV_FILE"), ENVIRONMENT=${ENVIRONMENT:-<unset>}>"
flutter "$@" --dart-define-from-file="$TMP_DEFINES"
