# SPDX-License-Identifier: MPL-2.0
const isVlc* =
    static:
        defined(vlc)

import os, tables, strutils

when isVlc:
    import vlc/helper
    import vlc/libvlc/libvlc
else:
    import mpv/player
    import mpv/libmpv

import ../utils/utilstypes
import ../ui/hidestderr

export isVlc, AudioEventKind, AudioContext, audioHandle

when isVlc:
    type
        VlcAudioContext* = ref object of AudioContext
            vlcHandle*: ref libvlcHandle
            hasPlayed*: bool
            lastSituation*: int
            lastTitle*: string
else:
    type
        MpvAudioContext* = ref object of AudioContext
            mpvHandle*: ptr Handle
            event*: ptr Event
            isObserving*: bool

proc initAudio*(shouldHideStderr: bool = true): AudioContext =
    when isVlc:
        let vlc = VlcAudioContext(
            vlcHandle: initNewCtx(),
            hasPlayed: false,
            lastTitle: "",
            lastSituation: 0
        )
        vlc.vlcHandle.setAllyOptionsVlc()
        result = vlc
    else:
        let mpv = MpvAudioContext(
            isObserving: false
        )
        when not defined(simple):
            if shouldHideStderr:
                var sState: StderrState
                sState.initSuppressStderr()
                mpv.mpvHandle = initGlobalMpv()
                sState.restoreStderr()
            else:
                mpv.mpvHandle = initGlobalMpv()
        else:
            mpv.mpvHandle = initGlobalMpv()
        result = mpv

proc deinitAudio*(ctx: AudioContext) =
    if ctx == nil: return
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            vlc.vlcHandle.deinitPlayer()
            vlc.vlcHandle = nil
    else:
        let mpv = MpvAudioContext(ctx)
        if mpv.mpvHandle != nil:
            mpv.mpvHandle.terminateDestroy()
            mpv.mpvHandle = nil

proc setAllyOptions*(ctx: AudioContext) =
    if ctx == nil: return
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            vlc.vlcHandle.setAllyOptionsVlc()
    else:
        let mpv = MpvAudioContext(ctx)
        if mpv.mpvHandle != nil:
            mpv.mpvHandle.setAllyOptionsToMpv()

proc allocateJob*(ctx: AudioContext, url: string) =
    if ctx == nil: return
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            vlc.hasPlayed = false
            vlc.lastTitle = ""
            vlc.vlcHandle.allocateJobVlc(url)
            vlc.vlcHandle.playPlayer()
    else:
        let mpv = MpvAudioContext(ctx)
        if mpv.mpvHandle != nil:
            mpv.isObserving = false
            mpv.mpvHandle.allocateJobMpv(url)

proc playPlayer*(ctx: AudioContext) =
    if ctx == nil: return
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            vlc.vlcHandle.playPlayer()
    else:
        let mpv = MpvAudioContext(ctx)
        if mpv.mpvHandle != nil:
            player.resume(mpv.mpvHandle)

proc resume*(ctx: AudioContext) =
    ctx.playPlayer()

proc pausePlayer*(ctx: AudioContext) =
    if ctx == nil: return
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            vlc.vlcHandle.pausePlayer()
    else:
        let mpv = MpvAudioContext(ctx)
        if mpv.mpvHandle != nil:
            mpv.mpvHandle.pause(true)

proc pause*(ctx: AudioContext, shouldPause: bool = true) =
    if shouldPause: ctx.pausePlayer()
    else: ctx.resume()

proc mute*(ctx: AudioContext, shouldMute: bool = true) =
    if ctx == nil: return
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            if shouldMute: vlc.vlcHandle.muteVolume()
            else: vlc.vlcHandle.unmuteVolume()
    else:
        let mpv = MpvAudioContext(ctx)
        if mpv.mpvHandle != nil:
            mpv.mpvHandle.mute(shouldMute)

proc unmute*(ctx: AudioContext) =
    ctx.mute(false)

proc muteVolume*(ctx: AudioContext) =
    ctx.mute(true)

proc unmuteVolume*(ctx: AudioContext) =
    ctx.mute(false)

proc setVolume*(ctx: AudioContext, vol: int) =
    if ctx == nil: return
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            vlc.vlcHandle.setVolume(vol)
    else:
        let mpv = MpvAudioContext(ctx)
        if mpv.mpvHandle != nil:
            mpv.mpvHandle.setVolumeMpv(vol)

proc stopCurrentJob*(ctx: AudioContext) =
    if ctx == nil: return
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            vlc.vlcHandle.stopPlayer()
    else:
        let mpv = MpvAudioContext(ctx)
        if mpv.mpvHandle != nil:
            mpv.mpvHandle.stopCurrentJob()

proc cleanupPlayer*(ctx: AudioContext) =
    ctx.stopCurrentJob()

proc isIdle*(ctx: AudioContext): bool =
    if ctx == nil: return true
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            return vlc.vlcHandle.isIdle()
        return true
    else:
        let mpv = MpvAudioContext(ctx)
        if mpv.mpvHandle != nil:
            return mpv.mpvHandle.isIdle()
        return true

proc getCurrentMediaTitle*(ctx: AudioContext, appState: AppState = nil): string =
    if ctx == nil: return ""
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            result = vlc.vlcHandle.getCurrentMediaTitleVlc()
            if result == "" or result == "nil":
                let artist = if vlc.vlcHandle.mediaDscptr != nil: $libvlc.mediaGetMeta(vlc.vlcHandle.mediaDscptr, libvlc.metaArtist) else: ""
                let title = if vlc.vlcHandle.mediaDscptr != nil: $libvlc.mediaGetMeta(vlc.vlcHandle.mediaDscptr, libvlc.metaTitle) else: ""
                if artist != "" and artist != "nil" and title != "" and title != "nil":
                    result = artist & " - " & title
                elif title != "" and title != "nil":
                    result = title
                else:
                    result = ""
            if appState != nil:
                appState.fullMediaTitle = result
    else:
        let mpv = MpvAudioContext(ctx)
        if mpv.mpvHandle != nil:
            result = mpv.mpvHandle.getCurrentMediaTitle(appState)

proc pollAudioEvent*(ctx: AudioContext, timeoutSec: float = mpvEventLoopTimeout): AudioEventKind =
    if ctx == nil: return aevNone
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle == nil: return aevNone
        sleep(max(1, int(timeoutSec * 1000)))
        if vlc.vlcHandle.mediaPlayerCtx == nil: return aevNone

        let st = libvlc.mediaPlayerGetState(vlc.vlcHandle.mediaPlayerCtx)
        vlc.lastSituation = ord(st)

        if not vlc.hasPlayed and (st in [libvlc.Playing, libvlc.Buffering] or vlc.vlcHandle.mediaPlayerIsPlaying()):
            vlc.hasPlayed = true
            return aevFileLoaded

        let currentTitle = ctx.getCurrentMediaTitle()
        if currentTitle != "" and currentTitle != vlc.lastTitle:
            vlc.lastTitle = currentTitle
            return aevTitleChanged

        if vlc.hasPlayed and st in [libvlc.Ended, libvlc.Error, libvlc.Stopped]:
            return aevEndFile

        return aevNone
    else:
        let mpv = MpvAudioContext(ctx)
        if mpv.mpvHandle == nil: return aevNone
        mpv.event = mpv.mpvHandle.waitEvent(cdouble timeoutSec)
        if mpv.event.eventID in {IDPlaybackRestart} and not mpv.isObserving:
            when not defined(simple): mpv.mpvHandle.observeMetadata()
            else: mpv.mpvHandle.observeMediaTitle()
            mpv.isObserving = true
            return aevNone
        elif mpv.event.eventID in {IDEventPropertyChange}:
            return aevTitleChanged
        elif mpv.event.eventID in {IDFileLoaded}:
            return aevFileLoaded
        elif mpv.event.eventID in {IDEndFile, IDShutdown}:
            return aevEndFile
        else:
            return aevNone

proc waitEvent*(ctx: AudioContext, timeout: float = 0) =
    discard ctx.pollAudioEvent(timeout)

proc resourceIsOver*(ctx: AudioContext): bool =
    if ctx == nil: return true
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            return not vlc.vlcHandle.mediaPlayerIsPlaying()
        return true
    else:
        let mpv = MpvAudioContext(ctx)
        return mpv.event != nil and mpv.event.eventID in {IDEndFile}

proc setVolumeOfBellRelativeToMainCtx*(ctx: AudioContext) =
    if ctx == nil: return
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            vlc.vlcHandle.setVolumeOfBellRelativeToMainCtx()
    else:
        let mpv = MpvAudioContext(ctx)
        if mpv.mpvHandle != nil:
            mpv.mpvHandle.setVolumeOfBellRelativeToMainCtx()

proc waitForCoreToInit*(ctx: AudioContext) =
    if ctx == nil: return
    when isVlc:
        let vlc = VlcAudioContext(ctx)
        if vlc.vlcHandle != nil:
            var waitIters = 0
            while waitIters < 100:
                sleep 10
                if vlc.vlcHandle.mediaPlayerIsPlaying(): break
                waitIters += 1
    else:
        sleep 10
