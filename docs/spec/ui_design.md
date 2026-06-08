# 列車コントローラー UI 設計書（運転モニター 3×1）

> 本書は仕様駆動ワークフローのフェーズ2（設計）成果物。`docs/spec/requirements.md` の REQ-DISP-01,02 と `docs/spec/design.md` の M10（`onDraw`）を実装可能な画面仕様へ詳細化する。対象は**運転台付き車（TA / TAB）**のみが持つ 3×1 モニター。TB / DEAD は画面を持たない。
>
> 画面は単一・遷移なしのため `docs/spec/screen_transitions.md` は作成しない（要件 §9.3）。

---

## 1. 物理仕様

| 項目 | 値 | 備考 |
|---|---|---|
| モニター構成 | 3×1（横3・縦1ブロック） | REQ-DISP-01 |
| 解像度 | **96 × 32 px** | 1ブロック=32px。`screen.getWidth()=96, getHeight()=32` |
| 文字フォント | 既定（約 5px 幅 / 6px 行高） | `screen.drawText` |
| 描画契機 | `onDraw`（Composite 関数呼び出し禁止） | REQ-DISP-02 |

> **REQ-DISP-02 厳守**：`onDraw` 内では `input.*` / `output.*`（Composite 関数）を呼ばない。描画に必要な値は `onTick` でグローバル変数へ退避する（§4 参照）。

---

## 2. 表示項目（要件 REQ-DISP-01）

最低限「スロットル・ブレーキ・進行方向・マスター状態」を含む。本設計では以下を表示する。

| 項目 | データ源（onTick 退避） | 表現 |
|---|---|---|
| マスター状態 | `disp_is_master` / `disp_master_present` | 文字 `MASTER` / `--`（不在時） |
| 進行方向 | `disp_gff`, `disp_back` | 矢印 `▶FWD` / `◀REV`（バック時） |
| スロットル | `disp_throttle`（0..1 大きさ） | 横バー＋数値 % |
| ブレーキ | `disp_brake`（0..1）, `disp_ebrake` | 横バー＋数値 %、非常時赤 `EMG` |
| 補助状態 | `disp_spot`, `disp_room`, `disp_door` | アイコン文字（S / L / D） |

---

## 3. レイアウト（96×32）

3列（各32px幅）に役割を割り当てる。

```
 col0:0-31      col1:32-63        col2:64-95
┌──────────┬──────────────┬──────────────┐
│ MASTER   │ ▶ FWD        │ THR ████░ 80%│  y=0-9
│ (or --)  │ (◀ REV)      │ BRK ██░░░ 25%│  y=10-19
│ S L D    │ spd/aux      │ EMG (赤/非常)│  y=20-31
└──────────┴──────────────┴──────────────┘
```

### 3.1 列0（0〜31px）：状態
- y=2 `MASTER`（マスター時）/ `--`（`master_present=false`）。
- y=12 `REQ`（自車リクエスト中＝`tgl_req` だが非マスター時の待機表示、任意）。
- y=24 補助インジケータ `S`(スポット) `L`(室内) `D`(ドア開) を ON のものだけ表示。

### 3.2 列1（32〜63px）：進行方向
- 中央に矢印＋ラベル：`disp_gff` 基準のグローバル前方を `▶ FWD`、バック反転中（`disp_back`）は `◀ REV`。
- `gff_valid=false`（方向未確定/マスター不在）は `-- ?`。

### 3.3 列2（64〜95px）：走行
- y=2 スロットル：ラベル `THR` ＋横バー（最大幅 ~20px）＋数値 `%`。
- y=12 ブレーキ：ラベル `BRK` ＋横バー＋数値 `%`。
- y=22 非常ブレーキ時 `EMG`（赤）。常用時は非表示。

---

## 4. onTick → onDraw データ受け渡し（REQ-DISP-02）

`onTick` 末尾で描画用グローバルへ退避する（`docs/spec/design.md` M10）。

```lua
-- onTick 末尾（退避のみ。値の算出は各モジュールで実施済み）
disp_is_master      = is_master
disp_master_present = master_present
disp_gff            = gff
disp_gff_valid      = gff_valid
disp_back           = tgl_back
disp_throttle       = is_master and (tgl_ebrk and 0 or throttle_input) or auth_throttle
disp_brake          = emergency_brake and 1.0 or auth_brake
disp_ebrake         = emergency_brake
disp_spot           = spot_on_cmd
disp_room           = room_light_cmd
disp_door           = (lr or ll)      -- いずれか開
```

```lua
function onDraw()
  local W = screen.getWidth()    -- 96
  -- 列0: 状態
  screen.setColor(0,255,0)
  screen.drawText(2,2, disp_is_master and "MASTER" or "--")
  -- 列1: 方向
  if not disp_gff_valid then screen.setColor(120,120,120); screen.drawText(36,12,"-- ?")
  else screen.setColor(0,200,255)
       screen.drawText(36,12, disp_back and "<REV" or ">FWD") end
  -- 列2: 走行
  draw_bar(66,2,  "THR", disp_throttle, 0,200,0)
  draw_bar(66,12, "BRK", disp_brake,   200,80,0)
  if disp_ebrake then screen.setColor(255,0,0); screen.drawText(66,22,"EMG") end
end
```

> 注：矢印記号 `▶/◀` がフォント未対応の場合は `>` `<` で代替（上記コードは代替表記）。最終文字種はゲーム内表示で確認する。

---

## 5. 配色ルール

| 状態 | 色 (r,g,b) | 用途 |
|---|---|---|
| 通常/マスター | 0,255,0 | マスター表示・正常 |
| 方向 | 0,200,255 | FWD/REV ラベル |
| 力行 | 0,200,0 | スロットルバー |
| 制動 | 200,80,0 | ブレーキバー |
| 非常/警告 | 255,0,0 | EMG・断裂・方向未確定の強調 |
| 無効/不在 | 120,120,120 | `--` / `-- ?` |

---

## 6. 状態別表示マトリクス

| 状況 | 列0 | 列1 | 列2 | 関連 |
|---|---|---|---|---|
| 自車マスター・前進 | `MASTER` | `>FWD` | THR/BRK 値 | REQ-DIR-01 |
| 自車マスター・バック | `MASTER` | `<REV`(赤系) | 同上 | REQ-DIR-02 / E5 |
| 非マスター（他車運転中） | `--` | `>FWD`(受信方向) | 認可値表示 | REQ-MAS-07 |
| マスター不在 | `--` | `-- ?`(灰) | THR 0 / BRK 100% | REQ-MAS-07 / EH1 |
| 編成断裂/方向未確定 | `--` | `-- ?`(灰) | BRK 100% | REQ-RUN-05 / EH2 |
| 非常ブレーキ | （現状） | （現状） | `EMG`(赤)・BRK 100% | REQ-RUN-03 |

---

## 7. 描画の非機能配慮

- `onDraw` は退避済みグローバルのみ参照（分岐・軽量演算のみ、重ループ禁止）＝ REQ-NFR-02。
- バー描画は `screen.drawRect`（塗り）で最大幅を px 換算（例 20px×値）。
- 文字数は各列幅（~6文字/32px）に収め、はみ出しを避ける。
- 本画面はロジックチップと同一マイコンに同居（8KB 制約 REQ-NFR-01 に留意。超過時は表示チップ分離＝`design.md` §9.3）。
