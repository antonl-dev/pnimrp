# SPDX-License-Identifier: MPL-2.0
const win32 =
    static:
        defined(windows)

when win32:
    const
        NULL_DEVICE = "NUL"
        TERMINAL_DEVICE = "CON"
else:
    const
        NULL_DEVICE = "/dev/null"
        TERMINAL_DEVICE = "/dev/tty"

type StderrState* = object
    originalStderrFd: cint

template error(str: cstring) = stderr.writeLine str

when win32:
    {.push header: "<io.h>".}
    proc c_dup(fd: cint): cint {.importc: "_dup".}
    proc c_dup2(oldfd, newfd: cint): cint {.importc: "_dup2".}
    proc c_fileno(stream: File): cint {.importc: "_fileno".}
    proc c_close(fd: cint): cint {.importc: "_close".}
    {.pop.}
else:
    {.push header: "<unistd.h>".}
    proc c_dup(fd: cint): cint {.importc: "dup".}
    proc c_dup2(oldfd, newfd: cint): cint {.importc: "dup2".}
    proc c_fileno(stream: File): cint {.importc: "fileno".}
    proc c_close(fd: cint): cint {.importc: "close".}
    {.pop.}

{.push header: "<stdio.h>".}
proc c_freopen(filename: cstring, mode: cstring, stream: File): File {.importc: "freopen".}
{.pop.}

template checkError(status: cint) =
    if status == -1:
        error "error!"
        quit(QuitFailure)

template cE(status: cint) =
    checkError(status)

proc initSuppressStderr*(state: var StderrState) =
    state.originalStderrFd = c_dup(c_fileno(stderr))

    if state.originalStderrFd == -1:
        error("failed to save original stderr")
        quit(QuitFailure)

    if c_freopen(NULL_DEVICE, "w", stderr) == nil:
        error("failed to suppress stderr")
        quit(QuitFailure)

proc restoreStderr*(state: var StderrState) =
    flushFile(stderr)

    if c_dup2(state.originalStderrFd, c_fileno(stderr)) == -1:
        error("failed to restore stderr")
        quit(QuitFailure)

    cE c_close(state.originalStderrFd)

    if c_freopen(TERMINAL_DEVICE, "w", stderr) == nil:
        error("failed to reopen stderr")
        stdout.write "using stdout as fallback for stderr"

        cE c_dup2(c_fileno(stdout), c_fileno(stderr))

when isMainModule:
    var state: StderrState
    echo("this goes to stdout")

    state.initSuppressStderr()
    stderr.writeLine "this would go to stderr, but its suppressed"
    state.restoreStderr()

    stderr.writeLine "this goes to stderr after restoration"
