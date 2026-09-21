---
name: open-output
description: AIが作成した画像やファイルを、場所を変えずに今使っているIDEで開く。引数でパス指定、なければ今回作成したファイルが対象
---

`/open-output [パス...]`。開くだけで、移動・コピー・削除・書き換えはしない。

## 手順

1. **対象を決める**
   - 引数あり: そのパス（`~` は展開）。存在しなければ推測せず報告する
   - 引数なし: 今回自分が作成したファイル。特定できなければ、直近数十分以内に更新されたものを作業ディレクトリ、`~/.codex/generated_images/`、一時ディレクトリから探す。決められなければ選んでもらう
   - 6件以上は、開く前に確認する
2. **IDEを判別する**: `echo "$__CFBundleIdentifier"`

   | 値 | 開き方 |
   |---|---|
   | `com.microsoft.VSCode` | `code -r <path>...` |
   | `com.apple.dt.Xcode` | `xed <path>...` |
   | その他のIDE | `open -b "$__CFBundleIdentifier" <path>...` |

   値が空、またはTerminal・iTerm・Ghostty・Warp などIDEでない場合は、既定のアプリで `open <path>` を使い、その旨を報告する。SSH やtmuxで自信がなければ確認する
3. **開く**: 絶対パスにし、スペースを含むパスはクォートする。IDEで表示できない形式（PDFなど）は `open <path>`。実行可能ファイル、`.app`、`.command`、スクリプトは `open` で開かない（実行されるため）。パスの報告だけにする
4. **報告する**: 開いたフルパスと使ったIDEを書く。開けなかったものは理由を添える
