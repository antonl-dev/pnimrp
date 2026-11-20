# SPDX-License-Identifier: MPL-2.0
# menu.nim

import
    terminal, os,
    strutils, net,
    random


import
    vendor/illwill,
    ui/[
        playerui,
        menuui,
    ],

    utils/[
      utils,
      utilstypes,
      jsonutils
    ],

    audio/[
      audio,
      mpv/player,
      mpv/libmpv
    ]

when not defined(simple):
    import
        ui/[
          stationstatus,
        ],
        json/[
            statuscache
        ]

proc chooseForMeOrChooseYourself(appState: AppState, itemsLen: int): Key =
    if appState.chooseForMe:
        randomize()
        appState.chooseForMe = false # Reset the flag after use

        var rndIdx = rand(itemsLen - 1) # Generate random index within bounds
        while rndIdx == appState.lastStationIdx and itemsLen >
                1: # Ensure it doesn't pick the last station again
            rndIdx = rand(itemsLen - 1)
        appState.lastStationIdx = rndIdx # Update the last station index

    # Convert the random index to a menu key (1-9, A-M)
        if rndIdx < 9:
            result = toKey(ord(Key.One) + rndIdx)
        else:
            result = toKey(ord(Key.A) + rndIdx - 9)
    else:
        return getKeyWithTimeout(int32.high)

type
    handleMenuIsHandling = enum
        hmIsHandlingDirectory,
        hmIsHandlingUrl,
        hmIsHandlingJson

func isHandlingJSON(state: handleMenuIsHandling): bool =
    if state == hmIsHandlingJson: true else: false

when not defined(simple):
    template accumulateStationStatusStateFromItemsPaths(
        stations: seq[StationStatus],
        items: seq[string],
        paths: seq[string],
        appState: AppState
    ) =
        for i in 0 ..< items.len:
            stations.add(
                StationStatus(
                    name: items[i],
                    coord: appState.emojiPositions[i], # From ui.nim
                    url: paths[i], # Station URL
                    status: lsChecking # Initial state
                )
            )

template accumulateToSubItemsAndPathsFromLoadCat(
    result: tuple[names: seq[string], paths: seq[string]],
    subItems, subPaths: seq[string]
) =
    for nameOffolder in result[0]:
        subItems.add(nameOffolder)
    for folderPath in result[1]:
        subPaths.add(folderPath)

template keyToChar(key: Key): char = char(int(key))

template toChar(key: Key): char = keyToChar(key)

template ordinalizeKeyForIndx: int =
    if key.toChar() in {'1' .. '9'}:
        ord(key.toChar()) - ord('1')
    else: ord(toLowerAscii(key.toChar())) - ord('a') + 9

template directoryHandlerHM(items: seq[string]) =
    var subItems, subPaths = newSeqOfCap[string](32)

    let result = loadCategories(selectedPath)
    result.accumulateToSubItemsAndPathsFromLoadCat(subItems, subPaths)

    if subItems.len != 0:
        # Navigate to subcategories with isMainMenu = false
        appState.handleMenu(
          items[choosenItem],
          subItems,
          subPaths,
          isMainMenu = false,
          baseDir = selectedPath,
          handleMenuIsHandling = hmIsHandlingDirectory,
        )
    else:
        warn("No station lists available in this category.")

template jsonFileHandlerHM(items: seq[string]) =
    # Handle JSON files (station lists)
    let stations = loadStations(selectedPath)
    if stations.names.len == 0 or stations.urls.len == 0:
        warn("No stations available. Please check the station list.")
    else:
        # Navigate to station list with isMainMenu = false
        appState.handleMenu(
          items[choosenItem],
          stations.names,
          stations.urls,
          stations.streams,
          isMainMenu = false,
          baseDir = baseDir,
          handleMenuIsHandling = hmIsHandlingJson,
        )

template statusCacheHandlerHM(
    items: seq[string], handleMenuIsHandling: handleMenuIsHandling,
            appState: AppState
) =
    if isHandlingJSON(handleMenuIsHandling):
        var statuscontext = StatusCache(sectionName: section)

        var stations = newSeqOfCap[StationStatus](32)

        stations.accumulateStationStatusStateFromItemsPaths(items, paths, appState)
        hookCacheResolveAndDisplay(stations, statuscontext, appState)

proc handleMenu*(
    appState: AppState,
    section: string,
    items: seq[string],
    paths: seq[string],
    streamsList: seq[seq[StreamInfo]] = @[],
    isMainMenu: bool = false,
    baseDir: string = "",
    handleMenuIsHandling: handleMenuIsHandling,
) =
    ## Handles a generic menu for station selection or main category selection.
    ## Supports both directories and JSON files.
    let resolvedBaseDir = (if baseDir == "": appState.stationsDir else: baseDir)
    while true:
        var returnToParent = false
        clear()
        appState.drawHeader()

        # Display the menu
        appState.drawMenu(
          section,
          items,
          isMainMenu = isMainMenu,
          isPlayerUI = false,
          isHandlingJSON = isHandlingJSON(handleMenuIsHandling),
        ) # Pass isPlayerUI here

        when not defined(simple):
            items.statusCacheHandlerHM(handleMenuIsHandling, appState)

        while true:
            try:
                let key = appState.chooseForMeOrChooseYourself(items.len)
                case key
                of Key.One .. Key.Nine, Key.A .. Key.M:
                    let choosenItem = ordinalizeKeyForIndx()

                    if choosenItem >= 0 and choosenItem < items.len:
                        let selectedPath = paths[choosenItem]
                        if dirExists(selectedPath):
                            directoryHandlerHM(items)

                        elif fileExists(selectedPath) and selectedPath.endsWith(".json"):
                            jsonFileHandlerHM(items)

                        else:
                            # Treat as a station URL and play directly
                            let stStreams = if choosenItem < streamsList.len: streamsList[choosenItem] else: @[]
                            let config = MenuConfig(
                              ctx: appState.audioCtx,
                              currentSection: section,
                              currentSubsection: "",
                              stationName: items[choosenItem],
                              stationUrl: selectedPath,
                              streams: stStreams,
                              currentStreamIdx: 0
                            )
                            appState.playStation(config)
                        break
                    else:
                        showInvalidChoice()

                of Key.N:
                    if isMainMenu: # Only allow Notes in the main menu
                        appState.showNotes()
                        break
                    else:
                        showInvalidChoice()

                of Key.U:
                    appState.showHelp()
                    break

                of Key.R, Key.BackSpace:
                    if not isMainMenu:
                        returnToParent = true
                        break
                    else:
                        showInvalidChoice()

                of Key.S:
                    appState.chooseForMe = true

                of Key.Q, Key.Escape, CtrlQ:
                    showExitMessage()
                    break

                of Key.Up, Key.Down, Key.Mouse:
                    discard

                else:
                    showInvalidChoice()

            except IndexDefect:
                warn "IndexDefect, did you fill too much stations?"
                break

        if returnToParent:
            break

proc handleMenu*(
    ctx: AudioContext,
    section: string,
    items: seq[string],
    paths: seq[string],
    streamsList: seq[seq[StreamInfo]] = @[],
    isMainMenu: bool = false,
    baseDir: string = getAppDir() / "assets",
    handleMenuIsHandling: handleMenuIsHandling,
) =
    var appState = newAppState()
    appState.audioCtx = ctx
    appState.handleMenu(section, items, paths, streamsList, isMainMenu, baseDir, handleMenuIsHandling)

when not defined(vlc):
    proc handleMenu*(
        ctx: ptr Handle,
        section: string,
        items: seq[string],
        paths: seq[string],
        streamsList: seq[seq[StreamInfo]] = @[],
        isMainMenu: bool = false,
        baseDir: string = getAppDir() / "assets",
        handleMenuIsHandling: handleMenuIsHandling,
    ) =
        var appState = newAppState()
        appState.mpvCtx = ctx
        appState.audioCtx = MpvAudioContext(mpvHandle: ctx)
        appState.handleMenu(section, items, paths, streamsList, isMainMenu, baseDir, handleMenuIsHandling)

proc drawMainMenu*(appState: AppState, baseDir = "") =
    ## Draws and handles the main category menu.
    when not defined(release) or defined(debug):
        const fullscreen = false
    else:
        const fullscreen = true
        ## stack traces are cleared, we dont want fullscreen until not debug
    illwillInit(fullscreen)
    let dir = (if baseDir == "": appState.stationsDir else: baseDir)
    let categories = loadCategories(dir)
    appState.handleMenu(
      "Main",
      categories.names,
      categories.paths,
      isMainMenu = true,
      baseDir = dir,
      handleMenuIsHandling = hmIsHandlingDirectory,
    )

proc drawMainMenu*(ctx: AudioContext, baseDir = getAppDir() / "assets") =
    var appState = newAppState(assetsDir = baseDir, stationsDir = baseDir / "stations")
    appState.audioCtx = ctx
    drawMainMenu(appState, baseDir)

when not defined(vlc):
    proc drawMainMenu*(ctx: ptr Handle, baseDir = getAppDir() / "assets") =
        var appState = newAppState(assetsDir = baseDir, stationsDir = baseDir / "stations")
        appState.mpvCtx = ctx
        appState.audioCtx = MpvAudioContext(mpvHandle: ctx)
        drawMainMenu(appState, baseDir)

export hideCursor, error
