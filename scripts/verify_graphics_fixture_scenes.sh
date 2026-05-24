#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-/tmp/opentoonz-graphics-fixtures}"

scripts/generate_graphics_fixture_scenes.sh "$out_dir" >/dev/null

sub_xsheet_scene="$out_dir/sub_xsheet_basic.tnz"
mesh_scene="$out_dir/mesh_skeleton_basic.tnz"
mesh_frame="$out_dir/mesh/basic_mesh.0001.mesh"
if [[ ! -s "$sub_xsheet_scene" ]]; then
  echo "verify-graphics-fixture-scenes: missing generated sub-xsheet scene" >&2
  exit 1
fi
if [[ ! -s "$mesh_scene" ]]; then
  echo "verify-graphics-fixture-scenes: missing generated mesh scene" >&2
  exit 1
fi
if [[ ! -s "$mesh_frame" ]]; then
  echo "verify-graphics-fixture-scenes: missing generated mesh frame" >&2
  exit 1
fi

for asset in dwanko/tga/A_converted.tlv dwanko/tga/A_converted.tpl; do
  if [[ ! -e "$out_dir/$asset" ]]; then
    echo "verify-graphics-fixture-scenes: missing generated fixture asset link: $out_dir/$asset" >&2
    exit 1
  fi
done

fail=0
if ! grep -q "<childLevel id='1'>" "$sub_xsheet_scene"; then
  echo "verify-graphics-fixture-scenes: sub-xsheet fixture has no childLevel" >&2
  fail=1
fi

if ! grep -q "<childLevel id='1'/>0001 1" "$sub_xsheet_scene"; then
  echo "verify-graphics-fixture-scenes: parent xsheet does not expose childLevel frames" >&2
  fail=1
fi

if ! grep -q '"\$scenefolder\\\\dwanko\\\\tga\\\\A_converted.tlv"' \
    "$sub_xsheet_scene"; then
  echo "verify-graphics-fixture-scenes: sub-xsheet fixture is not backed by sample TLV data" >&2
  fail=1
fi

if ! grep -q "<meshColumn id='2'>" "$mesh_scene"; then
  echo "verify-graphics-fixture-scenes: mesh fixture has no meshColumn" >&2
  fail=1
fi

if ! grep -q '"\$scenefolder\\\\mesh\\\\basic_mesh.mesh"' "$mesh_scene"; then
  echo "verify-graphics-fixture-scenes: mesh fixture is not relocatable through scenefolder" >&2
  fail=1
fi

for required_tag in "<header>" "<mesh>" "<V>" "<E>" "<F>" "<rigidities>"; do
  if ! grep -q "$required_tag" "$mesh_frame"; then
    echo "verify-graphics-fixture-scenes: mesh frame missing $required_tag" >&2
    fail=1
  fi
done

if (( fail != 0 )); then
  exit 1
fi

echo "verify-graphics-fixture-scenes: ok artifacts=$out_dir"
