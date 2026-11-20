type
    instance* = distinct object
    media* = distinct object
    mediaPlayer* = distinct object
    equalizer* = distinct object

const dynlibName* =
    when defined(windows): "libvlc.dll"
    elif defined(macosx): "libvlc(|.5|.6).dylib"
    else: "libvlc.so(|.5|.6)"
