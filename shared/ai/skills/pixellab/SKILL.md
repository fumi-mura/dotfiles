---
name: pixellab
description: PixelLab の API で、手持ちのドット絵（1枚）から動きのコマを作る。生成前にgenの見込みを伝えて確認し、終わったら消費したgenを報告して、一覧画像とGIFを開く
---

道具は `~/Program/aseprite-art/tools/` にある。コマンドはそのリポジトリの直下で実行する。

## 前提

- APIトークンはキーチェーンの `pixellab-api`（`animate_sprite.py` が読む）
- 画像から動きを作るのは有料プラン（Tier 1 以上）だけ。料金は月のgenから引かれる。64×64 の動きは1回1 gen

## 手順

1. **元の絵を用意する**: 64×64 の透過PNG。原本が `.aseprite` なら、影と効果のレイヤーを外して書き出す（`./aseprite -b --ignore-layer shadow --ignore-layer effect --frame-range 0,0 <原本> --save-as temp/<作業名>/src/<名前>.png`）。拡大した絵は渡さない
2. **確認を取る**: 呼ぶ回数・使うgen・指示文をユーザーに見せ、了承を得てから流す。`python3 -B tools/animate_sprite.py --balance` で残りを確かめる（gen は減らない）
3. **生成する**:
   ```sh
   python3 -B tools/animate_sprite.py --first <元の絵> --last <元の絵> --action "<英語の指示文>" --frames 8 --out temp/<作業名>/out/<名前>
   ```
   - `--last` に元の絵を渡すと、元の姿勢で終わる。姿勢を移る動きは、移った先の絵を渡す
   - 1回2〜3分かかる。複数あるときは並べて流す。一度送ると、手元を止めても gen は戻らない
4. **報告する**: 表示されたコマ数・秒数・使ったgen・残りのgenを伝える
5. **見せる**: `python3 -B tools/preview_frames.py temp/<作業名>/out/<名前> --out temp/<作業名>/preview` で一覧画像とGIFを作る。一覧画像を `open` でプレビューに開き、GIFは `open -R` でFinderに出す

## 指示文

- 短い英語で、1回に1つの動きを書く。立つ・膨らむ・爆発のような流れを1回に詰め込むと、大きな姿勢の変化が省かれた
- 長い流れは区切り、区切りごとに最初と最後の絵を渡す
