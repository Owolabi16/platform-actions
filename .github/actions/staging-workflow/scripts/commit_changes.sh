#!/bin/bash
set -e

# Check if argument is provided
if [ -z "$1" ]; then
    echo "Error: Platform version argument is required"
    echo "Usage: $0 <platform-version>"
    exit 1
fi

# Set environment variables
PLATFORM_VERSION=$1
BRANCH_NAME="platform-$PLATFORM_VERSION"
RELEASE_VERSION=$(echo "$PLATFORM_VERSION" | tr '-' '.')

# Commit and push changes
echo "Creating branch ${BRANCH_NAME} and committing changes..."
git checkout -B "${BRANCH_NAME}"
git add charts/platform/*
git commit -m "chore: Update platform charts for ${RELEASE_VERSION}" --no-verify || echo "No changes to commit."
git push origin "${BRANCH_NAME}"

echo "Changes pushed to branch ${BRANCH_NAME}."
