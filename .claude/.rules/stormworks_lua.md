# Stormworks Lua スクリプト ルール・仕様まとめ

出典: https://wikiwiki.jp/sbarjp/Lua%E3%82%B9%E3%82%AF%E3%83%AA%E3%83%97%E3%83%88

---

## 実行モデル

- `onTick()` : 論理ティックごとに 1 回呼ばれる。コンポジットデータの読み書きはここで行う。
- `onDraw()` : モニタ描画時に呼ばれる。複数モニタ接続時は複数回実行される。

**重要:** `onTick` 内で Screen 関数は無効。`onDraw` 内で Composite 関数は無効。

---

## コンポジット入出力（チャンネル 1〜32）

```lua
input.getBool(index)
input.getNumber(index)
output.setBool(index, value)
output.setNumber(index, value)
```

---

## プロパティアクセス

マイコン内プロパティコンポーネントの値を直接読み取る。ラベルは大文字小文字を区別し、ダブルクォーテーション必須。

```lua
property.getNumber("label")
property.getBool("label")
property.getText("label")
```

---

## 描画 API（onDraw 内で使用）

### 色設定

```lua
screen.setColor(r, g, b)        -- RGB 0-255
screen.setColor(r, g, b, a)     -- アルファ値付き
```

### 基本図形

```lua
screen.drawClear()                              -- 画面クリア
screen.drawLine(x1, y1, x2, y2)                -- 直線
screen.drawCircle(x, y, r)                     -- 円（枠のみ）
screen.drawCircleF(x, y, r)                    -- 円（塗りつぶし）
screen.drawRect(x, y, w, h)                    -- 矩形（枠のみ）
screen.drawRectF(x, y, w, h)                   -- 矩形（塗りつぶし）
screen.drawTriangle(x1, y1, x2, y2, x3, y3)   -- 三角形（枠のみ）
screen.drawTriangleF(x1, y1, x2, y2, x3, y3)  -- 三角形（塗りつぶし）
```

### テキスト

```lua
screen.drawText(x, y, "text")
screen.drawTextBox(x, y, w, h, "text", h_align, v_align)
-- h_align, v_align: -1（左/上）〜 1（右/下）
```

### 解像度取得

```lua
screen.getWidth()
screen.getHeight()
```

---

## マップ描画

```lua
screen.drawMap(x, y, zoom)
-- x, y: 世界座標（メートル）
-- zoom: 0.1〜50（横幅に表示する km 数）
```

### マップ色カスタマイズ

```lua
screen.setMapColorOcean(r, g, b, a)
screen.setMapColorShallows(r, g, b, a)
screen.setMapColorLand(r, g, b, a)
screen.setMapColorGrass(r, g, b, a)
screen.setMapColorSand(r, g, b, a)
screen.setMapColorSnow(r, g, b, a)
screen.setMapColorRock(r, g, b, a)
screen.setMapColorGravel(r, g, b, a)
```

---

## MAP API 座標変換

```lua
worldX, worldY = map.screenToMap(mapX, mapY, zoom, screenW, screenH, pixelX, pixelY)
pixelX, pixelY = map.mapToScreen(mapX, mapY, zoom, screenW, screenH, worldX, worldY)
```

**注意:** ピクセル座標の原点 (0, 0) は左上。Y 軸方向が世界座標と逆。

---

## タッチスクリーン入力

タッチスクリーンデータはコンポジットで渡される。

### 数値チャンネル

| チャンネル | 内容 |
|---|---|
| 1 | モニタ解像度 X |
| 2 | モニタ解像度 Y |
| 3 | タッチ 1 座標 X |
| 4 | タッチ 1 座標 Y |
| 5 | タッチ 2 座標 X |
| 6 | タッチ 2 座標 Y |

### ON/OFF チャンネル

| チャンネル | 内容 |
|---|---|
| 1 | タッチ 1 押下状態 |
| 2 | タッチ 2 押下状態 |

---

## 利用可能な Lua 標準機能

**グローバル関数:** `pairs`, `ipairs`, `next`, `tostring`, `tonumber`, `type`

**ライブラリ:** `math`, `table`, `string`（Lua 5.3 準拠）

**使用不可:** `require`, `dofile`, `loadfile`, `io`, `os`

---

## HTTP 通信

```lua
async.httpGet(port, "/path")
-- URL は / 始まりで指定。1 ティックに 1 回のみ実行可。超過分はキュー化される。

function httpReply(port, request_body, response_body)
  -- ポート・リクエスト・レスポンスを受け取る
end
```

---

## デバッグ API（非公式）

```lua
debug.log(str)
-- Windows 標準デバッグ出力にログを出力。DebugView で確認可能。
```

---

## 制約・注意事項

- **最大実行時間:** 1000 ミリ秒（超過するとスクリプトが強制終了される）
- **状態の初期化:** ビークルリスポーン時にスクリプト内部状態はリセットされる。永続化にはメモリレジスタなど外部コンポーネントを使用すること。
- **マルチプレイ:** ロジック入出力のみ同期。スクリプト内部は非同期で動作する可能性がある。
- **乱数:** `math.random` はマルチプレイ同期問題が起こる可能性があるため自己責任で使用。
- **コルーチン:** ティックをまたいだコルーチンは使用不可。状態はアップバリューまたはグローバル変数で保持する。
- **重いループ:** 1 ティックあたりの実行時間に制限があるため避けること。
