---
name: review-loop
description: 別のAIに作業させ、確かめる側のAIが判定して直す指示を返す流れを、決めた回数だけユーザー抜きでくり返す。画像の作成・修正やUIの実装など、何度か直しが要りそうな作業で使う
---

`/review-loop <task> work=codex review=self fix=1`

| 引数 | 意味 | 初期値 |
|---|---|---|
| `work` | 作る側（`codex`・`claude`） | `codex` |
| `review` | 確かめる側（`self`・`codex`・`claude`）。`self` はこのスキルを動かしているAI | `self` |
| `fix` | 直す回数（0〜3。4以上はユーザーに確かめる） | `1` |

画像の作成・修正や、UI・デザインの実装など、何度か直しが要りそうな作業に使う。一度で決まる作業（テストを書くなど）は、このスキルを使わずに自分で進める。

## 手順

1. 作業、終わりの条件（コマンド）、引数を表で見せ、ユーザーのOKをもらってから5まで続けて進める
2. 作る側を新しい会話で起動する。コミット・push・削除・外部への公開・範囲外の変更を禁じ、返事は変えたファイルと要点を10行以内にさせる
3. 終わりの条件のコマンドを自分で流し、その結果と `git diff` を確かめる側に渡す。画像やUIは、書き出した画像やスクリーンショットのパスも渡す。確かめる側は読むだけにし、毎回新しい会話で起動する（2回目からは前回の指摘も渡す）。返事は次の形にさせる

  ```text
  判定: OK | 要修正 | 要相談
  - <高/中/低> <ファイル:行> <直すこと>（重要な順に5つまで）
  ```

4. OKなら5へ。要相談なら止めてユーザーに聞く。要修正で `fix` が残っていれば、作る側の同じ会話に指摘を送って3へ。残っていなければ5へ
5. 各回の判定、残った指摘、`git diff --stat`、使った量を報告する

やり取りは `${TMPDIR:-/tmp}/review-loop/<日時>/` に残す。

## コマンド

| | Codex | Claude |
|---|---|---|
| 作る | `codex exec --json -o out.md "<指示>" < /dev/null > log.jsonl` | `claude -p --output-format json --max-budget-usd 1 --permission-mode acceptEdits "<指示>"` |
| 続ける | `codex exec resume --json -o out.md <ID> "<指摘>" < /dev/null > log.jsonl` | 作るに `--resume <ID>` を足す |
| 確かめる | 作るに `-s read-only` を足す | 作るの `acceptEdits` を `plan` にする |
| ID・返事 | `log.jsonl` 1行目の `thread_id`・`out.md` | JSONの `session_id`・`result` |
| 使った量 | `turn.completed` の `usage` | `total_cost_usd` |

- Codex は `< /dev/null` がないと、標準入力を待つことがある
- Codex に Swift のパッケージを扱わせるときは、指示に「`swift build`・`swift test` には `--disable-sandbox` を付ける」と入れる。Codex のサンドボックスの中では、SwiftPM の `sandbox-exec` が許されず止まるため
- Claude の作る側はコマンドを流せない（`acceptEdits`）ので、終わりの条件は自分で流す
- Codex は金額の上限を付けられないので、`fix` で抑える
- 1回に数分かかることがある。制限時間を超えそうなら、バックグラウンドで動かす
