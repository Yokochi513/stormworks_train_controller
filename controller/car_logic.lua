-- 汎用列車コントローラー ロジックチップ (car_logic.lua)
-- TA / TB / TAB / 一両車 対応。モニタ表示は別チップ car_display.lua が担当する。
-- 車種はプロパティ "Is TA" / "Is TAB" で決定 (両方 true で一両車)。
-- チャンネル詳細は controller/README.md / docs/spec/requirements.md を参照。
-- ローカル出力 Number3:マスターコード 4:車種コード, Bool6:PB は表示チップ向けメタ。

-- ===== 車種判定 (起動時に1回) =====
local IS_TA     = property.getBool("Is TA")
local IS_TAB    = property.getBool("Is TAB")
local IS_SINGLE = IS_TA and IS_TAB          -- 一両車 (車間通信なし)
local HAS_CAB   = IS_TA or IS_TAB           -- 運転台あり (マスターになれる)

-- ===== コネクタ基点チャンネル =====
local F_N, F_B = 11, 11   -- 前方コネクタ
local R_N, R_B = 21, 21   -- 後方コネクタ

-- ===== 保持状態 =====
local local_master = false
local door_right   = false
local door_left    = false
local light_int    = false
local light_spot   = false
local park_brake   = false
local is_reverse   = false

-- 直前の Bool 入力 (立ち上がり検出用)
local prev_dr, prev_dl, prev_li, prev_sp = false, false, false, false
local prev_mst, prev_pk, prev_rev        = false, false, false

-- 最後に出力した状態 (マスター不在時の保持・マスター奪取時の同期用)
local applied_R, applied_L         = false, false
local applied_light, applied_spot  = false, false

local function rising(cur, prev) return cur and not prev end

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

    -- REQ-M04: 解除要求パルス(req)を受信したらマスターを解除
    if HAS_CAB and local_master and (in_f.req or in_r.req) then
        local_master = false
    end

    -- --- ボタン立ち上がり処理 (運転台車のみマスター取得可) ---
    local b_dr  = input.getBool(1)
    local b_dl  = input.getBool(2)
    local b_li  = input.getBool(3)
    local b_sp  = input.getBool(4)
    local b_mst = input.getBool(5)
    local b_pk  = input.getBool(6)
    local b_rev = input.getBool(7)

    local release_pulse = false                 -- 取得tickのみ true
    if HAS_CAB then
        if rising(b_dr,  prev_dr)  then door_right = not door_right end
        if rising(b_dl,  prev_dl)  then door_left  = not door_left  end
        if rising(b_li,  prev_li)  then light_int  = not light_int  end
        if rising(b_sp,  prev_sp)  then light_spot = not light_spot end
        if rising(b_pk,  prev_pk)  then park_brake = not park_brake end
        if rising(b_rev, prev_rev) then is_reverse = not is_reverse end

        if rising(b_mst, prev_mst) then
            if not local_master then
                -- REQ-M02/M03: マスター取得＋解除要求を他運転台へ伝播
                local_master = true
                release_pulse = true
                -- REQ-M05: 現在の出力状態を引き継ぐ (TAB は左右が TA 基準と反転)
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
        if park_brake then                          -- REQ-T05
            thr = 0.0
            brk = 1.0                               -- PB自体ではなくブレーキ1.0を伝播
        end
        auth = {
            present = true, dir = own_dir,
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
        if auth.dir then                            -- REQ-D04: マスター方向で左右マッピング
            outR, outL = auth.doorR, auth.doorL
        else
            outR, outL = auth.doorL, auth.doorR
        end
        outLight = auth.light
        outSpot  = auth.spot
    else
        out_thr, out_brk = 0.0, 1.0                 -- REQ-T03: マスター不在
        outR, outL       = applied_R, applied_L     -- ドア・ライトは直前状態を保持
        outLight, outSpot = applied_light, applied_spot
    end

    local tail = HAS_CAB and not local_master       -- REQ-L03/L04
    local spot_out = HAS_CAB and outSpot            -- REQ-L02: 運転台車のみ

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
        local fm = math.max(base, in_r.marker or 0)
        local rm = math.max(base, in_f.marker or 0)
        writeConn(F_N, F_B, auth, fm)
        writeConn(R_N, R_B, auth, rm)
        -- 解除要求(req): TB中継+運転台が列車側へ注入 (REQ-M06)
        output.setBool(F_B + 1, in_r.req or (release_pulse and IS_TAB))
        output.setBool(R_B + 1, in_f.req or (release_pulse and IS_TA))
    end

    -- --- 表示チップ(car_display.lua)向けメタ情報 ---
    local master_code = 0                            -- 0:不在 1:TA 2:TAB
    if HAS_CAB and local_master then
        master_code = IS_TA and 1 or 2
    elseif auth.present then
        master_code = auth.dir and 1 or 2
    end
    local type_code = IS_SINGLE and 3 or (IS_TA and 1 or (IS_TAB and 2 or 0))
    output.setNumber(3, master_code)
    output.setNumber(4, type_code)
    output.setBool(6, park_brake)
end
