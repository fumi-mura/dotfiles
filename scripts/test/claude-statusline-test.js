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
    check(`Context 行が ${expectedCtx.toFixed(1)}%`,
      ctx && ctx.formattedValue === `${expectedCtx.toFixed(1)}%`, JSON.stringify(ctx));
    check('Context の normalizedValue が使用率/100',
      ctx && Math.abs(ctx.normalizedValue - expectedCtx / 100) < 1e-9, ctx && ctx.normalizedValue);

    const five = row(snapshot, '5h');
    check('5h 行に使用率とリセット時刻が入る',
      five && new RegExp(`^${expectedFive.toFixed(1)}% \\(~.+\\)$`).test(five.formattedValue), JSON.stringify(five));
    check('5h の normalizedValue が使用率/100',
      five && Math.abs(five.normalizedValue - expectedFive / 100) < 1e-9, five && five.normalizedValue);

    const seven = row(snapshot, '7d');
    check('7d 行に使用率とリセット時刻が入る',
      seven && new RegExp(`^${expectedSeven.toFixed(1)}% \\(~.+\\)$`).test(seven.formattedValue), JSON.stringify(seven));

    check('Cost 行は出力しない', !row(snapshot, 'Cost'), JSON.stringify(row(snapshot, 'Cost')));
  }

  check('ステータスラインにモデル名と思考レベルが出る',
    stdout.includes(`[${base.model.display_name} (${base.effort.level})]`), stdout.trim());
  check(`ステータスラインの割合が payload の used_percentage (${expectedCtx.toFixed(1)}%)`,
    stdout.includes(`${expectedCtx.toFixed(1)}%`), stdout.trim());
  check('ステータスラインにディレクトリ名が出る', stdout.includes(path.basename(base.cwd)), stdout.trim());
  check(`ステータスラインのトークン数が payload 由来 (${expectedTokenDisplay})`,
    stdout.includes(expectedTokenDisplay), stdout.trim());
  check('ステータスラインにセッションIDが出る', stdout.includes(base.session_id), stdout.trim());
}

console.log('case 2: effort なし');
{
  const payload = JSON.parse(JSON.stringify(base));
  delete payload.effort;
  const { stdout, snapshot } = run(payload);

  const model = row(snapshot, 'Model');
  check('Model 行は表示名だけになる',
    model && model.formattedValue === base.model.display_name, JSON.stringify(model));
  check('ステータスラインも表示名だけになる',
    stdout.includes(`[${base.model.display_name}]`), stdout.trim());
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
  check('ステータスラインは壊れない',
    stdout.includes(`[${base.model.display_name} (${base.effort.level})]`), stdout.trim());
}

console.log('case 6: 小数を含む使用率');
{
  const payload = JSON.parse(JSON.stringify(base));
  payload.context_window.used_percentage = 12.34;
  payload.rate_limits.five_hour.used_percentage = 57.99999999999999;
  payload.rate_limits.seven_day.used_percentage = 8.06;
  const { snapshot } = run(payload);

  const ctx = row(snapshot, 'Context');
  const five = row(snapshot, '5h');
  const seven = row(snapshot, '7d');

  check('小数第一位まで残る', ctx && ctx.formattedValue === '12.3%', JSON.stringify(ctx));
  check('浮動小数点の誤差が出ない', five && five.formattedValue.startsWith('58.0%'), JSON.stringify(five));
  check('小数第二位は丸める', seven && seven.formattedValue.startsWith('8.1%'), JSON.stringify(seven));
  check('normalizedValue も丸めた値を使う',
    ctx && Math.abs(ctx.normalizedValue - 0.123) < 1e-9, ctx && ctx.normalizedValue);

  const { stdout } = run(payload);
  check('ステータスラインも小数第一位で揃う', stdout.includes('12.3%'), stdout.trim());
}

console.log(failures === 0 ? '\nAll tests passed' : `\n${failures} test(s) failed`);
process.exit(failures === 0 ? 0 : 1);
