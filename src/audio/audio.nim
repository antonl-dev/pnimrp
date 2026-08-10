const isVlc =
  static:
    defined(vlc)

import os

import vlc/helper
import mpv/player

type
  audioHandle* = object
    mpvHandle: ptr Handle
    vlcHandle: ref libvlcHandle
    event:     ptr Event

using audioHandle: ref audioHandle

proc initAudio*(): ref audiohandle =
  result = new audiohandle
  when isVlc: result.vlcHandle = initNewCtx()
  else:       result.mpvHandle = initGlobalMpv()

proc deinitAudio*(audioHandle) =
  when isVlc: audioHandle.vlcHandle.deinitPlayer()
  else:       audioHandle.mpvHandle.deinitPlayer()

proc setAllyOptions*(audioHandle) =
  when isVlc: audioHandle.vlcHandle.setAllyOptionsVlc()
  else:       audioHandle.mpvHandle.setAllyOptionsToMpv()

proc allocateJob*(audioHandle; url: string) =
  when isVlc: audioHandle.vlcHandle.allocateJobVlc(url)
  else:       audioHandle.mpvHandle.allocateJobMpv(url)

proc waitEvent*(audioHandle; timeout: float = 0) =
  when isVlc:
    sleep int timeout
  else:
    audioHandle.event = audioHandle.mpvHandle.waitEvent(cdouble timeout)

proc resourceIsOver*(audioHandle): bool =
  when isVlc:
    not audioHandle.vlcHandle.mediaPlayerIsPlaying()
  else:
    audioHandle.event.eventID in {IDEndFile}

proc setVolumeOfBellRelativeToMainCtx*(audioHandle) =
  when isVlc: audioHandle.vlcHandle.setVolumeOfBellRelativeToMainCtx()
  else:       audioHandle.mpvHandle.setVolumeOfBellRelativeToMainCtx()

proc playPlayer*(audioHandle) =
  when isVlc: audioHandle.vlcHandle.playPlayer()
  else:       player.resume(audioHandle.mpvHandle)

proc waitForCoreToInit*(audioHandle) =
  when isVlc:
    while true: #wait for init
      sleep 10
      if audioHandle.vlchandle.mediaPlayerIsPlaying(): break
      else: continue
  else:
    sleep 10

proc muteVolume*(audioHandle) =
  when isVlc: audioHandle.vlcHandle.muteVolume()
  else:       audioHandle.mpvHandle.mute(shouldMute = true)

proc unmuteVolume*(audioHandle) =
  when isVlc: audioHandle.vlcHandle.unmuteVolume()
  else:       audioHandle.mpvHandle.unmute()

proc setVolume(audioHandle; vol: int) =
  when isVlc: audioHandle.vlcHandle.setVolume(vol)
  else:       audioHandle.mpvHandle.setVolumeMpv(vol)


#example for using helper
when isMainModule:
  import os

  proc example =
    let url = "https://listen.181fm.com/181-jammin_128k.mp3"

    var handle = initAudio()

    defer: handle.deinitAudio()

    handle.setAllyOptions()
    handle.allocateJob(url)
    handle.playPlayer()

    handle.waitForCoreToInit()
    #handle.setVolume(100)
    #var isMuted = false
    while true: #poll loop
      #handle.setVolume(100)
      handle.waitEvent(10)
      if handle.resourceIsOver():
        break

      #sleep 500

      #if not isMuted: handle.muteVolume()
      #else:           handle.unmuteVolume()
      #handle.unmuteVolume()
      #isMuted = not isMuted

      continue

  example()
