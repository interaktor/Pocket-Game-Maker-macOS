-- new line
--========================================
-- define game save functions
--========================================
-- new line
function GetSaveFolderPath()
	if PGMPSP then
		return "ms0:/psp/PGMSAVEDATA"
	elseif PGMIOS then
		return "../Documents/PGMSAVEDATA"
	elseif PGMPC then
		return "PGMSAVEDATA"
	elseif PGMARD then
		return "PGMSAVEDATA"
	end
	return "PGMSAVEDATA"
end
-- new line
function GetGameDataFolderPath(num)
	if num < 10 then
		return GAME_NAME .. "000" .. num
	elseif num < 100 then
		return GAME_NAME .. "00" .. num
	elseif num < 1000 then
		return GAME_NAME .. "0" .. num
	else
		return GAME_NAME ..  num
	end
end
-- new line
function GetFullGameDataFolderPath(num)
	return GetSaveFolderPath() .. "/" .. GetGameDataFolderPath(num)
end
-- new line
function GetFullPubGameDataFolderPath()
	return GetSaveFolderPath() .. "/" .. GAME_NAME .. "SYS"
end
-- new line
function CreatePGMSaveFolder()
	FolderCreate( GetSaveFolderPath() )
end
-- new line
function CreateGameDataBuffer()
	-- malloc 64kb
	local buffer,size = PGBufferCreate(1024 * 64)
	local offset = 0
-- new line
	-- read success flag
	MEMNUMCPY(buffer+offset,65535,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
-- new line
	if call_menu_flag then
		MEMNUMCPY(buffer+offset,1,MEM_UINT8)
	end
	offset = offset + MEMMODESIZE(MEM_UINT8)
-- new line
	-- value
	for i=1,TABLE_VALUE_MAX do
		MEMNUMCPY(buffer+offset,value[i],MEM_SINT32)
		offset = offset + MEMMODESIZE(MEM_SINT32)
	end
	-- event
	for i=1,TABLE_EVENT_MAX do
		MEMNUMCPY(buffer+offset,event[i],MEM_UINT8)
		offset = offset + MEMMODESIZE(MEM_UINT8)
	end
	-- line
	for i=1,TABLE_LINE_MAX do
		MEMSTRCPY(buffer+offset,line[i],MEM_UINT8_128)
		offset = offset + MEMMODESIZE(MEM_UINT8_128)
	end
-- new line
	-- font
	MEMSTRCPY(buffer+offset,FONT_PATH,MEM_UINT8_64)
	offset = offset + MEMMODESIZE(MEM_UINT8_64)
	MEMNUMCPY(buffer+offset,FONT_SIZE,MEM_UINT8)
	offset = offset + MEMMODESIZE(MEM_UINT8)
	MEMNUMCPY(buffer+offset,FONT_COLOR,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
-- new line
	-- matte
	MEMSTRCPY(buffer+offset,am_matte.name,MEM_UINT8_32)
	offset = offset + MEMMODESIZE(MEM_UINT8_32)
-- new line
	-- screen color
	MEMNUMCPY(buffer+offset,am_scene.r,MEM_SINT8)
	offset = offset + MEMMODESIZE(MEM_SINT8)
	MEMNUMCPY(buffer+offset,am_scene.g,MEM_SINT8)
	offset = offset + MEMMODESIZE(MEM_SINT8)
	MEMNUMCPY(buffer+offset,am_scene.b,MEM_SINT8)
	offset = offset + MEMMODESIZE(MEM_SINT8)
	MEMNUMCPY(buffer+offset,am_scene.a,MEM_SINT8)
	offset = offset + MEMMODESIZE(MEM_SINT8)
-- new line
	-- bg * x
	for i=1,AM_SCENE_BG_MAX do
		local bg = am_scene.bg[i]
		MEMSTRCPY(buffer+offset,bg.file,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		MEMNUMCPY(buffer+offset,bg.dx,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		MEMNUMCPY(buffer+offset,bg.dy,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		if bg.display then
			MEMNUMCPY(buffer+offset,1,MEM_SINT8)
		else
			MEMNUMCPY(buffer+offset,0,MEM_SINT8)
		end
		offset = offset + MEMMODESIZE(MEM_SINT8)
		MEMNUMCPY(buffer+offset,bg.dtype,MEM_SINT32)
		offset = offset + MEMMODESIZE(MEM_SINT32)
	end
-- new line
	-- fg * x
	for i=1,AM_SCENE_FG_MAX do
		local fg = am_scene.fg[i]
		MEMSTRCPY(buffer+offset,fg.file,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		MEMNUMCPY(buffer+offset,fg.dx,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		MEMNUMCPY(buffer+offset,fg.dy,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		if fg.display then
			MEMNUMCPY(buffer+offset,1,MEM_SINT8)
		else
			MEMNUMCPY(buffer+offset,0,MEM_SINT8)
		end
		offset = offset + MEMMODESIZE(MEM_SINT8)
		MEMNUMCPY(buffer+offset,fg.dtype,MEM_SINT32)
		offset = offset + MEMMODESIZE(MEM_SINT32)
	end
-- new line
	-- ani * x
	for i=1,AM_SCENE_ANI_MAX do
		local ani = am_scene.ani[i]
		MEMSTRCPY(buffer+offset,ani.file,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		MEMNUMCPY(buffer+offset,ani.dx,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		MEMNUMCPY(buffer+offset,ani.dy,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		MEMNUMCPY(buffer+offset,ani.ani_count,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		MEMNUMCPY(buffer+offset,ani.ani_speed,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		MEMNUMCPY(buffer+offset,ani.ani_time,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		if ani.display then
			MEMNUMCPY(buffer+offset,1,MEM_SINT8)
		else
			MEMNUMCPY(buffer+offset,0,MEM_SINT8)
		end
		offset = offset + MEMMODESIZE(MEM_SINT8)
	end
-- new line
	-- texfg * x
	for i=1,AM_SCENE_FG_MAX do
		-- str,dx,dy,display,w,h
		local texfg = am_scene.texfg[i]
		MEMSTRCPY(buffer+offset,texfg.str,MEM_UINT8_128)
		offset = offset + MEMMODESIZE(MEM_UINT8_128)
		MEMNUMCPY(buffer+offset,texfg.dx,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		MEMNUMCPY(buffer+offset,texfg.dy,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		if texfg.display then
			MEMNUMCPY(buffer+offset,1,MEM_SINT8)
		else
			MEMNUMCPY(buffer+offset,0,MEM_SINT8)
		end
		offset = offset + MEMMODESIZE(MEM_SINT8)
		MEMNUMCPY(buffer+offset,texfg.quad_w,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		MEMNUMCPY(buffer+offset,texfg.quad_h,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
	end
-- new line
	-- mp3 * 2
	for i=1,2 do
		-- name,vol,playtimes
		local mp3 = am_sound.mp3[i]
		MEMSTRCPY(buffer+offset,mp3.name,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		MEMNUMCPY(buffer+offset,mp3.vol,MEM_UINT8)
		offset = offset + MEMMODESIZE(MEM_UINT8)
		MEMNUMCPY(buffer+offset,mp3.playtimes,MEM_UINT8)
		offset = offset + MEMMODESIZE(MEM_UINT8)
	end
-- new line
	-- wav * 4
	for i=1,4 do
		-- name,vol,playtimes
		local wav = am_sound.wav[i]
		MEMSTRCPY(buffer+offset,wav.name,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		MEMNUMCPY(buffer+offset,wav.vol,MEM_UINT8)
		offset = offset + MEMMODESIZE(MEM_UINT8)
		MEMNUMCPY(buffer+offset,wav.playtimes,MEM_UINT8)
		offset = offset + MEMMODESIZE(MEM_UINT8)
	end
-- new line
	-- rect * x
	for i=1,AM_RECT_MAX do
		local rect = am_rect[i]
		MEMSTRCPY(buffer+offset,rect.script,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		MEMNUMCPY(buffer+offset,rect.top,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		MEMNUMCPY(buffer+offset,rect.bottom,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		MEMNUMCPY(buffer+offset,rect.left,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		MEMNUMCPY(buffer+offset,rect.right,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
	end
-- new line
	-- event script
	for i=1,16 do
		-- name,curr_i
		local scr = am_script[i]
		if scr then
			MEMSTRCPY(buffer+offset,EScriptName(scr),MEM_UINT8_64)
			offset = offset + MEMMODESIZE(MEM_UINT8_64)
			MEMNUMCPY(buffer+offset,EScriptCurrLine(scr),MEM_SINT32)
			offset = offset + MEMMODESIZE(MEM_SINT32)
		else
			offset = offset + 68
		end
	end
-- new line
	-- ramus
	if am_ramus then
		for i=1,16 do
			-- string
			if am_ramus.sel[i] then
				--print(am_ramus.test[i].string,am_ramus.label[i])
				MEMSTRCPY(buffer+offset,am_ramus.sel[i],MEM_UINT8_64)
				offset = offset + MEMMODESIZE(MEM_UINT8_64)
				MEMNUMCPY(buffer+offset,am_ramus.label[i],MEM_SINT32)
				offset = offset + MEMMODESIZE(MEM_SINT32)
			else
				offset = offset + MEMMODESIZE(MEM_UINT8_64)
				offset = offset + MEMMODESIZE(MEM_SINT32)
			end
		end
	else
		offset = offset + ((MEMMODESIZE(MEM_UINT8_64)+MEMMODESIZE(MEM_SINT32)) * 16)
	end
-- new line
	-- ini,dialog,speed,dx,dy,mode
	if speak_attribute().msg then
		MEMSTRCPY(buffer+offset,speak_attribute().msg,MEM_UINT8_1024)
		offset = offset + MEMMODESIZE(MEM_UINT8_1024)
	else
		offset = offset + MEMMODESIZE(MEM_UINT8_1024)
	end
-- new line
-- new line
	MEMNUMCPY(buffer+offset,DIALOG_FONT_WIDTH,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	MEMNUMCPY(buffer+offset,DIALOG_FONT_HEIGHT,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	MEMNUMCPY(buffer+offset,DIALOG_LINELEN,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	MEMNUMCPY(buffer+offset,DIALOG_LINEMAX,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	MEMNUMCPY(buffer+offset,DIALOG_SPEED,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	MEMNUMCPY(buffer+offset,DIALOG_MODE,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
-- new line
	MEMNUMCPY(buffer+offset,DIALOG_DX,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	MEMNUMCPY(buffer+offset,DIALOG_DY,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	MEMNUMCPY(buffer+offset,DIALOG_NAME_DX,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	MEMNUMCPY(buffer+offset,DIALOG_NAME_DY,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
-- new line
	return buffer,size
end
-- new line
function CreateGameDataInfoBuffer()
	local buffer,size = PGBufferCreate(1024 * 8)
	local offset = 0
-- new line
	-- gamename,version,time,msg
	MEMSTRCPY(buffer+offset,GAME_NAME,MEM_UINT8_64)
	offset = offset + MEMMODESIZE(MEM_UINT8_64)
	MEMNUMCPY(buffer+offset,GAME_VERSION,MEM_FLOAT)
	offset = offset + MEMMODESIZE(MEM_FLOAT)
-- new line
	local time = localtime()
	MEMNUMCPY(buffer+offset,time.year,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	MEMNUMCPY(buffer+offset,time.month,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	MEMNUMCPY(buffer+offset,time.day,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	MEMNUMCPY(buffer+offset,time.hour,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	MEMNUMCPY(buffer+offset,time.minutes,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	MEMNUMCPY(buffer+offset,time.seconds,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
-- new line
	MEMSTRCPY(buffer+offset,GAME_MSG,MEM_UINT8_128)
	offset = offset + MEMMODESIZE(MEM_UINT8_128)
-- new line
	return buffer,size
end
-- new line
function LoadGameData(buffer)
	local offset = 0
-- new line
	-- test
	local flag = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	if flag~=65535 then print("buffer have invalid data.") return end
-- new line
	stageclear()
-- new line
	if MEMGETNUM(buffer+offset,MEM_UINT8)==1 then
		call_menu_flag = true
	else
		call_menu_flag = false
	end
	offset = offset + MEMMODESIZE(MEM_UINT8)
-- new line
	for i=1,TABLE_VALUE_MAX do
		value[i] = MEMGETNUM(buffer+offset,MEM_SINT32)
		offset = offset + MEMMODESIZE(MEM_SINT32)
	end
	for i=1,TABLE_EVENT_MAX do
		event[i] = MEMGETNUM(buffer+offset,MEM_UINT8)
		offset = offset + MEMMODESIZE(MEM_UINT8)
	end
	for i=1,TABLE_LINE_MAX do
		line[i] = MEMGETSTR(buffer+offset,MEM_UINT8_128)
		if not line[i] then
			line[i]=""
		end
		offset = offset + MEMMODESIZE(MEM_UINT8_128)
	end
-- new line
	-- font
	FONT_PATH = MEMGETSTR(buffer+offset,MEM_UINT8_64)
	offset = offset + MEMMODESIZE(MEM_UINT8_64)
	FONT_SIZE = MEMGETNUM(buffer+offset,MEM_UINT8)
	offset = offset + MEMMODESIZE(MEM_UINT8)
	FONT_COLOR = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	-- font init
	if am_font.pf then
		FontDelete(am_font.pf)
		am_font.pf = nil
	end
	am_font_getinstance()
-- new line
	-- matte
	local matte = MEMGETSTR(buffer+offset,MEM_UINT8_32)
	offset = offset + MEMMODESIZE(MEM_UINT8_32)
	if matte then
		tstnull()
		tst(matte)
	end
-- new line
	-- screen color
	am_scene.r = MEMGETNUM(buffer+offset,MEM_SINT8)
	offset = offset + MEMMODESIZE(MEM_SINT8)
	am_scene.g = MEMGETNUM(buffer+offset,MEM_SINT8)
	offset = offset + MEMMODESIZE(MEM_SINT8)
	am_scene.b = MEMGETNUM(buffer+offset,MEM_SINT8)
	offset = offset + MEMMODESIZE(MEM_SINT8)
	am_scene.a = MEMGETNUM(buffer+offset,MEM_SINT8)
	offset = offset + MEMMODESIZE(MEM_SINT8)
	screencolor(am_scene.r,am_scene.g,am_scene.b,am_scene.a)
-- new line
	-- bg * x
	local bg = {}
	for i=1,AM_SCENE_BG_MAX do
		bg.file = MEMGETSTR(buffer+offset,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		bg.dx = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		bg.dy = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		bg.display = MEMGETNUM(buffer+offset,MEM_SINT8)
		offset = offset + MEMMODESIZE(MEM_SINT8)
		bg.dtype = MEMGETNUM(buffer+offset,MEM_SINT32)
		offset = offset + MEMMODESIZE(MEM_SINT32)
-- new line
		if bg.file then
			_bg(i,bg.file,0,0)
		end
		bgxy(i,bg.dx,bg.dy)
		if bg.display==1 then
			bgon(i)
		end
	end
-- new line
	-- fg * x
	local fg = {}
	for i=1,AM_SCENE_FG_MAX do
		fg.file = MEMGETSTR(buffer+offset,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		fg.dx = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		fg.dy = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		fg.display = MEMGETNUM(buffer+offset,MEM_SINT8)
		offset = offset + MEMMODESIZE(MEM_SINT8)
		fg.dtype = MEMGETNUM(buffer+offset,MEM_SINT32)
		offset = offset + MEMMODESIZE(MEM_SINT32)
-- new line
		if fg.file then
			if fg.dtype~=IMG_4444 then
				_fg(i,fg.file,0,0,fg.dtype)
			else
				_fg(i,fg.file,0,0)
			end
		end
		fgxy(i,fg.dx,fg.dy)
		if fg.display==1 then
			fgon(i)
		end
	end
-- new line
	-- ani * x
	local _ani = {}
	for i=1,AM_SCENE_ANI_MAX do
		_ani.file = MEMGETSTR(buffer+offset,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		_ani.dx = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		_ani.dy = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		_ani.ani_count = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		_ani.ani_speed = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		_ani.ani_time = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		_ani.display = MEMGETNUM(buffer+offset,MEM_SINT8)
		offset = offset + MEMMODESIZE(MEM_SINT8)
-- new line
		if _ani.file then
			ani(i,_ani.file)
			aniset(i,_ani.ani_count,_ani.ani_speed,_ani.ani_time)
			anixy(i,_ani.dx,_ani.dy)
		end
		if _ani.display == 1 then
			anion(i)
		end
	end
-- new line
	-- texfg * x
	local _texfg = {}
	for i=1,AM_SCENE_FG_MAX do
		-- str,dx,dy,display,w,h
		_texfg.str = MEMGETSTR(buffer+offset,MEM_UINT8_128)
		offset = offset + MEMMODESIZE(MEM_UINT8_128)
		_texfg.dx = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		_texfg.dy = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		_texfg.display = MEMGETNUM(buffer+offset,MEM_SINT8)
		offset = offset + MEMMODESIZE(MEM_SINT8)
		_texfg.w = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		_texfg.h = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
-- new line
		if _texfg.str then
			texfg(i,_texfg.str,0,0,_texfg.w,_texfg.h)
		end
		texfgxy(i,_texfg.dx,_texfg.dy)
		if _texfg.display==1 then
			texfgon(i)
		end
		if i==MSGNAME_NUM then
			_texfg.name = _texfg.str
		end
	end
-- new line
	local temp_folder = PGM_RES_FOLDER
	PGM_RES_FOLDER = ""
-- new line
	-- mp3 * 2
	local mp3 = {}
	for i=1,2 do
		-- name,vol,playtimes
		mp3.name = MEMGETSTR(buffer+offset,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		mp3.vol = MEMGETNUM(buffer+offset,MEM_UINT8)
		offset = offset + MEMMODESIZE(MEM_UINT8)
		mp3.playtimes = MEMGETNUM(buffer+offset,MEM_UINT8)
		offset = offset + MEMMODESIZE(MEM_UINT8)
		if mp3.name and mp3.playtimes==0 then
			mp3load(mp3.name,i)
			mp3playtimes(i,mp3.playtimes)
			mp3volume(i,mp3.vol)
			mp3play(i)
		elseif mp3.name and mp3.playtimes~=0 then
			mp3load(mp3.name,i)
			mp3playtimes(i,mp3.playtimes)
			mp3volume(i,mp3.vol)
			mp3play(i)
		end
	end
-- new line
	-- wav * 4
	local wav = {}
	for i=1,4 do
		-- name,vol,playtimes
		wav.name = MEMGETSTR(buffer+offset,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		wav.vol = MEMGETNUM(buffer+offset,MEM_UINT8)
		offset = offset + MEMMODESIZE(MEM_UINT8)
		wav.playtimes = MEMGETNUM(buffer+offset,MEM_UINT8)
		offset = offset + MEMMODESIZE(MEM_UINT8)
		if wav.name and wav.name~="buffer" and wav.playtimes==0 then
			wavload(wav.name,i)
			wavplaytimes(i,wav.playtimes)
			wavvolume(i,wav.vol)
			wavplay(i)
		end
	end
-- new line
	-- rect * x
	for i=1,AM_RECT_MAX do
		am_rect[i].script = MEMGETSTR(buffer+offset,MEM_UINT8_64)
		if not am_rect[i].script then am_rect[i].script="" end
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		am_rect[i].top = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		am_rect[i].bottom = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		am_rect[i].left = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
		am_rect[i].right = MEMGETNUM(buffer+offset,MEM_SINT16)
		offset = offset + MEMMODESIZE(MEM_SINT16)
	end
-- new line
	-- event script
	stacknull()
	for i=1,16 do
		-- name,curr_i
		local name = MEMGETSTR(buffer+offset,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		local label = MEMGETNUM(buffer+offset,MEM_SINT32)
		offset = offset + MEMMODESIZE(MEM_SINT32)
		if name then
			run(name)
			goto(label)
		end
	end
-- new line
	-- ramus
	am_ramus_fini()
	local ramus = {}
	for i=1,16 do
		-- string
		ramus[i] = {}
		ramus[i].str = MEMGETSTR(buffer+offset,MEM_UINT8_64)
		offset = offset + MEMMODESIZE(MEM_UINT8_64)
		ramus[i].label = MEMGETNUM(buffer+offset,MEM_SINT32)
		offset = offset + MEMMODESIZE(MEM_SINT32)
	end
-- new line
	if ramus[1].str then
		am_ramus = PGRamusButton.new(
			ramus[1].str,ramus[1].label,
			ramus[2].str,ramus[2].label,
			ramus[3].str,ramus[3].label,
			ramus[4].str,ramus[4].label,
			ramus[5].str,ramus[5].label,
			ramus[6].str,ramus[6].label,
			ramus[7].str,ramus[7].label,
			ramus[8].str,ramus[8].label,
			ramus[9].str,ramus[9].label,
			ramus[10].str,ramus[10].label,
			ramus[11].str,ramus[11].label,
			ramus[12].str,ramus[12].label,
			ramus[13].str,ramus[13].label,
			ramus[14].str,ramus[14].label,
			ramus[15].str,ramus[15].label,
			ramus[16].str,ramus[16].label)
		am_ramus:init()
	end
-- new line
	-- dialog
-- new line
	local dia_str = MEMGETSTR(buffer+offset,MEM_UINT8_1024)
	offset = offset + MEMMODESIZE(MEM_UINT8_1024)
-- new line
	DIALOG_FONT_WIDTH = MEMGETNUM(buffer+offset,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	DIALOG_FONT_HEIGHT = MEMGETNUM(buffer+offset,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	DIALOG_LINELEN = MEMGETNUM(buffer+offset,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	DIALOG_LINEMAX = MEMGETNUM(buffer+offset,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	DIALOG_SPEED = MEMGETNUM(buffer+offset,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	DIALOG_MODE = MEMGETNUM(buffer+offset,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
-- new line
	DIALOG_DX = MEMGETNUM(buffer+offset,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	DIALOG_DY = MEMGETNUM(buffer+offset,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	DIALOG_NAME_DX = MEMGETNUM(buffer+offset,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
	DIALOG_NAME_DY = MEMGETNUM(buffer+offset,MEM_UINT16)
	offset = offset + MEMMODESIZE(MEM_UINT16)
-- new line
	speak_attribute_reset()
-- new line
	textclear()
-- new line
	if dia_str then
		speak_attribute().msg=dia_str
		historybegin()
		history.count = 1
		history.script[history.count] = dia_str
		history.name[history.count] = _texfg.name
		history.voice[history.count] = string.sub(am_sound.mp3[2].name,5,-1)
	end
-- new line
	PGM_RES_FOLDER = temp_folder
-- new line
end
-- new line
function LoadGameDataInfo(buffer)
	-- get version
	local offset = 0
	local info = {}
-- new line
	if MEMGETSTR(buffer+offset,MEM_UINT8_64)~=GAME_NAME then
		print("this game data can not be read.")
		return nil
	end
	info.gamename = MEMGETSTR(buffer+offset,MEM_UINT8_64)
	offset = offset + MEMMODESIZE(MEM_UINT8_64)
-- new line
	if MEMGETNUM(buffer+offset,MEM_FLOAT)~=1.0 then
		print("this info can not be read.")
		return nil
	end
	info.version = MEMGETNUM(buffer+offset,MEM_FLOAT)
	offset = offset + MEMMODESIZE(MEM_FLOAT)
-- new line
	-- time,msg
	info.time = {}
	info.time.year = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	info.time.month = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	info.time.day = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	info.time.hour = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	info.time.minutes = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	info.time.seconds = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
-- new line
	info.msg = MEMGETSTR(buffer+offset,MEM_UINT8_128)
	offset = offset + MEMMODESIZE(MEM_UINT8_128)
-- new line
	return info
end
-- new line
function SaveGameScreen( filename )
	-- save screen
	local screen = ScreenToImage()
	ImageToFile( screen, filename )
	ImageFree( screen )
end
-- new line
function amp_save(num,screen)
	-- init
	amp_save_callback()
-- new line
	local game_buffer,gamebuf_size = CreateGameDataBuffer()
	local info_buffer,infobuf_size = CreateGameDataInfoBuffer()
-- new line
	-- save
	local folder = GetFullGameDataFolderPath(num)
	FolderCreate( folder )
	WriteBuffer(game_buffer, folder .. "/DATA.BIN", gamebuf_size)
	WriteBuffer(info_buffer, folder .. "/DATA.SFO", infobuf_size)
	if screen then
		ImageToFile( screen, folder .. "/PIC.TGA" )
	end
-- new line
	-- fini
	PGBufferDelete( game_buffer )
	PGBufferDelete( info_buffer )
end
-- new line
function amp_load(num)
	-- init
	local folder = GetFullGameDataFolderPath(num)
	local game_buffer,gamebuf_size = PGBufferCreate( folder .. "/DATA.BIN")
-- new line
	-- load
	LoadGameData( game_buffer )
-- new line
	-- fini
	PGBufferDelete( game_buffer )
	
	amp_load_callback()
end
-- new line
function amp_deldata(num)
	FolderDelete( GetFullGameDataFolderPath(num) )
end
-- new line
-- new line
function CreatePubGameDataBuffer()
	local buffer,size = PGBufferCreate(1024 * 64)
	local offset = 0
-- new line
	if not pub_value or not pub_event then
		print("pub data is nil.")
		return nil,nil
	end
-- new line
	-- read success flag
	MEMNUMCPY(buffer+offset,65535,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
-- new line
	-- pub_value
	for i=1,TABLE_VALUE_MAX do
		MEMNUMCPY(buffer+offset,pub_value[i],MEM_SINT32)
		offset = offset + MEMMODESIZE(MEM_SINT32)
	end
	-- pub_event
	for i=1,TABLE_EVENT_MAX do
		MEMNUMCPY(buffer+offset,pub_event[i],MEM_UINT8)
		offset = offset + MEMMODESIZE(MEM_UINT8)
	end
	-- line
	for i=1,TABLE_LINE_MAX do
		MEMSTRCPY(buffer+offset,pub_line[i],MEM_UINT8_128)
		offset = offset + MEMMODESIZE(MEM_UINT8_128)
	end
	return buffer,size
end
-- new line
function CreatePubGameDataInfoBuffer()
	local buffer,size = PGBufferCreate(1024 * 8)
	local offset = 0
-- new line
	-- gamename,version,time,msg
	MEMSTRCPY(buffer+offset,GAME_NAME,MEM_UINT8_64)
	offset = offset + MEMMODESIZE(MEM_UINT8_64)
	MEMNUMCPY(buffer+offset,GAME_VERSION,MEM_FLOAT)
	offset = offset + MEMMODESIZE(MEM_FLOAT)
-- new line
	local time = localtime()
	MEMNUMCPY(buffer+offset,time.year,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	MEMNUMCPY(buffer+offset,time.month,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	MEMNUMCPY(buffer+offset,time.day,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	MEMNUMCPY(buffer+offset,time.hour,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	MEMNUMCPY(buffer+offset,time.minutes,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	MEMNUMCPY(buffer+offset,time.seconds,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
-- new line
	return buffer,size
end
-- new line
function LoadPubGameData(buffer)
	local offset = 0
-- new line
	-- test
	local flag = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	if flag~=65535 then print("buffer have invalid data.") return end
-- new line
	-- pub_value
	for i=1,TABLE_VALUE_MAX do
		pub_value[i] = MEMGETNUM(buffer+offset,MEM_SINT32)
		offset = offset + MEMMODESIZE(MEM_SINT32)
	end
	-- pub_event
	for i=1,TABLE_EVENT_MAX do
		pub_event[i] = MEMGETNUM(buffer+offset,MEM_UINT8)
		offset = offset + MEMMODESIZE(MEM_UINT8)
	end
	-- pub_line
	for i=1,TABLE_LINE_MAX do
		pub_line[i] = MEMGETSTR(buffer+offset,MEM_UINT8_128)
		if not pub_line[i] then
			pub_line[i]=""
		end
		offset = offset + MEMMODESIZE(MEM_UINT8_128)
	end
end
-- new line
function LoadPubGameDataInfo(buffer)
	local offset = 0
	local info = {}
-- new line
	if MEMGETSTR(buffer+offset,MEM_UINT8_64)~=GAME_NAME then
		print("this game data can not be read.")
		return nil
	end
	info.gamename = MEMGETSTR(buffer+offset,MEM_UINT8_64)
	offset = offset + MEMMODESIZE(MEM_UINT8_64)
-- new line
	if MEMGETNUM(buffer+offset,MEM_FLOAT)~=1.0 then
		print("this info can not be read.")
		return nil
	end
	info.version = MEMGETNUM(buffer+offset,MEM_FLOAT)
	offset = offset + MEMMODESIZE(MEM_FLOAT)
-- new line
	-- time,msg
	info.time = {}
	info.time.year = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	info.time.month = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	info.time.day = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	info.time.hour = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	info.time.minutes = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
	info.time.seconds = MEMGETNUM(buffer+offset,MEM_SINT32)
	offset = offset + MEMMODESIZE(MEM_SINT32)
-- new line
	return info
end
-- new line
function amp_pubsave()
	-- init
	local game_buffer,gamebuf_size = CreatePubGameDataBuffer()
	local info_buffer,infobuf_size = CreatePubGameDataInfoBuffer()
-- new line
	-- save
	local folder = GetFullPubGameDataFolderPath()
	FolderCreate( folder )
	WriteBuffer(game_buffer, folder .. "/DATA.BIN", gamebuf_size)
	WriteBuffer(info_buffer, folder .. "/DATA.SFO", infobuf_size)
-- new line
	-- fini
	PGBufferDelete( game_buffer )
	PGBufferDelete( info_buffer )
end
-- new line
function amp_pubload()
	-- init
	local folder = GetFullPubGameDataFolderPath()
	if FileIsExist(folder .. "/DATA.SFO") then
		local game_buffer,gamebuf_size = PGBufferCreate( folder .. "/DATA.BIN")
		-- load
		LoadPubGameData( game_buffer )
		-- fini
		PGBufferDelete( game_buffer )
		return true
	end
	return false
end
-- new line
function amp_delpubdata()
	FolderDelete( GetFullPubGameDataFolderPath() )
end
-- new line
--=======================================================
-- new line
function psp_save(bg)
	--init
	amp_save_callback()
	
	local buffer,size = CreateGameDataBuffer()
	local icon0buf,icon0size = PGBufferCreate(am_pack.res,PSP_GAME_ICON0)
	--local icon1buf,icon1size = PGBufferCreate(am_pack.res,PSP_GAME_ICON1)
	local pic1buf,pic1size = PGBufferCreate(am_pack.res,PSP_GAME_PIC1)
	local snd0buf,snd0size = PGBufferCreate(am_pack.res,PSP_GAME_SND0)
	local image = bg
	if not bg then image=0 end
	CallPspSaveSystem(PSP_GAME_SAVEMODE,image,
		GAME_NAME,"0000","DATA.BIN",GAME_SAVELISTSIZE,
		GAME_NAME,"GAME DATA",GAME_MSG,
		buffer,size,
		icon0buf,icon0size,
		pic1buf,pic1size,
		0,0,
		snd0buf,snd0size)
	PGBufferDelete(buffer)
	PGBufferDelete(icon0buf)
	--PGBufferDelete(icon1buf)
	PGBufferDelete(pic1buf)
	PGBufferDelete(snd0buf)
-- new line
	--psp_pubsave(bg)
end
-- new line
function psp_load(bg)
	local buffer,size = PGBufferCreate(1024*64)
	local image = bg
	if not bg then image=0 end
	CallPspSaveSystem(PSP_GAME_LOADMODE,image,
		GAME_NAME,"0000","DATA.BIN",GAME_SAVELISTSIZE,
		GAME_NAME,"GAME DATA",GAME_MSG,
		buffer,size,
		0,0,0,0,0,0,0,0)
	LoadGameData(buffer)
	
	if MEMGETNUM(buffer,MEM_SINT32)==65535 then
		if speak_attribute().msg then
			speakmode(speak_mode_sample)
			if am_ramus then
				speak_load_text(speak_attribute().msg)
				drawskip()
			else
				say(speak_attribute().msg)
			end
		else
			drawevent()
		end
	else
		drawevent()
	end
	
	PGBufferDelete(buffer)
-- new line
	--psp_pubload(bg)
	--fini
	amp_load_callback()
end
-- new line
function psp_pubsave(bg)
	-- init
	local buffer,size = CreatePubGameDataBuffer()
	local icon0buf,icon0size = PGBufferCreate(am_pack.res,PSP_GAME_ICON0)
	local image = bg
	if not bg then image=0 end
-- new line
	-- save
	CallPspSaveSystem(PSP_UTILITY_SAVEDATA_AUTOSAVE,image,
		GAME_NAME.."SYS","0000","DATA.BIN",GAME_SAVELISTSIZE,
		GAME_NAME,"PUBLIC DATA","NO DETAILS",
		buffer,size,
		icon0buf,icon0size,
		0,0,0,0,0,0)
-- new line
	-- fini
	PGBufferDelete( buffer )
	PGBufferDelete( icon0buf )
end
-- new line
function psp_pubload(bg)
	local buffer,size = PGBufferCreate(1024 * 64)
	local image = bg
	if not bg then image=0 end
-- new line
	-- load
	CallPspSaveSystem(PSP_UTILITY_SAVEDATA_AUTOLOAD,image,
		GAME_NAME.."SYS","0000","DATA.BIN",GAME_SAVELISTSIZE,
		GAME_NAME,"PUBLIC DATA","NO DETAILS",
		buffer,size,
		0,0,0,0,0,0,0,0)
	LoadPubGameData(buffer )
-- new line
	-- fini
	PGBufferDelete( buffer )
end