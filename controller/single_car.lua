-- TA+TAB 一両車コントローラー (Phase 1)
-- 入力 Number: [1]スロットル(0-1), [2]ブレーキ(0-1)
-- 入力 Bool:   [1]右ドア, [2]左ドア, [3]室内ライト, [4]スポット,
--              [5]マスター要求, [6]パーキングブレーキ, [7]バック
-- 出力 Number: [1]スロットル(-1~1), [2]ブレーキ(0-1)
-- 出力 Bool:   [1]右ドア, [2]左ドア, [3]室内ライト, [4]スポット,
--              [5]テールライト

local is_master  = false
local is_reverse = false
local door_right = false
local door_left  = false
local light_int  = false
local light_spot = false
local park_brake = false

local prev_dr  = false
local prev_dl  = false
local prev_li  = false
local prev_sp  = false
local prev_mst = false
local prev_pk  = false
local prev_rev = false

local disp_throttle = 0.0
local disp_brake    = 0.0

local function rising(cur, prev) return cur and not prev end

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

function onTick()
    local thr_in = input.getNumber(1)
    local brk_in = input.getNumber(2)

    local b_dr  = input.getBool(1)
    local b_dl  = input.getBool(2)
    local b_li  = input.getBool(3)
    local b_sp  = input.getBool(4)
    local b_mst = input.getBool(5)
    local b_pk  = input.getBool(6)
    local b_rev = input.getBool(7)

    if rising(b_dr,  prev_dr)  then door_right = not door_right end
    if rising(b_dl,  prev_dl)  then door_left  = not door_left  end
    if rising(b_li,  prev_li)  then light_int  = not light_int  end
    if rising(b_sp,  prev_sp)  then light_spot = not light_spot end
    if rising(b_mst, prev_mst) then is_master  = not is_master  end
    if rising(b_pk,  prev_pk)  then park_brake = not park_brake end
    if rising(b_rev, prev_rev) then is_reverse = not is_reverse end

    prev_dr  = b_dr
    prev_dl  = b_dl
    prev_li  = b_li
    prev_sp  = b_sp
    prev_mst = b_mst
    prev_pk  = b_pk
    prev_rev = b_rev

    local throttle, brake
    if is_master then
        throttle = thr_in * (is_reverse and -1 or 1)
        brake    = brk_in
    else
        -- REQ-T03: マスター不在時はフルブレーキ
        throttle = 0.0
        brake    = 1.0
    end

    -- REQ-T05: PB ON時はブレーキを1.0に固定
    if park_brake then
        throttle = 0.0
        brake    = 1.0
    end

    output.setNumber(1, throttle)
    output.setNumber(2, brake)
    output.setBool(1, door_right)
    output.setBool(2, door_left)
    output.setBool(3, light_int)
    output.setBool(4, light_spot)
    output.setBool(5, not is_master)  -- REQ-L03: 非マスター時テールライト点灯

    disp_throttle = throttle
    disp_brake    = brake
end

function onDraw()
    -- 背景
    screen.setColor(15, 15, 15)
    screen.drawRectF(0, 0, 96, 32)

    -- 領域区切り線
    screen.setColor(50, 50, 50)
    screen.drawLine(32, 0, 32, 31)
    screen.drawLine(64, 0, 64, 31)

    -- === スロットルゲージ (x:0-31) ===
    -- ゲージ中央(y=17)がゼロ、上が前進(緑)、下が後退(青)
    screen.setColor(220, 220, 220)
    screen.drawText(1, 1, "THR")

    screen.setColor(60, 60, 60)
    screen.drawRectF(1, 8, 12, 20)

    screen.setColor(150, 150, 150)
    screen.drawLine(1, 17, 12, 17)

    if disp_throttle > 0 then
        local bh = math.floor(disp_throttle * 9)
        screen.setColor(80, 200, 80)
        screen.drawRectF(1, 17 - bh, 12, bh)
    elseif disp_throttle < 0 then
        local bh = math.floor(-disp_throttle * 9)
        screen.setColor(80, 120, 220)
        screen.drawRectF(1, 18, 12, bh)
    end

    screen.setColor(220, 220, 220)
    screen.drawText(14, 9, math.floor(math.abs(disp_throttle) * 100) .. "%")

    if disp_throttle < 0 then
        screen.setColor(80, 120, 220)
        screen.drawText(14, 19, "REV")
    end

    -- === ブレーキゲージ (x:32-63) ===
    screen.setColor(220, 220, 220)
    screen.drawText(33, 1, "BRK")

    screen.setColor(60, 60, 60)
    screen.drawRectF(33, 8, 12, 20)

    if disp_brake > 0 then
        local bh = math.floor(disp_brake * 20)
        screen.setColor(220, 80, 80)
        screen.drawRectF(33, 28 - bh, 12, bh)
    end

    screen.setColor(220, 220, 220)
    screen.drawText(47, 14, math.floor(disp_brake * 100) .. "%")

    -- === ステータス領域 (x:64-95) ===
    if is_master then
        screen.setColor(255, 220, 0)
    else
        screen.setColor(150, 150, 150)
    end
    screen.drawText(65, 1, "MST:" .. (is_master and "TA" or "--"))

    drawIndicator(65, 10, "RD", door_right, 255, 220,   0)
    drawIndicator(79, 10, "LD", door_left,  255, 220,   0)
    drawIndicator(65, 20, "LT", light_int,  255, 220,   0)
    drawIndicator(79, 20, "SP", light_spot, 255, 220,   0)
    drawIndicator(65, 27, "TL", not is_master, 255, 140, 0)
    drawIndicator(79, 27, "PB", park_brake, 220,  80,  80)
end
