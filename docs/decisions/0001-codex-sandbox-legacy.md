# 0001: Codex の権限プロファイルで Program 配下を管理する

- 日付: 2026-08-14
- 状態: 有効
- 対象: `ai/codex/.codex/config.toml`

## 決定

`default_permissions` と `[permissions.*]` を使う。
`program-edit` プロファイルは `/Users/fumiakimuramatsu/Program` をワークスペースに追加し、通常のファイル、`.agents/`、各リポジトリの `.git/` を書き込み可能にする。

`:workspace` を継承し、`.codex/` の読み取り専用保護を維持する。`.git/` の書き込み許可は、承認を求めず `git fetch` などを実行するための例外とする。
`make link` がスキルなどのリンクを作成するホーム配下の実ディレクトリ（`~/.claude/skills` など）だけを個別に `write` 許可する。ホーム全体や `.codex/` 全体は許可しない。これにより、スキル追加後のリンク作成にも対応する。
`~/.zshrc` や `~/.claude/CLAUDE.md` のようなシンボリックリンク自体は writable root に指定できず、指定すると Seatbelt の準備に失敗して Codex が起動しない（0.160.0 で確認）。リンク先は Program 配下にあり、ワークスペースの権限で書き込めるため指定不要。
`scripts/link.sh` はリンク先が既に正しい場合は張り直さない。ホーム直下など許可範囲外の既存リンクに触れずに `make link` を実行するため。許可範囲外のリンクが欠けているか誤っている場合は、その場所への書き込み権限が別途必要になる。
`"**/.git" = "write"` のように `**/` で始まる glob は `deny` にしか使えず、`write` を書くと設定全体が読み込めなくなり Codex が起動しない（0.160.0 で確認）。そのため `.git` は完全一致の 1 行だけにしている。0.160.0 の `codex sandbox` では、この行が無くても他リポジトリを含む `.git/` に書き込めた。

プロジェクト内の資格情報に使われる次のパターンは、読み書きを拒否する。

- `.env`、`.env.*`、`.netrc`（サブディレクトリを含む）
- `*.pem`、`*.key`、`*.p8`、`*.p12`、`*.mobileprovision`（サブディレクトリを含む）
- `credentials.*`、`secrets.*`（サブディレクトリを含む）

## 理由

`.agents/` はレガシーの `workspace-write` サンドボックスでは、ワークスペース内でも再帰的に読み取り専用となる。引き継ぎ資料を更新する用途には、`.agents` を明示的に書き込み可能にする権限プロファイルが必要だった。

Codex 0.147 では権限プロファイルでネットワークを許可できず、レガシー形式を維持していた。Codex 0.149 で `codex doctor --json` を確認したところ、`network sandbox` が `enabled` となり、`permissions.<name>.network.enabled = true` でネットワークを使える状態になった。

資格情報の追加パターンが必要になった場合は、書き込み許可を広げずにこのプロファイルの deny ルールへ追加する。
