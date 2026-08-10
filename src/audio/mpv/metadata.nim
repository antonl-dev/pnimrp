# SPDX-License-Identifier: MPL-2.0
# metadata.nim

import libmpv, ../../utils/utils

import tables, strutils, terminal

# Mapping of common tag names (case-insensitive) to preferred names
const tagMap* = {
  "artist": "Artist",
  "icy-artist": "Artist",
  "title": "Title",
  "icy-name": "Title",
  "icy-title": "Title",
  "genre": "Genre",
  "icy-genre": "Genre",
  "album": "Album",
  "icy-url": "URL",
  "url": "URL",
  "icy-br": "Bitrate",
  "icy-description": "Description",
  "icy-sr": "SampleRate",
  "description": "Description",
  "samplerate": "SampleRate",
  "bitrate": "Bitrate",
  "channels": "Channels",
  "variant_bitrate": "Variant Bitrate",
  "ice-samplerate": "SampleRate",
  "ice-channels": "Channels",
  "ice-bitrate": "Bitrate"
}.toTable

type
  MpvError* = object of CatchableError
  ## Custom error type for MPV-related errors

  NodeListIterator* = object
    list: ptr NodeList
    index: int

using list: ptr NodeList

func initNodeListIterator(list): NodeListIterator =
  result = NodeListIterator(list: list, index: 0)

func validateNodeListStructure(list): bool =
  ## Validates the basic structure of the NodeList.
  result = (list != nil)
  if not result:
    raise newException(MpvError, "Invalid NodeList encountered in items iterator")

func validateNodeListPointers(list): bool =
  ## Ensures that the keys and values pointers are not nil.
  result = (list.keys != nil) and (list.values != nil)
  if not result:
    raise newException(MpvError, "Invalid NodeList: nil pointer encountered")

func validateNodeListBounds(list): bool =
  ## Checks that the num field is within the expected bounds.
  result = (list.num >= 0) and (list.num < 100)
  if not result:
    raise newException(MpvError, "Invalid NodeList: num out of bounds (got: " & $list.num & ")")

func validateNodeList(list): bool =
  ## Validates the entire NodeList by combining the above validation functions.
  result = list.validateNodeListStructure() and
           list.validateNodeListPointers() and
           list.validateNodeListBounds()

iterator items(iter: var NodeListIterator): tuple[key: string, value: Node] =
  let valuePtr = cast[ptr UncheckedArray[Node]](iter.list.values)

  var index = iter.index
  while index < iter.list.num:
    let key = iter.list.keys[index]
    if key != nil: # Skip nil keys
      yield (key: $key, value: valuePtr[index])
    inc(index)

func handleIndividualTag(
    lowerKey: string,
    value: string,
    tagMap: Table[string, string],
    metadataTable: var Table[string, string],
) =
  # Handle individual tags based on the tagMap
  let preferredKey = tagMap[lowerKey]
  if preferredKey notin metadataTable:
    var formattedValue = value

    # Add units for specific keys
    if preferredKey == "Bitrate":
      formattedValue = formattedValue & " kbps"
    elif preferredKey == "SampleRate":
      formattedValue = formattedValue & " Hz"

    metadataTable[preferredKey] = formattedValue

func handleIcyAudioInfo(
    value: string,
    tagMap: Table[string, string],
    metadataTable: var Table[string, string]
  ) =
  # Handle icy-audio-info parsing
  let audioInfoParts = value.split(";")
  for part in audioInfoParts:
    let keyValue = part.split("=")
    if keyValue.len == 2:
      let audioInfoKey = keyValue[0].strip.toLowerAscii
      var audioInfoValue = keyValue[1].strip

      # Use preferred key if available, otherwise use the lowercase key
      let keyToAdd =
        if audioInfoKey in tagMap: tagMap[audioInfoKey]
        else:  audioInfoKey
      if keyToAdd notin metadataTable:
        # Add units for specific keys
        if keyToAdd == "Bitrate":
          audioInfoValue = audioInfoValue & " kbps"
        elif keyToAdd == "SampleRate":
          audioInfoValue = audioInfoValue & " Hz"

        metadataTable[keyToAdd] = audioInfoValue

const avoidTagList = [
    "icy-notice",
    "icy-notice1",
    "icy-notice2",
    "icy-pub",
    "icy-metadata",
    "icy-private",
    "icy-index-metadata",
    "icy-country-code",
    "icy-logo",
    "icy-vbr",
    "icy-language-codes",
    "icy-geo-lat-long",
    "icy-country-subdivision-code",
    "icy-main-stream-url",
    "icy-metaint",
    "icy-samplerate",
    "encoder",
    "icy-prebuffer",
    "icy-icq",
    "icy-irc",
    "icy-aim",
    "icy-audio-info"
]

const binTagList = [
    "com.elementaltechnologies.timestamp.utc",
    "com.apple.streaming.transportstreamtimestamp"
]

#func handleAppleTransportStreamTimeStamp(bin: string): int =
#  return 0

func handleID3v2PrivTag(lowerKey: string, value: string,
                         metadataTable: var Table[string, string]) =
  # Handle ID3v2_priv tags
  let owner = lowerKey.split(".")[1 .. lowerKey.split(".").high].join(".") # Extract owner identifier
  metadataTable[owner] = value # Store raw data with owner as key

proc collectMetadata(iter: var NodeListIterator,
                     parseAudioInfo: bool = true): Table[string, string] =
  var metadataTable = initTable[string, string]()
  when debug:
    var unkTable = initTable[string, string]()
    var unkFound: bool

  for key, nodeValue in items(iter):
    # Access the format field of the client.Node correctly
    if nodeValue.format == fmtString and nodeValue.u.str != nil:
      let lowerKey = key.toLowerAscii()
      let value = $nodeValue.u.str

      # Handle individual tags
      if lowerKey in tagMap:
        handleIndividualTag(lowerKey, value, tagMap, metadataTable)

      # Handle icy-audio-info
      elif lowerKey == "icy-audio-info" and parseAudioInfo:
        handleIcyAudioInfo(value, tagMap, metadataTable)

      elif lowerKey in binTagList:
        discard #handleAppleTransportStreamTimeStamp(lowerkey)

      # Handle ID3v2_priv tags
      elif lowerKey.startsWith("id3v2_priv."):
        handleID3v2PrivTag(lowerKey, value, metadataTable)

      # Handle unknown tags
      elif lowerKey notin metadataTable:
        when debug:
          if lowerKey notin avoidTagList:
            unkTable[lowerKey] = value
            unkFound = true
  when debug:
    if unkFound:
      #echo unkTable
      discard

  return metadataTable

proc metadata*(ctx: ptr Handle): Table[string, string] =
  try:
    var dataNode: Node
    cE getProperty(ctx, "metadata", fmtNode, addr dataNode)

    var metadataTable = initTable[string, string](16)
    if validateNodeList(dataNode.u.list):
      var iter = initNodeListIterator(dataNode.u.list)
      metadataTable = collectMetadata(iter)
    else:
      echo "Warning: Invalid metadata list received"

    freeNodeContents(addr dataNode)
    return metadataTable
  except CatchableError:
    discard

template willHitUIBottom(): bool = (result.len + startingPoint + 1) >= maxHeight

proc updateMetadataUI*(config: MenuConfig, ctx: ptr Handle, state: PlayerState): Table[string, string] =
  ## Updates and returns the metadata for the current station.
  result = metadata(ctx)
  var goingDown: int

  let maxHeight = terminalHeight()
  let startingPoint = 6
  cursorDown startingPoint

  if willHitUIBottom():
    return result

  if result.len > 0:
    for key, value in result:
      if (value == "") or (key.toLowerAscii().contains("title")): continue
      styledEcho fgCyan, "  " & key & ": '" & value.truncateMe() & "'"
      goingDown += 1

  cursorUp goingDown + startingPoint
