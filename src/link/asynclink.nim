# SPDX-License-Identifier: MPL-2.0
# asynclink.nim

import
  times, asyncdispatch, asyncnet,
  strutils

from net import TimeoutError

import  ../utils/utils, linkbase

when defined(asynclinkadv):
  import asynclinkadv

const
  ResolveTimeout = 5000 #ms

proc connectSocket(domain: string, port: Port): Future[bool] {.async.} =
  var socket = newAsyncSocket()
  await sleepAsync(5)
  let connectFuture = socket.connect(domain, port)
  await sleepAsync(5)
  let completed = await connectFuture.withTimeout(ResolveTimeout)
  await sleepAsync(5)
  socket.close()
  await sleepAsync(5)
  return completed

proc tryConnect(domain: string, port: Port): Future[LinkStatus] {.async.} =
  try:
    let connected = await connectSocket(domain, port)
    if not connected:
      return lsInvalid
    return lsValid
  except Exception as e:
    await sleepAsync(5)
    let result = handleLinkCheckError(e, ResolveTimeout)
    if result.isValid:
      return lsValid
    else:
      return lsInvalid

proc resolveLink*(url: string): Future[LinkStatus] {.async.} =
 let normalizedUrl = normalizeUrl(url)

 when not defined(asynclinkadv):
  try:
    let (protocol, domain, port) = parseUrlComponents(normalizedUrl)
    result = await tryConnect(domain, port)
  except Exception as e:
    await sleepAsync(5)
    let result = handleLinkCheckError(e, ResolveTimeout)
    if result.isValid:
      return lsValid
    else:
      return lsInvalid
 else:
  #try:
    when debug:
      var fileInConsideration: File
      let filePathNameExt = "debug.log"
      discard open(fileInConsideration, filePathNameExt, fmAppend)

    result = await asyncLinkCheckTolerantWithContentType(normalizedUrl)
    when debug:
      fileInConsideration.writeLine tempFileLogContent
      fileInConsideration.close()
      tempFileLogContent = ""

  #except Exception as e:
    #await sleepAsync(5)
    #let result = handleLinkCheckError(e, ResolveTimeout)
    #if result.isValid:
    #  return lsValid
    #else:
    #  return lsInvalid
