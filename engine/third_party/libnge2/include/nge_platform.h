/**
 * @file  nge_platform.h
 * @author Kun Wang <ifreedom.cn@gmail.com>
 * @date 2011/08/07 09:11:47
 *
 *  Copyright  2011  Kun Wang <ifreedom.cn@gmail.com>
 */

#ifndef _NGE_PLATFORM_H
#define _NGE_PLATFORM_H

#if defined _PSP
#define NGE_PSP

#elif defined __APPLE__
/*
 PGM-Mac: macOS 上 <TargetConditionals.h> 会把 TARGET_OS_IPHONE 定义成 0,
 而 defined TARGET_OS_IPHONE 判断的是有没有定义而非取值, 于是 macOS 会被
 误判成 iOS(NGE_IPHONE), 进而用上 GLES 头和 iOS 专属分支。
 这里改成先看 __APPLE__, 再用 TargetConditionals 的真值区分 iOS 与 macOS。
*/
#include <TargetConditionals.h>
#if defined TARGET_OS_IPHONE && TARGET_OS_IPHONE
#define NGE_IPHONE
#else
#define NGE_MAC
#endif
#elif defined __APPLE__
/* PGM-Mac: on macOS <TargetConditionals.h> defines TARGET_OS_IPHONE as 0.
   'defined TARGET_OS_IPHONE' tests for definition, not value, so macOS
   was misdetected as NGE_IPHONE and pulled in the GLES/iOS code paths.
   Check __APPLE__ first, then use the real TargetConditionals value. */
#include <TargetConditionals.h>
#if defined TARGET_OS_IPHONE && TARGET_OS_IPHONE
#define NGE_IPHONE
#else
#define NGE_MAC
#endif
#elif defined TARGET_OS_IPHONE || defined TARGET_IPHONE_SIMULATOR
#define NGE_IPHONE

#elif defined __ANDROID_API__ || defined ANDROID
#define NGE_ANDROID

#elif defined _WIN32
#define NGE_WIN


/*
  put linux to last one, because some other platform
  is build on top of linux, like android
*/
#elif defined __linux__
#define NGE_LINUX

#endif

#endif /* _NGE_PLATFORM_H */
