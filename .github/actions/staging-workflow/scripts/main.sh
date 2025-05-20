#!/bin/bash
set -e

PLATFORM_VERSION=$1
GITHUB_TOKEN=$2
GITHUB_ACTOR=$3

CHART_VERSION=$(echo "$PLATFORM_VERSION" | tr '-' '.')

echo "🚀 Starting Staging Release Automation for Platform Version: $CHART_VERSION"

# Step 1: Update the Platform PRs in Service Repos by removing the "-next" suffix
echo "🔄 Remove -next in Helm Charts for platform-$PLATFORM_VERSION branch in service repositories..."
scripts/update_service_chart_versions.sh "$PLATFORM_VERSION"

# Step 2: Merge PRs for Services and update the version in the service charts
echo "📌 Merging PR for services..."
scripts/merge_service_pr.sh "$PLATFORM_VERSION"

sleep 10

# Step 3: Monitor Release Workflows
echo "🕵️ Monitoring release workflows..."
node dist/monitor_release.js

# Step 4: Updating the Infra Platform Chart
echo "🛠️ Updating the Infra Platform Chart..."
scripts/update_infra_chart_versions.sh "$PLATFORM_VERSION"

# Step 5: Commit Changes
echo "📝 Committing changes to infra repo..."
scripts/commit_changes.sh "$PLATFORM_VERSION"

# Step 6: Merge Infra Platform Deployment PR
echo "📡 Merge Infra Platform Deployment..."
scripts/merge_infra.sh "$PLATFORM_VERSION"

echo "✅ Staging Release Automation Completed Successfully!"

platform_version=$(yq e '.version' charts/platform/Chart.yaml)
echo "platform_version=$platform_version" >> $GITHUB_OUTPUT
