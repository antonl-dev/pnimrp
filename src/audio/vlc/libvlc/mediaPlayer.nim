import base, media

when not defined(nlvm):
    {.push dynlib: dynlibName.}

proc mediaPlayerPlay*(p_mi: ptr mediaPlayer): cint
    {.importc: "libvlc_media_player_play".}

proc mediaPlayerPause*(p_mi: ptr mediaPlayer)
    {.importc: "libvlc_media_player_pause".}

proc audioSetVolume*(p_mi: ptr mediaPlayer, i_volume: cint): cint
    {.importc: "libvlc_audio_set_volume".}

proc audioGetVolume*(p_mi: ptr mediaPlayer): cint
    {.importc: "libvlc_audio_get_volume".}

proc mediaPlayerStop*(p_mi: ptr mediaPlayer)
    {.importc: "libvlc_media_player_stop".}

proc mediaPlayerGetState*(p_mi: ptr mediaPlayer): state
    {.importc: "libvlc_media_player_get_state".}

proc mediaPlayerIsPlaying*(p_mi: ptr mediaPlayer): cint
    {.importc: "libvlc_media_player_is_playing".}

proc mediaPlayerRelease*(p_mi: ptr mediaPlayer)
    {.importc: "libvlc_media_player_release".}

proc mediaPlayerNewFromMedia*(p_md: ptr media): ptr mediaPlayer
    {.importc: "libvlc_media_player_new_from_media".}

when not defined(nlvm):
    {.pop.}
