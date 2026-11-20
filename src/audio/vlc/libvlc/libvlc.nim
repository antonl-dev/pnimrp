import
    base, media, mediaPlayer

when not defined(nlvm):
    {.push dynlib: dynlibName.}

proc setUserAgent*(p_instance: ptr instance, name: cstring, http: cstring)
    {.importc: "libvlc_set_user_agent".}

proc new*(argc: cint, argv: cstringArray): ptr instance
    {.importc: "libvlc_new".}

proc setAppId*(p_instance: ptr instance, id: cstring, version: cstring, icon: cstring)
    {.importc: "libvlc_set_app_id".}

proc release*(p_instance: ptr instance)
    {.importc: "libvlc_release".}

proc errmsg*(): cstring
    {.importc: "libvlc_errmsg".}

when not defined(nlvm):
    {.pop.}

export #base
    instance, media, mediaPlayer, equalizer, errmsg

export #media
    meta, mediaGetMeta, mediaGetState, mediaRelease, mediaNewLocation,
    state

export #mediaPlayer
    audioSetVolume, audioGetVolume,
    mediaPlayerRelease, mediaPlayerNewFromMedia,
    mediaPlayerPlay, mediaPlayerPause, mediaPlayerStop,
    mediaPlayerGetState,
    mediaPlayerIsPlaying,
    audioEqualizerNew, audioEqualizerRelease,
    audioEqualizerSetPreamp, audioEqualizerGetPreamp,
    audioEqualizerSetAmpAtIndex, audioEqualizerGetAmpAtIndex,
    mediaPlayerSetEqualizer
