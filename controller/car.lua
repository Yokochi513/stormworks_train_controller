-- 汎用列車コントローラー (Phase 2) — TA / TB / TAB / 一両車 対応
--
-- 車種はプロパティで決定する:
--   "Is TA"=true,  "Is TAB"=false  → TA  (前部運転台)
--   "Is TA"=false, "Is TAB"=false  → TB  (中間車・運転台なし)
--   "Is TA"=false, "Is TAB"=true   → TAB (後部運転台)
--   "Is TA"=true,  "Is TAB"=true   → 一両車 (車間通信なし)
--
-- == チャンネル割り当て ==
-- 1 マイコンの単一コンポジット入出力に「ローカル運転台」「前方コネクタ」
-- 「後方コネクタ」を重複しないチャンネルへ分離して載せる。
--
-- 【ローカル入力】(TA/TAB のみ運転台から供給)
--   Number 1:スロットルレバー(0-1) 2:ブレーキレバー(0-1)
--   Bool   1:右ドア 2:左ドア 3:室内ライト 4:スポット
--          5:マスター要求 6:パーキングブレーキ 7:バック(逆転)
-- 【ローカル出力】(アクチュエータへ)
--   Number 1:スロットル(-1~1) 2:ブレーキ(0-1)
--   Bool   1:右ドア 2:左ドア 3:室内ライト 4:スポット 5:テールライト
--
-- 【前方コネクタ】Number 11-13 / Bool 11-17
-- 【後方コネクタ】Number 21-23 / Bool 21-27
--   Number +0:スロットル命令 +1:ブレーキ命令 +2:方向マーカー(TA=1.0/TAB=2.0)
--   Bool   +0:マスター存在 +1:マスター要求 +2:マスター方向(TA前=true)
--          +3:右ドア +4:左ドア +5:室内ライト +6:スポット
--   ※ 連結時、A 車の後方(21-)と B 車の前方(11-)を対応付けて配線する。

-- ===== 車種判定 (起動時に1回) =====
local IS_TA     = property.getBool("Is TA")
local IS_TAB    = property.getBool("Is TAB")
local IS_SINGLE = IS_TA and IS_TAB          -- 一両車 (車間通信なし)
local HAS_CAB   = IS_TA or IS_TAB           -- 運転台あり (マスターになれる)

local TYPE_LABEL =
    IS_SINGLE and "1CAR"
    or (IS_TA and "TA"
    or (IS_TAB and "TAB" or "TB"))

-- ===== コネクタ基点チャンネル =====
local F_N, F_B = 11, 11   -- 前方コネクタ
local R_N, R_B = 21, 21   -- 後方コネクタ

-- ===== 保持状態 =====
local local_master = false       -- 自車がマスターを保持しているか (運転台車のみ)
local door_right   = false
local door_left    = false
local light_int    = false
local light_spot   = false
local park_brake   = false
local is_reverse   = false

-- 直前の Bool 入力 (立ち上がり検出用)
local prev_dr, prev_dl, prev_li, prev_sp = false, false, false, false
local prev_mst, prev_pk, prev_rev        = false, false, false

-- 最後に出力した状態 (マスター不在時の保持・マスター奪取時の同期に使用)
local applied_R, applied_L         = false, false
local applied_light, applied_spot  = false, false

-- 描画用グローバル
g_throttle      = 0.0
g_brake         = 0.0
g_master_label  = "--"
g_door_right    = false
g_door_left     = false
g_light         = false
g_spotlight     = false
g_taillight     = false
g_parking_brake = false

local function rising(cur, prev) return cur and not prev end

-- 1コネクタ分の受信パケットを読む
local function readConn(nb, bb)
    return {
        throttle = input.getNumber(nb),
        brake    = input.getNumber(nb + 1),
        marker   = input.getNumber(nb + 2),
        present  = input.getBool(bb),
        req      = input.getBool(bb + 1),
        dir      = input.getBool(bb + 2),
        doorR    = input.getBool(bb + 3),
        doorL    = input.getBool(bb + 4),
        light    = input.getBool(bb + 5),
        spot     = input.getBool(bb + 6),
    }
end

-- 1コネクタ分の送信パケットを書く
local function writeConn(nb, bb, p, marker)
    output.setNumber(nb,     p.throttle or 0)
    output.setNumber(nb + 1, p.brake or 0)
    output.setNumber(nb + 2, marker or 0)
    output.setBool(bb,     p.present or false)
    output.setBool(bb + 1, p.req or false)
    output.setBool(bb + 2, p.dir or false)
    output.setBool(bb + 3, p.doorR or false)
    output.setBool(bb + 4, p.doorL or false)
    output.setBool(bb + 5, p.light or false)
    output.setBool(bb + 6, p.spot or false)
end

function onTick()
    -- --- ローカル運転台入力 ---
    local thr_in = input.getNumber(1)
    local brk_in = input.getNumber(2)

    -- --- 車間受信 ---
    local in_f, in_r
    if IS_SINGLE then
        in_f = { present = false }
        in_r = { present = false }
    else
        in_f = readConn(F_N, F_B)
        in_r = readConn(R_N, R_B)
    end

    local own_dir = IS_TA   -- 自車の前進方向 (TA前=true / TAB前=false)

    -- --- REQ-M04: 反対方向のマスターを受信したら自分のマスターを解除 ---
    if HAS_CAB and local_master then
        if (in_f.present and in_f.dir ~= own_dir)
            or (in_r.present and in_r.dir ~= own_dir) then
            local_master = false
        end
    end

    -- --- ボタン立ち上がり処理 (運転台車のみマスター取得可) ---
    local b_dr  = input.getBool(1)
    local b_dl  = input.getBool(2)
    local b_li  = input.getBool(3)
    local b_sp  = input.getBool(4)
    local b_mst = input.getBool(5)
    local b_pk  = input.getBool(6)
    local b_rev = input.getBool(7)

    if HAS_CAB then
        if rising(b_dr,  prev_dr)  then door_right = not door_right end
        if rising(b_dl,  prev_dl)  then door_left  = not door_left  end
        if rising(b_li,  prev_li)  then light_int  = not light_int  end
        if rising(b_sp,  prev_sp)  then light_spot = not light_spot end
        if rising(b_pk,  prev_pk)  then park_brake = not park_brake end
        if rising(b_rev, prev_rev) then is_reverse = not is_reverse end

        if rising(b_mst, prev_mst) then
            if not local_master then
                -- REQ-M02/M03: マスター取得
                local_master = true
                -- REQ-M05: 現在の出力状態を引き継ぎ、出力が飛ばないよう同期する
                -- (自車基準のトグル変数へ。TAB は左右が TA 基準と反転)
                if IS_TA then
                    door_right, door_left = applied_R, applied_L
                else
                    door_right, door_left = applied_L, applied_R
                end
                light_int, light_spot = applied_light, applied_spot
            else
                local_master = false
            end
        end
    end

    prev_dr, prev_dl, prev_li, prev_sp = b_dr, b_dl, b_li, b_sp
    prev_mst, prev_pk, prev_rev        = b_mst, b_pk, b_rev

    -- --- 権威パケット(全車へ流す命令)の決定 ---
    local auth
    if HAS_CAB and local_master then
        local rev_sign = is_reverse and -1 or 1
        local dir_sign = IS_TA and 1 or -1          -- スロットルを TA 基準へ変換
        local thr = thr_in * dir_sign * rev_sign
        local brk = brk_in
        if park_brake then                          -- REQ-T05 / 仕様変更_0602
            thr = 0.0
            brk = 1.0                                -- PB自体ではなくブレーキ1.0を伝播
        end
        auth = {
            present = true, dir = own_dir, req = true,
            throttle = thr, brake = brk,
            doorR = door_right, doorL = door_left,  -- マスター基準(自車基準)
            light = light_int, spot = light_spot,
        }
    elseif in_f.present then
        auth = in_f
    elseif in_r.present then
        auth = in_r
    else
        auth = { present = false }
    end

    -- --- ローカル出力の算出 ---
    local out_thr, out_brk, outR, outL, outLight, outSpot
    if auth.present then
        out_thr = auth.throttle                     -- 既に TA 基準
        out_brk = auth.brake
        -- REQ-D04: マスター方向フラグで左右を物理(TA基準)へマッピング
        if auth.dir then
            outR, outL = auth.doorR, auth.doorL
        else
            outR, outL = auth.doorL, auth.doorR
        end
        outLight = auth.light
        outSpot  = auth.spot
    else
        -- REQ-T03: マスター不在はスロットル0・フルブレーキ
        out_thr, out_brk = 0.0, 1.0
        -- ドア・ライトは直前状態を保持 (REQ-M05 の趣旨)
        outR, outL       = applied_R, applied_L
        outLight, outSpot = applied_light, applied_spot
    end

    local tail = HAS_CAB and not local_master       -- REQ-L03/L04
    local spot_out = HAS_CAB and outSpot             -- REQ-L02: 運転台車のみ

    output.setNumber(1, out_thr)
    output.setNumber(2, out_brk)
    output.setBool(1, outR)
    output.setBool(2, outL)
    output.setBool(3, outLight)
    output.setBool(4, spot_out)
    output.setBool(5, tail)

    applied_R, applied_L          = outR, outL
    applied_light, applied_spot   = outLight, outSpot

    -- --- 車間送信 (一両車を除く) ---
    if not IS_SINGLE then
        -- 方向マーカー: TA=1.0 / TAB=2.0 を発信、TB は反対側へ中継 (REQ 3.3)
        local base = IS_TA and 1.0 or (IS_TAB and 2.0 or 0)
        local fm = math.max(base, in_r.marker or 0)  -- 前方出力 = 後方受信を中継
        local rm = math.max(base, in_f.marker or 0)  -- 後方出力 = 前方受信を中継
        -- 命令は両コネクタへ流す (マスターから両端へ伝播・REQ-M06 中継)
        writeConn(F_N, F_B, auth, fm)
        writeConn(R_N, R_B, auth, rm)
    end

    -- --- 描画用状態 ---
    g_throttle      = out_thr
    g_brake         = out_brk
    g_door_right    = outR
    g_door_left     = outL
    g_light         = outLight
    g_spotlight     = spot_out
    g_taillight     = tail
    g_parking_brake = park_brake
    if HAS_CAB and local_master then
        g_master_label = IS_TA and "TA" or "TAB"
    elseif auth.present then
        g_master_label = auth.dir and "TA" or "TAB"
    else
        g_master_label = "--"
    end
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
    screen.setColor(120, 160, 220)
    screen.drawText(16, 1, TYPE_LABEL)

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
    if g_master_label ~= "--" then
        screen.setColor(255, 220, 0)
    else
        screen.setColor(150, 150, 150)
    end
    screen.drawText(65, 1, "MST:" .. g_master_label)

    drawIndicator(65, 10, "RD", g_door_right, 255, 220, 0)
    drawIndicator(79, 10, "LD", g_door_left,  255, 220, 0)
    drawIndicator(65, 20, "LT", g_light,      255, 220, 0)
    drawIndicator(79, 20, "SP", g_spotlight,  255, 220, 0)
    drawIndicator(65, 27, "TL", g_taillight,  255, 140, 0)
    drawIndicator(79, 27, "PB", g_parking_brake, 220, 80, 80)
end
