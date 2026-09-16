# 0001: Codex の権限プロファイルで Program 配下を管理する

- 日付: 2026-08-14
- 状態: 有効
- 対象: `ai/codex/.codex/config.toml`

## 決定

`default_permissions` と `[permissions.*]` を使う。
`program-edit` プロファイルは `/Users/fumiakimuramatsu/Program` をワークスペースに追加し、通常のファイルと `.agents/` を書き込み可能にする。

`:workspace` を継承し、`.git/` と `.codex/` の読み取り専用保護を維持する。プロジェクト内の資格情報に使われる次のパターンは、読み書きを拒否する。

- `.env`、`.env.*`、`.netrc`（サブディレクトリを含む）
- `*.pem`、`*.key`、`*.p8`、`*.p12`、`*.mobileprovision`（サブディレクトリを含む）
- `credentials.*`、`secrets.*`（サブディレクトリを含む）

## 理由

`.agents/` はレガシーの `workspace-write` サンドボックスでは、ワークスペース内でも再帰的に読み取り専用となる。引き継ぎ資料を更新する用途には、`.agents` を明示的に書き込み可能にする権限プロファイルが必要だった。

Codex 0.147 では権限プロファイルでネットワークを許可できず、レガシー形式を維持していた。Codex 0.149 で `codex doctor --json` を確認したところ、`network sandbox` が `enabled` となり、`permissions.<name>.network.enabled = true` でネットワークを使える状態になった。

資格情報の追加パターンが必要になった場合は、書き込み許可を広げずにこのプロファイルの deny ルールへ追加する。
