# SPDX-License-Identifier: MPL-2.0
import
    terminal, strutils, net,
    tables, os

import
    ../vendor/illwill, playeruiutils, menuui,

    ../audio/audio,
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

    let fileHint = (
      if config.currentSubsection != "": config.currentSubsection
        else: config.currentSection
    )
    setCursorPos(0, terminalHeight() - 4)

    warn("Failed to access station: " & config.stationName, delayMs = 0,
            dontRing = true)
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
    else: StatusPausedMuted

func isValidPlaylistUrl(url: string): bool =
    ## Checks if the URL points to a valid playlist format (.pls or .m3u).
    result = url.endsWith(".pls") or url.endsWith(".m3u")

func getPerCycleSleepTimeFade(vol: int): int =
    const toTime = 500 #ms
    let steps = int vol / 5
    result = int toTime / steps

template tryToPlayAgain(url: string) =
    ctx.allocateJob(url)

proc playStation*(appState: AppState, config: MenuConfig) =
    ## Plays a radio station and handles user input for playback control.
    let ctx = config.ctx
    if config.stationUrl == "":
        editBadFileHint(config)
        return

    # Validate the link
    try:
        initCheckingStationNotice()
        if not validateLink(config.stationUrl).isValid:
            editBadFileHint(config)
            return
        finishCheckingStationNotice(appState)
    except Exception:
        editBadFileHint(config)
        return

    var state = PlayerState(
      isPaused: false,
      isMuted: false,
      volume: appState.lastVolume
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


    ctx.allocateJob(config.stationUrl)

    when defined(volumeFade):
        ctx.setVolume(0)

    # Draw the initial player UI
    appState.drawPlayerUI(config.stationName, "Loading...", currentStatusEmoji(
            currentStatus(state), appState.terminalSupportsEmoji), state.volume)
    appState.showFooter(isPlayerUI = true)
    when defined(simple):
        fullTitle = fullTitle.truncateMe(appState.termWidth)

    while true:
        var audioEvent = aevNone
        if not state.isPaused:
            audioEvent = ctx.pollAudioEvent(mpvEventLoopTimeout)

        if audioEvent == aevTitleChanged:
            state.currentSong = ctx.getCurrentMediaTitle(appState)
            if fullTitle != state.currentSong:
                appState.appendToHistory(config)
            fullTitle = state.currentSong # Assign to fullTitle
            appState.fullMediaTitle = fullTitle
            appState.updateCurrentSongPlayerUI(state.currentSong)
            setCursorXPos 0
            when not defined(simple):
                appState.globalMetadata = updateMetadataUI(config, ctx, state)

        if audioEvent == aevFileLoaded:
            wasTheStreamPlayingForSomeTime = true
            when defined(volumeFade):
                var volumeForFading = 0
                ctx.setVolume(volumeForFading)
                while volumeForFading < state.volume:
                    volumeForFading = min(volumeForFading + VolumeStep, state.volume)
                    ctx.setVolume(volumeForFading)
                    sleep getPerCycleSleepTimeFade state.volume
            finishedLoading = true
        else:
            if not finishedLoading:
                spinnerState.spinLoadingSpinnerOnce(appState)

        when not defined(simple):
            # Increment the animation counter every 25ms (getKeyWithTimeout interval)
            animationCounter += 1

            # Check if it's time to update the animation (1350ms / 50ms = 54 iterations)
            if animationCounter == 27:
                appState.updateAnimationOnly(currentStatusEmoji(currentStatus(
                        state), appState.terminalSupportsEmoji),
                        state.currentSong, animationCounter)
                animationCounter = 0 # Reset the counter


        # Scrolling Logic
            if scrollCounter == 11:
                if state.currentSong.checkIfTooLongForUI(appState.termWidth):
                    scrollTextOnce(fullTitle, scrollOffset, appState.termWidth,
                            appState.startingX) # Corrected call
                    if fullTitle.len > appState.termWidth - appState.startingX:
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

            if audioEvent == aevEndFile:
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
                appState.updatePlayMutedStatePlayerUI(currentStatusEmoji(
                        currentStatus(state), appState.terminalSupportsEmoji))

            of Key.M:
                state.isMuted = not state.isMuted
                ctx.mute(state.isMuted)
                appState.updatePlayMutedStatePlayerUI(currentStatusEmoji(
                        currentStatus(state), appState.terminalSupportsEmoji))

            of Key.Slash, Key.Plus:
                state.volume = min(state.volume + VolumeStep, MaxVolume)
                appState.lastVolume = state.volume
                ctx.setVolume(state.volume)
                appState.updateVolumePlayerUI(state.volume)

            of Key.Asterisk, Key.Minus:
                state.volume = max(state.volume - VolumeStep, MinVolume)
                appState.lastVolume = state.volume
                ctx.setVolume(state.volume)
                appState.updateVolumePlayerUI(state.volume)

            of Key.R, Key.BackSpace:
                when defined(volumeFade):
                    if not state.isPaused and state.volume > 0:
                        var volumeForFading = state.volume
                        while volumeForFading > 0:
                            volumeForFading = max(volumeForFading - VolumeStep, 0)
                            ctx.setVolume(volumeForFading)
                            sleep getPerCycleSleepTimeFade state.volume

                if not state.isPaused:
                    ctx.cleanupPlayer()

                ctx.stopCurrentJob()
                when defined(volumeFade):
                    ctx.setVolume(state.volume)

                break

            of Key.Q, Key.Escape, CtrlQ:
                ctx.cleanupPlayer()
                showExitMessage()
                quit(QuitSuccess)

            of Key.L: # New key binding for "Like" action
                if state.currentSong != "":
                    appState.appendToLikedSongs(config)
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

    if state.isPaused: # reset states for globalCtx if user returned with P/M
        ctx.resume()
    if state.isMuted:
        ctx.unmute()

proc playStation*(ctx: AudioContext, config: MenuConfig) =
    var appState = newAppState()
    appState.audioCtx = ctx
    when not defined(vlc):
        if ctx != nil and ctx of MpvAudioContext:
            appState.mpvCtx = MpvAudioContext(ctx).mpvHandle
    playStation(appState, config)

when not defined(vlc):
    proc playStation*(ctx: ptr Handle, config: MenuConfig) =
        var appState = newAppState()
        appState.mpvCtx = ctx
        appState.audioCtx = MpvAudioContext(mpvHandle: ctx)
        playStation(appState, config)

#except Exception:
    #  let fileHint = if config.currentSubsection != "": config.currentSubsection else: config.currentSection
    #  warn("An error occurred during playback. Edit the station list in: " & fileHint & ".json")
    #  cleanupPlayer(mpvCtx)
    #  return
