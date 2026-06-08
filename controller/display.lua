-- =====================================================================
-- 列車コントローラー [3/3] display : 運転モニター 3×1（M10 / onDraw）
-- core.lua の表示バス（内部コンポジット）を読んで描画。Composite 関数は
-- onDraw 内で呼ばない（onTick で退避）＝ REQ-DISP-02。解像度 96×32。
-- 設計: docs/spec/ui_design.md
-- =====================================================================

-- 表示バス入力（core.lua の出力と一致させること）
local CB_THR,CB_BRK = 11,12
local CB_MP,CB_GFFV,CB_GFF,CB_EBRK,CB_DGR = 9,10,11,15,16
local CB_DGL,CB_ROOM,CB_SPOT,CB_LRD,CB_LLD,CB_ISM,CB_BACK = 25,26,27,28,29,31,32

local d_ism,d_mp,d_gff,d_gffv,d_back=false,false,false,false,false
local d_thr,d_brk=0,0
local d_ebrk,d_spot,d_room,d_door=false,false,false,false

function onTick()
  d_ism =input.getBool(CB_ISM)
  d_mp  =input.getBool(CB_MP)
  d_gff =input.getBool(CB_GFF)
  d_gffv=input.getBool(CB_GFFV)
  d_back=input.getBool(CB_BACK)
  d_ebrk=input.getBool(CB_EBRK)
  d_spot=input.getBool(CB_SPOT)
  d_room=input.getBool(CB_ROOM)
  d_thr =input.getNumber(CB_THR)
  d_brk =d_ebrk and 1.0 or input.getNumber(CB_BRK)
  -- ドア開インジケータ：在線時グローバル/不在時ローカルのいずれか開
  if d_mp then d_door=input.getBool(CB_DGR) or input.getBool(CB_DGL)
  else d_door=input.getBool(CB_LRD) or input.getBool(CB_LLD) end
end

local function bar(x,y,label,v,r,g,b)
  screen.setColor(160,160,160); screen.drawText(x,y,label)
  local w=math.floor(math.max(0,math.min(1,v))*20+0.5)
  screen.setColor(r,g,b); if w>0 then screen.drawRectF(x+16,y,w,5) end
  screen.setColor(200,200,200); screen.drawText(x+37,y,tostring(math.floor(v*100+0.5)))
end

function onDraw()
  -- 列0：状態
  if d_ism then screen.setColor(0,255,0); screen.drawText(2,2,"MASTER")
  else screen.setColor(120,120,120); screen.drawText(2,2,"--") end
  screen.setColor(0,200,255)
  local aux=""
  if d_spot then aux=aux.."S" end
  if d_room then aux=aux.."L" end
  if d_door then aux=aux.."D" end
  screen.drawText(2,24,aux)

  -- 列1：進行方向
  if not d_gffv then screen.setColor(120,120,120); screen.drawText(36,12,"-- ?")
  elseif d_back then screen.setColor(255,0,0); screen.drawText(36,12,"<REV")
  else screen.setColor(0,200,255); screen.drawText(36,12,">FWD") end

  -- 列2：走行
  bar(64,2, "THR",d_thr,0,200,0)
  bar(64,12,"BRK",d_brk,200,80,0)
  if d_ebrk then screen.setColor(255,0,0); screen.drawText(64,22,"EMG") end
end
