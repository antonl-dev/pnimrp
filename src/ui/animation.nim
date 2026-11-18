# SPDX-License-Identifier: MPL-2.0
# animation.nim

import ../utils/utils

import terminal

proc updateJinglingAnimation*(appState: AppState, status: string,
        animationCounter: int): string =
    if animationCounter == 27:
        appState.animationFrame = (appState.animationFrame +
                1) mod 2 #alternate between 0 and 1

    # Determine the animation symbol based on terminal support and player status
    if status == currentStatusEmoji(StatusPlaying,
            appState.terminalSupportsEmoji):
        if appState.terminalSupportsEmoji:
            return EmojiFrames[appState.animationFrame] # Use emoji frames
        else:
            return AsciiFrames[appState.animationFrame] # Use ASCII frames
    else:
        return "" # No animation for other statuses

proc updateAnimationOnly*(appState: AppState, status, currentSong: string,
        animationCounter: int) =
    ## Updates only the animation symbol in the "Now Playing" section.
    ##
    ## Args:
    ##   appState: The application state.
    ##   status: The player status (e.g., "🔊" for playing).
    ##   currentSong: The currently playing song.
    ##   animationCounter: The current counter value (incremented every 25ms).
    let animationSymbol = appState.updateJinglingAnimation(status,
            animationCounter) # Get the animation symbol

    # Move the cursor to the start of the "Now Playing" line (line 2)
    setCursorPos(0, 2)

    # Write ONLY the animation symbol and 3 spaces, then erase to the end of the line
    stdout.styledWrite(fgCyan, animationSymbol)
    stdout.flushFile()
