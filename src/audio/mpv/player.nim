# SPDX-License-Identifier: MPL-2.0
# player.nim

import libmpv, ../../utils/utilstypes
export cE # Export the error-checking macro for external use

type
  PlayerError* = object of CatchableError # Custom error type for player-related issues
  MediaInfo* = object # Structure to hold media player state
    title*: string    # Current media title
    isIdle*: bool     # Whether the player is idle
    volume*: int      # Current volume level
    isMuted*: bool    # Whether the player is muted
    isPaused*: bool   # Whether the player is paused

const
  VolumeStep* = 5  # Step size for volume adjustments
  MinVolume* = 0   # Minimum allowed volume
  MaxVolume* = 150 # Maximum allowed volume

using ctx: ptr Handle

func validateVolume(volume: int): int =
  ## Ensures the volume stays within valid bounds (0-150).
  result = max(MinVolume, min(MaxVolume, volume))

proc setAllyOptionsToMpv*(ctx) =
  var netTimeout = 5.0
  cE ctx.setOption("network-timeout", fmtFloat64, netTimeout.addr)

  var replayGain = 6.0
  cE ctx.setOption("replaygain-preamp", fmtFloat64, replayGain.addr)

  let optionList = [
    ("audio-display", "no"),
    ("vid", "no"),
    ("config", "no"),
    ("vo", "null"),
    ("audio-stream-silence", "yes"),
    ("gapless-audio", "weak"),
    ("audio-fallback-to-null", "no"),

    ("demuxer-lavf-o", "reconnect=1,reconnect_streamed=1,reconnect_delay_max=5"),
    ("user-agent", "pnimrp/0.1"),

    ("ytdl", "no"),
    ("demuxer-thread", "yes"),

    ("audio-normalize-downmix", "yes"),
    ("volume-max", "150"),

    ("terminal", "yes"),
    ("really-quiet", "yes"),
    ("osd-level", "0"),

    ("input-default-bindings", "no"),
    ("input-vo-keyboard", "no"),
    ("input-media-keys", "no"),

    ("demuxer-max-bytes", "2097152"), #2MB #thanks to github.com/florianjacob
    ("demuxer-max-back-bytes", "2097152") #see https://github.com/mpv-player/mpv/issues/5359
  ]

  for option in optionList:
    cE ctx.setOptionString(
      cstring(option[0]),
      cstring(option[1])
    )

proc initGlobalMpv*(): ptr Handle =
  try:
    result = create()
    result.setAllyOptionsToMpv()
    cE result.initialize()

  except Exception as e:
    raise newException(PlayerError, "MPV initialization failed: " & e.msg)

proc allocateJobMpv*(ctx; source: string) =
  let fileArgs = allocCStringArray(["loadfile", source])
  try:
    cE ctx.cmd(fileArgs)
  finally:
    deallocCStringArray(fileArgs)

proc stopCurrentJob*(ctx) =
  let cmdArgs = allocCStringArray(["stop"])
  #discard mpvCtx.waitEvent(1)
  try:
    cE ctx.cmd(cmdArgs)
  finally:
    deallocCStringArray(cmdArgs)

proc pause*(ctx; shouldPause: bool) {.raises: [PlayerError].} =
  ## Toggles the pause state of the player.
  ##
  ## Args:
  ##   ctx: Player handle
  ##   shouldPause: True to pause, False to play
  try:
    var pauseState = cint(shouldPause)
    cE ctx.setProperty("pause", fmtFlag, addr pauseState)
  except Exception as e:
    raise newException(PlayerError, "Failed to set pause state: " & e.msg)

template resume*(ctx) = ctx.pause(shouldPause = false)

proc mute*(ctx; shouldMute: bool) {.raises: [PlayerError].} =
  ## Toggles the mute state of the player.
  ##
  ## Args:
  ##   ctx: Player handle
  ##   shouldMute: True to mute, False to unmute
  try:
    var muteState = cint(shouldMute)
    cE ctx.setProperty("mute", fmtFlag, addr muteState)
  except Exception as e:
    raise newException(PlayerError, "Failed to set mute state: " & e.msg)

template unmute*(ctx) = ctx.mute(shouldMute = false)

proc observeMediaTitle*(ctx) {.raises: [PlayerError].} =
  ## Starts observing changes to the media title.
  ##
  ## Args:
  ##   ctx: Player handle
  try:
    cE ctx.observeProperty(0, "media-title", fmtNone)
  except Exception as e:
    raise newException(PlayerError, "Failed to observe media title: " & e.msg)

proc observeMetadata*(ctx) {.raises: [PlayerError].} =
  try:
    cE ctx.observeProperty(0, "metadata", fmtNone)
  except Exception as e:
    raise newException(PlayerError, "Failed to observe metadata: " & e.msg)

proc isIdle*(ctx): bool {.raises: [PlayerError].} =
  ## Checks if the player is currently idle.
  ##
  ## Args:
  ##   ctx: Player handle
  ##
  ## Returns:
  ##   True if the player is idle, False otherwise
  try:
    var idleState: cint
    cE ctx.getProperty("idle-active", fmtFlag, addr idleState)
    result = bool(idleState)
  except Exception as e:
    raise newException(PlayerError, "Failed to check idle state: " & e.msg)

proc getCurrentMediaTitle*(ctx; appState: AppState = nil): string {.raises: [].} =
  ## Retrieves the current media title.
  ##
  ## Args:
  ##   ctx: Player handle
  ##   appState: Optional AppState to store title
  ##
  ## Returns:
  ##   Current media title or an empty string if none
  try:
    var title: cstring
    cE ctx.getProperty("media-title", fmtString, addr title)

    # Convert the cstring to a Nim string immediately to ensure GC safety
    result = if title != nil: $title else: ""
    if appState != nil:
      appState.fullMediaTitle = result

    # Free the cstring allocated by libmpv
    if title != nil:
      libmpv.free(title)

  except Exception: #as e:
    #raise newException(PlayerError, "Failed to get media title: " & e.msg)
    discard

proc getMediaInfo*(ctx): MediaInfo {.raises: [PlayerError].} =
  ## Retrieves comprehensive information about the media player's current state.
  ##
  ## Args:
  ##   ctx: Player handle
  ##
  ## Returns:
  ##   MediaInfo object containing the current player state
  try:
    var
      volume: int
      muteState: cint
      pauseState: cint

    cE ctx.getProperty("volume", fmtInt64, addr volume)
    cE ctx.getProperty("mute", fmtFlag, addr muteState)
    cE ctx.getProperty("pause", fmtFlag, addr pauseState)

    result = MediaInfo(
      title: getCurrentMediaTitle(ctx),
      isIdle: isIdle(ctx),
      volume: volume,
      isMuted: bool(muteState),
      isPaused: bool(pauseState)
    )

  except Exception as e:
    raise newException(PlayerError, "Failed to get media info: " & e.msg)

proc setVolumeOfBellRelativeToMainCtx*(ctx; lastVolume = 100) =
  #set 1.5 times the last vol
  var newVolume = cstring $(float(lastVolume) * 1.5)
  cE ctx.setOptionString("volume", newVolume)
    #some platforms will might cmplain about type error and cause `mpv API error:`
    #by having the cost of string conversions, we are offloading the dirty work
    #to libmpv, which is very robust

template volume*(appState: AppState, inc = true) =
  if inc: state.volume = min(state.volume + VolumeStep, MaxVolume)
  else:   state.volume = max(state.volume - VolumeStep, MinVolume)
  appState.lastVolume = state.volume
  var vol64 = int64(state.volume)
  cE ctx.setProperty("volume", fmtInt64, addr vol64)

func getFileFormat*(ctx): string =
  # Query the `file-format` property
  var format = getPropertyString(ctx, "file-format")

  if format != nil:
    result = $format  # Convert cstring to Nim string
    free(format)  # Free the allocated cstring
  else:
    result = "unknown" # Fallback if the property is not available

template incVolume*(appState: AppState) = volume(appState, inc = true)
template decVolume*(appState: AppState) = volume(appState, inc = false)

export
  Handle, create, initialize,
  destroy, terminateDestroy,
  Event, EventID, waitEvent,
  setProperty

proc setVolumeMpv*(ctx; vol: int) =
  cE ctx.setOptionString("volume", cstring $vol)

proc deinitPlayer*(ctx) =
  ctx.terminateDestroy()
