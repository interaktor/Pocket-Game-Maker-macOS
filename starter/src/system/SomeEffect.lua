-- //////////////
-- 附加效果器
-- by kong
-- //////////
-- new line
-- =======================================
-- 使用说明
--[[
此脚本适用于PGMv0.5(AMT)以上任意版本。
指令：chara_down(...)、chara_up(...)、layer_move(layer_type,index,x1,y1,x2,y2,time)
-- new line
1、chara_down(...)
名字：下蹲效果
形参：无限个(范围：fg；编号：1~32)
例子：chara_down(1)
解释：1号立绘下蹲。
-- new line
2、chara_up(...)
名字：上跳效果
形参：无限个(范围：fg；编号：1~32)
例子：chara_up(1)
解释：1号立绘上跳。
-- new line
3、layer_move(layer_type,index,x1,y1,x2,y2,time)
名字：图层移动
形参：图层类型("bg"或"fg"),编号,初始横坐标,初始纵坐标,目标横坐标,目标纵坐标,效果时间
例子：layer_move("fg",1,0,0,100,0,100)
解释：1号立绘从坐标(0,0)直线移动到坐标(100,0)，效果时间100毫秒。
-- new line
]]--
-- ============以下内容请勿修改===========
Vector=class()
-- new line
function Vector:ctor()
	self.Array={}
	self.Size=0
end
-- new line
function Vector:destroy()
	self:clear()
end
-- new line
function Vector:push_back(obj)
	self.Size=self.Size+1
	self.Array[self.Size]=obj
end
-- new line
function Vector:pop_back()
	local v=self:TopIndex()
	if self.Size>0 then
		self.Array[self.Size]=false
		self.Size=self.Size-1
	end
	return v
end
-- new line
function Vector:clear()
	self.Array={}
	self.Size=0
end
-- new line
function Vector:size()
	return self.Size
end
-- new line
function Vector:Index(i)
	return self.Array[i]
end
-- new line
function Vector:TopIndex()
	return self.Array[self.Size]
end
-- new line
function Vector:swap(i1,i2)
	local temp=self.Array[i1]
	self.Array[i1]=self.Array[i2]
	self.Array[i2]=temp
end
-- new line
function Vector:BringTop(i)
	local index=i
	local size=self:size()
	while index < size do
		self:swap(index,index+1)
		index=index+1
	end
end
-- new line
-- ==================================================================
-- 效果基类
local EffectBase=class()
-- new line
function EffectBase:ctor()
-- new line
end
-- new line
function EffectBase:destroy()
-- new line
end
-- new line
function EffectBase:IsEnd()
	return true
end
-- new line
function EffectBase:update(dt)
	
end
-- new line
-- ==================================================================
-- 实际效果类,统统继承效果基类EffectBase
-- new line
-- 让角色上移
local MoveCharaUp=class(EffectBase)
-- new line
function MoveCharaUp:ctor()
	self.lasttick=0
	self.index=0		-- fg index
	self.finish=false
	self.mdx=0			-- 默认坐标
	self.mdy=0
	
	self.dx=0			-- 相对坐标
	self.dy=0
	
	self.dyV=8
end
-- new line
function MoveCharaUp:destroy()
-- new line
end
-- new line
function MoveCharaUp:update(dt)
	if self.finish then
		return
	end
	self.lasttick=self.lasttick+dt
	if self.lasttick >= 50 then
		self.lasttick=self.lasttick%50
		self.dy=self.dy+self.dyV
		if self.dy > 20 then
			self.dyV = -self.dyV
		elseif self.dy <= 0 then
			self.dy=0
			self.finish=true
		end
		fgxy(self.index,self.mdx+self.dx,self.mdy-self.dy)
	end
end
-- new line
function MoveCharaUp:IsEnd()
	return self.finish
end
-- new line
function MoveCharaUp:Init(index,dx,dy)
	self.index=index
	self.mdx=dx
	self.mdy=dy
	self.dx=0
	self.dy=0
end
-- new line
-- new line
-- 让角色下移
local MoveCharaDown=class(EffectBase)
-- new line
function MoveCharaDown:ctor()
	self.lasttick=0
	self.index=0		-- fg index
	self.finish=false
	self.mdx=0			-- 默认坐标
	self.mdy=0
	
	self.dx=0			-- 相对坐标
	self.dy=0
	
	self.dyV=5
end
-- new line
function MoveCharaDown:destroy()
-- new line
end
-- new line
function MoveCharaDown:update(dt)
	if self.finish then
		return
	end
	self.lasttick=self.lasttick+dt
	if self.lasttick >= 60 then
		self.lasttick=self.lasttick%60
		self.dy=self.dy+self.dyV
		if self.dy > 30 then
			self.dyV = -self.dyV
		elseif self.dy <= 0 then
			self.dy=0
			self.finish=true
		end
		fgxy(self.index,self.mdx+self.dx,self.mdy+self.dy)
	end
end
-- new line
function MoveCharaDown:IsEnd()
	return self.finish
end
-- new line
function MoveCharaDown:Init(index,dx,dy)
	self.index=index
	self.mdx=dx
	self.mdy=dy
	self.dx=0
	self.dy=0
end
-- new line
-- new line
-- 图层移动
local LayerMove=class(EffectBase)
-- new line
function LayerMove:ctor()
	self.lasttick = 0
	self.finish = false
	self.type = "bg"
	self.index = 1
	self.dx = 0
	self.dy = 0
	self.time = 0
	self.x1 = 0
	self.y1 = 0
	self.x2 = 0
	self.y2 = 0
end
-- new line
function LayerMove:destroy()
-- new line
end
-- new line
function LayerMove:IsEnd()
	return self.finish
end
-- new line
function LayerMove:update(dt)
	if self.finish then
		return
	end
	self.lasttick = self.lasttick + dt
	if self.lasttick > 1 then
		self.lasttick = self.lasttick % 1
		self.dx = self.dx + (self.x2-self.x1)*(15/self.time)
		self.dy = self.dy + (self.y2-self.y1)*(15/self.time)
		if self.x2-self.x1 >= 0 then
			if self.dx >= self.x2 then
				self.dx = self.x2
			end
		else
			if self.dx <= self.x2 then
				self.dx = self.x2
			end
		end
		if self.y2-self.y1 >= 0 then
			if self.dy >= self.y2 then
				self.dy = self.y2
			end
		else
			if self.dy <= self.y2 then
				self.dy = self.y2
			end
		end
		if self.type=="bg" then
			bgxy(self.index,self.dx,self.dy)
		elseif self.type=="fg" then
			fgxy(self.index,self.dx,self.dy)
		end
		if self.dx==self.x2 and self.dy==self.y2 then
			self.finish = true
		end
	end
end
-- new line
function LayerMove:Init(layer_type,index,x1,y1,x2,y2,time)
	self.finish = false
	self.type = layer_type
	self.index = index
	self.x1 = x1
	self.y1 = y1
	self.x2 = x2
	self.y2 = y2
	self.time = time
	self.dx = self.x1
	self.dy = self.y1
end
-- new line
-- 调节音量
local BgmVolumeFade=class(EffectBase)
-- new line
function BgmVolumeFade:ctor()
	self.volume=0
	self.maxVolume=0
	self.lasttick=0
	self.finish=false
	self.stepV=0
end
-- new line
function BgmVolumeFade:destroy()
-- new line
end
-- new line
function BgmVolumeFade:IsEnd()
	return self.finish
end
-- new line
function BgmVolumeFade:update(dt)
	if self.finish then
		return
	end
	self.lasttick = self.lasttick + dt
	if self.lasttick > 80 then
		self.lasttick = self.lasttick % 80
		self.volume = self.volume + self.stepV
		if self.stepV < 0 then
			if self.volume <= self.maxVolume then
				self.volume = self.maxVolume
				self.finish = true
			end
		elseif self.stepV > 0 then
			if self.volume >= self.maxVolume then
				self.volume = self.maxVolume
				self.finish = true
			end
		end
		mp3volume(1,self.volume)
	end
end
-- new line
function BgmVolumeFade:Init(volume,maxVolume,stepV)
	self.volume = volume
	self.maxVolume = math.abs(maxVolume)
	self.stepV = stepV
	self.finish = false
	if stepV < 0 then
		-- 音量下降的情况
		self.volume = mp3volume(1)
		self.stepV = math.abs((maxVolume-self.volume)/(maxVolume-volume)) * stepV
	end
	mp3volume(1,self.volume)
end
-- new line
local _mp3volume=mp3volume
function mp3volume(...)
	if table.getn(arg)==1 then
		return am_sound.mp3[1].vol
	else
		_mp3volume(arg[1],arg[2])
	end
end
-- new line
-- ==================================================================
-- 效果列表
local SomeEffect=Vector.new()
local Timer=TimerCreate()
local Lasttick=0
TimerStart(Timer)
-- new line
function SomeEffectUpdate()
	local dt=TimerGetTicks(Timer)-Lasttick
	for i=1,SomeEffect:size() do
		local effect=SomeEffect:Index(i)
		effect:update(dt)
		if effect:IsEnd() then
			SomeEffect:BringTop(i)
			SomeEffect:pop_back()
			effect:destroy()
			break
		end
	end
	Lasttick=TimerGetTicks(Timer)
end
-- new line
local function SomeEffectAdd(effect)
	SomeEffect:push_back(effect)
end
-- new line
-- new line
-- ========================
-- ev指令
function chara_down(...)
	for i=1,table.getn(arg) do
		local effect=MoveCharaDown.new()
		local index=arg[i]
		effect:Init(index,am_scene.fg[index].dx,am_scene.fg[index].dy)
		SomeEffectAdd(effect)
	end
end
-- new line
function chara_up(...)
	for i=1,table.getn(arg) do
		local effect=MoveCharaUp.new()
		local index=arg[i]
		effect:Init(index,am_scene.fg[index].dx,am_scene.fg[index].dy)
		SomeEffectAdd(effect)
	end
end
-- new line
function layer_move(layer_type,index,x1,y1,x2,y2,time)
	local effect=LayerMove.new()
	effect:Init(layer_type,index,x1,y1,x2,y2,time)
	SomeEffectAdd(effect)
end
-- new line
function bgmfade(volume,maxVolume,time)
	local effect=BgmVolumeFade.new()
	effect:Init(volume,maxVolume,(maxVolume-volume)/(time/80))
	SomeEffectAdd(effect)
end
-- new line