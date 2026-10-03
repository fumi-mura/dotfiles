---
name: sim-build
description: iOS アプリを iPhone 17 Pro Max のシミュレーターへ、Simulator.app を開かずにビルド・インストール・起動する。Orca の mobile emulator で表示している端末へ入れ直すときに使う
---

`/sim-build [scheme]`。Xcode の ⌘R は Simulator.app を開いてしまうため、`xcodebuild` と `simctl` だけで入れ直す。`open -a Simulator` は使わない。

## 手順

1. **端末を決める**: `xcrun simctl list devices available -j` から名前が `iPhone 17 Pro Max` のものを探す
   - 起動中（`Booted`）があればそれを使う。2台以上起動中なら選んでもらう
   - 起動中がなければ、iOS のバージョンがいちばん新しいものを `xcrun simctl boot <UDID>` で起動する（Simulator.app は開かない）。起動したことを報告に書く
   - 見つからなければ推測せず報告する
2. **プロジェクトと scheme を決める**
   - 作業ディレクトリの `*.xcworkspace`（`Pods` や `.xcodeproj` 内のものは除く）を優先し、なければ `*.xcodeproj`
   - scheme は引数があればそれ。なければ `xcodebuild -list -json` で調べ、プロジェクト名と同じものを使う。決められなければ選んでもらう
3. **ビルドする**
   ```sh
   xcodebuild -project <proj> -scheme <scheme> -destination 'id=<UDID>' -configuration Debug build -quiet
   ```
   workspace のときは `-workspace`。失敗したらエラー箇所を報告して止める
4. **入れ直して起動する**
   - 同じ引数で `-showBuildSettings -json` を実行し、アプリ本体のターゲットの `TARGET_BUILD_DIR`・`FULL_PRODUCT_NAME`・`PRODUCT_BUNDLE_IDENTIFIER` を取る（テストのターゲットと取り違えない）
   ```sh
   xcrun simctl install <UDID> "<TARGET_BUILD_DIR>/<FULL_PRODUCT_NAME>"
   xcrun simctl launch --terminate-running-process <UDID> <PRODUCT_BUNDLE_IDENTIFIER>
   ```
5. **報告する**: 端末名・iOS バージョン・UDID、scheme、起動できたかを書く。触覚・カメラ・音声セッションなどシミュレーターで確かめられない変更なら、実機での確認が要ることも添える
