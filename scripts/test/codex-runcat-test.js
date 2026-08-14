#!/usr/bin/env node
// runcat-usage.js が Codex のセッションログから RunCat Neo 用スナップショットを作れるかを検証する

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const ROOT_DIR = path.resolve(__dirname, '..', '..');
const SCRIPT = path.join(ROOT_DIR, 'ai', 'codex', '.codex', 'runcat-usage.js');
const FIXTURE = path.join(__dirname, 'fixtures', 'codex-session.jsonl');

let failures = 0;
function check(name, cond, detail) {
  if (cond) {
    console.log(`  ok   ${name}`);
  } else {
    failures++;
    console.log(`  FAIL ${name}${detail ? `\n     -> ${detail}` : ''}`);
  }
}

// セッションログを持つ一時的な CODEX_HOME を組み立てる
function makeHome(sessions) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-runcat-test-'));

  sessions.forEach((session, index) => {
    const dir = path.join(home, 'sessions', '2026', '08', String(11 + index).padStart(2, '0'));
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, `rollout-${index}.jsonl`);
    fs.writeFileSync(file, session.map(line => JSON.stringify(line)).join('\n') + '\n');
    // 更新時刻で新旧が決まるので、後ろの要素ほど新しくする
    const mtime = new Date(Date.now() - (sessions.length - index) * 60000);
    fs.utimesSync(file, mtime, mtime);
  });

  return home;
}

function run(home) {
  const result = execFileSync(SCRIPT, {
    input: '{}',
    encoding: 'utf-8',
    env: { ...process.env, CODEX_HOME: home }
  });
  const outFile = path.join(home, 'runcat-usage.json');
  const snapshot = fs.existsSync(outFile) ? JSON.parse(fs.readFileSync(outFile, 'utf-8')) : null;
  return { stdout: result, snapshot, outFile };
}

function row(snapshot, title) {
  return (snapshot.metrics || []).find(m => m.title === title);
}

const baseLines = fs.readFileSync(FIXTURE, 'utf-8').trim().split('\n').map(JSON.parse);
const tokenCount = baseLines.find(l => l.payload && l.payload.type === 'token_count');
const turnContext = baseLines.find(l => l.type === 'turn_context');

const expectedModel = `${turnContext.payload.model} (${turnContext.payload.effort})`;
const info = tokenCount.payload.info;
const expectedCtx = Math.round(info.last_token_usage.total_tokens / info.model_context_window * 1000) / 10;
const expectedPrimary = Math.round(tokenCount.payload.rate_limits.primary.used_percent * 10) / 10;

console.log('case 1: 通常のセッション');
{
  const { snapshot } = run(makeHome([baseLines]));

  check('スナップショットが書き出される', snapshot !== null);
  if (snapshot) {
    check('title が Codex', snapshot.title === 'Codex', snapshot.title);
    check('symbol が設定されている', typeof snapshot.symbol === 'string' && snapshot.symbol.length > 0);
    check('lastUpdatedDate が ISO8601(秒精度)',
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(snapshot.lastUpdatedDate || ''), snapshot.lastUpdatedDate);
    check('metricsBarValue は出力しない', snapshot.metricsBarValue === undefined, snapshot.metricsBarValue);

    const model = row(snapshot, 'Model');
    check(`Model 行が ${expectedModel}`, model && model.formattedValue === expectedModel, JSON.stringify(model));

    const ctx = row(snapshot, 'Context');
    check(`Context 行が ${expectedCtx.toFixed(1)}%`,
      ctx && ctx.formattedValue === `${expectedCtx.toFixed(1)}%`, JSON.stringify(ctx));
    check('Context の normalizedValue が使用率/100',
      ctx && Math.abs(ctx.normalizedValue - expectedCtx / 100) < 1e-9, ctx && ctx.normalizedValue);

    // window_minutes 10080 は 7 日
    const seven = row(snapshot, '7d');
    check('window_minutes 10080 が 7d 行になる',
      seven && new RegExp(`^${expectedPrimary.toFixed(1)}% \\(~.+\\)$`).test(seven.formattedValue), JSON.stringify(seven));
    check('7d の normalizedValue が使用率/100',
      seven && Math.abs(seven.normalizedValue - expectedPrimary / 100) < 1e-9, seven && seven.normalizedValue);

    check('secondary が null なら行を作らない', snapshot.metrics.length === 3, JSON.stringify(snapshot.metrics));
  }
}

// Codex は 2026-08 時点で 10080(7d) しか返さないが、window_minutes の解釈は Codex 側の
// 都合で変わるので、5h が復活しても壊れないことを確かめておく
console.log('case 2: primary と secondary の両方がある');
{
  const lines = JSON.parse(JSON.stringify(baseLines));
  const rl = lines.find(l => l.payload && l.payload.type === 'token_count').payload.rate_limits;
  rl.primary = { used_percent: 42.4, window_minutes: 300, resets_at: 1787042365 };
  rl.secondary = { used_percent: 12.6, window_minutes: 10080, resets_at: 1787042365 };
  const { snapshot } = run(makeHome([lines]));

  const five = row(snapshot, '5h');
  const seven = row(snapshot, '7d');
  check('window_minutes 300 は 5h 行になる', five && five.formattedValue.startsWith('42.4%'), JSON.stringify(five));
  check('secondary も 7d 行になる', seven && seven.formattedValue.startsWith('12.6%'), JSON.stringify(seven));
  check('5h が 7d より先に並ぶ',
    snapshot.metrics.findIndex(m => m.title === '5h') < snapshot.metrics.findIndex(m => m.title === '7d'));
}

console.log('case 3: 最新のセッションを使う');
{
  const older = JSON.parse(JSON.stringify(baseLines));
  older.find(l => l.type === 'turn_context').payload.model = 'gpt-old';
  const newer = JSON.parse(JSON.stringify(baseLines));
  newer.find(l => l.type === 'turn_context').payload.model = 'gpt-new';
  const { snapshot } = run(makeHome([older, newer]));

  const model = row(snapshot, 'Model');
  check('新しい方のセッションのモデルになる',
    model && model.formattedValue.startsWith('gpt-new'), JSON.stringify(model));
}

console.log('case 4: token_count がないセッションは既存スナップショットを壊さない');
{
  const home = makeHome([baseLines]);
  run(home);
  const before = fs.readFileSync(path.join(home, 'runcat-usage.json'), 'utf-8');

  const dir = path.join(home, 'sessions', '2026', '08', '20');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'rollout-empty.jsonl'),
    JSON.stringify(baseLines[0]) + '\n' + JSON.stringify(baseLines[1]) + '\n');

  run(home);
  const after = fs.readFileSync(path.join(home, 'runcat-usage.json'), 'utf-8');
  check('スナップショットが上書きされない', before === after, after);
}

console.log('case 5: effort がなければモデル名だけになる');
{
  const lines = JSON.parse(JSON.stringify(baseLines));
  delete lines.find(l => l.type === 'turn_context').payload.effort;
  const { snapshot } = run(makeHome([lines]));

  const model = row(snapshot, 'Model');
  check('Model 行はモデル名だけ', model && model.formattedValue === turnContext.payload.model, JSON.stringify(model));
}

console.log('case 6: sessions ディレクトリがなくても落ちない');
{
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-runcat-test-'));
  let threw = null;
  try {
    run(home);
  } catch (e) {
    threw = e;
  }
  check('例外を投げず正常終了する', threw === null, threw && threw.message);
  check('スナップショットは作らない', !fs.existsSync(path.join(home, 'runcat-usage.json')));
}

console.log('case 7: 壊れた行があっても処理を続ける');
{
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-runcat-test-'));
  const dir = path.join(home, 'sessions', '2026', '08', '11');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'rollout-broken.jsonl'),
    '{ this is not json\n' + baseLines.map(l => JSON.stringify(l)).join('\n') + '\n');

  const { snapshot } = run(home);
  check('スナップショットが書き出される', snapshot !== null);
  check('Context 行が入る', snapshot && !!row(snapshot, 'Context'));
}

console.log('case 8: 巨大なセッションでも末尾だけ読む');
{
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-runcat-test-'));
  const dir = path.join(home, 'sessions', '2026', '08', '11');
  fs.mkdirSync(dir, { recursive: true });

  // 実際に 500MB 級のセッションログが存在するので、全読みしない実装であることを確かめる
  const file = path.join(dir, 'rollout-big.jsonl');
  const pad = JSON.stringify({ type: 'event_msg', payload: { type: 'agent_message', message: 'x'.repeat(400) } }) + '\n';
  const handle = fs.openSync(file, 'w');
  const block = Buffer.from(pad.repeat(2000));
  for (let i = 0; i < 80; i++) fs.writeSync(handle, block);
  fs.writeSync(handle, baseLines.map(l => JSON.stringify(l)).join('\n') + '\n');
  fs.closeSync(handle);

  const sizeMb = fs.statSync(file).size / 1024 / 1024;
  const measured = spawnSync('/usr/bin/time', ['-l', SCRIPT], {
    input: '{}',
    encoding: 'utf-8',
    env: { ...process.env, CODEX_HOME: home }
  });
  const rssMb = Number((/(\d+)\s+maximum resident set size/.exec(measured.stderr) || [])[1]) / 1024 / 1024;
  const snapshot = JSON.parse(fs.readFileSync(path.join(home, 'runcat-usage.json'), 'utf-8'));

  check(`${sizeMb.toFixed(0)}MB のログでも正しく読める`, !!row(snapshot, 'Context'), JSON.stringify(snapshot.metrics));
  check(`メモリ使用量がファイルサイズに引きずられない (${rssMb.toFixed(0)}MB)`, rssMb < 150, `${rssMb.toFixed(0)}MB`);

  fs.rmSync(home, { recursive: true, force: true });
}

console.log(failures === 0 ? '\nAll tests passed' : `\n${failures} test(s) failed`);
process.exit(failures === 0 ? 0 : 1);
