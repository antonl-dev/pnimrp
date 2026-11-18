# SPDX-License-Identifier: MPL-2.0
# pnimrp.nim

import
    os, terminal, std/exitprocs, random,

    src/[
      menu, ui/illwill, ui/hidestderr, ui/menuui,
      utils/utils,
      audio/mpv/player,
    ]

when not defined(simple):
    import
        src /
          ui/theme

when compileOption("profiler"):
    import std/nimprof

var gAppState: AppState

const
    AppName = "Poor Man's Radio Player" # Name of the application
    Version = "0.1"                     # Current version of the application

template assertAssetNotFound(asset: string, isDir = true) =
    when isDir:
        let status = dirExists(asset)
    else:
        let status = fileExists(asset)
    if not status:
        error "Assets directory/file not found: " & asset

proc validateEnvironment(appState: AppState) =
    ## Validates the application environment, ensuring necessary assets and permissions are in place.
    let assetsDir = appState.assetsDir
    let stationsDir = appState.stationsDir
    let configDir = appState.configDir

    # Ensure the assets directory exists
    assertAssetNotFound assetsDir
    assertAssetNotFound stationsDir
    assertAssetNotFound configDir

    assertAssetNotFound configDir / "qoute.json", isDir = false
    assertAssetNotFound configDir / "themes.json", isDir = false
    assertAssetNotFound configDir / "sounds" / "bell.ogg", isDir = false

    when not defined(simple):
        checkIfCacheDirExistElseCreate()
    # Future: Add checks for required assets and write permissions if needed

proc showBanner() =
    ## Displays the application banner with version and copyright information.
    styledEcho(fgCyan, AppName & " v" & Version)
    styledEcho(fgCyan, "Copyright (c) 2021, 2022, 2024–2025 bloomingchad")

proc cleanup() =
    ## Performs cleanup tasks on application exit, such as restoring the cursor.
    try: illwillDeinit()
    except IllwillError: discard

    if gAppState != nil:
        gAppState.stderrState.restoreStderr()
    echo ""
    showQuotes()
    echo "Thank you for using " & AppName

proc handleInterrupt() {.noconv.} =
    ## Handles SIGINT (Ctrl+C) signal gracefully.
    cursorDown 1
    echo "Received interrupt signal (Ctrl+C). Exiting gracefully..."
    cleanup()
    quit(QuitSuccess)

when defined(dragonfly) or defined(macos):
    {.error: """
    PNimRP is not supported under your OS
    Please see user.rst for more information.
    """.}

proc main() =
    ## Main entry point for the application.
    when not defined(windows):
        if not stdin.isatty() or not stdout.isatty():
            error "please run within terminal!"
            quit QuitFailure

    let assetsDir = getAppDir() / "assets"
    let stationsDir = assetsDir / "stations"
    let configDir = assetsDir / "config"

    var appState = newAppState(
      assetsDir = assetsDir,
      stationsDir = stationsDir,
      configDir = configDir,
      version = Version
    )
    gAppState = appState

    appState.stderrState.initSuppressStderr()

    try:
        # Register cleanup procedure to run on exit
        addExitProc(cleanup)
        setControlCHook(handleInterrupt)

        when not defined(simple):
            # Load theme configuration
            let configPath = appState.configDir / "themes.json"
            appState.themeConfig = loadThemeConfig(configPath)
            appState.theme = getCurrentTheme(appState.themeConfig)

        else:
            appState.theme = Theme(
              header: fgYellow,
              separator: fgGreen,
              menu: fgBlue,
              footer: fgYellow,
              error: fgRed,
              warning: fgYellow,
              success: fgGreen,
              nowPlaying: fgCyan,
              volumeLow: fgBlue,
              volumeMedium: fgGreen,
              volumeHigh: fgRed
            )

        # Validate the environment and initialize configuration
        validateEnvironment(appState)

        # Display the application banner and hide the cursor
        showBanner()
        hideCursor()
        randomize()

        #init global mpv context for reuse
        appState.mpvCtx = initGlobalMpv()
        defer: appState.mpvCtx.terminateDestroy()

        # Start the main menu with the configured assets directory
        appState.drawMainMenu(appState.stationsDir)

    finally:
        # Ensure cleanup is always performed
        cleanup()

when isMainModule:
    main()
