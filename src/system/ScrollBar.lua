-- ////////////////
-- 横向滚动条(基类)
-- by kong
-- //////////
-- new line
--[[
【使用方法】
⑴scene内的创建&使用方法：（样板）
①ctor()：
	-- ScrollBar.new(底图,滑块,总刻度（可缺省）)
	self.scroll = ScrollBar.new("bottom.png","slider.png")
	-- 以下参数均可缺省
	self.scroll.dx = 20		--横坐标
	self.scroll.dy = 20		--纵坐标
	self.scroll.index = 0		--当前刻度
	self.scroll.temp = 9		--总刻度
	self.scroll.alpha = 255		--透明度
	self.scroll.ispress =false	--状态：是否选中
②fini()：
	self.scroll:fini()
	self.scroll=nil
③update()：
	self.scroll:update()
④render()：
	if self.scroll then
		self.scroll:render()
	end
⑵操纵方式：（样板）
①给self.scroll.index赋值控制当前刻度；
②self.scroll.ispress控制是否选中的状态；
③self.scroll.alpha控制透明度；
]]--
-- new line
--=========================
ScrollBar=class(PGBase)
-- new line
function ScrollBar:ctor(...)
	self.bottom = CacheImageLoad(am_pack.res,arg[1],IMG_4444)
	self.dx = 0	--外接：滚动条横坐标
	self.dy = 0	--外接：滚动条纵坐标
	self.slider = CacheImageLoad(am_pack.res,arg[2],IMG_4444)
	self.x1 = self.dx
	self.y1 = self.dy + 0.5*(ImageGetH(self.bottom)-ImageGetH(self.slider)/2)
	self.buf = self.x1
-- new line
	self.length = ImageGetW(self.bottom) - ImageGetW(self.slider)
	self.index = 0	--外接：当前刻度
	self.temp = 9	--可外接：总刻度
	if arg[3] then
		self.temp = arg[3]
	end
	
	self.ispress = false	--外接
	self.w = ImageGetW(self.slider)
	self.h = ImageGetH(self.slider) / 2
	self.alpha = 255	--外接
end
-- new line
function ScrollBar:init()
	
end
-- new line
function ScrollBar:fini()
	if self.bottom then
		ImageFree(self.bottom)
		self.bottom = nil
	end
	if self.slider then
		ImageFree(self.slider)
		self.slider = nil
	end
end
-- new line
function ScrollBar:update()
	self.x1 = self.dx
	self.y1 = self.dy + 0.5*(ImageGetH(self.bottom)-ImageGetH(self.slider)/2)
	self.buf = self.x1 + ( (self.index-1)/(self.temp-1) )*self.length
	if self.bottom then
		ImageSetMask(self.bottom,MAKE_RGBA_4444(255,255,255,self.alpha))
	end
	if self.slider then
		ImageSetMask(self.slider,MAKE_RGBA_4444(255,255,255,self.alpha))
	end
end
-- new line
function ScrollBar:render()
	if self.bottom then
		ImageToScreen(self.bottom,self.dx,self.dy)
	end
	if self.slider then
		if not self.ispress then
			DrawImage(self.slider,0,0,self.w,self.h,self.buf,self.y1,self.w,self.h)
		else
			DrawImage(self.slider,0,self.h,self.w,self.h,self.buf,self.y1,self.w,self.h)
		end
	end
end
-- new line