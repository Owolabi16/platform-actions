import * as core from "@actions/core";
import fs from "fs";
import path from "path";

const WORKFLOW_FILE = "rc-next-release.yaml";
const ORG_NAME = "occasio-technology-solutions";
const WORKFLOW_MAP: Record<string, string> = {
  "occasio": "occasio-apps",
  "ask-occasio": "occasio-apps",
  "fdw": "fdw",
  "reports": "reports",
  "gpt-search": "gpt-search",
  "document-api": "document-api",
  "autodor-py": "autodor-py",
  "file-api": "file-api",
  "graphql": "graphql_api"
};

function getChartRepos(): string[] {
  const fileLocation = process.env.FILE_LOCATION!;
  const servicesDir = path.join(fileLocation, "charts", "platform", "services");

  return fs
    .readdirSync(servicesDir)
    .filter((f) => fs.statSync(path.join(servicesDir, f)).isDirectory());
}

function resolveReposFromCharts(charts: string[]): string[] {
  const repos = new Set<string>();
  for (const chart of charts) {
    const mapped = WORKFLOW_MAP[chart];
    if (mapped) repos.add(mapped);
  }
  return Array.from(repos);
}

function filterForTargetRepo(repos: string[], targetRepo: string | null): string[] {
  if (!targetRepo) {
    return repos; // No target repo specified, return all repos
  }
  
  // Check if the target repo exists in the list
  if (repos.includes(targetRepo)) {
    core.info(`🎯 Targeting specific repository: ${targetRepo}`);
    return [targetRepo];
  }
  
  // Check if the target repo is actually a chart name that maps to a repo
  const mappedRepo = WORKFLOW_MAP[targetRepo];
  if (mappedRepo && repos.includes(mappedRepo)) {
    core.info(`🎯 Targeting specific repository: ${mappedRepo} (mapped from chart: ${targetRepo})`);
    return [mappedRepo];
  }
  
  // If target repo doesn't exist in the list, log warning and return empty array
  core.warning(`⚠️ Target repository '${targetRepo}' not found in the list of available repositories`);
  return [];
}

async function main() {
  try {
    // Check for target_repo input
    const targetRepo = process.env.TARGET_REPO || null;
    
    const charts = getChartRepos();
    let repos = resolveReposFromCharts(charts);
    
    // Apply filtering if target repo is specified
    if (targetRepo) {
      repos = filterForTargetRepo(repos, targetRepo);
      
      if (repos.length === 0) {
        throw new Error(`❌ Target repository '${targetRepo}' not found or does not have a matching workflow`);
      }
    }
    
    core.info(`🔗 Workflows to trigger: ${repos.join(", ")}`);

    for (const repo of repos) {
      const payload = {
        ref: process.env.BRANCH_NAME,
        inputs: { branch: process.env.BRANCH_NAME }
      };

      core.info(`🚀 Dispatching workflow to ${repo}`);
      const res = await fetch(
        `https://api.github.com/repos/${ORG_NAME}/${repo}/actions/workflows/${WORKFLOW_FILE}/dispatches`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${process.env.GITHUB_TOKEN}`,
            Accept: "application/vnd.github+json",
            "Content-Type": "application/json"
          },
          body: JSON.stringify(payload)
        }
      );

      if (!res.ok) {
        const errText = await res.text();
        throw new Error(`❌ Failed to trigger workflow for ${repo}: ${errText}`);
      }

      core.info(`✅ Triggered workflow for ${repo}`);
    }
  } catch (err: any) {
    core.setFailed(err.message);
  }
}

main();