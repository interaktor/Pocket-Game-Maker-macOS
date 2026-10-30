-- new line
TextQuad=class(ClassBase)
-- new line
function TextQuad:ctor()
	self.dx=0
	self.dy=0
	self.mode=-1	-- ×ó¶ÔÆë-1¡¢¾ÓÖÐ0¡¢ÓÒ¶ÔÆë1
	self.img=false
	self.w=0
	self.h=0
	self.scale=1
	self.mask=0
end
-- new line
function TextQuad:destory()
	if self.img then
		ImageFree(self.img)
		self.img=false
	end
end
-- new line
function TextQuad:update()
	
end
-- new line
function TextQuad:render()
	if not self.img then
		return	
	end
-- new line
	if self.mode==-1 then
		DrawImageMask(self.img,0,0,self.w,self.h,self.dx,self.dy,self.w*self.scale,self.h*self.scale,self.mask)
	elseif self.mode==1 then
		DrawImageMask(self.img,0,0,self.w,self.h,self.dx-self.w*self.scale,self.dy,self.w*self.scale,self.h*self.scale,self.mask)
	else
		DrawImageMask(self.img,0,0,self.w,self.h,self.dx-self.w*self.scale*0.5,self.dy-self.h*self.scale*0.5,self.w*self.scale,self.h*self.scale,self.mask)
	end
end
-- new line
function TextQuad:ImageCreate(w,h,disp)
	self.img=ImageCreate(w,h,disp)
	self.w=w
	self.h=h
	if disp==IMG_8888 then
		self.mask=MAKE_RGBA_8888(255,255,255,255)
	elseif disp==IMG_4444 then
		self.mask=MAKE_RGBA_4444(255,255,255,255)
	elseif disp==IMG_5551 then
		self.mask=MAKE_RGBA_5551(255,255,255,255)
	elseif disp==IMG_565 then
		self.mask=MAKE_RGBA_565(255,255,255,255)
	end
end
-- new line
function TextQuad:DrawStr(pf,str,x,y)
	FontDraw(pf,self.img,str,x,y)
end
-- new line
function TextQuad:SetScale(s)
	self.scale=s
end
-- new line
function TextQuad:SetXY(x,y)
	self.dx=x
	self.dy=y
end
-- new line
function TextQuad:SetWH(w,h)
	self.w=w
	self.h=h
end
-- new line
function TextQuad:SetMode(mode)
	self.mode=mode
end
-- new line
function TextQuad:SetMask(mask)
	self.mask=mask
end