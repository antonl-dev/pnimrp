# SPDX-License-Identifier: MPL-2.0
import json
from ../link/linkbase import normalizeUrl

import utilstypes

proc loadStationStdLib*(filePath: string): tuple[names, urls: seq[string], streams: seq[seq[StreamInfo]]] =
    let jsonData = parseJson(readFile(filePath))

    if not jsonData.hasKey("stations"):
        raise newException(JSONParseError, "Missing 'stations' key in JSON file.")

    let stations = jsonData["stations"]
    result = (names: newSeq[string](), urls: newSeq[string](), streams: newSeq[seq[StreamInfo]]())

    var countCap: uint8
    for stationName, stationNode in stations.pairs:
        if countCap == 20: break # exceed too much

        var defUrl = ""
        var streamList: seq[StreamInfo] = @[]

        if stationNode.kind == JString:
            let rawUrl = stationNode.getStr
            let norm = normalizeUrl(rawUrl)
            defUrl = norm
            streamList.add(StreamInfo(url: norm, bitrate: 0, codec: "", region: ""))
        elif stationNode.kind == JObject:
            if stationNode.hasKey("default"):
                defUrl = normalizeUrl(stationNode["default"].getStr(""))
            elif stationNode.hasKey("url"):
                defUrl = normalizeUrl(stationNode["url"].getStr(""))

            if stationNode.hasKey("streams") and stationNode["streams"].kind == JArray:
                for item in stationNode["streams"]:
                    if item.kind == JObject:
                        let sUrl = normalizeUrl(item.getOrDefault("url").getStr(""))
                        if sUrl.len > 0:
                            let sBitrate = item.getOrDefault("bitrate").getInt(0)
                            let sCodec = item.getOrDefault("codec").getStr("")
                            let sRegion = item.getOrDefault("region").getStr("")
                            streamList.add(StreamInfo(url: sUrl, bitrate: sBitrate, codec: sCodec, region: sRegion))
                    elif item.kind == JString:
                        let sUrl = normalizeUrl(item.getStr)
                        if sUrl.len > 0:
                            streamList.add(StreamInfo(url: sUrl, bitrate: 0, codec: "", region: ""))

            if defUrl.len == 0 and streamList.len > 0:
                defUrl = streamList[0].url

            if streamList.len == 0 and defUrl.len > 0:
                streamList.add(StreamInfo(url: defUrl, bitrate: 0, codec: "", region: ""))
        elif stationNode.kind == JArray:
            for item in stationNode:
                if item.kind == JObject:
                    let sUrl = normalizeUrl(item.getOrDefault("url").getStr(""))
                    if sUrl.len > 0:
                        let sBitrate = item.getOrDefault("bitrate").getInt(0)
                        let sCodec = item.getOrDefault("codec").getStr("")
                        let sRegion = item.getOrDefault("region").getStr("")
                        streamList.add(StreamInfo(url: sUrl, bitrate: sBitrate, codec: sCodec, region: sRegion))
                elif item.kind == JString:
                    let sUrl = normalizeUrl(item.getStr)
                    if sUrl.len > 0:
                        streamList.add(StreamInfo(url: sUrl, bitrate: 0, codec: "", region: ""))
            if streamList.len > 0:
                defUrl = streamList[0].url

        if defUrl.len > 0:
            result.names.add(stationName)
            result.urls.add(defUrl)
            result.streams.add(streamList)
            countCap += 1

    # Validate station names (only if it's not the quotes file)
    #if not filePath.endsWith("qoute.json"):
    #  validateLengthStationName(result.names, filePath)

proc loadQuotesStdLib*(filePath: string): QuoteData =
    ## Loads and validates quotes from a JSON file.
    ## Raises `UIError` if the quote data is invalid.
    let jsonData = parseJson(readFile(filePath))

    # Check if the JSON is an object (for the new format)
    if jsonData.kind != JObject:
        raise newException(InvalidDataError, "Invalid JSON format: expected an object.")

    # Initialize empty sequences
    result = QuoteData(
        quotes: newSeqOfCap[string](32),
        authors: newSeqOfCap[string](32)
    )

    # Iterate over the key-value pairs in the JSON object
    for quote, author in jsonData.pairs:
        result.quotes.add(quote) # Add the quote (key)
        result.authors.add(author.getStr) # Add the author (value, converted to string)

    # Validate quotes and authors
    for i in 0 ..< result.quotes.len:
        if result.quotes[i].len == 0:
            raise newException(InvalidDataError, "Empty quote found at index " & $i)
        if result.authors[i].len == 0:
            raise newException(InvalidDataError,
                    "Empty author found for quote at index " & $i)

