/***************************************************************************
 *            nge_audio_mac.m
 *
 *  macOS 音频后端（CoreAudio 之上的 AVFoundation）。
 *
 *  实现 libnge2 的 audio_play_t 虚表，供 PGM 的 bgm / voice / sound 使用。
 *
 *  为什么用 AVAudioPlayer 而不是 AudioQueue + 自己解码：
 *    * 它直接支持 mp3 / wav / aac / caf，省掉一个解码器依赖
 *    * 它的 play/pause/stop/currentTime/duration/volume 与虚表几乎一一对应
 *    * BGM/语音是完整文件播放，不是流式，正合 AVAudioPlayer 的用法
 *
 *  已知限制：**不支持 OGG**（AVFoundation 不解 OGG），CreateOggPlayer 返回 NULL。
 *  PGM 游戏默认用 mp3，所以影响有限；要支持 OGG 需要接 stb_vorbis 之类的解码器。
 ***************************************************************************/

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#include <string.h>
#include <stdlib.h>

#include "nge_platform.h"

#if defined NGE_MAC

#include "audio_interface.h"
#include "nge_debug_log.h"

typedef struct mac_audio {
	audio_play_t base;      /* 必须是第一个成员，便于强转 */
	AVAudioPlayer *player;
	int volume;             /* 0..255 */
	int looping;
} mac_audio;

static mac_audio *to_ma(struct audio_play *This)
{
	return (mac_audio *)This;
}

/* PGM 的 volume 取值可能是 0..100 或 0..255，统一归一化到 0..1 */
static float norm_volume(int v)
{
	if (v <= 0)
		return 0.0f;
	if (v > 100)
		return (float)v / 255.0f;
	return (float)v / 100.0f;
}

static int ma_load(struct audio_play *This, const char *filename)
{
	mac_audio *a = to_ma(This);
	NSString *path;
	NSURL *url;
	NSError *err = nil;

	if (!filename || !filename[0])
		return -1;

	@autoreleasepool {
		path = [NSString stringWithUTF8String:filename];
		url = [NSURL fileURLWithPath:path];
		a->player = [[AVAudioPlayer alloc] initWithContentsOfURL:url
														  error:&err];
		if (!a->player) {
			nge_log("mac audio: 打不开 %s (%s)\n", filename,
					err ? [[err localizedDescription] UTF8String] : "?");
			return -1;
		}
		[a->player prepareToPlay];
		[a->player setVolume:norm_volume(a->volume)];
		nge_log("mac audio: loaded %s (%.1fs)\n", filename,
				[a->player duration]);
	}
	return 0;
}

static int ma_load_buf(struct audio_play *This, const char *buf, int size)
{
	mac_audio *a = to_ma(This);
	NSData *data;
	NSError *err = nil;

	if (!buf || size <= 0)
		return -1;

	@autoreleasepool {
		data = [NSData dataWithBytes:buf length:(NSUInteger)size];
		a->player = [[AVAudioPlayer alloc] initWithData:data error:&err];
		if (!a->player) {
			nge_log("mac audio: 内存数据解析失败 (%s)\n",
					err ? [[err localizedDescription] UTF8String] : "?");
			return -1;
		}
		[a->player prepareToPlay];
		[a->player setVolume:norm_volume(a->volume)];
	}
	return 0;
}

static int ma_load_fp(struct audio_play *This, int handle, char closed_by_me)
{
	(void)This;
	(void)handle;
	(void)closed_by_me;
	return -1;   /* PGM 不用这条路径 */
}

static int ma_play(struct audio_play *This, int times, int free_when_stop)
{
	mac_audio *a = to_ma(This);
	(void)free_when_stop;

	if (!a->player)
		return -1;
	@autoreleasepool {
		/* times <= 0 或 == -1 视为无限循环 */
		a->looping = (times < 0);
		[a->player setNumberOfLoops:a->looping ? -1 : (times > 0 ? times - 1 : 0)];
		[a->player setCurrentTime:0];
		[a->player play];
	}
	return 0;
}

static int ma_playstop(struct audio_play *This)
{
	mac_audio *a = to_ma(This);
	(void)a;
	/* 循环类调用（BGM）在 PGM 里用 play(LOOP,-1) 走 ma_play，
	   这里保持"立即开始播放一次"的语义 */
	return ma_play(This, 1, 1);
}

static void ma_pause(struct audio_play *This)
{
	mac_audio *a = to_ma(This);
	if (a->player)
		[a->player pause];
}

static int ma_stop(struct audio_play *This)
{
	mac_audio *a = to_ma(This);
	if (!a->player)
		return -1;
	@autoreleasepool {
		[a->player stop];
		[a->player setCurrentTime:0];
	}
	return 0;
}

static void ma_resume(struct audio_play *This)
{
	mac_audio *a = to_ma(This);
	if (a->player)
		[a->player play];
}

static int ma_volume(struct audio_play *This, int volume)
{
	mac_audio *a = to_ma(This);
	a->volume = volume;
	if (a->player)
		[a->player setVolume:norm_volume(volume)];
	return 0;
}

static void ma_rewind(struct audio_play *This)
{
	mac_audio *a = to_ma(This);
	if (a->player)
		[a->player setCurrentTime:0];
}

/* flag: 0 = 绝对定位（ms），其它 = 相对当前位置 */
static void ma_seek(struct audio_play *This, int ms, int flag)
{
	mac_audio *a = to_ma(This);
	double t;

	if (!a->player)
		return;
	@autoreleasepool {
		t = (double)ms / 1000.0;
		if (flag != 0)
			t += [a->player currentTime];
		if (t < 0)
			t = 0;
		if (t <= [a->player duration])
			[a->player setCurrentTime:t];
	}
}

static int ma_iseof(struct audio_play *This)
{
	mac_audio *a = to_ma(This);
	int eof = 0;

	if (!a->player)
		return 1;
	@autoreleasepool {
		eof = (![a->player isPlaying] &&
			   [a->player currentTime] + 0.05 >= [a->player duration]);
	}
	return eof;
}

static int ma_ispaused(struct audio_play *This)
{
	mac_audio *a = to_ma(This);
	if (!a->player)
		return 1;
	return ![a->player isPlaying];
}

static int ma_destroy(struct audio_play *This)
{
	mac_audio *a = to_ma(This);

	if (!a)
		return 0;
	@autoreleasepool {
		if (a->player) {
			[a->player stop];
			[a->player release];
			a->player = nil;
		}
	}
	free(a);
	return 0;
}

/* ------------------------------------------------------------------ */

static audio_play_p make_player(void)
{
	mac_audio *a = (mac_audio *)calloc(1, sizeof(mac_audio));

	if (!a)
		return NULL;

	a->base.load     = ma_load;
	a->base.load_fp  = ma_load_fp;
	a->base.load_buf = ma_load_buf;
	a->base.play     = ma_play;
	a->base.playstop = ma_playstop;
	a->base.pause    = ma_pause;
	a->base.stop     = ma_stop;
	a->base.resume   = ma_resume;
	a->base.volume   = ma_volume;
	a->base.rewind   = ma_rewind;
	a->base.seek     = ma_seek;
	a->base.iseof    = ma_iseof;
	a->base.ispaused = ma_ispaused;
	a->base.destroy  = ma_destroy;
	a->volume = 100;

	return (audio_play_p)&a->base;
}

void CoolAudioDefaultInit(void)
{
	@autoreleasepool {
		/* AVAudioSession 是 iOS 的概念，macOS 上不需要配置 */
	}
	nge_log("CoolAudio: macOS 后端已就绪（AVAudioPlayer）\n");
}

void CoolAudioDefaultFini(void)
{
}

audio_play_p CreateMp3Player(void) { return make_player(); }
audio_play_p CreateWavPlayer(void) { return make_player(); }

/* AVFoundation 不解 OGG，返回 NULL；上层已经把它当"音频不可用"处理 */
audio_play_p CreateOggPlayer(void) { return NULL; }

#endif /* NGE_MAC */
