#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { execSync } = require('child_process');

// Constants
const COMPACTION_THRESHOLD = 200000

// 基本 ANSI カラーはターミナルのパレットで原色になるため、Codex と同じく 24bit で指定する
const RESET = '\x1b[0m';
const rgb = (r, g, b) => `\x1b[38;2;${r};${g};${b}m`;

const MUTED = rgb(107, 115, 148);
const DIRECTORY = rgb(158, 206, 106);
const BRANCH = rgb(122, 162, 247);
const LIMIT = rgb(187, 154, 247);
const CONTEXT = rgb(169, 177, 214);
const CONTEXT_WARN = rgb(224, 175, 104);
const CONTEXT_DANGER = rgb(247, 118, 142);
const SEPARATOR = `${MUTED} · ${RESET}`

// Read JSON from stdin
let input = '';
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', async () => {
  try {
    const data = JSON.parse(input);

    // Extract values
    const model = data.model?.display_name || 'Unknown';
    const effort = data.effort?.level;
    const currentDir = data.workspace?.current_dir || data.cwd || '.';
    const dirName = path.basename(currentDir);
    const sessionId = data.session_id;

    // Get Git branch
    let branch = '';
    if (currentDir && fs.existsSync(path.join(currentDir, '.git'))) {
      try {
        const branchName = execSync('git --no-optional-locks branch --show-current 2>/dev/null', {
          cwd: currentDir,
          encoding: 'utf-8'
        }).trim();
        if (branchName) {
          branch = branchName;
        }
      } catch (e) {
        // Gitコマンドエラーは無視
      }
    }

    // Write the RunCat Neo custom metrics snapshot
    writeRunCatSnapshot(data);

    // Calculate token usage for current session
    let totalTokens = 0;
    const currentUsage = data.context_window?.current_usage;

    if (currentUsage) {
      totalTokens = sumUsage(currentUsage);
    } else if (sessionId) {
      // Find all transcript files
      const projectsDir = path.join(process.env.HOME, '.claude', 'projects');

      if (fs.existsSync(projectsDir)) {
        // Get all project directories
        const projectDirs = fs.readdirSync(projectsDir)
          .map(dir => path.join(projectsDir, dir))
          .filter(dir => fs.statSync(dir).isDirectory());

        // Search for the current session's transcript file
        for (const projectDir of projectDirs) {
          const transcriptFile = path.join(projectDir, `${sessionId}.jsonl`);

          if (fs.existsSync(transcriptFile)) {
            totalTokens = await calculateTokensFromTranscript(transcriptFile);
            break;
          }
        }
      }
    }

    // Prefer the window size Claude reports; fall back to the transcript-based estimate
    const usedPercentage = data.context_window?.used_percentage;
    const percentage = Math.min(100, roundPercent(typeof usedPercentage === 'number'
      ? usedPercentage
      : (totalTokens / COMPACTION_THRESHOLD) * 100));

    let percentageColor = CONTEXT;
    if (percentage >= 56) percentageColor = CONTEXT_WARN;
    if (percentage >= 72) percentageColor = CONTEXT_DANGER;

    // Build status line
    const segments = [
      `${model}${effort ? ` ${effort}` : ''}`,
      `${DIRECTORY}${dirName}${RESET}`
    ];
    if (branch) segments.push(`${BRANCH}${branch}${RESET}`);
    segments.push(`${percentageColor}Context ${percentage.toFixed(1)}% used${RESET}`);
    segments.push(...formatRateLimits(data.rate_limits));
    segments.push(`${MUTED}${sessionId}${RESET}`);

    const statusLine = segments.join(SEPARATOR);

    console.log(statusLine);
  } catch (error) {
    // Fallback status line on error
    console.log('[Claude Code]');
  }
});

async function calculateTokensFromTranscript(filePath) {
  return new Promise((resolve, reject) => {
    let lastUsage = null;

    const fileStream = fs.createReadStream(filePath);
    const rl = readline.createInterface({
      input: fileStream,
      crlfDelay: Infinity
    });

    rl.on('line', (line) => {
      try {
        const entry = JSON.parse(line);

        // Check if this is an assistant message with usage data
        if (entry.type === 'assistant' && entry.message?.usage) {
          lastUsage = entry.message.usage;
        }
      } catch (e) {
        // Skip invalid JSON lines
      }
    });

    rl.on('close', () => {
      if (lastUsage) {
        // The last usage entry contains cumulative tokens
        resolve(sumUsage(lastUsage));
      } else {
        resolve(0);
      }
    });

    rl.on('error', (err) => {
      reject(err);
    });
  });
}

function sumUsage(usage) {
  return (usage.input_tokens || 0) +
    (usage.output_tokens || 0) +
    (usage.cache_creation_input_tokens || 0) +
    (usage.cache_read_input_tokens || 0);
}

// RunCat Neo watches this file and renders it as a dashboard card.
// Schema: https://github.com/runcat-dev/RunCatNeo/blob/main/docs/CustomMetricsSchema.md
function writeRunCatSnapshot(data) {
  try {
    const outPath = process.env.RUNCAT_OUT_FILE ||
      path.join(process.env.HOME, '.claude', 'runcat-usage.json');

    const rateLimits = data.rate_limits || {};
    const usedPercentage = data.context_window?.used_percentage;

    const metrics = [];
    if (data.model?.display_name) {
      const effort = data.effort?.level;
      metrics.push({
        title: 'Model',
        formattedValue: `${data.model.display_name}${effort ? ` (${effort})` : ''}`
      });
    }
    for (const metric of [
      buildPercentMetric('Context', usedPercentage),
      buildPercentMetric('5h', rateLimits.five_hour?.used_percentage, formatResetTime(rateLimits.five_hour?.resets_at)),
      buildPercentMetric('7d', rateLimits.seven_day?.used_percentage, formatResetTime(rateLimits.seven_day?.resets_at)),
    ]) {
      if (metric) metrics.push(metric);
    }

    const snapshot = {
      title: 'Claude Code',
      symbol: 'staroflife',
      metrics,
      lastUpdatedDate: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
    };

    // Write atomically so RunCat never reads a half-written file
    const outDir = path.dirname(outPath);
    fs.mkdirSync(outDir, { recursive: true });
    const tmpPath = path.join(outDir, `.runcat-${process.pid}.tmp`);
    fs.writeFileSync(tmpPath, JSON.stringify(snapshot));
    fs.renameSync(tmpPath, outPath);
  } catch (e) {
    // RunCat連携の失敗でステータスラインを壊さない
  }
}

// Codex は残量を出すので、使用量であることを明示して読み違えを防ぐ
function formatRateLimits(rateLimits) {
  const parts = [
    ['5h', rateLimits?.five_hour?.used_percentage],
    ['7d', rateLimits?.seven_day?.used_percentage]
  ]
    .filter(([, value]) => typeof value === 'number')
    .map(([label, value]) => `${label} ${Math.round(value)}%`);

  return parts.length ? [`${LIMIT}${parts.join('/')} used${RESET}`] : [];
}

function roundPercent(percentage) {
  return Math.round(percentage * 10) / 10;
}

function buildPercentMetric(title, percentage, resetTime) {
  if (typeof percentage !== 'number') return null;

  const rounded = roundPercent(percentage);

  return {
    title,
    formattedValue: `${rounded.toFixed(1)}%${resetTime ? ` (${resetTime})` : ''}`,
    normalizedValue: Math.min(1, Math.max(0, rounded / 100))
  };
}

function formatResetTime(epochSeconds) {
  if (typeof epochSeconds !== 'number') return null;

  const reset = new Date(epochSeconds * 1000);
  if (isNaN(reset.getTime())) return null;

  const hourMinute = `${String(reset.getHours()).padStart(2, '0')}:${String(reset.getMinutes()).padStart(2, '0')}`;
  if (reset.toDateString() === new Date().toDateString()) {
    return `~${hourMinute}`;
  }
  return `~${reset.getMonth() + 1}/${reset.getDate()} ${hourMinute}`;
}
