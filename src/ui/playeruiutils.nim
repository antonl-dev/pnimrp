import
  menuui,
  commonui,
  ../utils/utils

import
  terminal

proc drawHeaderPlayerUI(section: string) =
  ## Draws the header section of the player UI.

  # Draw header if section is provided
  if section.len > 0:
    setCursorPos(0, 0) # Line 0
    say(AppNameShort & " > " & section, fgYellow)

proc drawStatusAndVolumePlayerUI(status: string, volume: int) =
  ## Draws the status and volume section of the player UI.

  setCursorPos(0, 3)
  eraseLine()
  setCursorPos(0, 3)
  let volumeColor = volumeColor(volume)
  say("Status: " & status & "    | Volume: ", fgGreen, xOffset = 0, shouldEcho = false)
  styledEcho(" ", volumeColor, $volume & "%")

proc drawNowPlayingPlayerUI(nowPlaying: string) =
  when defined(simple):
    stdout.styledWrite(fgCyan, "Now Playing:   ", nowPlaying.truncateMe())


  else:
    # In normal mode, use the existing approach
    stdout.styledWrite(fgCyan, "   Now Playing:  ")
    if terminalSupportsEmoji:
      startingX = "  Now Playing: ".len + 1 # +1 for emoji space
    else:
      startingX = "  Now Playing: ".len + 3 # +3 because "[>]" is 3 chars long

    if not nowPlaying.checkIfTooLongForUI():
      stdout.styledWrite(fgCyan, nowPlaying)

proc updateVolumePlayerUI*(newVolume: int) =
  setCursorPos(24, 3)
  let volumeColor = volumeColor(newVolume)
  when defined(noEmoji):
    stdout.write "  "
  stdout.write " "
  stdout.styledWrite(volumeColor, $newVolume & "% ") #when go from 100 to less
  stdout.flushFile()

proc updateCurrentSongPlayerUI*(songName: string) =
  setCursorPos(0, 2) # Line 2 (below the separator)
  eraseLine()
  setCursorPos(0, 2) #explicit duplicate setting just to be consistent across OSes
  drawNowPlayingPlayerUI(songName)
  stdout.flushFile()

proc updatePlayMutedStatePlayerUI*(status: string) =
  setCursorPos(8, 3)
  stdout.styledWrite(fgGreen, status)
  when defined(noEmoji):
    stdout.write " "
  stdout.write " "
  stdout.flushFile()

proc drawPlayerUIInternal(section, nowPlaying, status: string, volume: int) =
  ## Internal function that handles the common logic for drawing and updating the player UI.
  menuui.updateTermWidth() # Ensure the terminal width is up-to-date

  # Clear the screen and reset cursor position
  clear()

  # Draw header if section is provided
  drawHeaderPlayerUI(section)

  # Draw top separator
  drawSeperatorUI(xpos = 1, '-', offset = 0) # Line 1

  # Display "Now Playing" with truncation if necessary
  setCursorPos(0, 2) # Line 2 (below the separator)
  eraseLine()
  drawNowPlayingPlayerUI(nowPlaying)

  # Display status and volume on the same line
  drawStatusAndVolumePlayerUI(status, volume)

  # Draw separator after status/volume
  drawSeperatorUI(xpos = 4, '-', offset = 0) # Line 4

  # Display footer options
  setCursorPos(0, 5) # Line 5
  let footerOptions = "[P] Pause/Play   [V] Adjust Volume   [Q] Quit"
  say(footerOptions, fgYellow, xOffset = (termWidth - footerOptions.len) div 2)

  # Draw the bottom border
  drawSeperatorUI(xpos = 6, offset = 0)

#leftover from updatePlayerUI
  # Reset scrollOffset when a new song starts
  #when not defined(simple):
  #  scrollOffset = 0

proc drawPlayerUI*(section, nowPlaying, status: string, volume: int) =
  ## Draws the modern music player UI with dynamic layout and visual enhancements.
  clear()
  drawPlayerUIInternal(section, nowPlaying, status, volume)

