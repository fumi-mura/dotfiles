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
    // 上限に弾かれたターンは info が null になるので、token_count の有無だけで判断する
    if (!state.tokenCount) return;

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
  const state = {
    tokenCount: false,
    info: null,
    rateLimits: null,
    model: null,
    effort: null,
    limitMessage: null,
    sawTaskComplete: false
  };
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
        if (state.tokenCount && state.model) return state;
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
  } else if (payload.type === 'token_count' && !state.tokenCount) {
    state.tokenCount = true;
    state.info = payload.info || null;
    state.rateLimits = payload.rate_limits || null;
  } else if (payload.type === 'task_complete' && !state.tokenCount && !state.sawTaskComplete) {
    // token_count より先に見つかる = そのターンのほうが新しい。
    // token_count の使用率は上限到達に遅れて追いつくので、新しいエラーのほうを信じる
    state.sawTaskComplete = true;
    const error = payload.error;
    if (error && error.codex_error_info === 'usage_limit_exceeded') {
      state.limitMessage = error.message || null;
    }
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

  const contextMetric = state.info && buildContextMetric(state.info);
  if (contextMetric) metrics.push(contextMetric);

  const rateLimits = state.rateLimits || {};
  for (const window of [rateLimits.primary, rateLimits.secondary]) {
    const metric = buildRateLimitMetric(window);
    if (metric) metrics.push(metric);
  }

  applyLimitReached(metrics, state.limitMessage);
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

// 上限に到達すると rate_limits の窓情報が丸ごと null で返ることがあり、そのままでは
// 残量が分からなくなる。エラーメッセージから復帰時刻を読んで 100% として埋める。
// rate_limits.rate_limit_reached_type も同じ用途に見えるが、手元のログでは常に null で
// 取りうる値を確認できていないため使っていない
function applyLimitReached(metrics, message) {
  const reached = message && parseLimitReached(message);
  if (!reached) return;

  const metric = buildPercentMetric(reached.title, 100, formatResetTime(reached.resetsAt));
  const index = metrics.findIndex(m => m.title === reached.title);

  if (index >= 0) {
    metrics[index] = metric;
  } else {
    metrics.push(metric);
  }
}

// Codex は復帰が当日なら時刻だけ、翌日以降なら日付付きで出す。
// どちらの窓が尽きたかは返ってこないので、この違いから 5h / 7d を推定する。
// 5h の窓が日をまたぐと 7d と誤判定するが、窓を偽るよりはましなので判定できた場合だけ扱う
function parseLimitReached(message) {
  const match = /try again at (.+?)\.?\s*$/.exec(message);
  if (!match) return null;

  const text = match[1];
  const dated = /^([A-Z][a-z]{2}) (\d{1,2})(?:st|nd|rd|th)?, (\d{4}) (.+)$/.exec(text);
  if (dated) {
    const reset = new Date(`${dated[1]} ${dated[2]}, ${dated[3]} ${dated[4]}`);
    return isNaN(reset.getTime()) ? null : { title: '7d', resetsAt: reset.getTime() / 1000 };
  }

  const timeOnly = /^(\d{1,2}):(\d{2})\s*(AM|PM)$/i.exec(text);
  if (timeOnly) {
    const reset = nextOccurrence(Number(timeOnly[1]) % 12 + (/pm/i.test(timeOnly[3]) ? 12 : 0), Number(timeOnly[2]));
    return { title: '5h', resetsAt: reset.getTime() / 1000 };
  }

  return null;
}

function nextOccurrence(hours, minutes) {
  const reset = new Date();
  reset.setHours(hours, minutes, 0, 0);
  // 復帰時刻は必ず未来なので、過ぎていれば翌日とみなす
  if (reset.getTime() <= Date.now()) reset.setDate(reset.getDate() + 1);

  return reset;
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
  const rounded = Math.round(percentage * 10) / 10;

  return {
    title,
    formattedValue: `${rounded.toFixed(1)}%${resetTime ? ` (${resetTime})` : ''}`,
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
