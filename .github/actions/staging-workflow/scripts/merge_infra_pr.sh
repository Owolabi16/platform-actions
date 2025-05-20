#!/bin/bash
# merge-infra-pr.sh

set -eo pipefail

# Validate input format
if [[ -z "$1" || ! "$1" =~ ^[0-9]+-[0-9]+-[0-9]+$ ]]; then
    echo "Error: Version must match pattern: digits-digits-digits (e.g. x-x-x)"
    echo "Usage: $0 <platform-version>"
    exit 1
fi

VERSION="$1"
ORG="alaffia-Technology-Solutions"
REPO="infra"
BRANCH_NAME="platform-$VERSION"

# Check if platform branch exists in infra
if ! gh api "repos/$ORG/$REPO/branches/$BRANCH_NAME" --silent >/dev/null 2>&1; then
    echo "❌ Platform branch $BRANCH_NAME does not exist in $REPO"
    exit 0
fi

# Get default branch
DEFAULT_BRANCH=$(gh repo view "$ORG/$REPO" --json defaultBranchRef -q '.defaultBranchRef.name')

# Find existing PR
PR_DATA=$(gh pr list --repo "$ORG/$REPO" \
    --head "$BRANCH_NAME" \
    --base "$DEFAULT_BRANCH" \
    --json number,mergeable,state,title -q '
        map(select(.state == "OPEN")) |
        sort_by(.number) |
        if length > 0 then .[0] else empty end
    ')

if [ -z "$PR_DATA" ]; then
    echo "ℹ️ No open PR found from $BRANCH_NAME to $DEFAULT_BRANCH in $REPO"
    exit 0
fi

PR_NUMBER=$(jq -r '.number' <<< "$PR_DATA")
MERGEABLE=$(jq -r '.mergeable' <<< "$PR_DATA")
TITLE=$(jq -r '.title' <<< "$PR_DATA")

if [ "$MERGEABLE" != "MERGEABLE" ]; then
    echo "❌ PR #$PR_NUMBER not mergeable (status: ${MERGEABLE:-UNKNOWN})"
    echo "   Title: $TITLE"
    exit 1
fi

echo "✅ Found mergeable PR: #$PR_NUMBER"
echo "   Title: $TITLE"
echo "   From: $BRANCH_NAME -> $DEFAULT_BRANCH"

# Perform merge
echo "🚀 Merging PR #$PR_NUMBER..."
gh pr merge "$PR_NUMBER" --repo "$ORG/$REPO" \
    --squash \
    --delete-branch \
    --body "Automated merge of platform release $VERSION"

echo "✅ Successfully merged PR #$PR_NUMBER in $REPO"
