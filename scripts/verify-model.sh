#!/bin/sh
set -eu
[ "$#" -eq 2 ] || { echo 'usage: verify-model.sh 4b|14b /path/to/model.gguf' >&2; exit 2; }
case "$1" in
  4b) name=Qwen3-4B-Q4_K_M.gguf ;;
  14b) name=Qwen3-14B-Q4_K_M.gguf ;;
  *) echo 'unknown model' >&2; exit 2 ;;
esac
[ -f "$2" ] && [ "$(basename "$2")" = "$name" ] || { echo 'missing model or wrong filename' >&2; exit 1; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
expected=$(awk -v n="$name" '$2 == n {print $1}' "$root/models.sha256")
[ -n "$expected" ] || { echo 'missing pinned digest' >&2; exit 1; }
actual=$(sha256sum "$2" | cut -d ' ' -f 1)
[ "$actual" = "$expected" ] || { echo "SHA256 mismatch: $name" >&2; exit 1; }
echo "verified: $name"
