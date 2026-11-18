# illwill.nim

## This file is adapted from the original work by John Novak and is licensed under the
## "DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE" (WTFPL).
##
## Original work: https://github.com/johnnovak/illwill
##
## This adaptation is part of a project licensed under the Mozilla Public License 2.0 (MPL-2.0).
## For more details on the MPL-2.0, see: https://www.mozilla.org/en-US/MPL/2.0/
##
## WTFPL License Text:
##
##            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
##                    Version 2, December 2004
##
## Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>
##
## Everyone is permitted to copy and distribute verbatim or modified
## copies of this license document, and changing it is allowed as long
## as the name is changed.
##
##            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
##   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
##
##  0. You just DO WHAT THE FUCK YOU WANT TO.

import terminal
when not defined windows: import unicode, macros, os

template debug*: bool =
    not(
        defined(release) or
        defined(danger)
    ) or
    defined(debug)

type
    Key* {.pure.} = enum       #Supported single key presses and key combinations
        None = (-1, "None"),

        # Special ASCII characters
        CtrlA = (1, "CtrlA"),
        CtrlB = (2, "CtrlB"),
        CtrlC = (3, "CtrlC"),
        CtrlD = (4, "CtrlD"),
        CtrlE = (5, "CtrlE"),
        CtrlF = (6, "CtrlF"),
        CtrlG = (7, "CtrlG"),
        CtrlH = (8, "CtrlH"),
        Tab = (9, "Tab"),      # Ctrl-I
        CtrlJ = (10, "CtrlJ"),
        CtrlK = (11, "CtrlK"),
        CtrlL = (12, "CtrlL"),
        Enter = (13, "Enter"), # Ctrl-M
        CtrlN = (14, "CtrlN"),
        CtrlO = (15, "CtrlO"),
        CtrlP = (16, "CtrlP"),
        CtrlQ = (17, "CtrlQ"),
        CtrlR = (18, "CtrlR"),
        CtrlS = (19, "CtrlS"),
        CtrlT = (20, "CtrlT"),
        CtrlU = (21, "CtrlU"),
        CtrlV = (22, "CtrlV"),
        CtrlW = (23, "CtrlW"),
        CtrlX = (24, "CtrlX"),
        CtrlY = (25, "CtrlY"),
        CtrlZ = (26, "CtrlZ"),
        Escape = (27, "Escape"),

        CtrlBackslash = (28, "CtrlBackslash"),
        CtrlRightBracket = (29, "CtrlRightBracket"),

        # Printable ASCII characters
        Space = (32, "Space"),
        ExclamationMark = (33, "ExclamationMark"),
        DoubleQuote = (34, "DoubleQuote"),
        Hash = (35, "Hash"),
        Dollar = (36, "Dollar"),
        Percent = (37, "Percent"),
        Ampersand = (38, "Ampersand"),
        SingleQuote = (39, "SingleQuote"),
        LeftParen = (40, "LeftParen"),
        RightParen = (41, "RightParen"),
        Asterisk = (42, "Asterisk"),
        Plus = (43, "Plus"),
        Comma = (44, "Comma"),
        Minus = (45, "Minus"),
        Dot = (46, "Dot"),
        Slash = (47, "Slash"),

        Zero = (48, "Zero"),
        One = (49, "One"),
        Two = (50, "Two"),
        Three = (51, "Three"),
        Four = (52, "Four"),
        Five = (53, "Five"),
        Six = (54, "Six"),
        Seven = (55, "Seven"),
        Eight = (56, "Eight"),
        Nine = (57, "Nine"),

        Colon = (58, "Colon"),
        Semicolon = (59, "Semicolon"),
        LessThan = (60, "LessThan"),
        Equals = (61, "Equals"),
        GreaterThan = (62, "GreaterThan"),
        QuestionMark = (63, "QuestionMark"),
        At = (64, "At"),

        ShiftA = (65, "ShiftA"),
        ShiftB = (66, "ShiftB"),
        ShiftC = (67, "ShiftC"),
        ShiftD = (68, "ShiftD"),
        ShiftE = (69, "ShiftE"),
        ShiftF = (70, "ShiftF"),
        ShiftG = (71, "ShiftG"),
        ShiftH = (72, "ShiftH"),
        ShiftI = (73, "ShiftI"),
        ShiftJ = (74, "ShiftJ"),
        ShiftK = (75, "ShiftK"),
        ShiftL = (76, "ShiftL"),
        ShiftM = (77, "ShiftM"),
        ShiftN = (78, "ShiftN"),
        ShiftO = (79, "ShiftO"),
        ShiftP = (80, "ShiftP"),
        ShiftQ = (81, "ShiftQ"),
        ShiftR = (82, "ShiftR"),
        ShiftS = (83, "ShiftS"),
        ShiftT = (84, "ShiftT"),
        ShiftU = (85, "ShiftU"),
        ShiftV = (86, "ShiftV"),
        ShiftW = (87, "ShiftW"),
        ShiftX = (88, "ShiftX"),
        ShiftY = (89, "ShiftY"),
        ShiftZ = (90, "ShiftZ"),

        LeftBracket = (91, "LeftBracket"),
        Backslash = (92, "Backslash"),
        RightBracket = (93, "RightBracket"),
        Caret = (94, "Caret"),
        Underscore = (95, "Underscore"),
        GraveAccent = (96, "GraveAccent"),

        A = (97, "A"),
        B = (98, "B"),
        C = (99, "C"),
        D = (100, "D"),
        E = (101, "E"),
        F = (102, "F"),
        G = (103, "G"),
        H = (104, "H"),
        I = (105, "I"),
        J = (106, "J"),
        K = (107, "K"),
        L = (108, "L"),
        M = (109, "M"),
        N = (110, "N"),
        O = (111, "O"),
        P = (112, "P"),
        Q = (113, "Q"),
        R = (114, "R"),
        S = (115, "S"),
        T = (116, "T"),
        U = (117, "U"),
        V = (118, "V"),
        W = (119, "W"),
        X = (120, "X"),
        Y = (121, "Y"),
        Z = (122, "Z"),

        LeftBrace = (123, "LeftBrace"),
        Pipe = (124, "Pipe"),
        RightBrace = (125, "RightBrace"),
        Tilde = (126, "Tilde"),
        Backspace = (127, "Backspace"),

        # Special characters with virtual keycodes
        Up = (1001, "Up"),
        Down = (1002, "Down"),
        Right = (1003, "Right"),
        Left = (1004, "Left"),
        Home = (1005, "Home"),
        Insert = (1006, "Insert"),
        Delete = (1007, "Delete"),
        End = (1008, "End"),
        PageUp = (1009, "PageUp"),
        PageDown = (1010, "PageDown"),

        F1 = (1011, "F1"),
        F2 = (1012, "F2"),
        F3 = (1013, "F3"),
        F4 = (1014, "F4"),
        F5 = (1015, "F5"),
        F6 = (1016, "F6"),
        F7 = (1017, "F7"),
        F8 = (1018, "F8"),
        F9 = (1019, "F9"),
        F10 = (1020, "F10"),
        F11 = (1021, "F11"),
        F12 = (1022, "F12"),

        Mouse = (5000, "Mouse")

    IllwillError* = object of CatchableError

func turnOffWarningForOldCompiler*(v: string): bool =
    v notin ["1.4.0", "1.4.2", "1.4.4", "1.4.6", "1.4.8"]

when turnOffWarningForOldCompiler(NimVersion):
    {.push warning[HoleEnumConv]: off.}

func toKey*(c: int): Key =
    try:
        result = Key(c)
    except RangeDefect: # ignore unknown keycodes
        result = Key.None

when turnOffWarningForOldCompiler(NimVersion):
    {.pop.}

var gIllwillInitialised = false
var gFullScreen = false
when not defined windows:
    var gFullRedrawNextFrame = false

when defined(windows):
    using ms: int32

    import winlean

    proc getConsoleMode(hConsoleHandle: Handle,
            dwMode: ptr DWORD): WINBOOL {.stdcall, dynlib: "kernel32",
            importc: "GetConsoleMode".}

    proc setConsoleMode(hConsoleHandle: Handle,
            dwMode: DWORD): WINBOOL {.stdcall, dynlib: "kernel32",
            importc: "SetConsoleMode".}

    type
        WCHAR = WinChar
        CHAR = char
        BOOL = WINBOOL
        WORD = uint16
        UINT = cint
        SHORT = int16

    # Windows console input structuress
    type
        KEY_EVENT_RECORD_UNION* {.bycopy, union.} = object
            UnicodeChar*: WCHAR
            AsciiChar*: CHAR

        INPUT_RECORD_UNION* {.bycopy, union.} = object
            KeyEvent*: KEY_EVENT_RECORD
            MenuEvent*: MENU_EVENT_RECORD
            FocusEvent*: FOCUS_EVENT_RECORD

        COORD* {.bycopy.} = object
            X*: SHORT
            Y*: SHORT

        PCOORD* = ptr COORD
        FOCUS_EVENT_RECORD* {.bycopy.} = object
            bSetFocus*: BOOL

        MENU_EVENT_RECORD* {.bycopy.} = object
            dwCommandId*: UINT

        PMENU_EVENT_RECORD* = ptr MENU_EVENT_RECORD

        INPUT_RECORD* {.bycopy.} = object
            EventType*: WORD
            Event*: INPUT_RECORD_UNION

    const
        ENABLE_WRAP_AT_EOL_OUTPUT = 0x0002

    var gOldConsoleModeInput: DWORD
    var gOldConsoleMode: DWORD

    proc consoleInit =
        discard getConsoleMode(getStdHandle(STD_INPUT_HANDLE),
                gOldConsoleModeInput.addr)
        if gFullScreen:
            if getConsoleMode(getStdHandle(STD_OUTPUT_HANDLE),
                    gOldConsoleMode.addr) != 0:
                var mode = gOldConsoleMode and (not ENABLE_WRAP_AT_EOL_OUTPUT)
                discard setConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), mode)
        else:
            discard getConsoleMode(getStdHandle(STD_OUTPUT_HANDLE),
                    gOldConsoleMode.addr)

    proc consoleDeinit =
        if gOldConsoleMode != 0:
            discard setConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), gOldConsoleMode)


    proc getchTimeout(ms): KEY_EVENT_RECORD =
        let fd = getStdHandle(STD_INPUT_HANDLE)
        var keyEvent = KEY_EVENT_RECORD()
        var numRead: cint
        while true:
            case waitForSingleObject(fd, ms)
            of WAIT_TIMEOUT:
                keyEvent.eventType = -1
                return
            of WAIT_OBJECT_0:
                doAssert(readConsoleInput(fd, addr(keyEvent), 1, addr(
                        numRead)) != 0)
                if numRead == 0 or keyEvent.eventType != 1 or
                        keyEvent.bKeyDown == 0:
                    continue
                return keyEvent
            else:
                doAssert(false)

    proc getKeyAsync(ms): Key =
        let event = getchTimeout(int32(ms))

        if event.eventType == -1:
            return Key.None

        if event.uChar != 0:
            return toKey(event.uChar)
        else:
            case event.wVirtualScanCode
            of 8: return Key.Backspace
            of 9: return Key.Tab
            of 13: return Key.Enter
            of 32: return Key.Space
            of 59: return Key.F1
            of 60: return Key.F2
            of 61: return Key.F3
            of 62: return Key.F4
            of 63: return Key.F5
            of 64: return Key.F6
            of 65: return Key.F7
            of 66: return Key.F8
            of 67: return Key.F9
            of 68: return Key.F10
            of 71: return Key.Home
            of 72: return Key.Up
            of 73: return Key.PageUp
            of 75: return Key.Left
            of 77: return Key.Right
            of 79: return Key.End
            of 80: return Key.Down
            of 81: return Key.PageDown
            of 82: return Key.Insert
            of 83: return Key.Delete
            of 87: return Key.F11
            of 88: return Key.F12
            else: return Key.None

else: # OS X & Linux
    using ms: int
    import posix, tables, termios, strutils

    proc consoleInit()
    proc consoleDeinit()

    # References:
    # https://de.wikipedia.org/wiki/ANSI-Escapesequenz
    # https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Extended-coordinates
    const
        KEYS_D = [Key.Up, Key.Down, Key.Right, Key.Left, Key.None, Key.End,
                Key.None, Key.Home]
        KEYS_E = [Key.Delete, Key.End, Key.PageUp, Key.PageDown, Key.Home, Key.End]
        KEYS_F = [Key.F1, Key.F2, Key.F3, Key.F4, Key.F5, Key.None, Key.F6,
                Key.F7, Key.F8]
        KEYS_G = [Key.F9, Key.F10, Key.None, Key.F11, Key.F12]

    # Adapted from:
    # https://ftp.gnu.org/old-gnu/Manuals/glibc-2.2.3/html_chapter/libc_24.html#SEC499
    proc SIGTSTP_handler(sig: cint) {.noconv.} =
        signal(SIGTSTP, SIG_DFL)
        # XXX why don't the below 3 lines seem to have any effect?
        resetAttributes()
        showCursor()
        consoleDeinit()
        discard posix.raise(SIGTSTP)

    proc SIGCONT_handler(sig: cint) {.noconv.} =
        signal(SIGCONT, SIGCONT_handler)
        signal(SIGTSTP, SIGTSTP_handler)

        gFullRedrawNextFrame = true
        consoleInit()
        hideCursor()

    proc installSignalHandlers =
        signal(SIGCONT, SIGCONT_handler)
        signal(SIGTSTP, SIGTSTP_handler)

    proc nonblock(enabled: bool) =
        var ttyState: Termios

        # get the terminal state
        discard tcGetAttr(STDIN_FILENO, ttyState.addr)

        if enabled:
            # turn off canonical mode & echo
            ttyState.c_lflag = ttyState.c_lflag and not Cflag(ICANON or ECHO)

            # minimum of number input read
            ttyState.c_cc[VMIN] = 0.char

        else:
            # turn on canonical mode & echo
            ttyState.c_lflag = ttyState.c_lflag or ICANON or ECHO

        # set the terminal attributes.
        discard tcSetAttr(STDIN_FILENO, TCSANOW, ttyState.addr)

    proc kbhit(ms): cint =
        var tv: Timeval
        tv.tv_sec = Time(ms div 1000)
        tv.tv_usec = 1000 * (int32(ms) mod 1000) # int32 because of macos

        var fds: TFdSet
        FD_ZERO(fds)
        FD_SET(STDIN_FILENO, fds)
        discard select(STDIN_FILENO+1, fds.addr, nil, nil, tv.addr)
        return FD_ISSET(STDIN_FILENO, fds)

    proc consoleInit =
        nonblock(true)
        installSignalHandlers()

    proc consoleDeinit =
        nonblock(false)

    # surely a 100 char buffer is more than enough; the longest
    # keycode sequence I've seen was 6 chars
    proc parseStdin[T](input: T): Key =
        var ch1, ch2, ch3, ch4, ch5: char
        result = Key.None
        if read(input, ch1.addr, 1) > 0:
            case ch1
            of '\e':
                if read(input, ch2.addr, 1) > 0:
                    if ch2 == 'O' and read(input, ch3.addr, 1) > 0:
                        if ch3 in "ABCDFH":
                            result = KEYS_D[int(ch3) - int('A')]
                        elif ch3 in "PQRS":
                            result = KEYS_F[int(ch3) - int('P')]
                    elif ch2 == '[' and read(input, ch3.addr, 1) > 0:
                        if ch3 in "ABCDFH":
                            result = KEYS_D[int(ch3) - int('A')]
                        elif ch3 in "PQRS":
                            result = KEYS_F[int(ch3) - int('P')]
                        elif ch3 == '1' and read(input, ch4.addr, 1) > 0:
                            if ch4 == '~':
                                result = Key.Home
                            elif ch4 in "12345789" and read(input, ch5.addr,
                                    1) > 0 and ch5 == '~':
                                result = KEYS_F[int(ch4) - int('1')]
                        elif ch3 == '2' and read(input, ch4.addr, 1) > 0:
                            if ch4 == '~':
                                result = Key.Insert
                            elif ch4 in "0134" and read(input, ch5.addr, 1) >
                                    0 and ch5 == '~':
                                result = KEYS_G[int(ch4) - int('0')]
                        elif ch3 in "345678" and read(input, ch4.addr, 1) >
                                0 and ch4 == '~':
                            result = KEYS_E[int(ch3) - int('3')]
                        else:
                            discard # if cannot parse full seq it is discarded
                    else:
                        discard # if cannot parse full seq it is discarded
                else:
                    result = Key.Escape
            of '\n':
                result = Key.Enter
            of '\b':
                result = Key.Backspace
            else:
                result = toKey(int(ch1))

    proc getKeyAsync(ms: int): Key =
        result = Key.None
        if kbhit(ms) > 0:
            result = parseStdin(cint(STDIN_FILENO))

when defined(posix):
    const
        XtermColor = "xterm-color"
        Xterm256Color = "xterm-256color"

proc enterFullScreen =
    ## Enters full-screen mode (clears the terminal).
    when defined(posix):
        case getEnv("TERM"):
        of XtermColor:
            stdout.write "\e7\e[?47h"
        of Xterm256Color:
            stdout.write "\e[?1049h"
        else:
            eraseScreen()
    else:
        eraseScreen()

proc exitFullScreen =
    ## Exits full-screen mode (restores the previous contents of the terminal).
    when defined(posix):
        case getEnv("TERM"):
        of XtermColor:
            stdout.write "\e[2J\e[?47l\e8"
        of Xterm256Color:
            stdout.write "\e[?1049l"
        else:
            eraseScreen()
    else:
        eraseScreen()
        setCursorPos(0, 0)

proc illwillInit*(fullScreen = true) =
    if gIllwillInitialised:
        raise newException(IllwillError, "Illwill already initialised")
    gFullScreen = fullScreen
    if gFullScreen: enterFullScreen()

    consoleInit()
    gIllwillInitialised = true
    resetAttributes()

proc checkInit =
    if not gIllwillInitialised:
        raise newException(IllwillError, "Illwill not initialised")

proc illwillDeinit* =
    when debug:
        checkInit()
    if gFullScreen: exitFullScreen()
    consoleDeinit()
    gIllwillInitialised = false
    resetAttributes()
    showCursor()

proc getKey*: Key =
    ## Reads the next keystroke in a non-blocking manner. If there are no
    ## keypress events in the buffer, `Key.None` is returned.
    ## If the module is not intialised, `IllwillError` is raised.
    when debug:
        checkInit()
    result = getKeyAsync(0)
    when defined(windows):
        if result == Key.None: discard

proc getKeyWithTimeout*(ms = 1000): Key =
    ## Reads the next keystroke with a timeout. If there were no keypress events
    ## in the specified `ms` period, `Key.None` is returned.
    ##
    ## If the module is not intialised, `IllwillError` is raised.
    when debug:
        checkInit()
    result = getKeyAsync(int32 ms)
    when defined(windows):
        if result == Key.None: discard

export
    terminalWidth, terminalHeight,
    terminalSize, hideCursor, showCursor,
    Style
