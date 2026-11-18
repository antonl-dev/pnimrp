# SPDX-License-Identifier: MPL-2.0
# utils.nim

import
    os, terminal,

    ../audio/mpv/[
        player,
        ],

    ../vendor/illwill,

    utilstypes,
    uiutils,
    jsonutils

let appDir* = getAppDir()

proc checkIfCacheDirExistElseCreate* =
    let statusCache = appDir / ".statuscache"
    if not dirExists statusCache:
        createDir statusCache

proc validateLengthStationName*(result: seq[string], filePath: string,
        maxLength: int = MaxStationNameLength) =
    ## Validates the length of station names (odd indices).
    ## Raises a `ValidationError` if any station name exceeds the maximum allowed length.
    var warnCount = 0
    for i in 0 ..< result.len:
        if warnCount == 3: break
        if i mod 2 == 0: # Only validate odd indices (0, 2, 4, ...)
            if result[i].len > maxLength:
                warn(
                  "Station name at index " & $i & " ('" & result[i] &
                          "') in file " & filePath & " is too long.",
                  xOffset = 4,
                  color = fgYellow
                )
                warn(
                  "Maximum allowed length is " & $maxLength & " characters.",
                  xOffset = 4,
                  color = fgYellow
                )
                sleep(400) # Pause for 400ms after displaying the warning
                warnCount += 1

proc checkIfTooLongMagic*(width: int = terminalWidth()): int =
    width - "  Now Playing: ".len - 6

proc checkIfTooLongForUI*(str: string, width: int = terminalWidth()): bool =
    str.len > checkIfTooLongMagic(width)

proc truncateMe*(str: string, width: int = terminalWidth()): string =
    if str.checkIfTooLongForUI(width):
        result = str.substr(0, checkIfTooLongMagic(width)) & "..."
    else: return str
        #1.65 good factor to stop nowplaying overflow, inc 1.65 if does

proc initCheckingStationNotice* =
    setCursorPos(0, terminalHeight() - 5)
    stdout.styledWrite fgYellow, "Checking stations... Please Wait"
    stdout.flushFile()

proc finishCheckingStationNotice*(appState: AppState = nil) =
    setCursorPos(0, terminalHeight() - 5)
    eraseLine()
    if appState != nil:
        appState.lastMenuSeparatorY = 0
    stdout.flushFile()

proc cleanupPlayer*(ctx: ptr Handle) =
    ## Cleans up player resources.
    #ctx.terminateDestroy()
    #stopCurrentJob()
    discard

template debug*: bool =
    not(
      defined(release) or
      defined(danger)
    ) or
    defined(debug)

export #jsonutils
    loadCategories, loadStations, loadQuotes

export #uiutils
    getSymbol, terminalSupportsEmoji, currentStatusEmoji,
    error, updateTermWidth, clear, warn, showInvalidChoice,
    centerText, truncateName, calculateColumnLayout

#export all internal within utils namespace
export #utilstypes
    AppState, newAppState,
    QuoteData,

    UIError, JSONParseError, FileNotFoundError,
    ValidationError, InvalidDataError,

    MenuOptions,
    LinkStatus,
    MenuError,
    PlayerState,
    MenuConfig,

    CheckIdleInterval,
    KeyTimeout,

    Theme,

    AnimationFrame,
    PlayerStatus,

    AsciiFrames,
    EmojiFrames,

    MenuChars,
    AppName,
    AppNameShort,
    DefaultErrorMsg,
    MinTerminalWidth,
    MaxStationNameLength,
    mpvEventLoopTimeout,
    RetryTimesWhenStreamInterrupt

when not defined(simple):
    export #utilstypes
        ThemeConfig,
        StatusCache
