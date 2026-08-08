# SPDX-License-Identifier: MPL-2.0
# linkbase.nim

import strutils, uri, net

type
  LinkCheckError* = object of CatchableError
  LinkValidationResult* = object
    isValid*: bool
    error*: string
    protocol*: string
    domain*: string
    port*: Port

func normalizeUrl*(url: string): string =
  result = url
  if not result.startsWith("http://") and not result.startsWith("https://"):
    result = "http://" & result # Default to HTTP if no protocol is specified

func parseUrlComponents*(url: string): tuple[protocol: string, domain: string, port: Port] =
  let uri = parseUri(url)
  let protocol = if uri.scheme == "": "http" else: uri.scheme
  let domain = uri.hostname

  let portNum =
    if uri.port == "":
      if protocol == "https": 443 else: 80
    else:
      parseInt(uri.port)

  let port = Port(portNum)

  if domain == "":
    raise newException(LinkCheckError, "Invalid domain")

  return (protocol, domain, port)

proc handleLinkCheckError*(e: ref Exception, timeout: int): LinkValidationResult =
  var err: string
  if e of OSError or e of IOError:
    err = "Connection error: " & e.msg
  elif e of TimeoutError:
    err = "Connection timed out after " & $timeout & "ms"
  elif e of LinkCheckError:
    err = "Invalid URL: " & e.msg
  elif e of ValueError:
    err = "Invalid URL format"
  else:
    err = "Unexpected error: " & e.msg

  result = LinkValidationResult(isValid: false, error: err)

template tryHttpGetWhenMediaServerDoesNotSupportHead*(url: string) = #TODO
  discard

const validPlaylistTypesList* = [
  "audio/x-scpls",
  "audio/x-mpegurl",
  "application/vnd.apple.mpegurl",
  "application/x-mpegurl",
  "application/pls+xml",
  "application/xspf+xml",
  "audio/x-ms-asx",
  "application/m3u8",
  "video/x-ms-asf",
  "text/m3u"
]

const validRawStreamTypesList* = [
  "application/ogg",
  "application/x-ogg",
  "application/aac",
  "application/aacp",
  "application/x-aac",
  "application/octet-stream"
]

func isValidRawStreamContentType*(contentType: string): bool =
  let normalized = contentType.toLowerAscii()
  if normalized.startsWith("audio/"): return true
  elif normalized in validRawStreamTypesList: return true
  return false

func isValidPlaylistContentType*(contentType: string): bool =
  let normalized = contentType.toLowerAscii()
  if normalized in validPlaylistTypesList: return true
  return false

func isValidAudioOrPlaylistStreamContentType*(contentType: string): bool =
  return isValidRawStreamContentType(contentType) or
    isValidPlaylistContentType(contentType)
