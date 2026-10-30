/***************************************************************************
 *            nge_audio_mac.c
 *
 *  macOS audio backend for libnge2 / PGM-Mac.
 *
 *  STATUS: P1 placeholder.
 *
 *  nge.c calls CoolAudioDefaultInit()/Fini() unconditionally, and the PGM
 *  host layer later needs Create{Mp3,Wav,Ogg}Player(). This file satisfies
 *  the linkage so the graphics milestone (P1) can be verified on its own.
 *
 *  The real CoreAudio/AVAudioEngine implementation (MP3 via AudioFile +
 *  ExtAudioFile, OGG via a vendored stb_vorbis) lands in milestone P4.
 *  Until then every player constructor returns NULL, which the upper layers
 *  already treat as "audio unavailable".
 ***************************************************************************/

#include "nge_platform.h"

#if defined NGE_MAC

#include "audio_interface.h"
#include "nge_debug_log.h"

void CoolAudioDefaultInit(void)
{
	nge_log("CoolAudio: macOS backend not implemented yet (P1 placeholder).\n");
}

void CoolAudioDefaultFini(void)
{
}

audio_play_p CreateMp3Player(void)
{
	return NULL;
}

audio_play_p CreateWavPlayer(void)
{
	return NULL;
}

audio_play_p CreateOggPlayer(void)
{
	return NULL;
}

#endif /* NGE_MAC */
