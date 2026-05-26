#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="$ROOT_DIR/release"

mkdir -p "$RELEASE_DIR"
rm -rf "$RELEASE_DIR"/*
echo "Cleared $RELEASE_DIR"
