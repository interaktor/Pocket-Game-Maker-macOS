-- new line
WaitScene=class(PGSceneBase)
-- new line
function WaitScene:ctor(time)
	self.ispress = false
	self.key = PSP_BUTTON_CIRCLE
	self.time = time
	self.timer = TimerCreate()			-- 创建计时器
	TimerStart(self.timer)                        	-- 让计时器开始计时
	self.lasttick = TimerGetTicks(self.timer)	-- 获取计时器时间
end
-- new line
function WaitScene:update()
	am_scene_update()
	if self.time then
	        if TimerGetTicks(self.timer)-self.lasttick >= self.time then
                	self.lasttick = TimerGetTicks(self.timer)
 			self.ispress = true
		end
	end
end
-- new line
function WaitScene:render()
	am_scene_render()
end
-- new line
function WaitScene:idle()
	if self.ispress or 
		speakmode()==speak_mode_skip then
		drawevent()
	end
end
-- new line
function WaitScene:KeyDown(key)
	if key==self.key then
		self.ispress = true
		playfile(DEFAULT_SOUND,4)
	end
end
-- new line
function WaitScene:TouchBegan(id,dx,dy,prev_dx,prev_dy,tapCount)
	self.ispress = true
end
-- new line
-- ================================================
-- new line
function waittime(time)
	if scene then scene:fini() end
	scene = WaitScene.new(time)
	scene:init()
	collectgarbage("collect")
end