# SPDX-License-Identifier: MPL-2.0
import
  times, terminal, tables,

  ../audio/mpv/libmpv

type
  QuoteData* = object
    quotes*: seq[string]
    authors*: seq[string]

  UIError* = object of CatchableError
  JSONParseError* = object of UIError
  FileNotFoundError* = object of UIError
  ValidationError* = object of UIError
  InvalidDataError* = object of UIError

  MenuOptions* = seq[string]

type
  LinkStatus* = enum
    lsChecking, lsValid, lsInvalid, lsUnknown

type
  MenuError* = object of CatchableError  # Custom error type for menu-related issues
  PlayerState* = object                   # Structure to hold the player's current state
    isPaused*: bool                       # Whether the player is paused
    isMuted*: bool                        # Whether the player is muted
    currentSong*: string                  # Currently playing song
    volume*: int                          # Current volume level

  MenuConfig* = object                    # Configuration for the menu and player
    ctx*: ptr Handle                      # Player handle
    currentSection*: string               # Current menu section
    currentSubsection*: string            # Current menu subsection
    stationName*: string                  # Name of the selected station
    stationUrl*: string                   # URL of the selected station

const
  CheckIdleInterval* = 25 # Interval to check if the player is idle
  KeyTimeout* = 25        # Timeout for key input in milliseconds

type
  Theme* = object
    header*:       ForegroundColor
    separator*:    ForegroundColor
    menu*:         ForegroundColor
    footer*:       ForegroundColor
    error*:        ForegroundColor
    warning*:      ForegroundColor
    success*:      ForegroundColor
    nowPlaying*:   ForegroundColor
    volumeLow*:    ForegroundColor
    volumeMedium*: ForegroundColor
    volumeHigh*:   ForegroundColor

type
  AnimationFrame* = object
    frame: int
    lastUpdate: DateTime

  PlayerStatus* = enum
    StatusPlaying
    StatusMuted
    StatusPaused
    StatusPausedMuted

#const area

var termWidth* = terminalWidth() ## Tracks the current terminal width.
var lastMenuSeparatorY* {.global.}: int

const
  AsciiFrames* = [$'#', "%"]
  EmojiFrames* = ["🎵", "🎶"]

var
  animationFrame*: int = 0  # Tracks the current frame of the animation
  lastAnimationUpdate*: DateTime = now()  # Tracks the last time the animation was updated

when not defined(simple):
  type
    StatusCache* = object
      sectionName*: string

  type
    ThemeConfig* = object
      themes*: Table[string, Theme]
      currentTheme*: string


  var globalMetadata* {.global.}: Table[string, string]

  # Global variable to store emoji positions.  Each tuple is (x, y).
  var emojiPositions* = newSeqOfCap[(int, int)](32)

# Global variable to hold the current theme
var currentTheme*: Theme

var
  scrollOffset* = 0
  lastWidth* = 0
  startingX* = 0
  scrollCounter* = 0

func milSecToSec(ms: int): float = ms / 1000

const
  MenuChars* = "123456789ABCDEFGHIJKLMOPTVWXYZ"
  AppName* = "Poor Mans Radio Player"
  AppNameShort* = "PNimRP"
  DefaultErrorMsg* = "INVALID CHOICE"
  MinTerminalWidth* = 40
  MaxStationNameLength* = 22
  mpvEventLoopTimeout* = KeyTimeout.milSecToSec()
  RetryTimesWhenStreamInterrupt* = 8
