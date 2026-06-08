# 列車コントローラー（1マイコン / 3スクリプト構成）

1個のマイコン内に Lua スクリプトを3つ置き、内部コンポジットで結線する。全車両が同一の3ファイルを搭載し、`Has Front Control` / `Has Back Control` プロパティのみで挙動が分岐する（単一ソース・データ駆動）。

| ファイル | 機能 | 対応設計 |
|---|---|---|
| `core.lua` | M1〜M6：入力・連結整列・マスター調停・GFF・指令パケット中継（**同一ティック完結のクリティカルパス**） | design.md §6.1–6.5 |
| `output.lua` | M7〜M9：走行・ドア・ライト出力写像 | design.md §6.6–6.8 |
| `display.lua` | M10：運転モニター 3×1 描画 | ui_design.md |

`output` / `display` は `core` の結果を消費するだけなので **core から1ティック遅延**するが、定常状態では不可視（系全体が元々マルチティック収束）。

## 分割理由（8KB 制約 / REQ-NFR-01）

各スクリプトは 8192 バイト制約を個別に持つ。統合版（約9.2KB）は1枚に収まらないため機能分割した。現状サイズ：core 8000 B / output 2557 B / display 2521 B（いずれも ≤8192）。

## 結線

### 1. core への入力（`core.in`）
- 前コネクタ由来 → 入力ch **1〜16**、後コネクタ由来 → 入力ch **17〜32**（物理コネクタ固定割り当て）。
- 運転手操作 → 空きch：N9=スロットル, N10=ブレーキ / B9=右ドア, B10=左ドア, B11=室内, B12=リクエスト, B13=非常, B14=バック, B15=スポット（全て push ボタン）。

### 2. core の出力（`core.out`）
1ノードに集約。内訳：
- **連結フレーム**：前=ch1〜16・後=ch17〜32 → 各コネクタへ（前後で別内容。ゲーム内オフセット配線で自車後フレーム出力(17-32)が隣の前入力(1-16)へ届くようにする＝design.md §12-R1）。
- **コマンド/表示バス**：下表のch。`core.out` を分岐して `output.in` と `display.in` へ内部配線（オフセットなしの素通し32ch）。

### 3. コマンド/表示バス（core → output / display）

| 内容 | ch | 型 | 読む側 |
|---|---|---|---|
| auth_throttle | N11 | Number | output, display |
| auth_brake | N12 | Number | output, display |
| master_present | B9 | Bool | output, display |
| gff_valid | B10 | Bool | output, display |
| gff | B11 | Bool | output, display |
| is_cab | B12 | Bool | output |
| is_front_end | B13 | Bool | output |
| is_rear_end | B14 | Bool | output |
| emergency_brake | B15 | Bool | output, display |
| door_g_right | B16 | Bool | output, display |
| door_g_left | B25 | Bool | output, display |
| room_cmd | B26 | Bool | output, display |
| spot_cmd | B27 | Bool | output, display |
| local_rdoor(tgl) | B28 | Bool | output, display |
| local_ldoor(tgl) | B29 | Bool | output, display |
| local_room(tgl) | B30 | Bool | output |
| is_master | B31 | Bool | display |
| back(tgl) | B32 | Bool | display |

> バスのch（N11-12, B9-16,25-32）は連結プロトコル（N1-3,17-19 / B1-8,17-24）と非衝突。コネクタ経由で隣車へ漏れても隣の core は protocol ch しか読まず無害。

### 4. output の出力（`output.out`）→ 車両機器
- N1=スロットル(-1〜1), N2=ブレーキ(0〜1)
- B1=右ドア, B2=左ドア, B3=室内ライト, B4=スポット, B5=テール

### 5. display
- 3×1 モニター（96×32）を接続。`core.out` 分岐を `display.in` へ。

## 最終確定

ch割り当て・コネクタ間オフセット配線は coordinator が `docs/spec/feature_dispatch_*.md` で最終確定・ゲーム内検証する（design.md §5.4, §12-R1）。各ファイル冒頭の定数表を1箇所として編集すること。
