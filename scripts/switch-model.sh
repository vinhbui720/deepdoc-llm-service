#!/bin/sh
# Local user-systemd switch only; never enables either service.
set -eu
[ "$#" -eq 1 ] || { echo 'usage: switch-model.sh 4b|14b' >&2; exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
models=${DEEPDOC_MODEL_DIR:-$root/../../models}
case "$1" in
  4b) target=deepdoc-llm-4b.service; other=deepdoc-llm-14b.service; model="$models/Qwen3-4B-Q4_K_M.gguf" ;;
  14b) target=deepdoc-llm-14b.service; other=deepdoc-llm-4b.service; model="$models/Qwen3-14B-Q4_K_M.gguf" ;;
  *) echo 'unknown model' >&2; exit 2 ;;
esac
"$root/scripts/verify-model.sh" "$1" "$model"
systemctl --user cat "$target" >/dev/null
systemctl --user cat "$other" >/dev/null
previous=
if systemctl --user is-active --quiet "$other"; then previous=$other; fi
if [ -z "$previous" ] && systemctl --user is-active --quiet "$target"; then
  echo "already active: $target"
  exit 0
fi
systemctl --user stop "$other"
systemctl --user stop "$target"
if systemctl --user is-active --quiet "$other" || systemctl --user is-active --quiet "$target"; then
  echo 'service still active; refusing concurrent start' >&2
  exit 1
fi
if ! systemctl --user start "$target" || ! systemctl --user is-active --quiet "$target"; then
  echo 'target failed; restoring previous service' >&2
  systemctl --user stop "$target"
  if [ -n "$previous" ]; then
    systemctl --user start "$previous" || echo 'rollback failed; previous service remains stopped' >&2
  fi
  exit 1
fi
echo "active: $target"
