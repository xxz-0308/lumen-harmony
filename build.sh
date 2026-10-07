#!/usr/bin/env bash
# Build an unsigned Release HAP unless local signing has been configured.
set -euo pipefail
cd "$(dirname "$0")"
if [[ -n "${DEVECO_HOME:-}" ]]; then
  home="$DEVECO_HOME"
  if command -v cygpath >/dev/null 2>&1; then home=$(cygpath -u "$home"); fi
  export PATH="$home/tools/node:$home/tools/ohpm/bin:$home/tools/hvigor/bin:$PATH"
  sdk="$home/sdk"
  if command -v cygpath >/dev/null 2>&1; then sdk=$(cygpath -m "$sdk"); fi
  export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$sdk}"
fi
if command -v hvigorw >/dev/null 2>&1; then
  HVIGOR=hvigorw
elif command -v hvigorw.bat >/dev/null 2>&1; then
  HVIGOR=hvigorw.bat
else
  printf 'Hvigor is not on PATH. Set DEVECO_HOME to your DevEco Studio installation.\n' >&2
  exit 2
fi
"$HVIGOR" --mode module -p product=default -p module=entry@default -p buildMode=release assembleHap --no-daemon "$@"
