# SPDX-License-Identifier: MPL-2.0
import
  terminal, strutils, net,
  tables, os

import
  illwill, playeruiutils, menuui,

  ../audio/mpv/[
      player
    ],

  ../link/link,
  ../utils/[
      utils
    ],

  ../misc/[like, bell]

when not defined(simple):
  import
    ../audio/mpv/metadata,
    ../ui/[
      scroll,
      animation,
    ]

proc editBadFileHint(config: MenuConfig, extraMsg = "") =
  if extraMsg != "": warn(extraMsg)

  let fileHint =
    if config.currentSubsection != "": config.currentSubsection
    else:                              config.currentSection
  setCursorPos(0, terminalHeight() - 4)

  warn("Failed to access station: " & config.stationName, delayMs = 0, dontRing = true)
  warn("URL: " & config.stationUrl, delayMs = 0, dontRing = true)
  warn("Edit station list in: " & fileHint & ".json", delayMs = 1350)

proc handlePlayerError(msg: string; config: MenuConfig; shouldReturn = false) =
  ## Handles player errors consistently and optionally destroys the player context.
  editBadFileHint(config, msg)
  if shouldReturn:
    return

func currentStatus(state: PlayerState): PlayerStatus =
  if not state.isPaused and not state.isMuted: StatusPlaying
  elif not state.isPaused and state.isMuted: StatusMuted
  elif state.isPaused and not state.isMuted: StatusPaused
  else:                                      StatusPausedMuted

func isValidPlaylistUrl(url: string): bool =
  ## Checks if the URL points to a valid playlist format (.pls or .m3u).
  result = url.endsWith(".pls") or url.endsWith(".m3u")

func getPerCycleSleepTimeFade(vol: int): int =
  const toTime = 500 #ms
  let steps = int vol / 5
  result = int toTime / steps

template tryToPlayAgain(url: string) =
  ctx.allocateJobMpv(url)

proc playStation*(ctx: ptr Handle, config: MenuConfig) =
  ## Plays a radio station and handles user input for playback control.
  #try:
  if config.stationUrl == "":
    editBadFileHint(config)
    return
  #defer: illwillDeinit()
  #illwillInit(false)

  # Validate the link
  try:
    initCheckingStationNotice()
    if not validateLink(config.stationUrl).isValid:
      editBadFileHint(config)
      return
    finishCheckingStationNotice()
  except Exception:
    editBadFileHint(config)
    return

  var state = PlayerState(
    isPaused: false,
    isMuted: false,
    volume: lastVolume
  ) # Use lastVolume
  var isObserving = false
  var coreIdleCounter: uint8
  var playlistFirstPass = false
  var scrollOffset: int = 0
  var lastWidth: int = 0
  var fullTitle: string # Declare fullTitle here
  var finishedLoading = false
  var spinnerState = 0
  var wasTheStreamPlayingForSomeTime: bool
  var streamInterruptRetryCount = 1

  when not defined(simple):
    var metadata = initTable[string, string](8) # Declare metadata here
    var scrollCounter: int = 0
    var animationCounter: int = 0 # Counter for animation updates


  ctx.allocateJobMpv(config.stationUrl)
  var event = ctx.waitEvent()

  when defined(volumeFade):
    ctx.setVolumeMpv(0)

  # Draw the initial player UI
  drawPlayerUI(config.stationName, "Loading...", currentStatusEmoji(currentStatus(state)), state.volume)
  showFooter(isPlayerUI = true)
  when defined(simple):
    fullTitle = fullTitle.truncateMe()

  while true:
    if not state.isPaused:
      event = ctx.waitEvent(mpvEventLoopTimeout)

    # Handle playback events
    if event.eventID in {IDPlaybackRestart} and not isObserving:
      when not defined(simple): ctx.observeMetadata()
      else:                     ctx.observeMediaTitle()
      isObserving = true

    if event.eventID in {IDEventPropertyChange}:
      state.currentSong = ctx.getCurrentMediaTitle()
      if fullTitle != state.currentSong:
        config.appendToHistory()
      fullTitle = state.currentSong # Assign to fullTitle
      updateCurrentSongPlayerUI(state.currentSong)
      setCursorXPos 0
      when not defined(simple):
        globalMetadata = updateMetadataUI(config, ctx, state)

    if event.eventID in {IDFileLoaded}:
      wasTheStreamPlayingForSomeTime = true
      when defined(volumeFade):
        var volumeForFading = 0
        ctx.setVolumeMpv(volumeForFading)
        while true:
          volumeForFading += VolumeStep
          ctx.setVolumeMpv(volumeForFading)
          sleep getPerCycleSleepTimeFade state.volume
          if volumeForFading == state.volume:
            break
      finishedLoading = true
    else:
      if not finishedLoading:
        spinnerState.spinLoadingSpinnerOnce()

    when not defined(simple):
      # Increment the animation counter every 25ms (getKeyWithTimeout interval)
      animationCounter += 1

      # Check if it's time to update the animation (1350ms / 50ms = 54 iterations)
      if animationCounter == 27:
        updateAnimationOnly(currentStatusEmoji(currentStatus(state)), state.currentSong, animationCounter)
        animationCounter = 0 # Reset the counter


        # Scrolling Logic
      if scrollCounter == 11:
        if state.currentSong.checkIfTooLongForUI():
          scrollTextOnce(fullTitle, scrollOffset, termWidth, startingX) # Corrected call
          if fullTitle.len > termWidth - startingX:
            scrollOffset += 1
          scrollCounter = 0
      else:
        scrollCounter += 1

    # Periodic checks
    if coreIdleCounter >= CheckIdleInterval:
      if ctx.isIdle():
        if streamInterruptRetryCount < RetryTimesWhenStreamInterrupt and
          wasTheStreamPlayingForSomeTime:
            tryToPlayAgain(config.stationUrl)
            streamInterruptRetryCount += 1
            setCursorPos 4, 7
            stdout.write "retrying count "
            echo streamInterruptRetryCount
            if streamInterruptRetryCount mod 2 != 0:
              warnBell()
            sleep 500
            cursorUp()
            eraseLine()

        else:
          handlePlayerError("Player core idle", config)
          break

      if event.eventID in {IDEndFile, IDShutdown}:
        if config.stationUrl.isValidPlaylistUrl():
          if playlistFirstPass:
            handlePlayerError("End of playlist reached", config)
            break
          playlistFirstPass = true
        else:
          handlePlayerError("Stream ended", config)
          break
      coreIdleCounter = 0
    inc coreIdleCounter

    # Handle user input
    case getKeyWithTimeout(KeyTimeout):
      of Key.P, Key.Space:
        state.isPaused = not state.isPaused
        ctx.pause(state.isPaused)
        updatePlayMutedStatePlayerUI(currentStatusEmoji(currentStatus(state)))

      of Key.M:
        state.isMuted = not state.isMuted
        ctx.mute(state.isMuted)
        updatePlayMutedStatePlayerUI(currentStatusEmoji(currentStatus(state)))

      of Key.Slash, Key.Plus:
        incVolume()
        updateVolumePlayerUI(state.volume)

      of Key.Asterisk, Key.Minus:
        decVolume()
        updateVolumePlayerUI(state.volume)

      of Key.R, Key.BackSpace:
        if not state.isPaused:
          ctx.cleanupPlayer()

        when defined(volumeFade):
          var volumeForFading = state.volume
          while true:
            volumeForFading -= VolumeStep
            ctx.setVolumeMpv(volumeForFading)
            sleep getPerCycleSleepTimeFade state.volume
            if volumeForFading == 0:
              break

        ctx.stopCurrentJob()
        when defined(volumeFade):
          ctx.setVolumeMpv(state.volume)

        break

      of Key.Q, Key.Escape, CtrlQ:
        ctx.cleanupPlayer()
        ctx.exit(state.isPaused)

      of Key.L: # New key binding for "Like" action
        if state.currentSong != "":
          appendToLikedSongs(config)
        else:
          warn("song field is currently empty")

      of Key.None:
        continue

      of Key.Up, Key.Down, Key.Left, Key.Right:
        when defined(android):
          continue
        else: showInvalidChoice()

      else:
        showInvalidChoice()

  if state.isPaused: #reset states for globalCtx if user returned with P/M
    ctx.resume()
  if state.isMuted:
    ctx.unmute()

#except Exception:
  #  let fileHint = if config.currentSubsection != "": config.currentSubsection else: config.currentSection
  #  warn("An error occurred during playback. Edit the station list in: " & fileHint & ".json")
  #  cleanupPlayer(mpvCtx)
  #  return
