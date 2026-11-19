# SPDX-License-Identifier: MPL-2.0
# tools/audit_stations.nim
## Automated audit harness to test stream link resolution against real MPV playback.
## Identifies any false negatives (stations where link check says dead/unknown but MPV plays).

import asyncdispatch, strutils, os, json, osproc, strformat

import "../src/utils/utils"
import "../src/link/linkbase"
import "../src/link/asynclinkadv"

type
    StationEntry = object
        category: string
        name: string
        url: string

    AuditResult = object
        station: StationEntry
        linkStatus: LinkStatus
        logInfo: string
        mpvPlayable: bool
        mpvReason: string

proc checkMpv(url: string, timeoutSec: int = 4): (bool, string) =
    ## Runs mpv headlessly with verbose logs to detect actual audio stream startup.
    let cmd = fmt"timeout {timeoutSec}s mpv -v --no-video --ao=null '{url}'"
    let (output, exitCode) = execCmdEx(cmd)

    if "starting audio playback" in output or "audio=playing" in output or
       "AO: [" in output or "● Audio" in output:
        return (true, "MPV started audio playback")
    elif "Found 'hls'" in output or "Found 'mp3'" in output or "Found 'aac'" in output:
        return (true, "MPV demuxed stream successfully")
    elif exitCode == 0:
        return (true, "MPV exited with 0")
    else:
        var errLine = ""
        for line in output.splitLines():
            if "failed" in line.toLowerAscii() or "error" in line.toLowerAscii():
                errLine = line.strip()
                break
        return (false, if errLine.len > 0: errLine else: "Failed to connect or decode")

proc auditStation(st: StationEntry): Future[AuditResult] {.async.} =
    result.station = st
    tempFileLogContent = ""
    result.linkStatus = await asyncLinkCheckTolerantWithContentType(st.url, timeout = 7000)
    result.logInfo = tempFileLogContent.strip()

    if result.linkStatus != lsValid:
        # Isolated retry to avoid concurrency rate-limiting artifacts
        await sleepAsync 100
        let retryStatus = await asyncLinkCheckTolerantWithContentType(st.url, timeout = 7000)
        if retryStatus == lsValid:
            result.linkStatus = lsValid

    if result.linkStatus != lsValid:
        # Check if mpv can play it anyway (False Negative test)
        let (playable, reason) = checkMpv(st.url, timeoutSec = 4)
        result.mpvPlayable = playable
        result.mpvReason = reason
    else:
        result.mpvPlayable = true
        result.mpvReason = "Link check valid"

proc loadStations(filterPattern: string = ""): seq[StationEntry] =
    let baseDir = getCurrentDir() / "assets/stations"
    for path in walkDirRec(baseDir):
        if not path.endsWith(".json"): continue
        let rel = path[baseDir.len + 1 .. ^1]
        if filterPattern.len > 0 and filterPattern.toLowerAscii() notin rel.toLowerAscii():
            continue
        try:
            let data = parseFile(path)
            if data.hasKey("stations"):
                for name, urlNode in data["stations"].pairs:
                    result.add StationEntry(
                        category: rel,
                        name: name,
                        url: urlNode.getStr()
                    )
        except Exception as e:
            echo "Failed to parse ", path, ": ", e.msg

proc runAudit(pattern: string = "") {.async.} =
    let stations = loadStations(pattern)
    echo fmt"Loaded {stations.len} stations matching filter '{pattern}'."

    var validCount = 0
    var deadCount = 0
    var unknownCount = 0
    var falseNegatives: seq[AuditResult] = @[]

    # Concurrency control: batch in groups of 8 to avoid socket / rate-limit exhaustion
    const batchSize = 8
    var idx = 0
    while idx < stations.len:
        let endIdx = min(idx + batchSize, stations.len)
        var futs: seq[Future[AuditResult]] = @[]
        for i in idx ..< endIdx:
            futs.add auditStation(stations[i])

        let results = await all(futs)
        for r in results:
            case r.linkStatus:
            of lsValid:
                inc validCount
                echo fmt"  🟢 [VALID] {r.station.category} | {r.station.name}"
            of lsInvalid:
                inc deadCount
                if r.mpvPlayable:
                    falseNegatives.add r
                    echo fmt"  🔴 [FALSE NEGATIVE] {r.station.category} | {r.station.name} -> Plays in MPV! ({r.station.url})"
                else:
                    echo fmt"  🔴 [DEAD] {r.station.category} | {r.station.name}"
            of lsUnknown:
                inc unknownCount
                if r.mpvPlayable:
                    falseNegatives.add r
                    echo fmt"  ❓ [FALSE NEGATIVE] {r.station.category} | {r.station.name} -> Plays in MPV! ({r.station.url})"
                else:
                    echo fmt"  ❓ [UNKNOWN / DEAD] {r.station.category} | {r.station.name}"
            of lsChecking: discard

        idx = endIdx
        await sleepAsync 20 # small breather between batches

    echo "\n================ AUDIT SUMMARY ================"
    echo fmt"Filter: '{pattern}'"
    echo fmt"Total Stations Tested: {stations.len}"
    echo fmt"  🟢 Valid (Link OK):   {validCount}"
    echo fmt"  🔴 Dead (Verified):   {deadCount - falseNegatives.len}"
    echo fmt"  ❓ Unknown (Verified):{unknownCount}"
    echo fmt"  ⚠️ False Negatives:   {falseNegatives.len} (Plays in MPV, but flagged 🔴 or ❓)"
    echo "================================================"

    if falseNegatives.len > 0:
        echo "\n🚨 Action Required - False Negatives Details:"
        for fn in falseNegatives:
            echo fmt"- [{fn.linkStatus}] {fn.station.name} ({fn.station.category})"
            echo fmt"  URL: {fn.station.url}"
            echo fmt"  MPV: {fn.mpvReason}"
            echo fmt"  Log: {fn.logInfo}"
            echo "------------------------------------------------"

proc main() {.async.} =
    let args = commandLineParams()
    let pattern = if args.len > 0: args[0] else: "blues.json"
    await runAudit(pattern)

waitFor main()
