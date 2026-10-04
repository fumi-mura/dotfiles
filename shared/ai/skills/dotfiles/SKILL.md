---
name: dotfiles
description: Mac・シェル・git・キーボード・Homebrew・AI ツール(Claude/Codex/Gemini)の設定を確認・変更、AI のスキルを作成・編集するときに使う。設定の実体は ~/Program/dotfiles リポジトリにある
---

## 前提

Mac の設定は `~/Program/dotfiles` で管理している。`~` 配下の設定ファイルの多くはこのリポへのシンボリックリンク。

- 確認・変更はリンク先ではなく、リポ側の実体に対して行う

## 対応表

| 対象 | 編集するファイル | リンク先 |
|---|---|---|
| zsh | `zsh/.zshrc`, `zsh/.zprofile` | `~/` |
| git | `git/.gitconfig`, `git/.config/git/ignore` | `~/` |
| Karabiner | `karabiner/.config/karabiner/karabiner.json` | `~/.config/karabiner/` |
| Homebrew | `Brewfile` | - |
| App Store アプリ | `scripts/mas.sh` | - |
| macOS の設定 | `scripts/macos.sh` | - |
| Claude | `ai/claude/.claude/` | `~/.claude/` |
| Codex | `ai/codex/.codex/` | `~/.codex/` |
| Gemini | `ai/gemini/.gemini/` | `~/.gemini/` |
| AI 共通の指示 | `shared/ai/AGENTS.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md` |
| AI 共通のスキル | `shared/ai/skills/<name>/SKILL.md` | `~/.claude/skills/`, `~/.codex/skills/`, `~/.gemini/skills/` |
| AI 共通の hooks | `shared/ai/hooks/` | 各ツールの `hooks/` |

リンクの張り方は `scripts/link.sh` を見る。

## スキルを作るとき

1. `shared/ai/skills/<name>/SKILL.md` に作る。特定の AI 専用のディレクトリには置かない
2. 形式は既存スキルに合わせる(frontmatter の `name` と `description`、本文は日本語)
3. 作成・追加したら `make link` を実行する。リンクを張るまでどの AI にも読み込まれない
4. `~/.agents/skills/` にあるスキルは外部からインストールしたもの。このリポの管理外なので編集しない

## 設定を変更したあと

- リンク対象を増やしたら `make link`
- `make test` を実行する
- 手動で行う設定手順は `docs/<tool>.md` に書く
- 将来「直そう」として壊されそうな設定は、`docs/decisions/` に記録し、一覧の表に追加する
