# SPDX-License-Identifier: MPL-2.0
# link.nim

import net
import linkbase
export linkbase

proc validateLink*(link: string, timeout: int = 2000): LinkValidationResult =
    ## Synchronously verifies socket connectivity to the target URL.
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
