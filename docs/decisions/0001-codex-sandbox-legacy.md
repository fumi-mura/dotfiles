# 0001: Codex のサンドボックスはレガシー形式を使う

- 日付: 2026-08-14
- 状態: 有効
- 対象: `ai/codex/.codex/config.toml`

## 決定

`sandbox_mode` と `[sandbox_workspace_write]` を使う。
新しい `default_permissions` と `[permissions.*]` には移行しない。

## 理由

`default_permissions` を設定すると `[sandbox_workspace_write]` が無視され、
ネットワーク許可の手段が無くなる。この状態では `npm install` や `curl` が
`Could not resolve host` で失敗する。

Codex 0.147 で以下を試したが、いずれもネットワークは開かなかった。

- `permissions.<name>.network = { mode = "full" }` および `{ mode = "limited", domains = {...} }`
- トップレベルの `[network]` セクション
- `--enable network_proxy` (experimental)

`:danger-full-access` だけは有効になるが、これはサンドボックス自体を無効化する。

## 解除条件

新モデルでネットワークを許可できるようになったら移行する。

```sh
codex doctor --json | grep '"network sandbox"'
```

これが `enabled` を返せば移行可能。`restricted` の間はレガシー形式を維持する。
