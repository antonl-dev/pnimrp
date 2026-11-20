# SPDX-License-Identifier: MPL-2.0
import
    terminal, strutils, net,
    tables, os

import
    ../vendor/illwill, playeruiutils, menuui,

    ../audio/audio,
    ../audio/equalizer,
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
        ../audio/metadata,
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

proc fadeVolume*(ctx: AudioContext, targetVol, startVol: int) =
    ## Smoothly ramps audio volume between startVol and targetVol.
    var current = startVol
    if targetVol > startVol:
        while current < targetVol:
            current = min(current + VolumeStep, targetVol)
            ctx.setVolume(current)
            sleep getPerCycleSleepTimeFade targetVol
    elif targetVol < startVol:
        while current > targetVol:
            current = max(current - VolumeStep, targetVol)
            ctx.setVolume(current)
            sleep getPerCycleSleepTimeFade startVol

proc validateStationPreflight*(appState: AppState, config: MenuConfig): bool =
    ## Validates station URL and link availability prior to playback.
    if config.stationUrl == "":
        editBadFileHint(config)
        return false

    try:
        initCheckingStationNotice()
        if not validateLink(config.stationUrl).isValid:
            editBadFileHint(config)
            return false
        finishCheckingStationNotice(appState)
        return true
    except Exception:
        editBadFileHint(config)
        return false

proc handlePlayerAudioEvent*(
    ctx: AudioContext,
    audioEvent: AudioEventKind,
    state: var PlayerState,
    config: MenuConfig,
    appState: AppState,
    fullTitle: var string,
    wasTheStreamPlayingForSomeTime: var bool,
    finishedLoading: var bool
) =
    ## Dispatches audio core events to UI updates and volume fading.
    if audioEvent in [aevFileLoaded, aevTitleChanged]:
        let newTitle = ctx.getCurrentMediaTitle(appState)
        if newTitle != "" and newTitle != "nil":
            state.currentSong = newTitle
            if fullTitle != state.currentSong:
                appState.appendToHistory(config)
            fullTitle = state.currentSong
            appState.fullMediaTitle = fullTitle
            appState.updateCurrentSongPlayerUI(state.currentSong)
            setCursorXPos 0
            when not defined(simple):
                appState.globalMetadata = updateMetadataUI(config, ctx, state)

    if audioEvent == aevFileLoaded:
        wasTheStreamPlayingForSomeTime = true
        when defined(volumeFade):
            ctx.fadeVolume(targetVol = state.volume, startVol = 0)
        finishedLoading = true

proc handlePlayerKeyInput*(
    ctx: AudioContext,
    key: Key,
    state: var PlayerState,
    appState: AppState,
    config: var MenuConfig
): bool =
    ## Dispatches user keyboard controls. Returns true if playback should stop/return.
    result = false
    let curStreamBadge = if config.streams.len > 0:
        formatStreamBadge(config.streams[config.currentStreamIdx], config.currentStreamIdx, config.streams.len)
    else: ""

    case key:
    of Key.P, Key.Space:
        state.isPaused = not state.isPaused
        ctx.pause(state.isPaused)
        appState.updatePlayMutedStatePlayerUI(currentStatusEmoji(
                currentStatus(state), appState.terminalSupportsEmoji), state.volume, streamBadge = curStreamBadge)

    of Key.M:
        state.isMuted = not state.isMuted
        ctx.mute(state.isMuted)
        appState.updatePlayMutedStatePlayerUI(currentStatusEmoji(
                currentStatus(state), appState.terminalSupportsEmoji), state.volume, streamBadge = curStreamBadge)

    of Key.Slash, Key.Plus:
        state.volume = min(state.volume + VolumeStep, MaxVolume)
        appState.lastVolume = state.volume
        ctx.setVolume(state.volume)
        appState.updateVolumePlayerUI(state.volume, currentStatusEmoji(
                currentStatus(state), appState.terminalSupportsEmoji), streamBadge = curStreamBadge)

    of Key.Asterisk, Key.Minus:
        state.volume = max(state.volume - VolumeStep, MinVolume)
        appState.lastVolume = state.volume
        ctx.setVolume(state.volume)
        appState.updateVolumePlayerUI(state.volume, currentStatusEmoji(
                currentStatus(state), appState.terminalSupportsEmoji), streamBadge = curStreamBadge)

    of Key.E:
        if appState != nil and appState.equalizerConfig.presets.len > 0:
            let nextPreset = appState.equalizerConfig.cycleNextPreset()
            ctx.applyEqualizer(nextPreset)
            let statusEmoji = currentStatusEmoji(currentStatus(state), appState.terminalSupportsEmoji)
            appState.drawStatusAndVolumePlayerUI(statusEmoji, state.volume, nextPreset.name, curStreamBadge)

    of Key.B:
        if config.streams.len > 1:
            config.currentStreamIdx = (config.currentStreamIdx + 1) mod config.streams.len
            let nextStream = config.streams[config.currentStreamIdx]
            config.stationUrl = nextStream.url
            ctx.allocateJob(config.stationUrl)
            if appState != nil and appState.equalizerConfig.enabled:
                let activePreset = appState.equalizerConfig.getActivePreset()
                ctx.applyEqualizer(activePreset)

            let newBadge = formatStreamBadge(nextStream, config.currentStreamIdx, config.streams.len)
            let statusEmoji = currentStatusEmoji(currentStatus(state), appState.terminalSupportsEmoji)
            let eqName = if appState != nil: appState.equalizerConfig.getActivePreset().name else: "Flat"
            appState.drawStatusAndVolumePlayerUI(statusEmoji, state.volume, eqName, newBadge)

    of Key.R, Key.BackSpace:
        when defined(volumeFade):
            if not state.isPaused and state.volume > 0:
                ctx.fadeVolume(targetVol = 0, startVol = state.volume)

        if not state.isPaused:
            ctx.cleanupPlayer()

        ctx.stopCurrentJob()
        when defined(volumeFade):
            ctx.setVolume(state.volume)

        return true

    of Key.Q, Key.Escape, CtrlQ:
        ctx.cleanupPlayer()
        showExitMessage()
        quit(QuitSuccess)

    of Key.L:
        if state.currentSong != "":
            appState.appendToLikedSongs(config)
        else:
            warn("song field is currently empty")

    of Key.None:
        discard

    of Key.Up, Key.Down, Key.Left, Key.Right:
        when not defined(android):
            showInvalidChoice()

    else:
        showInvalidChoice()

proc handleIdleAndDisconnection*(
    ctx: AudioContext,
    audioEvent: AudioEventKind,
    config: MenuConfig,
    wasTheStreamPlayingForSomeTime: bool,
    streamInterruptRetryCount: var int,
    playlistFirstPass: var bool
): bool =
    ## Handles idle timeouts, stream disconnection, and automatic reconnects.
    ## Returns true if the session has terminated.
    result = false
    if ctx.isIdle():
        if streamInterruptRetryCount < RetryTimesWhenStreamInterrupt and
           wasTheStreamPlayingForSomeTime:
            ctx.allocateJob(config.stationUrl)
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
            return true

    if audioEvent == aevEndFile:
        if config.stationUrl.isValidPlaylistUrl():
            if playlistFirstPass:
                handlePlayerError("End of playlist reached", config)
                return true
            playlistFirstPass = true
        else:
            handlePlayerError("Stream ended", config)
            return true

proc tickPlayerUIFrame*(
    appState: AppState,
    state: PlayerState,
    fullTitle: string,
    animationCounter: var int,
    scrollCounter: var int,
    scrollOffset: var int
) =
    ## Ticks text marquee scrolling and status animation.
    when not defined(simple):
        animationCounter += 1
        if animationCounter == 27:
            appState.updateAnimationOnly(currentStatusEmoji(currentStatus(
                    state), appState.terminalSupportsEmoji),
                    state.currentSong, animationCounter)
            animationCounter = 0

        if scrollCounter == 11:
            if state.currentSong.checkIfTooLongForUI(appState.termWidth):
                scrollTextOnce(fullTitle, scrollOffset, appState.termWidth,
                        appState.startingX)
                if fullTitle.len > appState.termWidth - appState.startingX:
                    scrollOffset += 1
                scrollCounter = 0
        else:
            scrollCounter += 1

proc playStation*(appState: AppState, config: MenuConfig) =
    ## Plays a radio station and handles user input for playback control.
    var playConfig = config
    let ctx = playConfig.ctx
    if not appState.validateStationPreflight(playConfig):
        return

    var state = PlayerState(
        isPaused: false,
        isMuted: false,
        volume: appState.lastVolume
    )
    var coreIdleCounter: uint8
    var playlistFirstPass = false
    var scrollOffset: int = 0
    var fullTitle: string
    var finishedLoading = false
    var spinnerState = 0
    var wasTheStreamPlayingForSomeTime: bool
    var streamInterruptRetryCount = 1

    when not defined(simple):
        var scrollCounter: int = 0
        var animationCounter: int = 0

    ctx.allocateJob(playConfig.stationUrl)

    if appState != nil and appState.equalizerConfig.enabled:
        let activePreset = appState.equalizerConfig.getActivePreset()
        ctx.applyEqualizer(activePreset)

    when defined(volumeFade):
        ctx.setVolume(0)

    # Draw the initial player UI
    let initBadge = if playConfig.streams.len > 0:
        formatStreamBadge(playConfig.streams[playConfig.currentStreamIdx], playConfig.currentStreamIdx, playConfig.streams.len)
    else: ""

    appState.drawPlayerUI(playConfig.stationName, "Loading...", currentStatusEmoji(
            currentStatus(state), appState.terminalSupportsEmoji), state.volume)
    if initBadge.len > 0:
        appState.drawStatusAndVolumePlayerUI(currentStatusEmoji(
                currentStatus(state), appState.terminalSupportsEmoji), state.volume, streamBadge = initBadge)
    appState.showFooter(isPlayerUI = true)
    when defined(simple):
        fullTitle = fullTitle.truncateMe(appState.termWidth)

    while true:
        var audioEvent = aevNone
        if not state.isPaused:
            audioEvent = ctx.pollAudioEvent(mpvEventLoopTimeout)

        ctx.handlePlayerAudioEvent(audioEvent, state, playConfig, appState,
                fullTitle, wasTheStreamPlayingForSomeTime, finishedLoading)

        if not finishedLoading and audioEvent != aevFileLoaded:
            spinnerState.spinLoadingSpinnerOnce(appState)

        when not defined(simple):
            appState.tickPlayerUIFrame(state, fullTitle, animationCounter,
                    scrollCounter, scrollOffset)

        # Periodic checks
        if coreIdleCounter >= CheckIdleInterval:
            if handleIdleAndDisconnection(ctx, audioEvent, playConfig,
                    wasTheStreamPlayingForSomeTime, streamInterruptRetryCount,
                    playlistFirstPass):
                break
            coreIdleCounter = 0
        inc coreIdleCounter

        # Handle user input
        let key = getKeyWithTimeout(KeyTimeout)
        if ctx.handlePlayerKeyInput(key, state, appState, playConfig):
            break

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
