# SPDX-License-Identifier: MPL-2.0
#asynclinkadv.nim
import
  times, ../utils/utils, asyncdispatch,
  strutils, linkbase

import std/net, httpclient

var tempFileLogContent*: string

proc asyncLinkCheckTolerantWithContentType*(url: string; timeout = 10000): Future[LinkStatus] {.async.} =
  let url = normalizeUrl(url)
  let sslCtxWithNoVerify = newContext(verifyMode = CVerifyNone)

  try:
  #block:
    var client = newAsyncHttpClient(
      #timeout = timeout,
      sslContext = sslCtxWithNoVerify,
      userAgent = "pnimrp/0.1",
      maxRedirects = 2
      )
    await sleepAsync 5
    let clientResponse = await client.head(url)

    await sleepAsync 5
    let clientResponseContentType = clientResponse.contentType()
    await sleepAsync 5
    let clientResponseStatusCodeString = $clientResponse.code()
    await sleepAsync 5
    client.close()
    var status: bool

    if clientResponseContentType != "":
      if clientResponseStatusCodeString[0] in ['1', '2', '3']:
        if clientResponseContentType.isValidAudioOrPlaylistStreamContentType():
          result = lsValid
        else: result = lsUnknown


    tempFileLogContent =
      tempFileLogContent & "url: " & url & " | " & clientResponseStatusCodeString

    if clientResponseStatusCodeString[0] == '4':
      #echo clientResponseStatusCodeString; result = lsInvalid
      case clientResponseStatusCodeString:
      of "401", "403", "404", "408", "410": return lsInvalid
      of "405", "400":
          tryHttpGetWhenMediaServerDoesNotSupportHead(url)
          return lsUnknown
      else: return lsUnknown #Invalid

    elif clientResponseStatusCodeString[0] == '5': return lsUnknown

    #result = LinkValidationResult(
    #  isValid: status
    #)
  except SslError, ProtocolError:
    #Handle exceptions using the reusable error-handling function
    return lsUnknown

  except OSError:
    #if "Connection Refused" == getCurrentExceptionMsg():
      return lsInvalid

    #result = lsInvalid #handleLinkCheckError(e, timeout)
    #echo ""
