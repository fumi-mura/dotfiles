---
name: devlog
description: DictCat の開発の進捗を、開発ビルドの実画面の録画から X に投稿する（TikTok・Instagram はアカウントができてから）。「進捗を投稿したい」「devlog を出して」「Build in Public の投稿を作って」と頼まれたときに使う
---

`/devlog`。ネタ出しから書き出しまでを進め、生成物と本文を見せて OK をもらってから送る。コマンドは PromoKit（`~/Program/promokit`）のルートで流す。撮り方と出力の詳細は `releases/dictcat/devlog/README.md`、本文と X の決まりは PromoKit の AGENTS.md「SNS の本文」「X」。

## 手順

1. **ネタを決める**
   - `releases/dictcat/devlog/*/commit.txt` のうち最新の投稿のコミットから、`~/Program/dictcat` の HEAD までの `git log`（まだ無ければ、どこからを対象にするか聞く）と、DictCat の `docs/plan.md` §12・§13 で増えた ✓ を読む
   - 画面で見える変化を3つまで候補に出し、選んでもらう。画面に出ない変更だけなら、今回は出さないことを提案する
   - `<id>` は `<YYYYMMDD>-<切り口>`（例 `20261103-cat-typing`）
2. **撮り方を決める**
   - 猫の動きやパネルの見た目を見せる回は、見本の文（既定）
   - 文字起こしの精度を見せる回は `--voice <秒>`。話す文を提案し、ユーザーに話してもらう
   - ペットの設定（`--pet-item laptop|none`）を、見せる動きに合わせる
3. **撮る**
   - `~/Program/dictcat/scripts/relaunch_dev_app.sh` で起動し直す
   - 「約15秒、画面に触らないでください」と伝えてから `python3 releases/dictcat/devlog/record/capture.py --out assets/footage/dictcat/inbox/<id>` を流す
   - 撮影用の操作スペースが無い、またはほかのウィンドウがあると止まるので、出た文言のとおりにユーザーへ頼む
4. **本文を書く**
   - `releases/dictcat/devlog/<id>/x.txt` と、Instagram・TikTok 用の `caption.txt`
   - 何ができるようになったかを1〜2文で書き、`#BuildInPublic #個人開発` を付ける。URL は付けない
   - 見本の文で撮った回は「表示している文章は動作確認用の見本です」と添える
5. **書き出す**
   - `npm run promokit -- devlog prepare`。`--image-crop`・`--video-crop` は `<inbox>/crops.json` の値を渡す（README.md）
6. **見せる**
   - 静止画4枚を横に並べた1枚と動画を `open` で開き、`npm run promokit -- x post --app dictcat --post <id>-video --dry-run`（画像の回は `<id>-image`）で本文と文字数を見せる
   - 見る点: 猫とパネルが枠に収まっているか、文字が切れていないか、話した内容に個人情報が無いか
7. **OK をもらってから送る**
   - `npm run promokit -- x post --app dictcat --post <id>-video`（または `-image`）
8. **記録する**
   - `releases/dictcat/devlog/<id>/commit.txt` に、撮った時点の DictCat の `git rev-parse HEAD` を書く
   - `generated/` の `.mp4` を消す。送った記録（`*.post.json`）と本文は残す
   - PromoKit で `/commit-push` を案内する
