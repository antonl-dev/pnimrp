# SPDX-License-Identifier: MPL-2.0
# asynclinkadv.nim
import
    times, asyncdispatch, asyncnet, uri,
    strutils, net

import
    linkbase,
    ../utils/utils

var tempFileLogContent*: string

proc safeClose(sock: AsyncSocket) =
    if sock != nil and not sock.isClosed:
        try:
            sock.close()
        except CatchableError:
            discard

proc asyncLinkCheckTolerantWithContentType*(url: string;
        timeout = 10000): Future[LinkStatus] {.async.} =
    var currentUrl = normalizeUrl(url)
    var redirects = 0
    const maxRedirects = 3

    while redirects < maxRedirects:
        await sleepAsync 5
        let u = parseUri(currentUrl)
        if u.hostname == "":
            return lsInvalid

        let isHttps = u.scheme.toLowerAscii() == "https"
        let port = if u.port.len > 0:
            try: Port(parseInt(u.port))
            except ValueError: return lsInvalid
        elif isHttps: Port(443)
        else: Port(80)

        let path = if u.path.len > 0:
            u.path & (if u.query.len > 0: "?" & u.query else: "")
        else: "/"

        var sock = newAsyncSocket()
        await sleepAsync 5

        try:
            let connectFut = sock.connect(u.hostname, port)
            await sleepAsync 5

            if not await withTimeout(connectFut, timeout):
                await sleepAsync 5
                safeClose(sock)
                return lsUnknown

            when defined(ssl):
                if isHttps:
                    let sslCtx = newContext(verifyMode = CVerifyNone, cipherList = "ALL:@SECLEVEL=1")
                    sslCtx.wrapConnectedSocket(sock, handshakeAsClient, u.hostname)
            else:
                if isHttps:
                    safeClose(sock)
                    return lsUnknown

            let portHeader = if (isHttps and port != Port(443)) or (not isHttps and port != Port(80)): ":" & $int(port) else: ""
            let req = "GET " & path & " HTTP/1.1\r\n" &
                      "Host: " & u.hostname & portHeader & "\r\n" &
                      "User-Agent: mpv/0.38.0\r\n" &
                      "Accept: */*\r\n" &
                      "Icy-MetaData: 1\r\n" &
                      "Connection: close\r\n\r\n"

            await sleepAsync 5
            await sock.send(req)
            await sleepAsync 5

            let recvLineFut = sock.recvLine()
            await sleepAsync 5

            if not await withTimeout(recvLineFut, timeout):
                await sleepAsync 5
                safeClose(sock)
                return lsUnknown

            let statusLine = await recvLineFut
            await sleepAsync 5

            var statusCode = 0
            let trimmedStatus = statusLine.strip()

            if trimmedStatus.toUpperAscii().startsWith("ICY "):
                let parts = trimmedStatus.splitWhitespace()
                if parts.len >= 2:
                    try: statusCode = parseInt(parts[1])
                    except ValueError: statusCode = 200
                else:
                    statusCode = 200
            elif trimmedStatus.toUpperAscii().startsWith("HTTP/"):
                let parts = trimmedStatus.splitWhitespace()
                if parts.len >= 2:
                    try: statusCode = parseInt(parts[1])
                    except ValueError: statusCode = 0
            else:
                safeClose(sock)
                return lsUnknown

            tempFileLogContent = tempFileLogContent & "url: " & currentUrl & " | " & $statusCode & "\n"

            var headers: seq[string] = @[]
            var contentType = ""
            var location = ""
            var hasIcy = trimmedStatus.toUpperAscii().startsWith("ICY ")

            while headers.len < 100:
                let lineFut = sock.recvLine()
                if not await withTimeout(lineFut, 3000):
                    break
                let line = await lineFut
                let stripped = line.strip()
                if stripped.len == 0:
                    break
                headers.add(stripped)

                let lowLine = stripped.toLowerAscii()
                if lowLine.startsWith("content-type:"):
                    contentType = stripped[13..^1].strip()
                elif lowLine.startsWith("location:"):
                    location = stripped[9..^1].strip()
                elif lowLine.startsWith("icy-"):
                    hasIcy = true

            safeClose(sock)
            await sleepAsync 5

            if statusCode in [301, 302, 303, 307, 308] and location.len > 0:
                inc redirects
                if location.startsWith("http://") or location.startsWith("https://"):
                    currentUrl = location
                else:
                    currentUrl = $combine(parseUri(currentUrl), parseUri(location))
                continue

            let isPlaylist = isPlaylistUrl(url) or isPlaylistUrl(currentUrl)
            let isFlacStream = "flac" in url.toLowerAscii() or "flac" in currentUrl.toLowerAscii()

            if statusCode in [200, 206]:
                if contentType.len > 0 and contentType.isValidAudioOrPlaylistStreamContentType():
                    return lsValid
                elif hasIcy or isPlaylist or isFlacStream:
                    return lsValid
                else:
                    return lsUnknown
            elif statusCode in [401, 403, 404, 408, 410]:
                return lsInvalid
            elif statusCode in [500, 502, 503, 504]:
                return lsUnknown
            else:
                return lsUnknown

        except SslError:
            safeClose(sock)
            return lsUnknown
        except OSError as e:
            safeClose(sock)
            if "Connection refused" in e.msg or "No route to host" in e.msg:
                return lsInvalid
            return lsUnknown
        except Exception:
            safeClose(sock)
            return lsUnknown

    return lsUnknown
