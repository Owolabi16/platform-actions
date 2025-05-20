#!/bin/bash
set -euo pipefail

case "$1" in
1)
  echo "🧩 Installing chart dependencies..."
  helm dependency update charts/platform
  ;;
*)
  echo "❌ Unknown argument: $1"
  exit 1
  ;;
esac
