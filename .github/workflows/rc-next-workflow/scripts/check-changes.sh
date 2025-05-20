#!/bin/bash
set -euo pipefail

CHART_DIR="charts/platform"

# Check for modified files in the chart dir
if [[ -n "$(git status --porcelain "$CHART_DIR")" ]]; then
  echo "changes_detected=true" >> $GITHUB_OUTPUT
else
  echo "changes_detected=false" >> $GITHUB_OUTPUT
fi
