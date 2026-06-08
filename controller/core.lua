-- 列車コントローラー [1/3] core : M1〜M6（design.md §6.1-6.5）
-- マスター調停＝優先度フラッド: prio=取得順優先度 / live=生存ホップ（§6.4）
local F = {link=1,  prio=4,  live=5,  athr=2,  abrk=3,  mp=1,  sgff=2,  ebrk=3,  dr=4,  dl=5,  room=6,  spot=7,  lv=1}
local B = {link=17, prio=20, live=21, athr=18, abrk=19, mp=17, sgff=18, ebrk=19, dr=20, dl=21, room=22, spot=23, lv=-1}

-- 運転手入力（空きch）N:9,10  B:9-15
local IN_THR,IN_BRK = 9,10
local IN_RDOOR,IN_LDOOR,IN_ROOM = 9,10,11
local IN_REQ,IN_EBRK,IN_BACK,IN_SPOT = 12,13,14,15

-- コマンド/表示バス出力
local CB_THR,CB_BRK = 11,12
local CB_MP,CB_GFFV,CB_GFF,CB_CAB,CB_FEND,CB_REND,CB_EBRK,CB_DGR = 9,10,11,12,13,14,15,16
local CB_DGL,CB_ROOM,CB_SPOT,CB_LRD,CB_LLD,CB_LRM,CB_ISM,CB_BACK = 25,26,27,28,29,30,31,32

local HOPS = 40        -- 生存ホップ上限

-- 保持状態
local inited=false
local has_fc,has_bc = false,false
local car_type,is_cab = "TB",false
local cab_bias=0       -- TA/TAB タイブレーク
local prev_rdoor,tgl_rdoor=false,false
local prev_ldoor,tgl_ldoor=false,false
local prev_room, tgl_room =false,false
local prev_req,  tgl_req  =false,false
local prev_ebrk, tgl_ebrk =false,false
local prev_back, tgl_back =false,false
local prev_spot, tgl_spot =false,false
local prev_tgl_req=false
local front_connected,back_connected=false,false
local front_aligned,back_aligned=false,false
local is_master=false
local own_prio=0       -- 優先度（0=非マスター）
local master_present=false
local gff,gff_valid=true,false
local is_front_end,is_rear_end=false,false

local function et(raw,prev,tgl)            -- push 立ち上がりでトグル
  if raw and not prev then tgl=not tgl end
  return raw,tgl
end

local function read_frame(f)
  local link=input.getNumber(f.link)
  return {
    link=link, connected=math.abs(link)>0.5,
    prio=input.getNumber(f.prio), live=input.getNumber(f.live),
    master_present=input.getBool(f.mp), sender_gff=input.getBool(f.sgff),
    auth_throttle=input.getNumber(f.athr), auth_brake=input.getNumber(f.abrk),
    emergency_brake=input.getBool(f.ebrk),
    door_g_right=input.getBool(f.dr), door_g_left=input.getBool(f.dl),
    room_light=input.getBool(f.room), spot_on=input.getBool(f.spot),
  }
end

local function write_frame(f,p,prio,live)
  output.setNumber(f.link,f.lv)
  output.setNumber(f.prio,prio); output.setNumber(f.live,live)
  output.setNumber(f.athr,p.auth_throttle); output.setNumber(f.abrk,p.auth_brake)
  output.setBool(f.mp,p.master_present); output.setBool(f.sgff,p.sender_gff)
  output.setBool(f.ebrk,p.emergency_brake)
  output.setBool(f.dr,p.door_g_right); output.setBool(f.dl,p.door_g_left)
  output.setBool(f.room,p.room_light); output.setBool(f.spot,p.spot_on)
end

function onTick()
  -- M1 車種判定
  if not inited then
    inited=true
    has_fc=property.getBool("Has Front Control")
    has_bc=property.getBool("Has Back Control")
    is_cab=(has_fc~=has_bc)
    if has_fc and not has_bc then car_type="TA"
    elseif has_bc and not has_fc then car_type="TAB"
    elseif has_fc and has_bc then car_type="DEAD"
    else car_type="TB" end
    cab_bias=(car_type=="TA") and 0.3 or 0.6
  end

  -- M2 push トグル化
  if car_type~="DEAD" then
    prev_rdoor,tgl_rdoor=et(input.getBool(IN_RDOOR),prev_rdoor,tgl_rdoor)
    prev_ldoor,tgl_ldoor=et(input.getBool(IN_LDOOR),prev_ldoor,tgl_ldoor)
    prev_room, tgl_room =et(input.getBool(IN_ROOM), prev_room, tgl_room)
  end
  if is_cab then
    prev_req, tgl_req =et(input.getBool(IN_REQ), prev_req, tgl_req)
    prev_ebrk,tgl_ebrk=et(input.getBool(IN_EBRK),prev_ebrk,tgl_ebrk)
    prev_back,tgl_back=et(input.getBool(IN_BACK),prev_back,tgl_back)
    prev_spot,tgl_spot=et(input.getBool(IN_SPOT),prev_spot,tgl_spot)
  end
  local throttle_input=is_cab and input.getNumber(IN_THR) or 0
  local brake_input   =is_cab and input.getNumber(IN_BRK) or 0

  -- M3 連結受信・整列
  local rxf,rxb=read_frame(F),read_frame(B)
  front_connected,back_connected=rxf.connected,rxb.connected
  front_aligned=front_connected and (rxf.link<0)
  back_aligned =back_connected  and (rxb.link>0)
  local f_alive=front_connected and rxf.live>0.5 and rxf.prio>0
  local b_alive=back_connected  and rxb.live>0.5 and rxb.prio>0

  -- M4 マスター調停（優先度フラッド）
  -- claim 選択: prio 優先、同 prio は live 高い側（マスター近い新鮮側／点滅防止）。
  local in_prio,in_live,in_front=0,0,false
  if f_alive then in_prio,in_live,in_front=rxf.prio,rxf.live,true end
  if b_alive and (rxb.prio>in_prio or (rxb.prio==in_prio and rxb.live>in_live)) then
    in_prio,in_live,in_front=rxb.prio,rxb.live,false
  end

  if is_cab then
    if tgl_req and not prev_tgl_req then              -- 取得：最高優先+1 を採番
      is_master=true
      own_prio=math.floor(in_prio+1e-6)+1+cab_bias
    elseif (not tgl_req) and prev_tgl_req then        -- 解放
      is_master=false; own_prio=0
    end
  end
  if is_master and in_prio>own_prio+1e-6 then         -- 高優先在→降格
    is_master=false; own_prio=0; tgl_req=false        -- 再取得は OFF→ON 必須
  end

  -- 両側へフラッド（マスター=満タン / 中継=live-1）
  local out_prio,out_live
  if is_master then out_prio,out_live=own_prio,HOPS
  elseif in_prio>0 and in_live>1 then out_prio,out_live=in_prio,in_live-1
  else out_prio,out_live=0,0 end
  master_present=is_master or out_prio>0
  local src=(not is_master) and (in_front and rxf or rxb) or nil

  -- M5 GFF 導出 ★中核★
  if car_type=="DEAD" then
    gff_valid=false
  elseif is_master then
    if car_type=="TA" then gff=not tgl_back else gff=tgl_back end
    gff_valid=true
  elseif master_present and src then
    local al=in_front and front_aligned or back_aligned
    gff=(src.sender_gff==al); gff_valid=true
  else
    gff_valid=false
  end
  is_front_end=(gff and not front_connected) or ((not gff) and not back_connected)
  is_rear_end =(gff and not back_connected)  or ((not gff) and not front_connected)

  -- M6 指令パケット生成・中継
  local p
  if car_type=="DEAD" then                            -- クロス中継
    write_frame(F,rxb, b_alive and rxb.prio or 0, b_alive and rxb.live-1 or 0)
    write_frame(B,rxf, f_alive and rxf.prio or 0, f_alive and rxf.live-1 or 0)
  else
    if is_master then
      local ebrk=tgl_ebrk
      p={master_present=true,sender_gff=gff,
         auth_throttle=ebrk and 0 or throttle_input, auth_brake=brake_input,
         emergency_brake=ebrk, door_g_right=tgl_rdoor, door_g_left=tgl_ldoor,
         room_light=tgl_room, spot_on=tgl_spot}
    elseif master_present and src then
      p={master_present=true,sender_gff=gff,
         auth_throttle=src.auth_throttle, auth_brake=src.auth_brake,
         emergency_brake=src.emergency_brake, door_g_right=src.door_g_right,
         door_g_left=src.door_g_left, room_light=src.room_light,
         spot_on=src.spot_on}
    else
      p={master_present=false,sender_gff=gff, auth_throttle=0,auth_brake=0,
         emergency_brake=false, door_g_right=false,door_g_left=false,
         room_light=false,spot_on=false}
    end
    write_frame(F,p,out_prio,out_live); write_frame(B,p,out_prio,out_live)
  end

  -- コマンド/表示バスへ出力
  if car_type=="DEAD" then p={master_present=false,auth_throttle=0,auth_brake=0,
    emergency_brake=false,door_g_right=false,door_g_left=false,room_light=false,spot_on=false} end
  output.setNumber(CB_THR,p.auth_throttle); output.setNumber(CB_BRK,p.auth_brake)
  output.setBool(CB_MP,master_present); output.setBool(CB_GFFV,gff_valid)
  output.setBool(CB_GFF,gff); output.setBool(CB_CAB,is_cab)
  output.setBool(CB_FEND,is_front_end); output.setBool(CB_REND,is_rear_end)
  output.setBool(CB_EBRK,p.emergency_brake)
  output.setBool(CB_DGR,p.door_g_right); output.setBool(CB_DGL,p.door_g_left)
  output.setBool(CB_ROOM,p.room_light); output.setBool(CB_SPOT,p.spot_on)
  output.setBool(CB_LRD,tgl_rdoor); output.setBool(CB_LLD,tgl_ldoor); output.setBool(CB_LRM,tgl_room)
  output.setBool(CB_ISM,is_master); output.setBool(CB_BACK,tgl_back)

  prev_tgl_req=tgl_req
end
