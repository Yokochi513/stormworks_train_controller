# CLAUDE.md

このファイルは、リポジトリ内のコードを扱う Claude Code (claude.ai/code) へのガイダンスを提供します。

## プロジェクト概要

このリポジトリは、乗り物建築ゲーム **Stormworks: Build and Rescue** 内のマイコン（マイクロコントローラー）で動作する Lua スクリプトを管理します。現在の主な目的は**列車コントローラーシステム**の開発です。

## Stormworks Lua 環境

マイコンは Lua 5.3 のサンドボックス環境で動作します。ファイルシステム・`require`・標準 I/O は使用できません。エントリーポイントは以下の 2 つのグローバルコールバックです。

```lua
function onTick()  end  -- ゲームティックごとに呼ばれる（デフォルト約60Hz）
function onDraw()  end  -- スクリーン描画時に呼ばれる
```

### I/O API

| 関数 | 説明 |
|---|---|
| `input.getNumber(channel)` | コンポジット数値入力を読む（チャンネル 1〜32） |
| `input.getBool(channel)` | コンポジット論理値入力を読む（チャンネル 1〜32） |
| `output.setNumber(channel, value)` | コンポジット数値出力に書く（チャンネル 1〜32） |
| `output.setBool(channel, value)` | コンポジット論理値出力に書く（チャンネル 1〜32） |

### スクリーン描画 API（`onDraw` 内で使用）

```lua
screen.getWidth()  screen.getHeight()
screen.setColor(r, g, b, a)   -- 0〜255
screen.drawText(x, y, text)
screen.drawRect(x, y, w, h)
screen.drawCircle(x, y, radius)
```

### 制約事項

- `require`・`dofile`・`loadfile`・`io`/`os` ライブラリは使用不可。
- ティックをまたいだコルーチンは使えないため、状態はアップバリューまたはグローバル変数で保持する。
- 1 ティックあたりの実行時間に制限があるため、重いループは避ける。

## 開発ワークフロー

スクリプトは通常の `.lua` ファイルとして編集し、内容をゲーム内マイコンエディターに貼り付けて使用します。ゲーム側にビルドシステムやテストランナーはありません。

**リント（任意）:** `luacheck` がインストールされている場合：
```
luacheck *.lua
```

## リポジトリ構成

プロジェクトの規模が大きくなるにつれ、サブシステムごとにスクリプトを分けて管理することを想定しています（例：`controller/`、`display/`、`signals/`）。各 `.lua` ファイルが 1 つのマイコンチップに対応します。
