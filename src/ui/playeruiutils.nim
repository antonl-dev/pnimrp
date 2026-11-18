import
  menuui,
  commonui,
  ../utils/utils

import
  terminal

proc drawHeaderPlayerUI(appState: AppState, section: string) =
  ## Draws the header section of the player UI.

  # Draw header if section is provided
  if section.len > 0:
    setCursorPos(0, 0) # Line 0
    say(AppNameShort & " > " & section, fgYellow)

proc drawStatusAndVolumePlayerUI(appState: AppState, status: string, volume: int) =
  ## Draws the status and volume section of the player UI.

  setCursorPos(0, 3)
  eraseLine()
  setCursorPos(0, 3)
  let volumeColor = volumeColor(volume)
  say("Status: " & status & "    | Volume: ", fgGreen, xOffset = 0, shouldEcho = false)
  styledEcho(" ", volumeColor, $volume & "%")

proc drawNowPlayingPlayerUI(appState: AppState, nowPlaying: string) =
  when defined(simple):
    stdout.styledWrite(fgCyan, "Now Playing:   ", nowPlaying.truncateMe(appState.termWidth))

  else:
    # In normal mode, use the existing approach
    stdout.styledWrite(fgCyan, "   Now Playing:  ")
    if appState.terminalSupportsEmoji:
      appState.startingX = "  Now Playing: ".len + 1 # +1 for emoji space
    else:
      appState.startingX = "  Now Playing: ".len + 3 # +3 because "[>]" is 3 chars long

    if not nowPlaying.checkIfTooLongForUI(appState.termWidth):
      stdout.styledWrite(fgCyan, nowPlaying)

proc updateVolumePlayerUI*(appState: AppState, newVolume: int) =
  setCursorPos(24, 3)
  let volumeColor = volumeColor(newVolume)
  if not appState.terminalSupportsEmoji:
    stdout.write "  "
  stdout.write " "
  stdout.styledWrite(volumeColor, $newVolume & "% ") #when go from 100 to less
  stdout.flushFile()

proc updateCurrentSongPlayerUI*(appState: AppState, songName: string) =
  setCursorPos(0, 2) # Line 2 (below the separator)
  eraseLine()
  setCursorPos(0, 2) #explicit duplicate setting just to be consistent across OSes
  appState.drawNowPlayingPlayerUI(songName)
  stdout.flushFile()

proc updatePlayMutedStatePlayerUI*(appState: AppState, status: string) =
  setCursorPos(8, 3)
  stdout.styledWrite(fgGreen, status)
  if not appState.terminalSupportsEmoji:
    stdout.write " "
  stdout.write " "
  stdout.flushFile()

proc drawPlayerUIInternal(appState: AppState, section, nowPlaying, status: string, volume: int) =
  ## Internal function that handles the common logic for drawing and updating the player UI.
  appState.updateTermWidth() # Ensure the terminal width is up-to-date

  # Clear the screen and reset cursor position
  clear()

  # Draw header if section is provided
  appState.drawHeaderPlayerUI(section)

  # Draw top separator
  setCursorPos(0, 1)
  drawSeperatorUI(xpos = -1, sep = '-', offset = 0, color = fgGreen, width = appState.termWidth) # Line 1

  # Display "Now Playing" with truncation if necessary
  setCursorPos(0, 2) # Line 2 (below the separator)
  eraseLine()
  appState.drawNowPlayingPlayerUI(nowPlaying)

  # Display status and volume on the same line
  appState.drawStatusAndVolumePlayerUI(status, volume)

  # Draw separator after status/volume
  setCursorPos(0, 4)
  drawSeperatorUI(xpos = -1, sep = '-', offset = 0, color = fgGreen, width = appState.termWidth) # Line 4

  # Display footer options
  setCursorPos(0, 5) # Line 5
  let footerOptions = "[P] Pause/Play   [-/+] Adjust Volume   [Q] Quit"
  say(footerOptions, fgYellow, xOffset = (appState.termWidth - footerOptions.len) div 2)

  # Draw the bottom border
  setCursorPos(0, 6)
  drawSeperatorUI(xpos = -1, sep = '=', offset = 0, color = fgGreen, width = appState.termWidth)

proc drawPlayerUI*(appState: AppState, section, nowPlaying, status: string, volume: int) =
  ## Draws the modern music player UI with dynamic layout and visual enhancements.
  clear()
  appState.drawPlayerUIInternal(section, nowPlaying, status, volume)

