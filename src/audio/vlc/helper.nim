import strutils
import libvlc/[libvlc, base]

type VlcError* = object of CatchableError

type
    libvlcStateInfo = object
        playerCurrentSituation*: libvlc.state
        currentVol*: cint
        volumeBeforeMuted*: int

type libvlcHandle* = object
    ctx*: ptr instance
    mediaDscptr*: ptr media
    mediaPlayerCtx*: ptr mediaPlayer
    stateInfo: libvlcStateInfo

proc checkError*(status: cint, msg: cstring) =
    if status == -1:
        raise newException(VlcError, $msg)

template cE*(status: cint, msg: cstring) =
    checkError(status, msg)

using Handle: ref libvlcHandle

proc playPlayer*(Handle) =
    let msg: cstring = "fail to play player"
    cE(libvlc.mediaPlayerPlay(Handle.mediaPlayerCtx), msg)

template resume*(Handle) =
    playPlayer(Handle)

proc pausePlayer*(Handle) =
    mediaPlayerPause(Handle.mediaPlayerCtx)

proc setVolume*(Handle; volume: int) =
    if Handle == nil: return
    let clamped = clamp(volume, 0, 200)
    Handle.stateInfo.currentVol = cint(clamped)
    if Handle.mediaPlayerCtx != nil:
        discard audioSetVolume(Handle.mediaPlayerCtx, cint(clamped))

template volumeChange*(Handle; inc: bool) =
    when inc: currentVol += 5
    else: currentVol -= 5

    Handle.setVolume(currentVol)

proc muteVolume*(Handle) =
    if Handle == nil: return
    let current = if Handle.mediaPlayerCtx != nil:
        int(libvlc.audioGetVolume(Handle.mediaPlayerCtx))
    else:
        int(Handle.stateInfo.currentVol)
    Handle.stateInfo.volumeBeforeMuted = if current > 0: current else: int(Handle.stateInfo.currentVol)
    setVolume(Handle, 0)

proc unmuteVolume*(Handle) =
    if Handle == nil: return
    var targetVol = Handle.stateInfo.volumeBeforeMuted
    if targetVol <= 0:
        targetVol = 100
    Handle.setVolume(targetVol)
    Handle.stateInfo.volumeBeforeMuted = -1

template volumeUp*(Handle) =
    volumeChange(Handle, true)

template volumeDown*(Handle) =
    volumeChange(Handle, false)

proc setVolumeOfBellRelativeToMainCtx*(Handle) =
    var relativeVol = int(1.5 * float(Handle.stateInfo.currentVol))
    setVolume(Handle, relativeVol)

proc stopPlayer*(Handle) =
    if Handle != nil and Handle.mediaPlayerCtx != nil:
        libvlc.mediaPlayerStop(Handle.mediaPlayerCtx)

proc isIdle*(Handle): bool =
    Handle.stateInfo.playerCurrentSituation = libvlc.mediaPlayerGetState(
            Handle.mediaPlayerCtx)
    if Handle.stateInfo.playerCurrentSituation in
      [libvlc.Ended, libvlc.Error, libvlc.Stopped]:
        return true
    else:
        return false

#proc observeMediaTitle(Handle)

proc getCurrentMediaTitleVlc*(Handle): string =
    if Handle == nil or Handle.mediaDscptr == nil: return ""
    let c = libvlc.mediaGetMeta(Handle.mediaDscptr, libvlc.metaNowPlaying)
    if c != nil:
        let s = ($c).strip()
        if s != "" and s != "nil":
            return s
    return ""

proc initNewCtx*(): ref libvlchandle =
    result = new libvlcHandle
    var ctx = libvlc.new(0, nil)
    if ctx.isNil:
        let err = libvlc.errmsg()
        let detail = (
            if err != nil: $err
            else: "No VLC plugins found. Please install 'vlc-plugin-base' (e.g. sudo apt install vlc-plugin-base)."
        )
        raise newException(VlcError, "Failed to create libvlc instance: " & detail)

    result.ctx = ctx
    return result

proc deinitPlayer*(Handle) =
    if Handle == nil: return
    if Handle.mediaPlayerCtx != nil:
        libvlc.mediaPlayerRelease(Handle.mediaPlayerCtx)
        Handle.mediaPlayerCtx = nil
    if Handle.mediaDscptr != nil:
        libvlc.mediaRelease(Handle.mediaDscptr)
        Handle.mediaDscptr = nil
    if Handle.ctx != nil:
        libvlc.release(Handle.ctx)
        Handle.ctx = nil

proc allocateJobVlc*(Handle; url: string) =
    if Handle.mediaPlayerCtx != nil:
        libvlc.mediaPlayerStop(Handle.mediaPlayerCtx)
        libvlc.mediaPlayerRelease(Handle.mediaPlayerCtx)
        Handle.mediaPlayerCtx = nil
    if Handle.mediaDscptr != nil:
        libvlc.mediaRelease(Handle.mediaDscptr)
        Handle.mediaDscptr = nil
    Handle.mediaDscptr = libvlc.mediaNewLocation(Handle.ctx, cstring(url))
    Handle.mediaPlayerCtx = libvlc.mediaPlayerNewFromMedia(Handle.mediaDscptr)
    if Handle.stateInfo.currentVol > 0:
        discard audioSetVolume(Handle.mediaPlayerCtx, Handle.stateInfo.currentVol)

proc setAllyOptionsVlc*(Handle) =
    libvlc.setUserAgent(Handle.ctx, "pnimrp/0.1", "pnimrp/0.1")
    libvlc.setAppId(Handle.ctx, "pnimrp", "0.1", "")

proc mediaPlayerIsPlaying*(Handle): bool =
    bool libvlc.mediaPlayerIsPlaying(Handle.mediaPlayerCtx)




#example for using helper
when isMainModule:
    import os

    proc example =
        let url = "https://listen.181fm.com/181-jammin_128k.mp3"

        var handle = initNewCtx()
        defer: handle.deinitPlayer()

        handle.setAllyOptionsVlc()
        handle.allocateJobVlc(url)
        handle.playPlayer()

        while true: #wait for init
            sleep 10
            if handle.mediaPlayerIsPlaying(): break
            else: continue

        var isMuted = false
        while handle.mediaPlayerIsPlaying(): #poll loop
            sleep 500

            if not isMuted: handle.muteVolume()
            else: handle.unmuteVolume()
            isMuted = not isMuted

            continue

    example()
