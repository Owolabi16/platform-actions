#!/bin/bash
set -eo pipefail

# Validate input
if [[ -z "$1" || ! "$1" =~ ^[0-9]+-[0-9]+-[0-9]+$ ]]; then
    echo "Error: Version must match pattern: digits-digits-digits (e.g. 1-0-0)"
    echo "Usage: $0 <version>"
    exit 1
fi

VERSION="$1"
ORG="Alaffia-Technology-Solutions"  # Fixed casing
BRANCH_PREFIX="platform-$VERSION"

# Validate and set MAX_PARALLEL
MAX_PARALLEL=${MAX_PARALLEL:-5}
[[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]] || MAX_PARALLEL=5

# Secure output directory
OUTPUT_DIR="${GITHUB_WORKSPACE}/artifacts"
mkdir -p "$OUTPUT_DIR"
MERGED_REPOS="${OUTPUT_DIR}/merged-repos.txt"
: > "$MERGED_REPOS"  # Initialize empty file

EXCLUDED_REPO="infra"

# Function to safely append to merged-repos
record_merged_repo() {
    local repo=$1
    local merged_at=$2
    (
        flock -x 200
        echo "$repo,$merged_at" >> "$MERGED_REPOS"
    ) 200>"$MERGED_REPOS.lock"
}

# Function to process each repository
process_repo() {
    local repo=$1
    
    # Silent branch check
    if ! gh api "repos/$ORG/$repo/branches/$BRANCH_PREFIX" --silent >/dev/null 2>&1; then
        return
    fi

    echo "🔍 Processing $repo..."
    
    local default_branch retry_count
    default_branch=$(gh repo view "$ORG/$repo" --json defaultBranchRef -q '.defaultBranchRef.name')
    
    # Get PR data with error handling
    local prs
    if ! prs=$(gh pr list --repo "$ORG/$repo" \
        --head "$BRANCH_PREFIX" \
        --base "$default_branch" \
        --json number,mergeable,state 2>&1); then
        echo "   ❗ Failed to get PR list for $repo: $prs"
        return
    fi

    prs=$(jq -e '
        map(select(.state == "OPEN")) |
        sort_by(.number) |
        if length > 0 then .[0] else empty end
    ' <<< "$prs" || { echo "   ❗ Invalid PR data for $repo"; return; })

    if [ -z "$prs" ]; then
        echo "   ⚠️ No open PR found"
        return
    fi

    local pr_number mergeable
    pr_number=$(jq -r '.number' <<< "$prs")
    mergeable=$(jq -r '.mergeable' <<< "$prs")
    
    if [ "$mergeable" != "MERGEABLE" ]; then
        echo "   ❌ PR #$pr_number not mergeable in ${repo} (status: ${mergeable:-UNKNOWN})"
        return
    fi

    # Merge PR with retries
    for attempt in {1..3}; do
        echo "   ✅ Attempt $attempt: Merging PR #$pr_number..."
        if gh pr merge "$pr_number" --repo "$ORG/$repo" \
            --squash \
            --delete-branch \
            --body "Automated merge of platform release $VERSION"; then
            break
        else
            echo "   ⚠️ Merge attempt $attempt failed in ${repo}"
            sleep $((attempt * 2))
            if [[ $attempt -eq 3 ]]; then
                echo "   ❌ All merge attempts failed for PR #$pr_number in ${repo}"
                return
            fi
        fi
    done

    # Get mergedAt with retries
    local merged_at
    for retry_count in {1..5}; do
        merged_at=$(gh pr view "$pr_number" --repo "$ORG/$repo" --json mergedAt -q '.mergedAt' 2>/dev/null || true)
        [ -n "$merged_at" ] && break
        sleep 2
    done
    merged_at=${merged_at:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}  # Fallback timestamp

    record_merged_repo "$repo" "$merged_at"
    echo "   ✔️ Successfully merged PR #$pr_number (merged at: ${merged_at:-unknown})"
}

export -f process_repo record_merged_repo
export ORG BRANCH_PREFIX VERSION EXCLUDED_REPO MERGED_REPOS

echo "🚀 Starting PR merges for platform-$VERSION branches"
gh repo list "$ORG" --json name -q '.[].name | select(. != "infra")' \
    | tr '\n' '\0' \
    | xargs -0 -P "$MAX_PARALLEL" -I {} bash -c 'process_repo "$@"' _ {}

echo -e "\n✅ Completed PR processing for platform-$VERSION branches"
echo "Merged repositories:"
column -t -s, "$MERGED_REPOS" 2>/dev/null || cat "$MERGED_REPOS"

echo "Output saved to $MERGED_REPOS"
echo "🚀 Merging process completed for all repositories."
