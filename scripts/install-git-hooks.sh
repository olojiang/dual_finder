#!/usr/bin/env bash
# Install git hooks from scripts/git-hooks into .git/hooks.
# Re-runnable; overwrites existing hook symlinks/files of the same name.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src_dir="$repo_root/scripts/git-hooks"
dest_dir="$repo_root/.git/hooks"

if [[ ! -d "$dest_dir" ]]; then
    echo "[install-git-hooks] .git/hooks not found at $dest_dir — not a git repo?" >&2
    exit 1
fi

for src in "$src_dir"/*; do
    [[ -f "$src" ]] || continue
    name="$(basename "$src")"
    dest="$dest_dir/$name"
    rm -f "$dest"
    ln -s "$src" "$dest"
    chmod +x "$src"
    echo "[install-git-hooks] linked $name -> $src"
done

echo "[install-git-hooks] done."
