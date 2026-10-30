-- new line
ColorButton=class(ClassBase)
-- new line
function ColorButton:ctor()
	self.img=false
	self.dx=0
	self.dy=0
	self.ispress=false
-- new line
	self.w=0
	self.h=0
	
	self.xd=0
	self.yd=0
end
-- new line
function ColorButton:destory()
	if self.img then
		ImageFree(self.img)
		self.img=false
	end
end
-- new line
function ColorButton:loadImage(filename)
	if self.img then
		ImageFree(self.img)
	end
	self.img=ImageLoad(am_pack.res,filename,IMG_4444)
	self.w=ImageGetW(self.img)
	self.h=ImageGetH(self.img)
end
-- new line
function ColorButton:render(img1,img2,xd,yd)
	if not self.ispress then
		if img1 then
			ImageToScreen(img1,self.dx,self.dy)
		end
	else
		if img2 then
			if xd and yd then
				ImageToScreen(img2,self.dx+xd,self.dy+yd)
			else
				ImageToScreen(img2,self.dx,self.dy)
			end
		end
	end
	if self.img then
		ImageToScreen(self.img,self.dx+self.xd,self.dy+self.yd)
	end
end
-- new line
function ColorButton:testrect(x,y)
	if x > self.dx and x < self.dx+self.w and
		y > self.dy and y < self.dy+self.h then
		return true
	end
	return false
end
-- new line
function ColorButton:press_down()
	self.ispress=true
end
-- new line
function ColorButton:press_up()
	self.ispress=false
end