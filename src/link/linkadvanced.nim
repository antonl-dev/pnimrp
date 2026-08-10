# SPDX-License-Identifier: MPL-2.0
import linkbase

import net, httpclient, strutils

proc validateLinkWithContentTypeCheck*(url: string; timeout = 2000): LinkValidationResult =
  let url = normalizeUrl(url)
  let sslCtxWithNoVerify = newContext(verifyMode = CVerifyNone)

  try:
    var client = newHttpClient(
      timeout = timeout,
      sslContext = sslCtxWithNoVerify
      )
    let clientResponse = client.head(url)

    let clientResponseContentType = clientResponse.contentType()
    let clientResponseStatusCodeString = $clientResponse.code()
    client.close()

    var status: bool

    if clientResponseContentType != "":
      status = clientResponseContentType.isValidAudioOrPlaylistStreamContentType()

    if clientResponseStatusCodeString == $405:
      tryHttpGetWhenMediaServerDoesNotSupportHead(url)
      result = LinkValidationResult(isValid: status)

    elif clientResponseStatusCodeString[0] in ['4', '5']:
      result = LinkValidationResult(isValid: false)

    result = LinkValidationResult(
      isValid: status
    )
  except Exception as e:
    result = handleLinkCheckError(e, timeout)
