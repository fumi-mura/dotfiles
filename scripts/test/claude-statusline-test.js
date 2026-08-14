#!/usr/bin/env node
// statusline.js が RunCat Neo 用スナップショットを正しく書き出すかを検証する

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT_DIR = path.resolve(__dirname, '..', '..');
const STATUSLINE = path.join(ROOT_DIR, 'ai', 'claude', '.claude', 'statusline.js');
const FIXTURE = path.join(__dirname, 'fixtures', 'claude-statusline-payload.json');

let failures = 0;
function check(name, cond, detail) {
  if (cond) {
    console.log(`  ok   ${name}`);
  } else {
    failures++;
    console.log(`  FAIL ${name}${detail ? `\n     -> ${detail}` : ''}`);
  }
}

function run(payload) {
  const outFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'runcat-test-')), 'runcat-usage.json');
  const stdout = execFileSync(STATUSLINE, {
    input: JSON.stringify(payload),
    encoding: 'utf-8',
    env: { ...process.env, RUNCAT_OUT_FILE: outFile }
  });
  const snapshot = fs.existsSync(outFile) ? JSON.parse(fs.readFileSync(outFile, 'utf-8')) : null;
  return { stdout, snapshot };
}

function row(snapshot, title) {
  return (snapshot.metrics || []).find(m => m.title === title);
}

const base = JSON.parse(fs.readFileSync(FIXTURE, 'utf-8'));

// 期待値はフィクスチャから導出する（値を差し替えても壊れないように）
const expectedTokens = Object.values(base.context_window.current_usage).reduce((a, b) => a + b, 0);
const expectedTokenDisplay = `${(expectedTokens / 1000).toFixed(1)}K`;
const expectedCtx = base.context_window.used_percentage;
const expectedFive = base.rate_limits.five_hour.used_percentage;
const expectedSeven = base.rate_limits.seven_day.used_percentage;
const expectedCost = `$${base.cost.total_cost_usd.toFixed(2)}`;

console.log('case 1: 通常の payload');
{
  const { stdout, snapshot } = run(base);

  check('スナップショットが書き出される', snapshot !== null);
  if (snapshot) {
    check('title が Claude Code', snapshot.title === 'Claude Code', snapshot.title);
    check('symbol が設定されている', typeof snapshot.symbol === 'string' && snapshot.symbol.length > 0);
    check('metricsBarValue は出力しない', snapshot.metricsBarValue === undefined, snapshot.metricsBarValue);
    check('lastUpdatedDate が ISO8601(秒精度)',
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(snapshot.lastUpdatedDate || ''), snapshot.lastUpdatedDate);

    const model = row(snapshot, 'Model');
    check('Model 行に表示名と思考レベルが入る',
      model && model.formattedValue === `${base.model.display_name} (${base.effort.level})`, JSON.stringify(model));

    const ctx = row(snapshot, 'Context');
    check(`Context 行が ${expectedCtx}%`, ctx && ctx.formattedValue === `${expectedCtx}%`, JSON.stringify(ctx));
    check('Context の normalizedValue が使用率/100',
      ctx && Math.abs(ctx.normalizedValue - expectedCtx / 100) < 1e-9, ctx && ctx.normalizedValue);

    const five = row(snapshot, '5h');
    check('5h 行に使用率とリセット時刻が入る',
      five && new RegExp(`^${expectedFive}% \\(~.+\\)$`).test(five.formattedValue), JSON.stringify(five));
    check('5h の normalizedValue が使用率/100',
      five && Math.abs(five.normalizedValue - expectedFive / 100) < 1e-9, five && five.normalizedValue);

    const seven = row(snapshot, '7d');
    check('7d 行に使用率とリセット時刻が入る',
      seven && new RegExp(`^${expectedSeven}% \\(~.+\\)$`).test(seven.formattedValue), JSON.stringify(seven));

    const cost = row(snapshot, 'Cost');
    check(`Cost 行が ${expectedCost}`, cost && cost.formattedValue === expectedCost, JSON.stringify(cost));
  }

  check('ステータスラインにモデル名が出る', stdout.includes(`[${base.model.display_name}]`), stdout.trim());
  check('ステータスラインにディレクトリ名が出る', stdout.includes(path.basename(base.cwd)), stdout.trim());
  check(`ステータスラインのトークン数が payload 由来 (${expectedTokenDisplay})`,
    stdout.includes(expectedTokenDisplay), stdout.trim());
  check('ステータスラインにセッションIDが出る', stdout.includes(base.session_id), stdout.trim());
}

console.log('case 2: effort なし');
{
  const payload = JSON.parse(JSON.stringify(base));
  delete payload.effort;
  const { snapshot } = run(payload);

  const model = row(snapshot, 'Model');
  check('Model 行は表示名だけになる',
    model && model.formattedValue === base.model.display_name, JSON.stringify(model));
}

console.log('case 3: rate_limits なし');
{
  const payload = JSON.parse(JSON.stringify(base));
  delete payload.rate_limits;
  const { snapshot } = run(payload);

  check('5h 行が出ない', snapshot && !row(snapshot, '5h'));
  check('7d 行が出ない', snapshot && !row(snapshot, '7d'));
  check('Context 行は残る', snapshot && !!row(snapshot, 'Context'));
}

console.log('case 4: 空 payload');
{
  const { stdout, snapshot } = run({});

  check('クラッシュせず書き出される', snapshot !== null);
  check('metrics が空でも title は入る', snapshot && snapshot.title === 'Claude Code');
  check('ステータスラインは出力される', stdout.trim().length > 0);
}

console.log('case 5: context_window なし');
{
  const payload = JSON.parse(JSON.stringify(base));
  delete payload.context_window;
  const { stdout, snapshot } = run(payload);

  check('Context 行が出ない', snapshot && !row(snapshot, 'Context'));
  check('Model 行は残る', snapshot && !!row(snapshot, 'Model'));
  check('ステータスラインは壊れない', stdout.includes(`[${base.model.display_name}]`), stdout.trim());
}

console.log(failures === 0 ? '\nAll tests passed' : `\n${failures} test(s) failed`);
process.exit(failures === 0 ? 0 : 1);
