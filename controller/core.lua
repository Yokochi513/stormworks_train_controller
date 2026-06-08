-- 列車コントローラー [1/3] core : 中核ロジック M1〜M6（クリティカルパス）
-- 入力/連結整列/マスター調停/GFF/指令パケット中継。結果をコマンド・表示バスへ出力。
-- 設計 docs/spec/design.md §6.1-6.5。全車同一ソース、プロパティで分岐。

-- 連結プロトコル 前F=1-16 / 後B=17-32（§5.4）
local F = {link=1,  athr=2,  abrk=3,  mp=1,  sgff=2,  ebrk=3,  dr=4,  dl=5,  room=6,  spot=7,  fr=8,  lv=1}
local B = {link=17, athr=18, abrk=19, mp=17, sgff=18, ebrk=19, dr=20, dl=21, room=22, spot=23, fr=24, lv=-1}

-- 運転手入力（空きch）N:9,10  B:9-15
local IN_THR,IN_BRK = 9,10
local IN_RDOOR,IN_LDOOR,IN_ROOM = 9,10,11
local IN_REQ,IN_EBRK,IN_BACK,IN_SPOT = 12,13,14,15

-- コマンド/表示バス出力（output/display が読む内部コンポジット）
local CB_THR,CB_BRK = 11,12
local CB_MP,CB_GFFV,CB_GFF,CB_CAB,CB_FEND,CB_REND,CB_EBRK,CB_DGR = 9,10,11,12,13,14,15,16
local CB_DGL,CB_ROOM,CB_SPOT,CB_LRD,CB_LLD,CB_LRM,CB_ISM,CB_BACK = 25,26,27,28,29,30,31,32

local WIN,MAX_HOP = 8,32

-- 保持状態
local inited=false
local has_fc,has_bc = false,false
local car_type,is_cab = "TB",false
local prev_rdoor,tgl_rdoor=false,false
local prev_ldoor,tgl_ldoor=false,false
local prev_room, tgl_room =false,false
local prev_req,  tgl_req  =false,false
local prev_ebrk, tgl_ebrk =false,false
local prev_back, tgl_back =false,false
local prev_spot, tgl_spot =false,false
local prev_tgl_req=false
local front_connected,back_connected=false,false
local prev_fconn,prev_bconn=false,false
local front_aligned,back_aligned=false,false
local is_master=false
local acquire_window=0
local master_present=false
local gff,gff_valid=true,false
local is_front_end,is_rear_end=false,false
local fr_ttl=0

local function et(raw,prev,tgl)            -- push 立ち上がりでトグル
  if raw and not prev then tgl=not tgl end
  return raw,tgl
end

local function read_frame(f)
  local link=input.getNumber(f.link)
  return {
    link=link, connected=math.abs(link)>0.5,
    master_present=input.getBool(f.mp), sender_gff=input.getBool(f.sgff),
    auth_throttle=input.getNumber(f.athr), auth_brake=input.getNumber(f.abrk),
    emergency_brake=input.getBool(f.ebrk),
    door_g_right=input.getBool(f.dr), door_g_left=input.getBool(f.dl),
    room_light=input.getBool(f.room), spot_on=input.getBool(f.spot),
    force_release=input.getBool(f.fr),
  }
end

local function write_frame(f,p)            -- link=送信元符号 + パケット
  output.setNumber(f.link,f.lv)
  output.setNumber(f.athr,p.auth_throttle); output.setNumber(f.abrk,p.auth_brake)
  output.setBool(f.mp,p.master_present); output.setBool(f.sgff,p.sender_gff)
  output.setBool(f.ebrk,p.emergency_brake)
  output.setBool(f.dr,p.door_g_right); output.setBool(f.dl,p.door_g_left)
  output.setBool(f.room,p.room_light); output.setBool(f.spot,p.spot_on)
  output.setBool(f.fr,p.force_release)
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
  front_aligned=front_connected and (rxf.link<0)   -- 前で受け隣の後(-1)→整列
  back_aligned =back_connected  and (rxb.link>0)    -- 後で受け隣の前(+1)→整列

  -- M4 マスター調停
  local emitted=false
  if is_cab then
    if tgl_req and not prev_tgl_req then            -- 取得
      is_master=true; emitted=true; acquire_window=WIN
    elseif (not tgl_req) and prev_tgl_req then      -- 解放
      is_master=false
    end
  end
  local new_conn=(front_connected and not prev_fconn) or (back_connected and not prev_bconn)
  if is_cab and new_conn then emitted=true end      -- 運転台付き新規連結→既存解放
  local rx_fr=rxf.force_release or rxb.force_release
  if rx_fr and is_master and acquire_window==0 then -- 横取りで降格
    is_master=false; tgl_req=false                  -- 再取得は OFF→ON 必須
  end
  if emitted then fr_ttl=MAX_HOP
  elseif rx_fr and fr_ttl==0 then fr_ttl=MAX_HOP end
  local fr_out=(fr_ttl>0)
  if fr_ttl>0 then fr_ttl=fr_ttl-1 end
  acquire_window=math.max(0,acquire_window-1)
  master_present=is_master or rxf.master_present or rxb.master_present

  -- M5 GFF 導出 ★中核★
  if car_type=="DEAD" then
    gff_valid=false
  elseif is_master then
    if car_type=="TA" then gff=not tgl_back else gff=tgl_back end
    gff_valid=true
  else
    local got,s_gff,al=false,false,false
    if rxb.master_present then got,s_gff,al=true,rxb.sender_gff,back_aligned end
    if rxf.master_present then got,s_gff,al=true,rxf.sender_gff,front_aligned end  -- 前優先
    if got then gff=(s_gff==al); gff_valid=true else gff_valid=false end
  end
  is_front_end=(gff and not front_connected) or ((not gff) and not back_connected)
  is_rear_end =(gff and not back_connected)  or ((not gff) and not front_connected)

  -- M6 指令パケット生成・中継
  local p
  if car_type=="DEAD" then
    write_frame(F,rxb); write_frame(B,rxf)          -- クロス中継
  else
    if is_master then
      local ebrk=tgl_ebrk
      p={master_present=true,sender_gff=gff,
         auth_throttle=ebrk and 0 or throttle_input, auth_brake=brake_input,
         emergency_brake=ebrk, door_g_right=tgl_rdoor, door_g_left=tgl_ldoor,
         room_light=tgl_room, spot_on=tgl_spot, force_release=fr_out}
    elseif master_present then
      local src=rxf.master_present and rxf or rxb   -- 前優先
      p={master_present=true,sender_gff=gff,
         auth_throttle=src.auth_throttle, auth_brake=src.auth_brake,
         emergency_brake=src.emergency_brake, door_g_right=src.door_g_right,
         door_g_left=src.door_g_left, room_light=src.room_light,
         spot_on=src.spot_on, force_release=fr_out}
    else
      p={master_present=false,sender_gff=gff, auth_throttle=0,auth_brake=0,
         emergency_brake=false, door_g_right=false,door_g_left=false,
         room_light=false,spot_on=false, force_release=fr_out}
    end
    write_frame(F,p); write_frame(B,p)
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

  -- 立ち上がり検出用の前ティック状態を更新（取得/連結を1ティックのエッジに限定）
  -- ※ここを更新しないと毎ティック取得が再発火し acquire_window が降りず、
  --   force_release 相互降格が働かずマスターが複数並存する。
  prev_tgl_req=tgl_req
  prev_fconn,prev_bconn=front_connected,back_connected
end
