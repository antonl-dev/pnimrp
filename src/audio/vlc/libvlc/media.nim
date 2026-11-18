import base

type meta* = enum
    metaTitle
    meta_Artist
    metaGenre
    metaCopyright
    metaAlbum
    metaTrackNumber
    metaDescription
    metaRating
    metaDate
    metaSetting
    metaURL
    metaLanguage
    metaNowPlaying
    metaPublisher
    metaEncodedBy
    metaArtworkURL
    metaTrackID
    metaTrackTotal
    metaDirector
    metaSeason
    metaEpisode
    metaShowName
    metaActors
    metaAlbumArtist
    metaDiscNumber
    metaDiscTotal

proc mediaGetMeta*(p_md: ptr media, e_meta: meta): cstring
    {.importc: "libvlc_media_get_meta".}


type state* = enum
    NothingSpecial = 0
    Opening
    Buffering
    Playing
    Paused
    Stopped
    Ended
    Error

##  XXX: `libvlc_Buffering` Deprecated value. Check the
## libvlc_MediaPlayerBuffering event to know the
## buffering state of a libvlc_media_player


proc mediaGetState*(p_md: ptr media): state
    {.importc: "libvlc_media_get_state".}

proc mediaRelease*(p_md: ptr media)
    {.importc: "libvlc_media_release".}

proc mediaNewLocation*(p_instance: ptr instance, psz_mrl: cstring): ptr media
    {.importc: "libvlc_media_new_location".}
