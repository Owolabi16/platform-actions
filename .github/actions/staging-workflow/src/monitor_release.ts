import { Octokit } from '@octokit/core';
import * as core from '@actions/core';
import * as fs from 'fs';
import * as path from 'path';

const POLL_INTERVAL = 15000; // 15 seconds
const MAX_WAIT = 3600000; // 1 hour
const WORKFLOW_FILE = '.github/workflows/staging-release.yaml';
const ORG_NAME = 'Alaffia-Technology-Solutions';

interface WorkflowRun {
  id: number;
  status: 'queued' | 'in_progress' | 'completed' | null;
  conclusion: string | null;
  html_url: string;
  created_at: string;
  workflow_id: number;
  name?: string;
}

interface RepositoryStatus {
  repo: string;
  status: 'pending' | 'success' | 'failure' | 'timed_out';
  run_id?: number;
  url?: string;
}

interface MergedRepo {
  repo: string;
  mergeTime: string;
}

async function loadMergedRepos(): Promise<MergedRepo[]> {
  const filePath = path.join(
    process.env.GITHUB_WORKSPACE || '',
    'artifacts', // Ensure the 'artifacts' directory is included
    'merged-repos.txt'
  );

  core.info(`ℹ️ Resolved path to merged-repos.txt: ${filePath}`);
  
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    return content
      .split('\n')
      .filter(line => line.trim())
      .map(line => {
        const [repo, mergeTime] = line.split(',');
        if (!repo || !mergeTime) {
          core.warning(`Invalid line in merged-repos.txt: ${line}`);
          return null;
        }
        return { repo, mergeTime };
      })
      .filter((entry): entry is MergedRepo => entry !== null)
      .filter((v, i, a) => 
        a.findIndex(e => e.repo === v.repo) === i // Deduplicate
      );
  } catch (error) {
    core.info('ℹ️ No merged repositories file found');
    return [];
  }
}

async function findRecentWorkflowRun(
  octokit: Octokit,
  repo: string,
  mergeTime: string
): Promise<WorkflowRun | null> {
  try {
    const { data } = await octokit.request(
      'GET /repos/{owner}/{repo}/actions/runs',
      {
        owner: ORG_NAME,
        repo,
        event: 'push',
        per_page: 5
      }
    );

    const foundRun = data.workflow_runs.find(run => 
      run.path === WORKFLOW_FILE &&
      new Date(run.created_at) >= new Date(mergeTime)
    );

    if (!foundRun) {
      core.info(`No workflow run found for ${repo} after merge time ${mergeTime}.`);
      return null;
    }

    return {
      id: foundRun.id,
      status: (foundRun.status as 'queued' | 'in_progress' | 'completed' | null) || null,
      conclusion: foundRun.conclusion,
      html_url: foundRun.html_url,
      created_at: foundRun.created_at,
      workflow_id: foundRun.workflow_id,
      name: foundRun.name ?? undefined
    };
  } catch (error) {
    core.error(`🔍 Error finding workflows for ${repo}: ${error instanceof Error ? error.message : 'Unknown error'}`);
    return null;
  }
}


async function monitorRepository(
  octokit: Octokit,
  repo: string,
  mergeTime: string
): Promise<RepositoryStatus> {
  const status: RepositoryStatus = { repo, status: 'pending' };
  const startTime = Date.now();

  while (Date.now() - startTime < MAX_WAIT) {
    const run = await findRecentWorkflowRun(octokit, repo, mergeTime);
    
    if (run) {
      status.run_id = run.id;
      status.url = run.html_url;
      core.info(`🔍 Found ${repo} release workflow: ${run.html_url}`);
      return monitorExistingRun(octokit, repo, run);
    }

    await new Promise(resolve => setTimeout(resolve, POLL_INTERVAL));
  }

  status.status = 'timed_out';
  return status;
}

async function monitorExistingRun(
  octokit: Octokit,
  repo: string,
  run: WorkflowRun
): Promise<RepositoryStatus> {
  const status: RepositoryStatus = {
    repo,
    status: 'pending',
    run_id: run.id,
    url: run.html_url
  };

  while (true) {
    const { data: currentRun } = await octokit.request(
      'GET /repos/{owner}/{repo}/actions/runs/{run_id}',
      { owner: ORG_NAME, repo, run_id: run.id }
    );

    const currentStatus = currentRun.status || 'unknown';
    core.info(`${repo} status: ${currentStatus} [${currentRun.html_url}]`);

    if (currentStatus === 'completed') {
      status.status = currentRun.conclusion === 'success' ? 'success' : 'failure';
      return status;
    }

    await new Promise(resolve => setTimeout(resolve, POLL_INTERVAL));
  }
}

async function main(): Promise<void> {
  try {
    const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN });
    const mergedRepos = await loadMergedRepos();
    const mergeTime = new Date().toISOString();

    if (mergedRepos.length === 0) {
      core.info('⏩ No merged repositories to monitor');
      return;
    }

    core.info(`👀 Monitoring release workflows for:\n- ${mergedRepos.map(r => r.repo).join('\n- ')}`);

    const results = await Promise.all(
      mergedRepos.map(({ repo, mergeTime }) => 
        monitorRepository(octokit, repo, mergeTime)
      )
    );

    const summary = results.map(r => 
      `${r.status === 'success' ? '✅' : '❌'} ${r.repo.padEnd(20)} ${r.status} ${r.url || ''}`
    ).join('\n');

    core.info('\n📊 Release Monitoring Summary:\n' + summary);

    const failures = results.filter(r => r.status !== 'success');
    if (failures.length > 0) {
      throw new Error(`${failures.length} release workflows failed`);
    }

    core.info('\n🎉 All release workflows completed successfully');
  } catch (error) {
    core.setFailed(error instanceof Error ? error.message : 'Unknown error');
    process.exit(1);
  }
}

main();
