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

proc audioEqualizerNew*(): ptr equalizer
    {.importc: "libvlc_audio_equalizer_new".}

proc audioEqualizerRelease*(p_equalizer: ptr equalizer)
    {.importc: "libvlc_audio_equalizer_release".}

proc audioEqualizerSetPreamp*(p_equalizer: ptr equalizer, f_preamp: cfloat): cint
    {.importc: "libvlc_audio_equalizer_set_preamp".}

proc audioEqualizerGetPreamp*(p_equalizer: ptr equalizer): cfloat
    {.importc: "libvlc_audio_equalizer_get_preamp".}

proc audioEqualizerSetAmpAtIndex*(p_equalizer: ptr equalizer, f_amp: cfloat, u_band: cuint): cint
    {.importc: "libvlc_audio_equalizer_set_amp_at_index".}

proc audioEqualizerGetAmpAtIndex*(p_equalizer: ptr equalizer, u_band: cuint): cfloat
    {.importc: "libvlc_audio_equalizer_get_amp_at_index".}

proc mediaPlayerSetEqualizer*(p_mi: ptr mediaPlayer, p_equalizer: ptr equalizer): cint
    {.importc: "libvlc_media_player_set_equalizer".}

when not defined(nlvm):
    {.pop.}
