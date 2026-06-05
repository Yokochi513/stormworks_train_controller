-- 列車コントローラー 表示チップ (car_display.lua)
-- car_logic.lua のローカル出力コンポジットを受け取り、運転台モニタへ描画する。
-- onTick で入力を読み、onDraw で描画する (onDraw 内では input が無効なため)。
--
-- 入力 (コンポジット, car_logic のローカル出力と同一バスに接続):
--   Number 1:スロットル(-1~1) 2:ブレーキ(0~1)
--          3:マスターコード(0=不在/1=TA/2=TAB) 4:車種コード(0=TB/1=TA/2=TAB/3=一両車)
--   Bool   1:右ドア 2:左ドア 3:室内ライト 4:スポット 5:テール 6:パーキングブレーキ

local g_throttle, g_brake = 0.0, 0.0
local g_master, g_type    = 0, 0
local g_dr, g_dl, g_lt, g_sp, g_tl, g_pb = false, false, false, false, false, false

function onTick()
    g_throttle = input.getNumber(1)
    g_brake    = input.getNumber(2)
    g_master   = input.getNumber(3)
    g_type     = input.getNumber(4)
    g_dr = input.getBool(1)
    g_dl = input.getBool(2)
    g_lt = input.getBool(3)
    g_sp = input.getBool(4)
    g_tl = input.getBool(5)
    g_pb = input.getBool(6)
end

local function drawIndicator(x, y, label, active, r, g, b)
    screen.setColor(220, 220, 220)
    screen.drawText(x, y, label)
    if active then
        screen.setColor(r, g, b)
        screen.drawCircleF(x + 9, y + 2, 2)
    else
        screen.setColor(80, 80, 80)
        screen.drawCircle(x + 9, y + 2, 2)
    end
end

function onDraw()
    -- 背景
    screen.setColor(15, 15, 15)
    screen.drawRectF(0, 0, 96, 32)

    -- 領域区切り線
    screen.setColor(50, 50, 50)
    screen.drawLine(32, 0, 32, 31)
    screen.drawLine(64, 0, 64, 31)

    -- 車種タグ
    local type_label = g_type == 3 and "1CAR"
        or (g_type == 1 and "TA" or (g_type == 2 and "TAB" or "TB"))
    screen.setColor(120, 160, 220)
    screen.drawText(16, 1, type_label)

    -- === スロットルゲージ (x:0-31) ===
    screen.setColor(220, 220, 220)
    screen.drawText(1, 1, "THR")

    screen.setColor(60, 60, 60)
    screen.drawRectF(1, 8, 12, 20)

    screen.setColor(150, 150, 150)
    screen.drawLine(1, 17, 12, 17)

    if g_throttle > 0 then
        local bh = math.floor(g_throttle * 9)
        screen.setColor(80, 200, 80)
        screen.drawRectF(1, 17 - bh, 12, bh)
    elseif g_throttle < 0 then
        local bh = math.floor(-g_throttle * 9)
        screen.setColor(80, 120, 220)
        screen.drawRectF(1, 18, 12, bh)
    end

    screen.setColor(220, 220, 220)
    screen.drawText(14, 9, math.floor(math.abs(g_throttle) * 100) .. "%")

    if g_throttle < 0 then
        screen.setColor(80, 120, 220)
        screen.drawText(14, 19, "REV")
    end

    -- === ブレーキゲージ (x:32-63) ===
    screen.setColor(220, 220, 220)
    screen.drawText(33, 1, "BRK")

    screen.setColor(60, 60, 60)
    screen.drawRectF(33, 8, 12, 20)

    if g_brake > 0 then
        local bh = math.floor(g_brake * 20)
        screen.setColor(220, 80, 80)
        screen.drawRectF(33, 28 - bh, 12, bh)
    end

    screen.setColor(220, 220, 220)
    screen.drawText(47, 14, math.floor(g_brake * 100) .. "%")

    -- === ステータス領域 (x:64-95) ===
    local mlabel = g_master == 1 and "TA" or (g_master == 2 and "TAB" or "--")
    if mlabel ~= "--" then
        screen.setColor(255, 220, 0)
    else
        screen.setColor(150, 150, 150)
    end
    screen.drawText(65, 1, "MST:" .. mlabel)

    drawIndicator(65, 10, "RD", g_dr, 255, 220, 0)
    drawIndicator(79, 10, "LD", g_dl, 255, 220, 0)
    drawIndicator(65, 20, "LT", g_lt, 255, 220, 0)
    drawIndicator(79, 20, "SP", g_sp, 255, 220, 0)
    drawIndicator(65, 27, "TL", g_tl, 255, 140, 0)
    drawIndicator(79, 27, "PB", g_pb, 220, 80, 80)
end
