#!/bin/bash
# update-chart-versions.sh

set -eo pipefail

# Validate input
if [[ -z "$1" || ! "$1" =~ ^[0-9]+-[0-9]+-[0-9]+$ ]]; then
    echo "Error: Version must match pattern: digits-digits-digits (e.g. x-0-0)"
    echo "Usage: $0 <version>"
    exit 1
fi

VERSION="$1"
ORG="alaffia-Technology-Solutions"
BRANCH_NAME="platform-$VERSION"
EXCLUDED_REPO="infra"
MAX_PARALLEL=8

# Function to process each repository
process_repo() {
    local repo=$1
    
    # Silent branch check
    if ! gh api "repos/$ORG/$repo/branches/$BRANCH_NAME" --silent >/dev/null 2>&1; then
        return  # Silent exit for missing branches
    fi

    echo "🔍 Processing $repo..."
    
    # Check if platform branch exists
    if ! gh api "repos/$ORG/$repo/branches/$BRANCH_NAME" --silent >/dev/null 2>&1; then
        echo "   ⏩ Platform branch $BRANCH_NAME does not exist in $repo"
        return
    fi

    # Create unique temp directory
    local tmp_dir=$(mktemp -d)
    
    # Shallow clone with minimal config
    git -c advice.detachedHead=false \
        clone \
        --branch "$BRANCH_NAME" \
        --single-branch \
        --depth=1 \
        "https://github.com/$ORG/$repo.git" \
        "$tmp_dir" >/dev/null 2>&1

    echo " Shallow clone done for $repo"
    pushd "$tmp_dir" >/dev/null

    # Find all Chart.yaml files (up to 2 levels deep)
    local charts=()
    while IFS= read -r -d '' chart; do
        charts+=("$chart")
    done < <(find . -maxdepth 3 -name Chart.yaml -print0)

    if [ ${#charts[@]} -eq 0 ]; then
        echo "   ⚠️ No Chart.yaml files found in $repo"
        popd >/dev/null
        rm -rf "$tmp_dir"
        return
    fi

    # Process charts
    local changes_made=false
    for chart in "${charts[@]}"; do
        local current_version=$(yq '.version' "$chart")
        if [[ "$current_version" == *"-next"* ]]; then
            local new_version="${current_version%-next*}"
            yq -i ".version = \"$new_version\"" "$chart"
            changes_made=true
            echo "   ✅ Updated chart version in $chart: $current_version → $new_version"
        fi

        local app_current_version=$(yq '.appVersion' "$chart")
        if [[ "$app_current_version" == *"-next"* ]]; then
            local app_new_version="${app_current_version%-next*}"
            yq -i ".appVersion = \"$app_new_version\"" "$chart"
            changes_made=true
            echo "   ✅ Updated app version in $chart: $app_current_version → $app_new_version"
        fi
    done

    # Commit and push if changes
    if $changes_made; then
        git add . >/dev/null
        git commit -s -m "[skip ci] Remove -next suffix" --no-verify >/dev/null
        git push origin "$BRANCH_NAME" >/dev/null 2>&1
        echo "   🚀 Pushed changes to $repo"
    else
        echo "   ⏭️ No changes needed in $repo"
    fi

    popd >/dev/null
    rm -rf "$tmp_dir"
}

export -f process_repo
export ORG BRANCH_NAME EXCLUDED_REPO

echo "🚀 Starting updates for existing platform branches"
gh repo list "$ORG" --json name -q '.[].name | select(. != "infra")' \
    | xargs -P $MAX_PARALLEL -I {} bash -c 'process_repo "$@"' _ {}

echo "✅ Completed updates for repositories with platform-$VERSION branch"
