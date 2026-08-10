# SPDX-License-Identifier: MPL-2.0
# menu.nim

import
  terminal, os,
  strutils, net,
  random


import
  ui/[
    illwill,
    playerui,
    menuui,
  ],

  utils/[
    utils,
    jsonutils
  ],

  audio/[
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

var chooseForMe* = false # Declare as mutable global variable
var lastStationIdx*: int = -1 # Declare a global variable to track the last station index

proc chooseForMeOrChooseYourself(itemsLen: int): Key =
  if chooseForMe:
    randomize()
    chooseForMe = false # Reset the flag after use

    var rndIdx = rand(itemsLen - 1) # Generate random index within bounds
    while rndIdx == lastStationIdx and itemsLen > 1: # Ensure it doesn't pick the last station again
      rndIdx = rand(itemsLen - 1)
    lastStationIdx = rndIdx # Update the last station index

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
    paths: seq[string]
  ) =
    for i in 0 ..< items.len:
      stations.add(
        StationStatus(
          name:     items[i],
          coord:    emojiPositions[i],  # From ui.nim
          url:      paths[i],             # Station URL
          status:   lsChecking         # Initial state
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
    ctx.handleMenu(
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
    ctx.handleMenu(
      items[choosenItem],
      stations.names,
      stations.urls,
      isMainMenu = false,
      baseDir = baseDir,
      handleMenuIsHandling = hmIsHandlingJson,
    )

template statusCacheHandlerHM(
    items: seq[string], handleMenuIsHandling: handleMenuIsHandling
) =
  if isHandlingJSON(handleMenuIsHandling):
    var statuscontext = StatusCache(sectionName: section)

    var stations = newSeqOfCap[StationStatus](32)

    stations.accumulateStationStatusStateFromItemsPaths(items, paths)
    hookCacheResolveAndDisplay(stations, statuscontext)

proc handleMenu*(
    ctx: ptr Handle,
    section: string,
    items: seq[string],
    paths: seq[string],
    isMainMenu: bool = false,
    baseDir: string = getAppDir() / "assets",
    handleMenuIsHandling: handleMenuIsHandling,
) =
  ## Handles a generic menu for station selection or main category selection.
  ## Supports both directories and JSON files.
  while true:
    var returnToParent = false
    clear()
    drawHeader()

    # Display the menu
    drawMenu(
      section,
      items,
      isMainMenu = isMainMenu,
      isPlayerUI = false,
      isHandlingJSON = isHandlingJSON(handleMenuIsHandling),
    ) # Pass isPlayerUI here

    when not defined(simple):
      items.statusCacheHandlerHM(handleMenuIsHandling)

    while true:
      try:
        let key = chooseForMeOrChooseYourself(items.len)
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
              let config = MenuConfig(
                currentSection: section,
                currentSubsection: "",
                stationName: items[choosenItem],
                stationUrl: selectedPath
              )
              ctx.playStation(config)
            break
          else:
            showInvalidChoice()

        of Key.N:
          if isMainMenu: # Only allow Notes in the main menu
            showNotes()
            break
          else:
            showInvalidChoice()

        of Key.U:
          showHelp()
          break

        of Key.R, Key.BackSpace:
          if not isMainMenu:
            returnToParent = true
            break
          else:
            showInvalidChoice()

        of Key.S:
          chooseForMe = true

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

proc drawMainMenu*(ctx: ptr Handle, baseDir = getAppDir() / "assets") =
  ## Draws and handles the main category menu.
  const fullscreen = when not defined(release) or defined(debug): false else: true
    ## stack traces are cleared, we dont want fullscreen until not debug
  illwillInit(fullscreen)
  let categories = loadCategories(baseDir)
  ctx.handleMenu(
    "Main",
    categories.names,
    categories.paths,
    isMainMenu = true,
    baseDir = baseDir,
    handleMenuIsHandling = hmIsHandlingDirectory,
  )

export hideCursor, error
