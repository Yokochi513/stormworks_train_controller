-- =====================================================================
-- 列車コントローラー [2/3] output : 車両機器出力（M7〜M9）
-- core.lua のコマンドバス（内部コンポジット）を読み、走行/ドア/ライトへ写像。
-- 中核結果の消費のみのため core から1ティック遅延（定常では不可視）。
-- 設計: docs/spec/design.md §6.6〜6.8 / REQ-RUN/DOOR/LIGHT-*
-- =====================================================================

-- コマンドバス入力（core.lua の出力と一致させること）
local CB_THR,CB_BRK = 11,12
local CB_MP,CB_GFFV,CB_GFF,CB_CAB,CB_FEND,CB_REND,CB_EBRK,CB_DGR = 9,10,11,12,13,14,15,16
local CB_DGL,CB_ROOM,CB_SPOT,CB_LRD,CB_LLD,CB_LRM = 25,26,27,28,29,30

-- 車両機器出力（このスクリプト専用の出力ノード）
local OUT_THR,OUT_BRK = 1,2                          -- N: スロットル -1..1 / ブレーキ 0..1
local OUT_RDOOR,OUT_LDOOR,OUT_ROOM,OUT_SPOT,OUT_TAIL = 1,2,3,4,5  -- B

function onTick()
  local mp   = input.getBool(CB_MP)
  local gffv = input.getBool(CB_GFFV)
  local gff  = input.getBool(CB_GFF)
  local cab  = input.getBool(CB_CAB)
  local fend = input.getBool(CB_FEND)
  local rend = input.getBool(CB_REND)
  local athr = input.getNumber(CB_THR)
  local abrk = input.getNumber(CB_BRK)
  local ebrk = input.getBool(CB_EBRK)
  local dgr  = input.getBool(CB_DGR)
  local dgl  = input.getBool(CB_DGL)
  local room = input.getBool(CB_ROOM)
  local spot = input.getBool(CB_SPOT)
  local lrd  = input.getBool(CB_LRD)   -- ローカル右ドアトグル（不在時）
  local lld  = input.getBool(CB_LLD)
  local lrm  = input.getBool(CB_LRM)

  -- M7 走行（REQ-RUN-03〜05, REQ-DIR-03）
  if (not mp) or (not gffv) then
    output.setNumber(OUT_THR,0); output.setNumber(OUT_BRK,1.0)   -- 安全側
  else
    output.setNumber(OUT_THR,(gff and 1 or -1)*athr)
    output.setNumber(OUT_BRK,ebrk and 1.0 or abrk)
  end

  -- M8 ドア（グローバル左右↔ローカル左右・REQ-DOOR-01〜03）
  local lr,ll
  if mp then
    if gff then lr,ll=dgr,dgl else lr,ll=dgl,dgr end
  else
    lr,ll=lrd,lld                                                -- 不在時ローカル操作
  end
  output.setBool(OUT_RDOOR,lr); output.setBool(OUT_LDOOR,ll)

  -- M9 ライト（室内/前端スポット/後端テール・REQ-LIGHT-01〜06）
  output.setBool(OUT_ROOM, mp and room or ((not mp) and lrm))
  output.setBool(OUT_SPOT, cab and fend and spot)
  output.setBool(OUT_TAIL, cab and mp and rend and not fend)
end
