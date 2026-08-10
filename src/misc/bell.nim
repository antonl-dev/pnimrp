# SPDX-License-Identifier: MPL-2.0
import
  os, terminal,

  ../audio/mpv/[
    player,
    libmpv
  ],
  ../audio/audio

template milSecToSec(ms: int): float = ms / 1000

const
  KeyTimeout = 25
  mpvEventLoopTimeout = KeyTimeout.milSecToSec()

proc warnBell* =
  #dont interrupt main player
  var handle = initAudio()

  try:
    let assetsDir = getAppDir() / "assets"
    let bellPath = assetsDir / "config" / "sounds" / "bell.ogg"

    handle.setAllyOptions()
    handle.allocateJob("file://" & absolutePath bellPath)
    handle.playPlayer()
    handle.waitForCoreToInit()

    while true:
      handle.waitEvent(mpvEventLoopTimeout)
      if handle.resourceIsOver():
        break

  except Exception as e:
    stderr.writeLine "Warning bell error: ", e.msg
  finally:
    handle.deinitAudio()
    hideCursor() #somehow we need this ._.
