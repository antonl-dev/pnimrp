# SPDX-License-Identifier: MPL-2.0
import
  terminal, times,

  ../utils/utils,
  ../audio/mpv/player

proc appendToFileReUsable(filen: string, config: MenuConfig, isLike: bool) =
  try:
    let file = open(filen, fmAppend)
    defer: file.close()

    # Append the song and a newline

    file.writeLine(
        getDateStr()  &  " | "  &
        getClockStr() &  " | "  &
        config.currentSection   & " | " &
        config.stationName      & " | " &
      fullMediaTitle
    )
    if isLike:
      cursorDown 5
      warn("Song added to likedSongs.txt")
      cursorUp()
      eraseLine()
      cursorUp 5

  except IOError as e:
    warn("Failed to save song to likedSongs.txt: " & e.msg)

  finally:
    stdout.flushFile()

template appendToLikedSongs*(config: MenuConfig) =
  appendToFileReUsable("likedSongs.txt", config, isLike = true)

template appendToHistory*(config: MenuConfig) =
  appendToFileReUsable("history.txt", config, isLike = false)
