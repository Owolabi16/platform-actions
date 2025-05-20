#!/bin/bash
set -euo pipefail

RELEASE_VERSION="$1"

# Set paths
CHART_PATH="charts/platform"
CHART_FILE="$CHART_PATH/Chart.yaml"
VALUES_FILE="$CHART_PATH/values.yaml"

# Set chart version
yq eval ".version = \"$RELEASE_VERSION\"" -i "$CHART_FILE"

# Update appVersion in values.yaml if needed
if yq eval '.appVersion' "$VALUES_FILE" >/dev/null 2>&1; then
  yq eval ".appVersion = \"$RELEASE_VERSION\"" -i "$VALUES_FILE"
fi
