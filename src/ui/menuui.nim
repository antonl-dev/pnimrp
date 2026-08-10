import
  terminal, random, os,
  strutils, ../audio/mpv/player,

  ../utils/[
    utils,
    jsonutils
  ]

when not defined(simple):
  import stationstatus

using str: string

import commonui

proc say*(
  message: string,
  color = fgYellow,
  xOffset = 5,
  shouldEcho = true
) =
  if color in {fgBlue, fgGreen}:
    setCursorXPos(xOffset)
    if color == fgGreen and not shouldEcho:
      stdout.styledWrite(fgGreen, message)
    else:
      styledEcho(color, message)
  else:
    styledEcho(color, message)

proc showQuotes* =
  let quotesData = loadQuotes(getAppDir() / "assets" / "config" / "qoute.json")
  let rand = rand(0 .. quotesData.quotes.high)

  when debug:
    echo "free mem: ", $(getFreeMem() / 1024), " kB"
    echo "total/max mem: ", $(getTotalMem() / 1024), " kB"
    echo "occupied mem: ", $(getOccupiedMem() / 1024), " kB"

  if quotesData.quotes[rand] == "":
    error("no quote found")

  styledEcho(fgCyan, quotesData.quotes[rand], "...")
  setCursorXPos(15)
  styledEcho(fgGreen, "—", quotesData.authors[rand])

  if quotesData.authors[rand] == "":
    error("there can be no quote without an author")
    if rand * 2 != -1:
      error("@ line: " & $(rand * 2) & " in qoute.json")

proc showExitMessage* =
  setCursorPos(0, 15)
  echo ""
  quit(QuitSuccess)

proc drawSeperatorUI*(xpos = -1, sep = '=', offset = 5, color = fgGreen) =
  if not xpos == -1:
    setCursorXPos xpos
  say(sep.repeat(termWidth), color, offset)

proc drawHeader*() =
  ## Draws the application header with decorative lines and emojis.
  updateTermWidth()
  if termWidth < MinTerminalWidth:
    raise newException(UIError, "Terminal width too small.")

  # Draw the top border using the theme's separator color
  drawSeperatorUI(xpos = -1, offset = 0, color = currentTheme.separator)

  # Draw the application title with emojis using the theme's header color
  let title =
    when not defined(noEmoji):
      "       🎧 " & AppName & " 🎧"
    else:
      "          " & AppName
  say(title, currentTheme.header, xOffset = (termWidth - title.len) div 2)

  # Draw the bottom border of the header using the theme's separator color
  drawSeperatorUI(xpos = -1, offset = 0, color = currentTheme.separator)

var lastTermWidth = termWidth # Track the last terminal width

proc updateTermWidth* =
  ## Updates the terminal width if it has changed significantly.
  let newWidth = terminalWidth()
  if abs(newWidth - lastTermWidth) >= 5: # Only update if the change is significant
    termWidth = newWidth
    lastTermWidth = newWidth

proc renderMenuOptions(
    options: MenuOptions, numColumns: int, maxColumnLengths: seq[int], spacing: int
) =
  ## Renders the menu options in a multi-column layout.
  when not defined(simple):
    emojiPositions = @[] # Clear previous positions
  let itemsPerColumn = (options.len + numColumns - 1) div numColumns

  # Wait for the terminal width to stabilize
  var stableWidth = false
  while not stableWidth:
    updateTermWidth()
    if abs(termWidth - lastTermWidth) < 5: # Terminal width is stable
      stableWidth = true
    else:
      sleep(100) # Wait for 100ms before checking again

  var currentY = 5 # Starting Y coordinate (after header and category title)

  for row in 0 ..< itemsPerColumn:
    var currentLine = ""
    for col in 0 ..< numColumns:
      let index = row + col * itemsPerColumn
      if index < options.len:
        # Calculate the prefix for the menu option
        var prefix =
          if index < 9: $(index + 1) & "."                    # Use numbers 1-9
          else:
            if index < MenuChars.len: $MenuChars[index] & "." # Use A-Z
            else: "?"                                         # Fallback

        when not defined(simple):
          # Calculate X position for the emoji
          var emojiX = 0
          for i in 0 ..< col:
            emojiX += maxColumnLengths[i] + spacing

          emojiX += prefix.len + 1 # +1 for the space after the number/letter

          # Add to emojiPositions.  currentY is calculated *before* adding the line.
          emojiPositions.add((emojiX, currentY))

        prefix = " " & prefix

        # Truncate and format
        let truncatedName =
          truncateName(options[index], maxColumnLengths[col] - prefix.len)
        var dashToSpaced = truncatedName

        proc isFound(s: int): bool =
          if s < 0: return false
          else: return true

        if isFound dashToSpaced.find("!"):
          dashToSpaced = dashToSpaced.replace("!", "")
          dashToSpaced[0] = dashToSpaced[0].toUpperAscii()

        if isFound dashToSpaced.find("_"):
          var getVal = dashToSpaced.find("_")
          dashToSpaced = dashToSpaced.replace("_", " ")
          dashToSpaced[getVal+1] = dashToSpaced[getVal+1].toUpperAscii()

        let formattedOption = prefix & dashToSpaced
        let padding = maxColumnLengths[col] - formattedOption.len
        currentLine.add(formattedOption & " ".repeat(padding))

      else:
        # Add empty space
        currentLine.add(" ".repeat(maxColumnLengths[col]))

      # Add spacing between columns
      if col < numColumns - 1:
        currentLine.add(" ".repeat(spacing))

    # Render the line
    say(currentLine, fgBlue)
    currentY += 1 # Increment Y *after* drawing the line


proc displayMenu*(
    options: MenuOptions,
    showReturnOption = true,
    highlightActive = true,
    isMainMenu = false,
    isPlayerUI = false,
    isHandlingJSON = false
) =
  ## Displays menu options in a formatted multi-column layout.
  updateTermWidth()

  var options = options

  # 1. Initialization
  var currentY = 1 # Start at the top

  # Draw the "Station Categories" section header
  let categoriesHeader =
    when not defined(noEmoji):
          "         📻 Station Categories 📻"
    else:
      "         \\[o=] Station Categories [o=]/"
  say(categoriesHeader, fgCyan, xOffset = (termWidth - categoriesHeader.len) div 2)
  currentY += 1 # Increment after header

  # Draw the separator line
  drawSeperatorUI(xpos = -1, sep = '-', offset = 0)
  currentY += 1 # Increment after separator

  # Calculate column layout and render menu options
  let (numColumns, maxColumnLengths, spacing) = calculateColumnLayout(options)
  renderMenuOptions(options, numColumns, maxColumnLengths, spacing)

  # 3. Counting Rows (after rendering)
  let itemsPerColumn = (options.len + numColumns - 1) div numColumns
  currentY += itemsPerColumn

  when not defined(simple):
    if isHandlingJSON:
      initDrawMenuEmojis() # Draw yellow emojis *after* rendering text
  echo ""
  currentY += 1 # Increment after the empty line
  # 4. Tracking the Separator's Y
  # footerSeparatorLineY = currentY  # Store the Y position *before* drawing
  lastMenuSeparatorY = currentY # Store the Y position *before* drawing, renamed variable
  # Draw the separator line
  #say(separatorLine, fgGreen, xOffset = 0)
  drawSeperatorUI(xpos = -1, sep = '-', offset = 0)
  currentY += 1 #increment after second separator

  # Display the footer options
  let footerOptions = getFooterOptions(isMainMenu, isPlayerUI) # Pass isPlayerUI here
  say(footerOptions, fgYellow, xOffset = (termWidth - footerOptions.len) div 2)
  currentY += 1

  # Draw the bottom border
  drawSeperatorUI(xpos = -1, offset = 0)
  currentY += 1 #we are not tracking this, but it's good practice

proc drawMenu*(
    section: string,
    options: string | MenuOptions,
    subsection = "",
    showNowPlaying = true,
    isMainMenu = false,
    isPlayerUI = false,
    isHandlingJSON = false
) =
  ## Draws a complete menu with header and options.
  clear()

  # Draw header
  drawHeader()
  # Display menu options
  when options is string:
    for line in splitLines(options):
      say(line, fgBlue)
  else:
    displayMenu(
      options,
      isMainMenu = isMainMenu,
      isPlayerUI = isPlayerUI,
      isHandlingJSON = isHandlingJSON
    )

proc showFooter*(
    lineToDraw = 4,
    isMainMenu = false,
    isPlayerUI = false,
    separatorColor = fgGreen,
    footerColor = fgYellow
) =
  ## Displays the footer with dynamic options based on the context.
  updateTermWidth()
  setCursorPos(0, lineToDraw)
  drawSeperatorUI(xpos = -1, '-', offset = 0, separatorColor)

  # Add footer with controls at the bottom
  setCursorPos(0, lineToDraw + 1)
  let footerOptions = getFooterOptions(isMainMenu, isPlayerUI)
  say(footerOptions, footerColor, xOffset = (termWidth - footerOptions.len) div 2)

  # Draw bottom border
  setCursorPos(0, lineToDraw + 2)
  drawSeperatorUI(xpos = -1, '=', offset = 0, separatorColor)

proc drawHeader*(section: string) =
  ## Draws the application header with the current section.
  updateTermWidth()

  if termWidth < MinTerminalWidth:
    raise newException(UIError, "Terminal width too small")

  # Draw header
  say(AppNameShort & " > " & section, fgGreen)
  drawSeperatorUI(xpos = -1, '-')

proc showHelp*() =
  ## Displays instructions on how to use the app.
  clear()

  drawHeader()
  say("Welcome to " & AppName & "!", fgYellow)
  say("Here's how to use the app:", fgGreen)
  say("1. Use the number keys (1-9) or letters (A-Z) to select a station.", fgBlue)
  say("2. In the player UI, use the following keys:", fgBlue)
  say("   - [P] Pause/Play", fgBlue)
  say("   - [-/+] Adjust Volume", fgBlue)
  say("   - [R] Return to the previous menu", fgBlue)
  say("   - [Q] Quit the application", fgBlue)
  say("3. Press [N] in the main menu to view notes.", fgBlue)
  say("4. Press [H] in the main menu to view this help screen.", fgBlue)
  say("=".repeat(termWidth), fgGreen, xOffset = 0)
  say("Press any key to return to the main menu.", fgYellow)
  discard getch()

proc showNotes* =
  while true:
    var shouldReturn = false
    drawMenu(
      "Notes",
      """PNimRP Copyright (C) 2021, 2022, 2024–2025 antonl-dev
This program comes with ABSOLUTELY NO WARRANTY
This is free software, and you are welcome to redistribute
under certain conditions.""",
      showNowPlaying = false
    )
    showFooter(lineToDraw = 9, isMainMenu = true)

    while true:
      case getch():
        of 'r', 'R':
          shouldReturn = true
          break
        of 'q', 'Q':
          showExitMessage()
        else:
          showInvalidChoice()

    if shouldReturn:
      break

proc exit*(ctx: ptr Handle, isPaused: bool) =
  showExitMessage()
  quit(QuitSuccess)

proc spinLoadingSpinnerOnce*(frame: var int, coord = (-1, -1)) =
  const spinner = @["-", "\\", "|", "/"]
  if coord == (-1, -1): setCursorPos(termWidth - 3, 2)
  else:                 setCursorPos(coord[0], coord[1])
  stdout.write("[" & spinner[frame] & "]")
  stdout.flushFile()
  if frame == 3: frame = 0
  else: frame += 1

when isMainModule:
  var spinnerFrame = 0
  while true:
    spinnerFrame.spinLoadingSpinnerOnce()
