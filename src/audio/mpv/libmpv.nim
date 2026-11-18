# SPDX-License-Identifier: MPL-2.0
# libmpv.nim

##[
This module binds libmpv's client.h which is used to play streams.

.. warning::
  - module does NOT wrap deprecated functions.

.. note::
  - this module renames procedures to camelCase (e.g., sdl2 module)
  - please refer to official documentation available in mpv/client.h for
    most information
  - Cites and Tools Used:
    - c2nim -> wrapped most of objects
  - order of code:
    - templates > consts > types > procedures

Imports
-------
* terminal
  - showCursor

Type Context
------------
.. code-block:: nim
  - ctx: ptr Handle
  - replyUserData, error: cint
  - argsArr: cstringArray
  - result, Node: ptr Node
  - argsStr, name: cstring
  - data: pointer
  - format: format

Terms Used
----------
- libmpv > official mpv documentation
- isStaticConst > it returns static const string
     (needless of dealloc() & is always valid)
     !!making static is not implemented yet!!
]##

const dynlibName =
    when defined(windows): "mpv-(1|2|3).dll"
    elif defined(macosx): "libmpv(|.1|.2|.3).dylib"
    else: "libmpv.so(|.1|.2|.3)"

when not defined(nlvm):
    {.push dynlib: dynlibName.}

# Templates
template makePackedVersion*(major, minor: untyped): untyped =
    major shl 16 or minor or 0'u32 ##[
   version is incremented on each change, minor = 16 lower bits, major = 16
   higher bits. when api becomes incompatible with previous, major is
   incremented, affecting only C parts and not properties and options
   (see libmpv/docs/client-api-changes.rst for changelog)
]##

template getUnpackedVersionComponents*(version: untyped): untyped = #:tuple[num, num]
    ## gets major and minor components from a version number
    ((version shr 16) and 0xFFFF'u32,
        version and 0xFFFF'u32)

#constants
#let clientApiVersion* = { defined at bottom (stupid compiler)}

# Types
type
    Error* = enum                     ## Error codes returned by API procedures
        errGeneric = -20,             ## Unspecified error
        errNotImplemented = -19,      ## Procedure called was stub-only
        errUnsupported = -18,         ## (Was system requirements met?)
        errUnknownFormat = -17,       ## File format could not be determined
        errNothingToPlay = -16,       ## No video/audio to play
        errVOInitFailed = -15,        ## Failed to init video output
        errAOInitFailed = -14,        ## Failed to init audio output
        errLoadFailed = -13,          ## Loading failed (used with EventEndFile.error)
        errCmd = -12,                 ## Error when running a command with cmd()
        errOnProperty = -11,          ## Error when setting or getting property
        errPropertyUnavailable = -10, ## Property exists but is unavailable
        errPropertyFormat = -9,       ## Set or get property using unsupported format
        errPropertyNotFound = -8,     ## Said property not found
        errOnOption = -7,             ## Setting option failed (parsing errors?)
        errOptionFormat = -6,         ## Set option using unsupported format
        errOptionNotFound = -5,       ## Set option that doesn't exist
        errInvalidParameter = -4,     ## Error when parameter is invalid or unsupported
        errUninitialized = -3,        ## API wasn't initialized yet
        errNoMem = -2,                ## Memory allocation failed
        errEventQueueFull = -1,       ## Client is choked & can't receive any Events
        errSuccess = 0                ## No error occurred, '>= 0' means success

    Format* = enum ## Type for options and properties, can get/set properties and options
        fmtNone = 0,      ## Invalid, used for empty values
        fmtString = 1,    ## Basic type is cstring
        fmtOSDString = 2, ## Basic type is cstring, returns OSD property string
        fmtFlag = 3,      ## Basic type is cint, allowed values are 0=no and 1=yes
        fmtInt64 = 4,     ## Basic type is int64
        fmtFloat64 = 5,   ## Basic type is float64
        fmtNode = 6,      ## Type is Node
        fmtNodeArray = 7, ## Used with Node (not directly!)
        fmtNodeMap = 8,   ## See formatNodeArray
        fmtByteArray = 9  ## Raw, untyped byteArray, used with Node

    EventID* = enum                 ## Event type
        IDNone = 0,                 ## Nothing happened
        IDShutdown = 1,             ## When player quits
        IDLogMessage = 2,           ## See requestLogMessages()
        IDGetPropertyReply = 3,     ## Reply to getPropertyAsync()
        IDSetPropertyReply = 4,     ## Reply to setPropertyAsync()
        IDCommandReply = 5,         ## Reply to commandAsync() or commandNodeAsync()
        IDStartFile = 6,            ## Notification before playback start of file
        IDEndFile = 7,              ## Notification after playback ends
        IDFileLoaded = 8,           ## Notification when file has been loaded
        IDClientMessage = 16,       ## Triggered by script-message input command
        IDVideoReConfig = 17,       ## Happens when video gets changed
        IDAudioReConfig = 18,       ## Similar as EventIDVideoReConfig
        IDSeek = 20,                ## Happens when a seek was initiated
        IDPlayBackRestart = 21,     ## There was discontinuity like a seek
        IDEventPropertyChange = 22, ## Event sent due to observeProperty()
        IDQueueOverFlow = 24,       ## Happens if internal Handle ringBuffer OverFlows
        IDEventHook = 25            ## Triggered if hook Handler was registered

    EndFileReason* = enum ## End file reason enum
        efrEOF = 0,       ## Reaching end of file
        efrStop = 2,      ## External action (controls?)
        efrQuit = 3,      ## Quitted
        efrError = 4,     ## Some error made it stop
        efrReDirect = 5   ## Playlist endofFile redirect mechanism

    LogLevel* = enum  ## Enum describing log level verbosity
        llNone = 0,   ## No messages, never used when receiving messages
        llFatal = 10, ## Fatal/abortive errors
        llError = 20, ## Simple errors
        llWarn = 30,  ## Possible problem warnings
        llInfo = 40,  ## Info
        llV = 50,     ## Noisy info
        llDebug = 60, ## More noisy verbose info
        llTrace = 70  ## Extremely verbose

    Handle* = distinct object ## Basic type, used by API to infer the context

{.push bycopy.}
type
    ClientUnionType* {.union.} = object
        str*: cstring
        flag*, int*: cint
        double*: cdouble
        list*: ptr NodeList
        ba*: ptr ByteArray

    Node* = object
        u*: ClientUnionType
        format*: Format

    NodeList* = object
        num*: cint
        values*: ptr Node
        keys*: cstringArray

    ByteArray* = object
        data*: pointer
        size*: csize_t

    EventProperty* = object
        name*: cstring
        format*: Format
        data*: pointer

    EventLogMessage* = object
        prefix*, level*, text*: cstring
        logLevel*: LogLevel

    EventEndFile* = object
        reason*, error*: cint

    EventClientMessage* = object
        numArgs*: cint
        args*: cstringArray

    EventHook* = object
        name*: cstring
        id*: cint

    EventCmd* = object
        result*: Node

    Event* = object
        eventID*: EventID
        error*: int
        replyUserData*: uint64
        data*: pointer

{.pop.}

# Procedures
using
    ctx: ptr Handle
    replyUserData: uint64
    error: cint
    argsArr: cstringArray
    result, node: ptr Node
    argsStr, name: cstring
    data: pointer
    fmt: Format

proc abortAsyncCmd*(ctx; replyUserData)
    {.importc: "mpv_abort_async_command".}

proc cmd*(ctx; argsArr): cint
    {.importc: "mpv_command".}

proc cmdAsync*(ctx; replyUserData; argsArr): cint
    {.importc: "mpv_command_async".}

proc cmdNode*(ctx; argsArr; result): cint
    {.importc: "mpv_command_node".}

proc cmdNodeAsync*(ctx; replyUserData; result): cint
    {.importc: "mpv_command_node_async".}

proc cmdRet*(ctx; argsArr; result): cint
    {.importc: "mpv_command_ret".}

proc cmdString*(ctx; argsStr): cint
    {.importc: "mpv_command_string".}

proc create*: ptr Handle
    {.importc: "mpv_create".}

proc createClient*(ctx; name): ptr Handle
    {.importc: "mpv_create_client".}

proc createWeakClient*(ctx; name): ptr Handle
    {.importc: "mpv_create_weak_client".}

proc destroy*(ctx)
    {.importc: "mpv_destroy".}

proc errorString*(error): cstring
    {.importc: "mpv_error_string".}

proc eventName*(event: EventID): cstring
    {.importc: "mpv_event_name".}

proc free*(data)
    {.importc: "mpv_free".}

proc freeNodeContents*(node)
    {.importc: "mpv_free_node_contents".}

proc getClientApiVersion*: culong
    {.importc: "mpv_client_api_version".}

proc getClientName*(ctx): cstring
    {.importc: "mpv_client_name".}

proc getProperty*(ctx; name; fmt; data): cint
    {.importc: "mpv_get_property".}

proc getPropertyAsync*(ctx; replyUserData; name; fmt): cint
    {.importc: "mpv_get_property_async".}

proc getPropertyOSDString*(ctx; name): cstring
    {.importc: "mpv_get_property_osd_string".}

proc getPropertyString*(ctx; name): cstring
    {.importc: "mpv_get_property_string".}

proc getTimeUS*(ctx): cint
    {.importc: "mpv_get_time_us".}

proc hookAdd*(ctx; replyUserData; name; priority: cint): cint
    {.importc: "mpv_hook_add".}

proc hookContinue*(ctx; id: cint): cint
    {.importc: "mpv_hook_continue".}

proc initialize*(ctx): cint
    {.importc: "mpv_initialize".}

proc loadConfigFile*(ctx; filename: cstring): cint
    {.importc: "mpv_load_config_file".}

proc observeProperty*(ctx; replyUserData; name; fmt): cint
    {.importc: "mpv_observe_property".}

proc requestEvent*(ctx; event: EventID; enable: cint): cint
    {.importc: "mpv_request_event".}

proc requestLogMsgs*(ctx; minLevel: cstring): cint
    {.importc: "mpv_request_log_messages".}

proc setOption*(ctx; name; fmt; data): cint
    {.importc: "mpv_set_option".}

proc setOptionString*(ctx; name; data: cstring): cint
    {.importc: "mpv_set_option_string".}

proc setProperty*(ctx; name; fmt; data): cint
    {.importc: "mpv_set_property".}

proc setPropertyAsync*(ctx; replyUserData; name; fmt; data): cint
    {.importc: "mpv_set_property_async".}

proc setPropertyString*(ctx; name; data: cstring): cint
    {.importc: "mpv_set_property_string".}

proc setWakeupCallback*(ctx; cb: proc (d: pointer); d: pointer)
    {.importc: "mpv_set_wakeup_callback".}

proc terminateDestroy*(ctx)
    {.importc: "mpv_terminate_destroy".}

proc unobserveProperty*(ctx; registeredReplyUserData: uint64): cint
    {.importc: "mpv_unobserve_property".}

proc waitAsyncRequests*(ctx)
    {.importc: "mpv_wait_async_requests".}

proc waitEvent*(ctx; timeout: cdouble = 0): ptr Event
    {.importc: "mpv_wait_event".}

proc wakeup*(ctx)
    {.importc: "mpv_wakeup".}

func checkError*(status: cint) =
    ## Checks the return value of input procedure, quits with failure exit status if less than 0
    if status < 0:
        raise newException(CatchableError, "mpv API error: " & $errorString(status))

template cE*(s: int) = checkError(s)

when not defined(nlvm):
    {.pop.}

# Constants
let clientApiVersion* = getUnpackedVersionComponents getClientApiVersion()
