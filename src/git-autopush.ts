/**
 * Git Auto-Push
 *
 * Polls configured git repositories for unpushed commits and pushes them to
 * origin. Intended for repos that are written to by container agents (which
 * lack host SSH credentials) so that commits land on GitHub automatically.
 */
import { exec } from 'child_process';
import { existsSync } from 'fs';
import { promisify } from 'util';

import { logger } from './logger.js';

const execAsync = promisify(exec);

const POLL_INTERVAL_MS = 10_000;

async function hasUnpushedCommits(repoPath: string): Promise<boolean> {
  try {
    const { stdout } = await execAsync(
      'git log origin/HEAD..HEAD --oneline 2>/dev/null || git log origin/main..HEAD --oneline 2>/dev/null',
      { cwd: repoPath },
    );
    return stdout.trim().length > 0;
  } catch {
    return false;
  }
}

async function pushRepo(repoPath: string): Promise<void> {
  try {
    const { stdout, stderr } = await execAsync('git push', { cwd: repoPath });
    logger.info(
      { repoPath, stdout: stdout.trim(), stderr: stderr.trim() },
      'git-autopush: pushed unpushed commits',
    );
  } catch (err: any) {
    logger.warn(
      { repoPath, err: err.message, stderr: err.stderr },
      'git-autopush: push failed',
    );
  }
}

async function pollOnce(repoPaths: string[]): Promise<void> {
  for (const repoPath of repoPaths) {
    try {
      if (await hasUnpushedCommits(repoPath)) {
        await pushRepo(repoPath);
      }
    } catch (err) {
      logger.debug({ repoPath, err }, 'git-autopush: error checking repo');
    }
  }
}

export function startGitAutopush(repoPaths: string[]): void {
  const validPaths = repoPaths.filter((p) => {
    if (!existsSync(p)) {
      logger.warn({ path: p }, 'git-autopush: path does not exist, skipping');
      return false;
    }
    return true;
  });

  if (validPaths.length === 0) return;

  logger.info({ paths: validPaths }, 'git-autopush: watching repos');

  const poll = async () => {
    await pollOnce(validPaths);
    setTimeout(poll, POLL_INTERVAL_MS);
  };

  poll();
}
