# dotfiles

Mac の買い替えや複数 Mac で、同じ環境を少ない手順で再現するためのリポジトリです。

`make install` で、次のセットアップをまとめて実行します。

- Homebrew と Brewfile の適用
- dotfiles(.xxx ファイル) のシンボリックリンク作成
- App Store アプリのインストール
- MacOS 設定の反映

## Setup

### 1. Clone repository

```sh
# Git の設定前
cd ~ && \
curl -LO https://github.com/fumi-mura/mac-auto-setup/archive/refs/heads/main.zip && \
unzip -q main.zip && mv dotfiles-main dotfiles && \
rm main.zip

# Git の設定後
git clone {this_repository}
```

### 2. Run full setup

```sh
cd ~/dotfiles
make install
```

`make` が使えない場合は、次のコマンドでも実行できます。

```sh
cd ~/dotfiles
./scripts/install.sh
```

## Partial setup

```sh
make brew
make link
make mas
make macos
```

## Test

```sh
make test
```

## Repository layout

- `zsh`, `git`, `karabiner`: shell と各種ローカル設定
- `ai`: Claude / Codex / Gemini の設定
- `shared/ai`: AI ツール間で共有する指示や skills
- `scripts/test`: セットアップスクリプトと AI ツール連携のテスト
- `docs`: 手動設定や補足手順

## Other software list

- Chrome Extensions
  - Authenticator
  - DeepL
  - Keepa
  - Octotree
  - Wappalyzer
