# SPDX-License-Identifier: MPL-2.0
# link.nim

import linkbase

import net

#when not defined(simple):
#  import linkadvanced

proc validateLinkSimpleSocket(link: string, timeout: int = 2000): LinkValidationResult =
  let finalLink = normalizeUrl(link)

  try:
    let (protocol, domain, port) = parseUrlComponents(finalLink)

    var socket = newSocket()
    socket.connect(domain, port, timeout = timeout)
    socket.close()

    result = LinkValidationResult(
      isValid: true,
      error: "",
      protocol: protocol,
      domain: domain,
      port: port
    )
  except Exception as e:
    result = handleLinkCheckError(e, timeout)

template validateLink*(url: string; timeout = 2000): LinkValidationResult =
  #when defined(simple):
    validateLinkSimpleSocket(url, timeout)
  #else:
  #  validateLinkWithContentTypeCheck(url, timeout)
