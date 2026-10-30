/* 自动生成，勿手改：由 scripts/gen_api_list.py 生成 */
/* 来源：PGM指令表v0.7.txt（150 个接口）+ Lua 脚本扫描（55 个文件） */

#ifndef PGM_API_NAMES_H
#define PGM_API_NAMES_H

/* 接口函数名（文档优先，扫描补充） */
static const char *PGM_API_NAMES[] = {
	"ShowFps", "SetClip", "ResetClip", "Drawline",
	"DrawRect", "DrawCircle", "FillRect", "ImageToScreen",
	"DrawImageMask", "DrawImage", "RenderQuad", "ScreenToImage",
	"ScreenShot", "SetScreenColor", "SetTexBlend", "ResetTexBlend",
	"MAKE_RGBA_565", "MAKE_RGBA_5551", "MAKE_RGBA_4444", "MAKE_RGBA_8888",
	"BeginScene", "EndScene", "ImageLoad", "ImageCreate",
	"ImageFree", "ImageGetW", "ImageGetH", "ImageSetMask",
	"ImageSetCentre", "ImageClone", "ImageClear", "ImageFlipH",
	"ImageFlipV", "ImageScale", "ImageConv", "ImageToImage",
	"ImageToFile", "SoundCreate", "SoundDelete", "SoundLoad",
	"SoundUnload", "SoundPlay", "SoundPause", "SoundResume",
	"SoundEos", "SoundVolume", "SoundRewind", "MovieCreate",
	"MovieDelete", "MoviePlay", "MovieEos", "PackCreate",
	"PackDelete", "FontCreate", "FontCreateBuf", "FontDelete",
	"FontDraw", "FontSetColor", "FontResize", "EffectFadeInCreate",
	"EffectFadeOutCreate", "EffectShakeCreate", "EffectTransCreate", "EffectDelete",
	"EffectDrawImage", "EffectGetState", "InputProc", "ControlReset",
	"TouchInit", "ControlInit", "PGSetState", "PGGetState",
	"PGDoFile", "PGBufferCreate", "PGBufferDelete", "WriteBuffer",
	"MEMSET", "MEMCPY", "MEMSTRCPY", "MEMNUMCPY",
	"MEMMODESIZE", "MEMGETSTR", "MEMGETNUM", "localtime",
	"sysparam", "FolderCreate", "FolderDelete", "FileIsExist",
	"CallPspSaveSystem", "PGMShutDown", "EScriptCreate", "EScriptDelete",
	"EScriptDoline", "EScriptNext", "EScriptBack", "EScriptJump",
	"EScriptPrint", "EScriptCurrLine", "EScriptCurrCode", "EScriptLineSize",
	"EScriptName", "EScriptIsEnd", "TimerCreate", "TimerDelete",
	"TimerStart", "TimerPause", "TimerIsStart", "TimerIsPause",
	"TimerGetTicks", "TimerStop", "TimerUnPause", "CachePGDoFile",
	"CacheImageLoad", "CacheEScriptCreate", "CacheMapLoad", "CacheClear",
	"CacheReject", "CacheResize", "CacheIsExist", "CacheMsg",
	"MapCreate", "MapDelete", "MapRender", "MapSpirit",
	"MapTiles", "MapColorMask", "MapUnload", "MapLoad",
	"MapCoord", "MapTileSize", "MapClip", "MapGetWH",
	"MapLayerCounts", "MapGetRef", "DialogCreate", "DialogDelete",
	"FontTextSize", "PGDoString", "ParticleCreate", "ParticleDelete",
	"ParticleFire", "ParticleMoveTo", "ParticleRender", "ParticleSetDeploy",
	"ParticleSetTexture", "ParticleStop", "ParticleUpdate", "SomeEffectUpdate",
	"bgmfade", "gmcode", "gmdata", "include",
	"waittime",
};

/* 常量/宏名 */
static const char *PGM_API_MACROS[] = {
	"IMG_8888", "IMG_4444", "IMG_5551", "IMG_565",
	"BLEND_ZERO", "BLEND_ONE", "BLEND_SRC_COLOR", "BLEND_ONE_MINUS_SRC_COLOR",
	"BLEND_SRC_ALPHA", "BLEND_ONE_MINUS_SRC_ALPHA", "BLEND_DST_ALPHA", "BLEND_ONE_MINUS_DST_ALPHA",
	"BLEND_DST_COLOR", "BLEND_ONE_MINUS_DST_COLOR", "BLEND_SRC_ALPHA_SATURATE", "EFFECT_STOP",
	"EFFECT_PLAY", "EFFECT_INIT", "PSP_BUTTON_UP", "PSP_BUTTON_DOWN",
	"PSP_BUTTON_LEFT", "PSP_BUTTON_RIGHT", "PSP_BUTTON_TRIANGLE", "PSP_BUTTON_CIRCLE",
	"PSP_BUTTON_CROSS", "PSP_BUTTON_SQUARE", "PSP_BUTTON_LEFT_TRIGGER", "PSP_BUTTON_RIGHT_TRIGGER",
	"PSP_BUTTON_SELECT", "PSP_BUTTON_START", "MOUSE_LBUTTON_DOWN", "MOUSE_LBUTTON_UP",
	"MOUSE_RBUTTON_DOWN", "MOUSE_RBUTTON_UP", "PGM_QUIT", "PGM_SCRIPT",
	"PGM_INIT", "PGM_LOOP", "PGM_FINI", "PGD_UNKNOWN",
	"PGD_SINT8", "PGD_UINT8", "PGD_CODE", "PGD_NEWLINE",
	"PGD_TABLE", "PGD_COLOR", "PGD_DCOLOR", "PGD_DELAY",
	"PGD_WAITKEY",
};

#endif /* PGM_API_NAMES_H */
