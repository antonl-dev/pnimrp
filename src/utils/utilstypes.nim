# SPDX-License-Identifier: MPL-2.0
import
    times, terminal, tables,

    ../audio/mpv/libmpv,
    ../ui/hidestderr

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
    MenuError* = object of CatchableError # Custom error type for menu-related issues
    PlayerState* = object    # Structure to hold the player's current state
        isPaused*: bool      # Whether the player is paused
        isMuted*: bool       # Whether the player is muted
        currentSong*: string # Currently playing song
        volume*: int         # Current volume level

    MenuConfig* = object           # Configuration for the menu and player
        ctx*: ptr Handle           # Player handle
        currentSection*: string    # Current menu section
        currentSubsection*: string # Current menu subsection
        stationName*: string       # Name of the selected station
        stationUrl*: string        # URL of the selected station

const
    CheckIdleInterval* = 25 # Interval to check if the player is idle
    KeyTimeout* = 25        # Timeout for key input in milliseconds

type
    Theme* = object
        header*: ForegroundColor
        separator*: ForegroundColor
        menu*: ForegroundColor
        footer*: ForegroundColor
        error*: ForegroundColor
        warning*: ForegroundColor
        success*: ForegroundColor
        nowPlaying*: ForegroundColor
        volumeLow*: ForegroundColor
        volumeMedium*: ForegroundColor
        volumeHigh*: ForegroundColor

type
    AnimationFrame* = object
        frame: int
        lastUpdate: DateTime

    PlayerStatus* = enum
        StatusPlaying
        StatusMuted
        StatusPaused
        StatusPausedMuted

const
    AsciiFrames* = [$'#', "%"]
    EmojiFrames* = ["🎵", "🎶"]

when not defined(simple):
    type
        StatusCache* = object
            sectionName*: string

    type
        ThemeConfig* = object
            themes*: Table[string, Theme]
            currentTheme*: string

type
    AppState* = ref object
        # Directories and metadata
        assetsDir*: string
        stationsDir*: string
        configDir*: string
        version*: string

        # Audio / MPV state
        mpvCtx*: ptr Handle
        lastVolume*: int
        fullMediaTitle*: string

        # Theme
        theme*: Theme
        when not defined(simple):
            themeConfig*: ThemeConfig

        # Menu navigation state
        chooseForMe*: bool
        lastStationIdx*: int
        currentMenuGen*: int

        # UI and terminal state
        termWidth*: int
        lastTermWidth*: int
        lastMenuSeparatorY*: int
        animationFrame*: int
        lastAnimationUpdate*: DateTime
        startingX*: int
        when not defined(simple):
            emojiPositions*: seq[(int, int)]
            globalMetadata*: Table[string, string]
        terminalSupportsEmoji*: bool
        stderrState*: StderrState

proc newAppState*(
    assetsDir: string = "",
    stationsDir: string = "",
    configDir: string = "",
    version: string = "0.1"
): AppState =
    let curWidth = terminalWidth()
    result = AppState(
      assetsDir: assetsDir,
      stationsDir: stationsDir,
      configDir: configDir,
      version: version,
      lastVolume: 100,
      fullMediaTitle: "",
      chooseForMe: false,
      lastStationIdx: -1,
      currentMenuGen: 0,
      termWidth: curWidth,
      lastTermWidth: curWidth,
      lastMenuSeparatorY: 0,
      animationFrame: 0,
      lastAnimationUpdate: now(),
      startingX: 0,
      terminalSupportsEmoji: (when defined(noEmoji): false else: true)
    )
    when not defined(simple):
        result.emojiPositions = newSeqOfCap[(int, int)](32)
        result.globalMetadata = initTable[string, string]()

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
