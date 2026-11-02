#!/bin/sh
# Runner must be dedicated, trusted and configured out of band. No privileged installation.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
[ "$(git rev-parse HEAD)" = "${EXPECTED_COMMIT:-missing}" ] || { echo 'commit mismatch' >&2; exit 1; }
[ "${GITHUB_REF:-}" = refs/heads/main ] || { echo 'not main' >&2; exit 1; }
[ "${GITHUB_REPOSITORY:-}" = vinhbui720/deepdoc-llm-service ] || { echo 'wrong repository' >&2; exit 1; }
[ -f /etc/deepdoc-llm/deploy-enabled ] || { echo 'runner deployment not provisioned' >&2; exit 1; }
[ -n "${DEEPDOC_MODEL_DIR:-}" ] && [ -d "$DEEPDOC_MODEL_DIR" ] || { echo 'model directory missing' >&2; exit 1; }
[ -n "${DEEPDOC_MODEL:-}" ] || { echo 'DEEPDOC_MODEL must be 4b or 14b' >&2; exit 1; }
case "$DEEPDOC_MODEL" in 4b|14b) ;; *) exit 1 ;; esac
[ -n "${DEEPDOC_MODEL_URL:-}" ] && [ -n "${DEEPDOC_MODEL_REVISION:-}" ] || { echo 'pinned model provenance missing' >&2; exit 1; }
# Provenance is operator-reviewed, immutable URL with explicit revision; never fetch a mutable URL here.
case "$DEEPDOC_MODEL_URL" in https://*"$DEEPDOC_MODEL_REVISION"*) ;; *) echo 'model URL lacks pinned revision' >&2; exit 1 ;; esac
case "$DEEPDOC_MODEL" in 4b) name=Qwen3-4B-Q4_K_M.gguf ;; 14b) name=Qwen3-14B-Q4_K_M.gguf ;; esac
model="$DEEPDOC_MODEL_DIR/$name"
if [ ! -f "$model" ]; then
  tmp=$(mktemp "$DEEPDOC_MODEL_DIR/.download.XXXXXXXX")
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  curl --fail --location --proto '=https' --proto-redir '=https' --max-time 1200 --output "$tmp" "$DEEPDOC_MODEL_URL"
  stage=$(mktemp -d "$DEEPDOC_MODEL_DIR/.stage.XXXXXXXX")
  cp "$tmp" "$stage/$name"
  "$root/scripts/verify-model.sh" "$DEEPDOC_MODEL" "$stage/$name"
  mv "$stage/$name" "$model"
  rmdir "$stage"
fi
"$root/scripts/verify-model.sh" "$DEEPDOC_MODEL" "$model"
[ -n "${DEEPDOC_HEALTH_URL:-}" ] && [ -n "${DEEPDOC_HEALTH_TOKEN_FILE:-}" ] && [ -r "$DEEPDOC_HEALTH_TOKEN_FILE" ] || { echo 'health credentials missing' >&2; exit 1; }
case "$DEEPDOC_HEALTH_URL" in https://*) ;; *) exit 1 ;; esac
previous=
if systemctl --user is-active --quiet deepdoc-llm-4b.service; then previous=4b; fi
if systemctl --user is-active --quiet deepdoc-llm-14b.service; then
  [ -z "$previous" ] || { echo 'both services active; refusing deployment' >&2; exit 1; }
  previous=14b
fi
[ -n "$previous" ] || { echo 'no prior service for rollback' >&2; exit 1; }
[ -n "${DEEPDOC_BACKUP_DIR:-}" ] && [ -d "$DEEPDOC_BACKUP_DIR" ] || { echo 'backup directory missing' >&2; exit 1; }
backup=$(mktemp -d "$DEEPDOC_BACKUP_DIR/deploy.XXXXXXXX")
systemctl --user cat "deepdoc-llm-$previous.service" > "$backup/previous.service"
printf '%s\n' "$previous" > "$backup/previous-model"
"$root/scripts/switch-model.sh" "$DEEPDOC_MODEL"
if ! curl --fail --silent --show-error --max-time 15 --cacert "${DEEPDOC_CA_FILE:?missing CA}" --header "Authorization: Bearer $(cat "$DEEPDOC_HEALTH_TOKEN_FILE")" "$DEEPDOC_HEALTH_URL" >/dev/null; then
  echo 'health failed; restoring previous service' >&2
  if [ "$previous" != "$DEEPDOC_MODEL" ]; then "$root/scripts/switch-model.sh" "$previous" || echo 'rollback failed; manual intervention required' >&2; fi
  exit 1
fi
