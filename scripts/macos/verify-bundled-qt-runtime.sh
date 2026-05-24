#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-${OPENTOONZ_APP:-toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app}}"

if [[ ! -d "$app_path" ]]; then
  echo "verify-bundled-qt-runtime: app bundle not found: $app_path" >&2
  exit 1
fi

app_path="$(cd "$(dirname "$app_path")" && pwd)/$(basename "$app_path")"
macos_dir="$app_path/Contents/MacOS"
frameworks_dir="$app_path/Contents/Frameworks"
plugins_dir="$app_path/Contents/PlugIns"

if [[ ! -x "$macos_dir/OpenToonz" ]]; then
  echo "verify-bundled-qt-runtime: missing executable: $macos_dir/OpenToonz" >&2
  exit 1
fi

tmp="/tmp/opentoonz-bundled-qt-runtime.$$"
trap 'rm -f "$tmp"' EXIT

find_macho_files() {
  local roots=("$macos_dir")
  [[ -d "$frameworks_dir" ]] && roots+=("$frameworks_dir")
  [[ -d "$plugins_dir" ]] && roots+=("$plugins_dir")

  find "${roots[@]}" -type f -print0 |
    while IFS= read -r -d '' path; do
      if file "$path" | grep -q 'Mach-O'; then
        printf '%s\0' "$path"
      fi
    done
}

if [[ -d "$frameworks_dir" ]] &&
   find "$frameworks_dir" -maxdepth 1 -name 'libQt5*.dylib' -print -quit |
     grep -q .; then
  while IFS= read -r -d '' macho; do
    otool -L "$macho" |
      awk '/\/nix\/store\/.*libQt5.*\.dylib/ { print file ":" $1 }' \
        file="$macho" >>"$tmp"
  done < <(find_macho_files)

  if [[ -s "$tmp" ]]; then
    echo "verify-bundled-qt-runtime: bundle contains Qt dylibs but still references Nix Qt:" >&2
    cat "$tmp" >&2
    exit 1
  fi
fi

if [[ -d "$plugins_dir/platforms" ]]; then
  for plugin in "$plugins_dir"/platforms/libq*.dylib; do
    [[ -e "$plugin" ]] || continue
    if otool -L "$plugin" |
      awk '/\/nix\/store\/.*libQt5.*\.dylib/ { found=1 } END { exit found ? 0 : 1 }'; then
      echo "verify-bundled-qt-runtime: Qt platform plugin references Nix Qt: $plugin" >&2
      otool -L "$plugin" >&2
      exit 1
    fi
  done
fi

if command -v dyld_info >/dev/null 2>&1; then
  : >"$tmp"
  while IFS= read -r -d '' macho; do
    dyld_info -imports "$macho" 2>/dev/null |
      awk '/_libiconv($|_)/ && /\(from libiconv\)/ { print file ":" $0 }' \
        file="$macho" >>"$tmp"
  done < <(find_macho_files)

  if [[ -s "$tmp" ]]; then
    echo "verify-bundled-qt-runtime: GNU libiconv symbols resolve to Darwin libiconv:" >&2
    cat "$tmp" >&2
    echo "verify-bundled-qt-runtime: expected _libiconv imports to resolve to bundled libgnuiconv.2.dylib" >&2
    exit 1
  fi
fi

if [[ -e "$frameworks_dir/libidn2.0.dylib" ]]; then
  if ! otool -L "$frameworks_dir/libidn2.0.dylib" |
      grep -q '@executable_path/../Frameworks/libgnuiconv\.2\.dylib'; then
    echo "verify-bundled-qt-runtime: libidn2.0.dylib is not linked to bundled libgnuiconv.2.dylib" >&2
    otool -L "$frameworks_dir/libidn2.0.dylib" >&2
    exit 1
  fi

  if [[ ! -e "$frameworks_dir/libgnuiconv.2.dylib" ]]; then
    echo "verify-bundled-qt-runtime: missing bundled libgnuiconv.2.dylib required by libidn2.0.dylib" >&2
    exit 1
  fi

  if ! nm -gU "$frameworks_dir/libgnuiconv.2.dylib" 2>/dev/null |
      grep -Eq ' T _libiconv($|_)'; then
    echo "verify-bundled-qt-runtime: bundled libgnuiconv.2.dylib does not export GNU libiconv symbols" >&2
    exit 1
  fi
fi

echo "verify-bundled-qt-runtime: ok $app_path"
