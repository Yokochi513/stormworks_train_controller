# 列車コントローラーシステム 基本設計書

> 本書は仕様駆動ワークフロー（`.github/.instructions/spec-driven-workflow.instructions.md`）の**フェーズ2（設計）**成果物である。入力は `docs/spec/requirements.md`（フェーズ1：EARS 要件定義）であり、要件の各 REQ-* を実装可能な技術設計（アーキテクチャ・プロトコル・アルゴリズム・データモデル・テスト戦略・実装計画）へ落とし込む。
>
> Stormworks 実行環境の制約は `.claude/.rules/stormworks_lua.md`、UI 詳細は `docs/spec/ui_design.md` に従う。最終的なコンポジットチャンネル割り当ては、衝突回避責任を持つ `stormworks-coordinator` が `docs/spec/feature_dispatch_*.md` で確定する（本書はその確定の基礎となる**論理プロトコルと推奨チャンネルマップ**を提示する）。
>
> 参照成果物：
> - `docs/spec/requirements.md`（フェーズ1）
> - `.claude/.rules/stormworks_lua.md` / `.claude/.rules/stormworks_user_guide.md`
> - `CLAUDE.md`

---

## 1. 設計方針

### 1.1 適応的実行戦略（信頼度80%＝中信頼度）

要件 §9.1 の信頼度評価は **80%（中信頼度）**。ワークフロー規約フェーズ2の中信頼度戦略に従い、以下を採る。

- **最もリスクの高い機能を PoC として先行検証**してから全機能へ拡大する。
- リスク最大の対象は要件 §9.1 の通り **「進行方向伝播（マスター指令の到来側からの GFF 導出）＋ 運転台連結過渡（荒ぶり）の収束」**。
- PoC の成功基準は本書 §9 に定義する（要件 §9.2 を具体化）。
- PoC 成功後、本書 §10 の実装計画（T0〜T10）を依存順に展開する。

### 1.2 設計上の基本原理（要件 §4.1 の具体化）

| 原理 | 設計への反映 |
|---|---|
| 隣接通信のみ | 全状態は隣へのホップ伝播。1ホップ＝1ティック遅延を前提に、伝播フィールドは収束するよう冪等・単調に設計する（§6.3〜§6.5）。 |
| 前後コネクタ識別 | 連結マーカーに**送信元コネクタの符号**を載せ、受信チャンネル（前/後）と組み合わせて整列/反転を一意化する（§5.2）。 |
| 進行方向＝マスター指令の到来方向 | GFF を「隣（マスター側）の GFF と自車整列の排他的論理和」で**再帰導出**する（§6.3）。 |
| 手動割り当て禁止 | プロパティは `Has Front Control` / `Has Back Control` のみ。番号・位置・向きは信号から自動判定。 |
| push 型入力 | 全 Bool 入力を立ち上がり検出で内部トグル化（§6.1）。状態はアップバリュー保持、リスポーンでリセット前提。 |

---

## 2. システムアーキテクチャ

### 2.1 物理構成

- **1 車両 = 1 マイコン = 1 Lua ファイル**（`CLAUDE.md`）。全車両は**同一の Lua ソース**を搭載し、`property.getBool` で読む `Has Front Control` / `Has Back Control` のみで車種別挙動を分岐する（単一ソース・データ駆動）。
- 各マイコンは前コネクタ・後コネクタの2方向と通信する。I/O モデルは以下で確定する（2026-06-08 設計判断）。
  - **入力＝物理コネクタ固定割り当て**：前コネクタ由来の信号は必ず `Number/Bool 1〜16`、後コネクタ由来は `17〜32` に入る（隣車の物理向きに無関係）。よって**受信した自車の物理側（前/後）はチャンネル帯から即判定**でき、符号マーカーに依存しない。
  - **出力＝1ノードに集約**し、中身を**前フレーム（1〜16）／後フレーム（17〜32）に分けて各コネクタへ別内容**を送る。前後で異なる中継内容を載せられるため、§6.5 の load-swap 中継モデルをそのまま維持できる。
  - フレーム⇔チャンネルの最終対応・コネクタ間の配線オフセットはゲーム内ビルド側の責務であり、coordinator が `feature_dispatch_*.md` で確定・検証する（§5.4, §12-R1）。
- 運転台付き車（TA/TAB）のみ 3×1 モニター（`onDraw`）を持つ。

### 2.2 モジュール分割

各マイコンの `onTick` を以下の処理モジュール（関数単位）に分割する。番号は概ね実行順かつ実装タスク T0〜T9（§10）に対応する。

| ID | モジュール | 責務 | 主な参照要件 |
|---|---|---|---|
| **M1** | 初期化・車種判定 | プロパティ読み、`car_type` 決定（TA/TAB/TB/DEAD） | REQ-TYPE-01〜05 |
| **M2** | push 入力トグル化 | 全 Bool 入力の立ち上がり検出と内部トグル更新 | REQ-MAS-01〜03,10 |
| **M3** | コネクタ I/O・整列判定 | 連結マーカー送受信、接続/整列/編成端判定、新規連結検出 | REQ-ORI-01〜03,05, REQ-COMM-01,02 |
| **M4** | マスター調停 | 取得/解放/相互排他/連結クリア、`master_present` 伝播 | REQ-MAS-02〜10, REQ-EDGE-01,02 |
| **M5** | 進行方向・GFF 導出 | 到来側からの GFF 再帰導出、編成端（前後端）確定 | REQ-ORI-04,06, REQ-DIR-01〜03 |
| **M6** | 指令パケット生成・中継 | マスター時生成、非マスター時写像中継、DEAD クロス中継 | REQ-COMM-03〜06, REQ-RUN-01,02 |
| **M7** | 走行出力写像 | 認可力行へ GFF 符号適用（-1〜1）、ブレーキ、安全側 | REQ-RUN-03〜05, REQ-DIR-03 |
| **M8** | ドア出力写像 | グローバル左右↔ローカル左右、不在時ローカル操作 | REQ-DOOR-01〜03 |
| **M9** | ライト出力 | 室内/スポット（前端）/テール（後端）、進行方向追従 | REQ-LIGHT-01〜06 |
| **M10** | モニター描画 (`onDraw`) | 3×1 運転データ描画 | REQ-DISP-01,02 |

### 2.3 onTick 処理シーケンス

```
onTick():
  1. M1  初回のみ: プロパティ読込→car_type 確定（以後キャッシュ）
  2. M2  生 Bool 入力読込→tgl_* 更新（立ち上がり検出）
  3. M3  前/後コネクタの連結マーカー受信→connected/aligned/新規連結エッジ
         自車の連結マーカーを前/後へ出力
  4. M4  マスター調停（取得/解放/相互排他/連結クリア/force_release 中継）
         master_present 集約
  5. M5  GFF 導出（マスター=種別シード / 非マスター=到来側再帰） → 編成端確定
  6. M6  指令パケット構築（マスター=生成 / 非マスター=写像中継 / DEAD=クロス中継）
         前/後フレームへ書き出し
  7. M7  走行出力（throttle -1..1, brake）  ※安全側ガード
  8. M8  ドア出力（左右写像 or ローカル）
  9. M9  ライト出力（室内/スポット/テール）
 10.     onDraw 用グローバルへ値を退避（REQ-DISP-02）
onDraw():
 11. M10 退避値のみで描画（Composite 関数を呼ばない）
```

> **伝播遅延の扱い**：コンポジットは隣→隣へ1ティックで渡るため、N 両編成は端まで最大 N ティック遅延する。`master_present`・`gff`・`auth_*` は毎ティック再評価され、構成が定常なら数ティックで収束する（REQ-NFR-04）。`force_release` のみイベント性が高いため TTL 付きで強制中継する（§6.4）。

### 2.4 全体データフロー

```
 [運転手操作]──push──▶ M2(tgl_*) ─┐
 [property]──▶ M1(car_type) ───────┤
                                   ▼
 前コネクタ受信 ─▶ M3 ─▶ connected/aligned ─▶ M5(GFF) ─▶ M7/M8/M9 ─▶[車両機器出力]
 後コネクタ受信 ─▶      └▶ 新規連結 ─▶ M4(master) ─▶ master_present ─┘
                                   │                     │
                          M4 force_release          M6(packet)
                                   ▼                     ▼
                          前/後コネクタ送信 ◀── M6 写像中継 ──┘
                                                        └─▶ M10(onDraw)
```

---

## 3. 状態モデル（保持変数の確定）

要件 §6 のデータモデルを実装変数として確定する。命名は `snake_case`、ティックまたぎ保持はアップバリュー（チャンク先頭の `local`）とする。

### 3.1 定数・車種

| 変数 | 型 | 由来 | 意味 |
|---|---|---|---|
| `has_front_control` | bool | `property.getBool("Has Front Control")` | 前運転台の有無 |
| `has_back_control` | bool | `property.getBool("Has Back Control")` | 後運転台の有無 |
| `car_type` | string | 導出 | `"TA"`/`"TAB"`/`"TB"`/`"DEAD"`（§3.4 表） |
| `is_cab` | bool | `has_front_control ~= has_back_control` | マスターになり得る運転台付き車 |

### 3.2 push トグル状態

各 Bool 入力につき前ティック生値 `prev_*` と内部トグル `tgl_*` を保持（要件 §6）。

| 対象 | 変数 | 適用車種 |
|---|---|---|
| 右ドア | `prev_rdoor`, `tgl_rdoor` | 全車 |
| 左ドア | `prev_ldoor`, `tgl_ldoor` | 全車 |
| 室内ライト | `prev_room`, `tgl_room` | 全車 |
| リクエスト | `prev_req`, `tgl_req` | 運転台付き車のみ |
| ブレーキ(非常) | `prev_ebrk`, `tgl_ebrk` | 運転台付き車のみ |
| バック | `prev_back`, `tgl_back` | 運転台付き車のみ |
| スポットライト | `prev_spot`, `tgl_spot` | 運転台付き車のみ |

### 3.3 編成・伝播状態

| 変数 | 型 | 意味 | 参照 |
|---|---|---|---|
| `front_connected`, `back_connected` | bool | 各コネクタ接続有無 | REQ-ORI-01 |
| `prev_fconn`, `prev_bconn` | bool | 新規連結エッジ検出用 | REQ-MAS-05 |
| `front_aligned`, `back_aligned` | bool | 隣接の整列(true)/反転(false) | REQ-ORI-03 |
| `is_master` | bool | 自車がマスターか | REQ-MAS-* |
| `acquire_window` | int | 取得直後に外来解放を無視する残ティック | REQ-MAS-04,09 |
| `master_present` | bool | 編成内にマスター在（伝播集約） | REQ-COMM-04 |
| `gff` | bool | グローバル前方が自車ローカル前を指すか | REQ-ORI-04,06 |
| `gff_valid` | bool | 進行方向確定（マスター在＋到来側確定） | REQ-RUN-05 |
| `is_front_end`, `is_rear_end` | bool | グローバル基準の前端/後端 | REQ-LIGHT-03,04 |
| `fr_ttl` | int | force_release の残中継ホップ | REQ-MAS-05 |

### 3.4 車種判定（M1）

| `Has Front` | `Has Back` | `car_type` | `is_cab` | 動力 | 挙動概要 |
|---|---|---|---|---|---|
| true | false | `TA` | ○ | あり | 正スロットルでローカル前。GFF シード=`not tgl_back` |
| false | true | `TAB` | ○ | あり | 正スロットルでローカル後。GFF シード=`tgl_back` |
| false | false | `TB` | × | あり | 到来側から GFF を受信。運転入力なし |
| true | true | `DEAD` | × | なし | フェイルセーフ：両コネクタをクロス中継のみ（REQ-TYPE-04） |

---

## 4. （欠番：プロトコルは §5、アルゴリズムは §6 に集約）

---

## 5. コネクタ・コンポジット信号プロトコル設計

### 5.1 通信モデル

- 各車は**前フレーム**（前コネクタへ送る／前コネクタから受ける情報の集合：チャンネル 1〜16）と**後フレーム**（17〜32）を持つ。**入力は物理コネクタ固定割り当て**のため、受信フレームが前コネクタ由来か後コネクタ由来か（＝自車の物理側）は**チャンネル帯から直接わかる**（§2.1）。
- 一方「**送信元（隣接車）が自分のどちらのコネクタから送ったか**」はフレーム内の**符号マーカー**で示す（§5.2）。受信側は「自車の物理側（チャンネル帯）」＋「送信元の側（マーカー符号）」を併せ、整列/反転と進行方向を導く。
- 出力は1ノードに集約しつつ前後で別内容（load-swap 中継・§6.5）。物理配線（コネクタ↔コンポジットの結線、コネクタ間チャンネルオフセット）はゲーム内ビルド側の責務であり、本プロトコルは**論理的なチャンネル意味**を定義する。最終チャンネル番号は coordinator が確定（§5.4）。

### 5.2 連結マーカー（接続検出＋前後識別）

各車は毎ティック、前後フレームへ**符号付きマーカー値**を出力する（REQ-COMM-01）。

- **前フレーム（出力 1〜16）に `link_marker = +1`**、**後フレーム（出力 17〜32）に `link_marker = -1`**（大きさ 1＝接続生存信号、符号＝**送信元コネクタ識別**）。
- 受信側の判定（REQ-ORI-01,03）。**受信した自車側は入力チャンネル帯で確定**（前入力 1〜16／後入力 17〜32）、**送信元の側はマーカー符号**で確定する：

| 受信した自車側 | 受信値の符号 | 送信元の隣接コネクタ | 整列/反転 |
|---|---|---|---|
| 前で受信 | `-1`（隣の後） | 隣の後 ↔ 自前 = 前後結合 | **整列**（`front_aligned=true`） |
| 前で受信 | `+1`（隣の前） | 隣の前 ↔ 自前 = 前前結合 | **反転**（`front_aligned=false`） |
| 後で受信 | `+1`（隣の前） | 隣の前 ↔ 自後 = 前後結合 | **整列**（`back_aligned=true`） |
| 後で受信 | `-1`（隣の後） | 隣の後 ↔ 自後 = 後後結合 | **反転**（`back_aligned=false`） |
| （いずれか）| `0`/欠落 | 未接続 | `*_connected=false` |

- 接続有無：`front_connected = (abs(前マーカー受信値) > 0.5)`、後も同様。
- **整列規則の要点**：「自分が受けた側」と「相手が送った側」が**逆（前後）なら整列、同じなら反転**。

### 5.3 指令パケット（マスター在時のみ有意・REQ-COMM-03）

マスターが生成し、両端へ伝播。各中間車は受信を自車フレームへ写像して反対側へ中継する。論理フィールド：

| フィールド | 型 | 意味 | 生成元 | 参照 |
|---|---|---|---|---|
| `master_present` | bool | マスター在否 | マスター=1, 中継=OR | REQ-COMM-04 |
| `sender_gff` | bool | **送信車**の GFF（受信側の GFF 再帰に使用） | 各ホップで自車 GFF を載せ替え | REQ-ORI-04 |
| `auth_throttle` | number 0..1 | 認可力行（大きさのみ） | マスター入力 | REQ-RUN-01 |
| `auth_brake` | number 0..1 | 認可常用ブレーキ | マスター入力 | REQ-RUN-02 |
| `emergency_brake` | bool | 非常/パーキング | マスター `tgl_ebrk` | REQ-RUN-03 |
| `door_g_right` | bool | グローバル右ドア指令 | マスター | REQ-DOOR-01 |
| `door_g_left` | bool | グローバル左ドア指令 | マスター | REQ-DOOR-01 |
| `room_light` | bool | 室内ライト指令 | マスター `tgl_room` | REQ-LIGHT-01 |
| `spot_on` | bool | スポット指令 | マスター `tgl_spot` | REQ-LIGHT-02 |
| ~~`force_release`~~ | — | **廃止**（§6.4 改訂）。マスター調停は `master_prio`/`master_live`（N4/N5・N20/N21）の優先度フラッドへ置換 | — | REQ-MAS-04,05 |

> **`sender_gff` の載せ替えが本プロトコルの肝**。マスターは自種別から GFF をシードし（§3.4）、中継車は到来側の `sender_gff` と整列から自 GFF を計算し（§6.3）、**反対側へ出力するパケットには自車 GFF を `sender_gff` として載せる**。これにより反転車を跨いでも全車の進行方向が整合する（REQ-ORI-06）。

### 5.4 推奨チャンネルマップ（coordinator 確定対象）

I/O モデル確定（2026-06-08）に従い、**前フレーム＝チャンネル 1〜16、後フレーム＝17〜32 を Number・Bool 双方に適用**する。入力は物理コネクタ固定割り当て（前コネクタ→1〜16、後コネクタ→17〜32）、出力は1ノードで前後を別内容として書き分ける。下表は推奨割り当て（残りは予備）。

| 役割 | 前フレーム | 後フレーム | 型 |
|---|---|---|---|
| link_marker（送信元コネクタ識別／接続生存） | N1 | N17 | Number |
| auth_throttle | N2 | N18 | Number |
| auth_brake | N3 | N19 | Number |
| master_prio（マスター優先度フラッド・§6.4） | N4 | N20 | Number |
| master_live（生存ホップ・中継毎 -1） | N5 | N21 | Number |
| master_present | B1 | B17 | Bool |
| sender_gff | B2 | B18 | Bool |
| emergency_brake | B3 | B19 | Bool |
| door_g_right | B4 | B20 | Bool |
| door_g_left | B5 | B21 | Bool |
| room_light | B6 | B22 | Bool |
| spot_on | B7 | B23 | Bool |
| ~~force_release~~（廃止・§6.4 改訂で prio/live へ置換） | ~~B8~~ | ~~B24~~ | — |

> 入力側でも同一マップを用いる（前コネクタ由来＝N/B 1〜16、後コネクタ由来＝N/B 17〜32）。コネクタ間で出力の後フレーム(17〜32)が相手の前入力(1〜16)へ届くようにする**チャンネルオフセット配線**は、§12-R1 の通り coordinator がビルド側で確定・検証する。

> **未決事項（§12-R1）**：マイコン単一チャンネル空間と物理コネクタの前後対応（自車「後フレーム出力」が隣の「前フレーム入力」として読まれる結線）はゲーム内ビルド・配線で実現する。配線方式次第でフレーム⇔チャンネルの対応を反転する必要があり得るため、**チャンネル定数は 1 箇所（コード冒頭の定数表）に集約**し、coordinator が `feature_dispatch_*.md` で最終確定・ゲーム内検証する。

---

## 6. 主要アルゴリズム設計

擬似コードは Lua 寄り。`==` の bool 比較・`xor` は `a ~= b` で表現する。

### 6.1 push 入力トグル化（M2 / REQ-MAS-01〜03,10）

```lua
-- 立ち上がり（OFF→ON）でトグル反転
local function edge_toggle(raw, prev, tgl)
  if raw and not prev then tgl = not tgl end
  return raw, tgl            -- prev は raw を返して更新
end
-- 例: prev_req, tgl_req = edge_toggle(input.getBool(CH_REQ), prev_req, tgl_req)
```

- リスポーン直後は全 `tgl_*`=false、`prev_*`=false（REQ-MAS-01）。
- TB/DEAD は運転入力チャンネルを読まない（`tgl_req/ebrk/back/spot` 不使用）。

### 6.2 接続・整列・編成端判定（M3,M5 / REQ-ORI-01〜03）

```lua
-- 受信: 自車側は入力チャンネル帯で確定（前=N1, 後=N17）。値の符号＝送信元コネクタ
local rx_front_marker = input.getNumber(1)    -- 前コネクタ由来（前入力帯 1〜16）
local rx_back_marker  = input.getNumber(17)   -- 後コネクタ由来（後入力帯 17〜32）
front_connected = math.abs(rx_front_marker) > 0.5
back_connected  = math.abs(rx_back_marker)  > 0.5
-- 整列: 受けた自車側と送信元側が逆(前後)なら整列、同じなら反転
front_aligned = front_connected and (rx_front_marker < 0)   -- 前で受け, 隣が後(-1)から送信→整列
back_aligned  = back_connected  and (rx_back_marker  > 0)   -- 後で受け, 隣が前(+1)から送信→整列
-- 出力: 前フレーム(1〜16)に +1, 後フレーム(17〜32)に -1
output.setNumber(1,  1)   -- 前フレーム link_marker
output.setNumber(17, -1)  -- 後フレーム link_marker
```

編成端は GFF 確定後に算出（§6.6 と同所で）。

### 6.3 進行方向・GFF 導出（M5 / REQ-ORI-04,06, REQ-DIR-01〜03）★中核★

**マスター（シード）**：
```lua
if is_master then
  if car_type == "TA"  then gff = not tgl_back  -- 前運転台: back off で前=GFF true
  else                       gff = tgl_back end  -- TAB 後運転台: back off で後=GFF false
  gff_valid = true
```
**非マスター（到来側再帰）**：到来したコネクタの `sender_gff` と整列の排他的論理和。
```lua
else
  local got, s_gff, side_aligned = false, false, false
  if rx_front.master_present then got, s_gff, side_aligned = true, rx_front.sender_gff, front_aligned end
  if rx_back.master_present  then got, s_gff, side_aligned = true, rx_back.sender_gff,  back_aligned  end
  if got then
    gff = (s_gff == side_aligned)   -- 整列なら同符号, 反転なら反転
    gff_valid = true
  else
    gff_valid = false               -- マスター不在/未到達 → 安全側
  end
end
```
> **導出原理**：「マスター側の隣車 GFF」を基準に、自車が隣と整列していれば GFF は同じ、反転していれば反転する。`gff = (sender_gff == arrival_aligned)`。マスター指令の到来側を辿るので、TB も自車ローカル前/後のどちらが進行方向かを一意決定できる（REQ-ORI-04）。両側から到来する定常状態では両者が一致するよう収束する（収束検証は §9 PoC）。

**スロットル符号**：`throttle_sign = gff and 1 or -1`（REQ-DIR-03）。

### 6.4 マスター調停（M4 / REQ-MAS-02〜10, REQ-EDGE-01,02）★優先度フラッド方式★

> **改訂（2026-06-08）**：当初の `force_release` パルス中継方式は、(1) エッジ用 `prev_*` 未更新で毎ティック再取得し `acquire_window` が降りず複数マスターが並存、(2) パルスが車間を往復し続け（中継で TTL 再充填）自車のエコーで単独マスターが自滅、という2バグを生んだ。これを廃し、**優先度フラッド（prio/live）方式**へ置換する。`force_release`／`fr_ttl`／`acquire_window`／`new_conn` 解放は廃止。

各車は隣へ2値を流す：`prio`（取得順の優先度＝後で取得したほど大）、`live`（生存ホップ数＝中継ごとに -1、0 で消滅）。マスターは毎ティック `live` を満タン（`HOPS`）に再供給し、不在になれば `live` 減衰で claim が編成全体から自己消滅する（誤った滞留・自滅エコーが起きない）。

```lua
-- (a) 隣接からの生存マスター claim を選ぶ（live>0 のみ有効, 同値なら前優先）
local f_alive = front_connected and rx_front.live > 0 and rx_front.prio > 0
local b_alive = back_connected  and rx_back.live  > 0 and rx_back.prio  > 0
local in_prio, in_live, in_front = 0, 0, false
if f_alive then in_prio, in_live, in_front = rx_front.prio, rx_front.live, true end
if b_alive and rx_back.prio > in_prio then in_prio, in_live, in_front = rx_back.prio, rx_back.live, false end
-- (b) 取得/解放エッジ
if is_cab then
  if (tgl_req and not prev_tgl_req) then           -- 取得：現編成の最高優先の一段上を採番
    is_master = true
    own_prio  = math.floor(in_prio + 1e-6) + 1 + cab_bias   -- 後取得が勝つ＋TA/TABタイブレーク(0.3/0.6)
  elseif (not tgl_req and prev_tgl_req) then        -- 解放
    is_master, own_prio = false, 0
  end
end
-- (c) より高い優先のマスターが居れば降格（自分の反射は同値なので降りない＝単独マスターは自滅しない）
if is_master and in_prio > own_prio + 1e-6 then
  is_master, own_prio, tgl_req = false, 0, false    -- 横取り後の再取得は OFF→ON 必須 (REQ-MAS-09,10)
end
-- (d) 両側へフラッド（マスター=満タン再供給 / 中継=live を1減衰 / 尽きたら消滅）
local out_prio, out_live
if is_master then out_prio, out_live = own_prio, HOPS
elseif in_prio > 0 and in_live > 1 then out_prio, out_live = in_prio, in_live - 1
else out_prio, out_live = 0, 0 end
-- (e) 集約
master_present = is_master or out_prio > 0
```

- **相互排他（REQ-MAS-04,09 / E2,E11）**：優先度は取得のたびに「現編成の最高優先 +1」で単調採番されるため**最後に取得した車が最高優先＝勝ち**。低優先のマスターは高優先 claim を受けて降格し `tgl_req=false`（ボタン再押下まで再取得しない）。編成内マスター数は 0/1 に収束。同レベルの同時取得は `cab_bias`（TA=0.3 / TAB=0.6）で一意化する（同種2運転台の完全同時取得のみ残課題）。
- **自滅しない（本改訂の要点）**：自車 claim の反射は `in_prio == own_prio` で「より高い」条件を満たさないため、単独マスターは隣車のエコーで降格しない。`live` 減衰により、マスター不在時のみ claim が消滅する。
- **連結過渡（REQ-MAS-05 / E1,E9）**：旧方式の「新規連結で 0 マスターへ落とす」は廃止。連結時は両編成の claim フラッドが合流し、高優先（後取得）側が生存・低優先側が降格して 1 マスターへ自然収束する（マスターを保持したまま安全に統合）。`HOPS` は最大編成長以上（実装 `HOPS=40`）。
- `WIN`・`MAX_HOP` は編成最大両数以上（例 `MAX_HOP=32`, `WIN=8`）。値は §9 PoC で調整。

### 6.5 指令パケット中継（M6 / REQ-COMM-03〜06）

```lua
local function build_packet(side_gff)
  if is_master then
    local ebrk = tgl_ebrk
    return {
      master_present = true, sender_gff = side_gff,
      auth_throttle  = ebrk and 0 or throttle_input,   -- 0..1
      auth_brake     = auth_brake_input,                -- 0..1
      emergency_brake= ebrk,
      door_g_right   = tgl_rdoor, door_g_left = tgl_ldoor,
      room_light     = tgl_room,  spot_on    = tgl_spot,
      force_release  = fr_out,
    }
  else
    -- 中継: 走行/付帯はそのまま、sender_gff のみ自車値へ載せ替え
    local p = pick_incoming_packet()        -- master_present 側を採用
    p.sender_gff = side_gff
    p.force_release = fr_out
    return p
  end
end
-- 前へ出すパケットの sender_gff = 自車 gff、後へも同じく自車 gff
write_front_frame(build_packet(gff))
write_back_frame (build_packet(gff))
```

- **DEAD（あり得ない組合せ・REQ-TYPE-04, REQ-COMM-06 / E12）**：パケットを自車消費せず、**前受信をそのまま後出力・後受信をそのまま前出力**にクロス中継する（`sender_gff` も含め素通し）。走行/ドア/ライト出力は行わない。
- 非マスター中継時、両側から `master_present` が来る定常状態では片側（マスターに近い側）を採用すればよい。実装は「前優先で master_present の立つ側」を `pick_incoming_packet` とする。

### 6.6 走行出力写像（M7 / REQ-RUN-03〜05, REQ-DIR-03）

```lua
is_front_end = (gff and not front_connected) or (not gff and not back_connected)
is_rear_end  = (gff and not back_connected)  or (not gff and not front_connected)

local safe = (not master_present) or (not gff_valid)   -- 不在/断裂/方向未確定
if safe then
  output.setNumber(CH_OUT_THROTTLE, 0)
  output.setNumber(CH_OUT_BRAKE, 1.0)                  -- 安全側 (REQ-RUN-05 / E4)
else
  local sign = gff and 1 or -1
  output.setNumber(CH_OUT_THROTTLE, sign * auth_throttle)   -- -1..1 (REQ-RUN-04)
  output.setNumber(CH_OUT_BRAKE, emergency_brake and 1.0 or auth_brake)  -- REQ-RUN-03
end
```

- `master_present=false`（マスター不在）では走行指令を一切出さない（throttle 0）＝ REQ-MAS-07。
- 編成断裂で分離側はパケット未到達→`gff_valid=false`→安全側（REQ-COMM-05 / E4）。

### 6.7 ドア出力写像（M8 / REQ-DOOR-01〜03）

```lua
local lr, ll                          -- 自車ローカル右/左ドアの開閉
if master_present then
  -- グローバル右/左 → ローカル右/左 (GFF false で左右反転)
  lr = gff and door_g_right or door_g_left
  ll = gff and door_g_left  or door_g_right
else
  lr, ll = tgl_rdoor, tgl_ldoor       -- 不在時ローカル操作(左右ローカル基準) REQ-MAS-08
end
output.setBool(CH_OUT_RDOOR, lr); output.setBool(CH_OUT_LDOOR, ll)
```

### 6.8 ライト出力（M9 / REQ-LIGHT-01〜06）

```lua
-- 室内ライト
local room = master_present and room_light_cmd or (not master_present and tgl_room)
output.setBool(CH_OUT_ROOM, room)
-- スポット: 前端の運転台付き車のみ (REQ-LIGHT-03,06)
output.setBool(CH_OUT_SPOT, is_cab and is_front_end and spot_on_cmd)
-- テール: 後端の運転台付き車のみ自動。ただし単車(前端かつ後端)は消灯 (REQ-LIGHT-04,06 / E7,E8)
output.setBool(CH_OUT_TAIL, is_cab and master_present and is_rear_end and not is_front_end)
```

- 進行方向変化（バック/マスター移動）で `gff` が反転 → `is_front_end/is_rear_end` が入替 → スポット/テールの点灯車が追従（REQ-LIGHT-05 / E5,E10）。
- 後端が TB の編成はテール出力を持つ車が後端に無く点灯しない（許容・E8）。

---

## 7. エラーハンドリングマトリクス

要件 §7 のエッジケースを、検出条件・応答・関連要件で構造化する。

| # | 異常/エッジ | 検出条件 | システム応答 | 関連要件 |
|---|---|---|---|---|
| EH1 | マスター不在 | `master_present=false` | 走行不可（throttle 0, brake 1.0）。付帯はローカル操作 | REQ-MAS-07,08 / E3 |
| EH2 | 編成断裂 | パケット未到達→`gff_valid=false` | 分離側を安全側へ | REQ-RUN-05, REQ-COMM-05 / E4 |
| EH3 | 進行方向未確定 | `gff_valid=false` | throttle 0, brake 安全側 | REQ-RUN-05 |
| EH4 | 運転台付き車 新規連結 | 連結エッジ `new_conn` | 既存マスター解放→0マスターへ収束 | REQ-MAS-05, REQ-EDGE-01 / E1 |
| EH5 | 複数マスター同時成立 | force_release 相互 | 最後の取得車が勝ち、他は降格＋`tgl_req=false` | REQ-MAS-04,09, REQ-EDGE-02 / E2,E11 |
| EH6 | 反転連結中間車 | `*_aligned=false` | GFF を反転（§6.3）し符号・左右整合 | REQ-ORI-04, REQ-DOOR-02 / E6 |
| EH7 | バック操作 | `tgl_back` 変化→`gff` 反転 | 全車符号反転・前後端ライト入替 | REQ-DIR-02, REQ-LIGHT-05 / E5 |
| EH8 | マスター他端移動 | 旧マスター降格・新マスターシード | 進行方向/前後端/灯火が新マスター向きに追従 | REQ-DIR-01, REQ-LIGHT-05 / E10 |
| EH9 | 単車（TA/TAB 単独） | 前端かつ後端 | スポットは指令従、テール消灯 | REQ-LIGHT-06 / E7 |
| EH10 | 後端が TB | 後端にテール保有車なし | テール点灯せず（許容） | REQ-LIGHT-04 / E8 |
| EH11 | リスポーン直後 | 全 `tgl_*`=false, `is_master`=false | 0マスターから開始、数ティックで再確立 | REQ-MAS-01, REQ-NFR-04 / E9 |
| EH12 | `Has Front=Has Back=true` | `car_type="DEAD"` | 走行出力せず両コネクタをクロス中継、マスター不可 | REQ-TYPE-04, REQ-COMM-06 / E12 |

---

## 8. ユニットテスト戦略

ゲーム内にテストランナーは無いため（`CLAUDE.md`）、**コアロジックを Python へ移植したシミュレーションで検証**する（要件 §9.2, REQ-EDGE-03）。Lua 実装とアルゴリズムを 1:1 対応させ、純関数化したロジック（GFF 導出・整列判定・マスター調停・出力写像）を検証可能にする。

### 8.1 テスト対象（純関数）

| 対象 | 入力 | 期待 | 参照 |
|---|---|---|---|
| `derive_alignment` | 受信マーカー符号×受信側 | connected/aligned | §6.2 / REQ-ORI-01,03 |
| `derive_gff` | sender_gff, arrival_aligned / 種別+back | gff | §6.3 / REQ-ORI-04 |
| `master_arbitration` | リクエスト列・連結列・force_release | is_master 列が 0/1 収束 | §6.4 / REQ-MAS-* |
| `throttle_map` | gff, auth_throttle, emergency | -1..1, 安全側 | §6.6 / REQ-RUN-* |
| `door_map` | gff, global L/R | local L/R | §6.7 / REQ-DOOR-* |
| `end_light` | gff, connected, is_cab | 前端/後端/スポット/テール | §6.8 / REQ-LIGHT-* |

### 8.2 編成シミュレーション（統合）

`N` 両を配列で表現し、毎ティック「各車 onTick→隣へフレーム伝播」をループ。検証シナリオ（要件 §9.2 を具体化）：

1. **任意向き編成の向き確定**：`TA-TB-TAB`、中間に反転 TB を含む構成で、全車の `gff`/物理左右/編成端が一意かつ安定に定まる（数ティックで収束）。
2. **マスター収束**：TA/TAB の連結・分離シーケンス、TA↔TAB のマスター移動で `sum(is_master) ∈ {0,1}` が常に成立し発散しない。
3. **一括整合切替**：バック反転・マスター移動で全車のスロットル符号・ドア左右・前後灯火が同時整合する。

### 8.3 成功判定

各シナリオで「収束ティック数 ≤ MAX_HOP+α」「不変条件 `0≤sum(is_master)≤1`」「全車 GFF 整合（隣接整列との一貫性）」をアサート。CI 化はせず手元 Python 実行（`要件メモ` L26）。

---

## 9. PoC 定義と成功基準（中信頼度戦略）

### 9.1 PoC スコープ

リスク最大の **§6.3 GFF 到来側導出 ＋ §6.4 マスター調停（連結過渡収束）** を、§8.2 の Python 編成シミュレーションで先行実装・検証する。Lua 実装（T2〜T5 相当のコア）と同一ロジック。

### 9.2 成功基準（要件 §9.2 準拠）

- **SC1**：`TA-TB-TAB` および反転 TB を含む任意向き編成で、全車の `gff`・物理左右・編成端が **MAX_HOP 以内**に安定一意化（全車種）。
- **SC2**：TA/TAB 連結・分離、TA↔TAB マスター移動の各シーケンスで `sum(is_master)` が常に 0/1 に収束し発散しない。
- **SC3**：バック反転・マスター移動で全車のスロットル符号(-1〜1)・ドア左右・前後灯火が一括整合切替。

### 9.3 PoC 合格後の展開

成功基準達成後、§10 実装計画の残タスク（T6〜T10：出力写像・ライト・モニター）を依存順に展開し、Lua 単一ファイルへ統合、`test_lua_max_bite.py` で 8KB 制約（REQ-NFR-01）を確認する。超過時はロジック/表示チップ分割を検討。

---

## 10. 実装計画（タスク・依存・機能発注単位）

要件 §9.3 のタスク表を、本設計の各 §へリンクし機能発注単位（`stormworks-feature` への発注粒度）として確定する。

| # | タスク | 依存 | 設計参照 | 期待結果 | 検証 |
|---|---|---|---|---|---|
| T0 | push 入力トグル化 | — | §6.1 | 全 Bool の立ち上がり検出・内部状態 | 単体 §8.1 |
| T1 | コネクタ・プロトコル確定（チャンネルマップ） | — | §5 | チャンネル定数表・衝突なし（coordinator） | 目視・ゲーム内 |
| T2 | 連結マーカー送受信・接続/整列/編成端 | T1 | §6.2 | REQ-ORI-01〜03,05 | 単体 §8.1 |
| T3 | マスター調停 | T0,T2 | §6.4 | REQ-MAS-01〜06,09,10 | 統合 §8.2-2 ★PoC |
| T4 | 進行方向・GFF・符号 | T2,T3 | §6.3 | REQ-ORI-04,06, REQ-DIR-01〜03 | 統合 §8.2-1 ★PoC |
| T5 | 指令パケット伝播・中継（クロス中継） | T3,T4 | §6.5 | REQ-COMM-03〜06 | 統合 §8.2 |
| T6 | 走行出力写像（-1〜1） | T4,T5 | §6.6 | REQ-RUN-01〜05 | 単体 §8.1 |
| T7 | ドア左右写像・ローカル操作 | T4,T5 | §6.7 | REQ-DOOR-01〜03 | 単体 §8.1 |
| T8 | ライト（室内/スポット/テール） | T2,T5 | §6.8 | REQ-LIGHT-01〜06 | 単体 §8.1 |
| T9 | 運転モニター描画（3×1） | T4,T6 | §6 M10, `ui_design.md` | REQ-DISP-01,02 | ゲーム内目視 |
| T10 | Python 検証（過渡・移動・収束） | T3〜T8 | §8,§9 | REQ-EDGE-01〜03 | §8.2 全シナリオ |

> 発注順序：**T0,T1 → T2 → T3/T4（PoC）→ T5 → T6,T7,T8 → T9 → T10**。チャンネル/プロパティ衝突回避と統合は coordinator が `feature_dispatch_*.md` で管理する。

---

## 11. 要件トレーサビリティ（REQ → 設計）

| 要件群 | 主な設計箇所 |
|---|---|
| REQ-TYPE-01〜05 | §2.1, §3.4(車種), §6.5(DEAD) |
| REQ-ORI-01〜06 | §5.2(マーカー), §6.2(整列), §6.3(GFF), §6.6(端) |
| REQ-MAS-01〜10 | §6.1(トグル初期化), §6.4(調停) |
| REQ-DIR-01〜03 | §6.3(GFF シード/符号) |
| REQ-RUN-01〜05 | §5.3(auth), §6.6(写像/安全側) |
| REQ-DOOR-01〜03 | §6.7 |
| REQ-LIGHT-01〜06 | §6.8 |
| REQ-DISP-01,02 | §2.2 M10, `docs/spec/ui_design.md` |
| REQ-COMM-01〜06 | §5(プロトコル), §6.5(中継/クロス) |
| REQ-EDGE-01〜03 | §6.4, §7, §8.2, §9 |
| REQ-NFR-01〜04 | §2.1(単一ファイル), §9.3(8KB), §6(状態保持) |

---

## 12. 未決事項・リスク

| ID | 事項 | 内容 | 緩和 |
|---|---|---|---|
| R1 | コネクタ間チャンネルオフセット配線 | I/O モデルは確定（入力＝物理コネクタ固定 前1〜16/後17〜32、出力＝1ノードで前後別内容・§2.1）。残る論点は、自車の後フレーム出力(17〜32)を相手の前入力(1〜16)へ届けるコネクタ間オフセット配線が成立するか | チャンネル定数を1箇所集約。coordinator が `feature_dispatch_*.md` で確定しゲーム内検証 |
| R2 | 伝播遅延と収束 | 長編成での `master_present`/`gff` 収束ティック数 | §9 PoC で MAX_HOP/WIN を実測調整 |
| R3 | 両側到来パケットの採用 | 非マスター中継で前後双方から master_present が来る場合の採用規則 | §6.5 で片側優先。定常一致を §8.2 で検証 |
| R4 | 8KB 制約 | 全機能統合後のソースサイズ | §9.3 で計測、超過時チップ分割（REQ-NFR-01） |
| R5 | DEAD 車の素通し整合 | クロス中継時の遅延・整列影響 | §8.2 にテストシナリオ追加（任意） |

---

## 付録A：画面設計の所在

3×1 モニターの UI 設計は `docs/spec/ui_design.md` に分離する（要件 §9.3）。画面は単一・遷移なしのため `docs/spec/screen_transitions.md` は作成しない（要件 §9.3 の判断を踏襲）。
