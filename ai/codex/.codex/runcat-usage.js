#!/usr/bin/env node

// Codex の Stop フックから呼ばれ、RunCat Neo が監視するスナップショットを書き出す。
// Schema: https://github.com/runcat-dev/RunCatNeo/blob/main/docs/CustomMetricsSchema.md

const fs = require('fs');
const path = require('path');

// セッションログは 500MB を超えることがあるので、末尾からチャンク単位で遡って読む
const CHUNK_SIZE = 256 * 1024;
const MAX_TAIL_BYTES = 16 * 1024 * 1024;

const CODEX_HOME = process.env.CODEX_HOME || path.join(process.env.HOME, '.codex');
const OUT_PATH = process.env.RUNCAT_OUT_FILE || path.join(CODEX_HOME, 'runcat-usage.json');

main();

function main() {
  try {
    drainStdin();

    const sessionFile = findLatestSession(path.join(CODEX_HOME, 'sessions'));
    if (!sessionFile) return;

    const state = readSessionState(sessionFile);
    if (!state.info) return;

    writeSnapshot(buildSnapshot(state));
  } catch (e) {
    // RunCat連携の失敗で Codex のターンを止めない
  }
}

// フック側が書き込んだ stdin を捨てておく
function drainStdin() {
  try {
    fs.readFileSync(0);
  } catch (e) {
    // stdin がなくても問題ない
  }
}

function findLatestSession(sessionsDir) {
  if (!fs.existsSync(sessionsDir)) return null;

  let latest = null;

  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const entryPath = path.join(dir, entry.name);

      if (entry.isDirectory()) {
        walk(entryPath);
      } else if (entry.name.endsWith('.jsonl')) {
        const mtime = fs.statSync(entryPath).mtimeMs;
        if (!latest || mtime > latest.mtime) {
          latest = { path: entryPath, mtime };
        }
      }
    }
  };

  walk(sessionsDir);

  return latest && latest.path;
}

function readSessionState(sessionFile) {
  const state = { info: null, rateLimits: null, model: null, effort: null };
  const fd = fs.openSync(sessionFile, 'r');

  try {
    const size = fs.fstatSync(fd).size;
    let end = size;
    let carry = Buffer.alloc(0);

    while (end > 0 && size - end < MAX_TAIL_BYTES) {
      const start = Math.max(0, end - CHUNK_SIZE);
      const chunk = Buffer.alloc(end - start);
      fs.readSync(fd, chunk, 0, chunk.length, start);

      const lines = splitLines(Buffer.concat([chunk, carry]));
      // チャンクの先頭は行の途中で切れている可能性があるので次の周回へ持ち越す
      carry = start > 0 ? lines.shift() : Buffer.alloc(0);

      for (let i = lines.length - 1; i >= 0; i--) {
        applyLine(state, lines[i]);
        if (state.info && state.model) return state;
      }

      end = start;
    }
  } finally {
    fs.closeSync(fd);
  }

  return state;
}

function splitLines(buffer) {
  const lines = [];
  let start = 0;

  for (let i = 0; i < buffer.length; i++) {
    if (buffer[i] === 0x0a) {
      lines.push(buffer.subarray(start, i));
      start = i + 1;
    }
  }
  lines.push(buffer.subarray(start));

  return lines;
}

// 末尾から遡るので、先に見つかったものが最新になる
function applyLine(state, line) {
  if (line.length === 0) return;

  let entry;
  try {
    entry = JSON.parse(line.toString('utf-8'));
  } catch (e) {
    return;
  }

  const payload = entry.payload;
  if (!payload) return;

  if (entry.type === 'turn_context' && payload.model && !state.model) {
    state.model = payload.model;
    state.effort = payload.effort || null;
  } else if (payload.type === 'token_count' && payload.info && !state.info) {
    state.info = payload.info;
    state.rateLimits = payload.rate_limits || null;
  }
}

function buildSnapshot(state) {
  const metrics = [];

  if (state.model) {
    metrics.push({
      title: 'Model',
      formattedValue: `${state.model}${state.effort ? ` (${state.effort})` : ''}`
    });
  }

  const contextMetric = buildContextMetric(state.info);
  if (contextMetric) metrics.push(contextMetric);

  const rateLimits = state.rateLimits || {};
  for (const window of [rateLimits.primary, rateLimits.secondary]) {
    const metric = buildRateLimitMetric(window);
    if (metric) metrics.push(metric);
  }

  metrics.sort(byRateLimitWindow);

  return {
    title: 'Codex',
    symbol: 'chevron.left.forwardslash.chevron.right',
    metrics,
    lastUpdatedDate: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
  };
}

function buildContextMetric(info) {
  const used = info.last_token_usage && info.last_token_usage.total_tokens;
  const size = info.model_context_window;
  if (typeof used !== 'number' || typeof size !== 'number' || size <= 0) return null;

  return buildPercentMetric('Context', used / size * 100);
}

function buildRateLimitMetric(window) {
  if (!window || typeof window.used_percent !== 'number') return null;

  return buildPercentMetric(
    formatWindow(window.window_minutes),
    window.used_percent,
    formatResetTime(window.resets_at)
  );
}

function buildPercentMetric(title, percentage, resetTime) {
  const rounded = Math.round(percentage);

  return {
    title,
    formattedValue: `${rounded}%${resetTime ? ` (${resetTime})` : ''}`,
    normalizedValue: Math.min(1, Math.max(0, rounded / 100))
  };
}

// 短い期間の上限を先に並べる
function byRateLimitWindow(a, b) {
  return windowRank(a.title) - windowRank(b.title);
}

function windowRank(title) {
  const match = /^(\d+)([hd])$/.exec(title);
  if (!match) return -1;

  return Number(match[1]) * (match[2] === 'd' ? 1440 : 60);
}

function formatWindow(minutes) {
  if (typeof minutes !== 'number') return 'Limit';
  if (minutes % 1440 === 0) return `${minutes / 1440}d`;
  if (minutes % 60 === 0) return `${minutes / 60}h`;

  return `${minutes}m`;
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

// RunCat が読みかけのファイルを掴まないよう原子的に置き換える
function writeSnapshot(snapshot) {
  const outDir = path.dirname(OUT_PATH);
  fs.mkdirSync(outDir, { recursive: true });

  const tmpPath = path.join(outDir, `.runcat-${process.pid}.tmp`);
  fs.writeFileSync(tmpPath, JSON.stringify(snapshot));
  fs.renameSync(tmpPath, OUT_PATH);
}
