-- new line
HgePar=class(ClassBase)
-- new line
function HgePar:ctor()
	self.par=ParticleCreate()
	self.img=false
end
-- new line
function HgePar:destory()
	if self.par then
		ParticleDelete(self.par)
	end
	if self.img then
		ImageFree(self.img)	
	end
end
-- new line
function HgePar:loadPsi(filename)
	local buffer,size=PGBufferCreate(filename)
	ParticleSetDeploy(self.par,buffer,size)
	PGBufferDelete(buffer)
end
-- new line
function HgePar:loadSprite(filename,x,y,w,h)
	self.img=ImageLoad(filename,IMG_8888)
	ParticleSetTexture(self.par,self.img,x,y,w,h)
end
-- new line
function HgePar:loadPsiFrom(pk,filename)
	local buffer,size=PGBufferCreate(pk,filename)
	ParticleSetDeploy(self.par,buffer,size)
	PGBufferDelete(buffer)
end
-- new line
function HgePar:loadSpriteFrom(pk,filename,x,y,w,h)
	self.img=ImageLoad(pk,filename,IMG_8888)
	ParticleSetTexture(self.par,self.img,x,y,w,h)
end
-- new line
function HgePar:update()
	ParticleUpdate(self.par)
end
-- new line
function HgePar:render()
	ParticleRender(self.par)
end
-- new line
function HgePar:fire(dx,dy)
	ParticleFire(self.par,dx,dy)
end
-- new line
function HgePar:stop(bool)
	ParticleStop(self.par,bool)
end
-- new line
function HgePar:moveto(x,y,bool)
	ParticleMoveTo(self.par,x,y,bool)
end