-- //////////////
-- Ò¡¸Ë¿ØÖÆbg
-- by kong
-- //////////
-- new line
AnalogScene=class(PGSceneBase)
-- new line
function AnalogScene:ctor()
	self.dx = 0
	self.dy = 0
	self.analogdx = 127
	self.analogdy = 127
	self.move_speed = 3
	self.bg = {}
	self.x = 0
	self.y = 0
end
-- new line
function AnalogScene:init()
	for i=1,AM_SCENE_BG_MAX do
		self.bg[i] = {}
		if am_scene.bg[i].image_p[am_scene.bg[i].image_index+1] then
			self.bg[i].dx = am_scene.bg[i].dx
			self.bg[i].dy = am_scene.bg[i].dy
			self.bg[i].w = ImageGetW(am_scene.bg[i].image_p[am_scene.bg[i].image_index+1])
			self.bg[i].h = ImageGetH(am_scene.bg[i].image_p[am_scene.bg[i].image_index+1])
		elseif not am_scene.bg[i].image_p[am_scene.bg[i].image_index+1] then
			self.bg[i].dx = 0
			self.bg[i].dy = 0
			self.bg[i].w = PGM_ORI_SCREEN_WIDTH
			self.bg[i].h = PGM_ORI_SCREEN_HEIGHT
		end
	end
	self.sw = self.bg[1].w - PGM_ORI_SCREEN_WIDTH
	self.sh = self.bg[1].h - PGM_ORI_SCREEN_HEIGHT
	--print("1ºÅ±³¾°×ø±ê£º",self.bg[1].dx ..",".. self.bg[1].dy)
	--print("1ºÅ±³¾°´óÐ¡£º",self.bg[1].w .."*".. self.bg[1].h)
	
	self.x = self.bg[2].dx - self.bg[1].dx
	self.y = self.bg[2].dy - self.bg[1].dy
end
-- new line
-- new line
function AnalogScene:fini()
-- new line
end
-- new line
function AnalogScene:update()
	if self.analogdx < 64 then
		self.bg[1].dx = self.bg[1].dx + self.move_speed
	elseif self.analogdx > 192 then
		self.bg[1].dx = self.bg[1].dx - self.move_speed
	end
	if self.analogdy < 64 then
		self.bg[1].dy = self.bg[1].dy + self.move_speed
	elseif self.analogdy > 192 then
		self.bg[1].dy = self.bg[1].dy - self.move_speed
	end
-- new line
	if self.bg[1].dx < -self.sw then
		self.bg[1].dx = -self.sw
	elseif self.bg[1].dx > 0 then
		self.bg[1].dx = 0
	end
	if self.bg[1].dy < -self.sh then
		self.bg[1].dy = -self.sh
	elseif self.bg[1].dy > 0 then
		self.bg[1].dy = 0
	end
-- new line
	bgxy(1,self.bg[1].dx,self.bg[1].dy)
	bgxy(2,self.bg[1].dx+self.x,self.bg[1].dy+self.y)
	am_scene_update()
end
-- new line
function AnalogScene:render()
	am_scene_render()
end
-- new line
function AnalogScene:KeyDown(key)
	if key==PSP_BUTTON_CIRCLE then
		self:KeyDown(PSP_BUTTON_CROSS)
	elseif key==PSP_BUTTON_CROSS then
		drawevent()
	end	
end
-- new line
function AnalogScene:AnalogProc(x,y)
	self.analogdx = x
	self.analogdy = y
end
-- new line
function SpeakScene:AnalogProc(x,y)
	if x < 64 or x > 192 or 
		y < 64 or y > 192 then
		drawanalog()
	end
end
-- new line
function AnalogScene:TouchEnded(id,dx,dy,prev_dx,prev_dy,tapCount)
	self:KeyDown(PSP_BUTTON_CROSS)
end
-- new line
--===============================
-- new line
function drawanalog()
	if scene then scene:fini() end
	scene = AnalogScene.new()
	scene:init()
	collectgarbage("collect")
end