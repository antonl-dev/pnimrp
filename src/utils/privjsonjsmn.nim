# SPDX-License-Identifier: MPL-2.0
when defined(useJsmn):
    import
        utilstypes

    from ../link/linkbase import normalizeUrl

    import ../json/jsmn

    proc loadStationJSMN*(filePath: string): tuple[names, urls: seq[string]] =
        var tokens = parseJson(readFile(filePath), autoResize = true)
        # Helper proc to get string value from token
        proc getString(jsonStr: string, token: JsmnToken): string =
            result = jsonStr[token.start ..< token.stop]

        # Find "stations" token
        var stationsTokenIndex = -1
        for i in 0 ..< tokens.len:
            if tokens[i].kind == JSMN_STRING and
                getString(readFile(filePath), tokens[i]) == "stations":
                stationsTokenIndex = i + 1 # The object/array is *after* the "stations" string
                break

        if stationsTokenIndex == -1 or tokens[stationsTokenIndex].kind != JSMN_OBJECT:
            raise newException(JSONParseError, "Missing or invalid 'stations' key in JSON file.")

        # Iterate through stations object
        let stationsToken = tokens[stationsTokenIndex]
        var childIndex = stationsTokenIndex + 1
        result = (names: newSeq[string](), urls: newSeq[string]())

        var pairsCount = 0
        var countCap: uint8

        while pairsCount < stationsToken.size:
            if countCap == 20: break # exceed too much

            # Expecting a string (key)
            if tokens[childIndex].kind != JSMN_STRING:
                raise newException(JSONParseError, "Expected station name (string).")

            let stationName = getString(readFile(filePath), tokens[childIndex])
            inc childIndex

            # Expecting a string (value/URL)
            if tokens[childIndex].kind != JSMN_STRING:
                raise newException(JSONParseError, "Expected station URL (string).")
            let stationUrl = getString(readFile(filePath), tokens[childIndex])
            inc childIndex

            let normalizedUrl = normalizeUrl(stationUrl)
            result.names.add(stationName)
            result.urls.add(normalizedUrl)
            inc pairsCount
            inc countCap

    proc loadQuotesJSMN*(filePath: string): QuoteData =
        ## Loads and validates quotes from a JSON file.
        ## Raises `UIError` if the quote data is invalid.

        var tokens = parseJson(readFile(filePath), autoResize = true)
        # Helper proc to get string value
        proc getString(jsonStr: string, token: JsmnToken): string =
            result = jsonStr[token.start ..< token.stop]

        if tokens[0].kind != JSMN_OBJECT:
            raise newException(InvalidDataError, "Invalid JSON format: expected an object.")

        result = QuoteData(
            quotes: newSeqOfCap[string](32),
            authors: newSeqOfCap[string](32)
        )
        var childIndex = 1
        var pairCount = 0

        while pairCount < tokens[0].size: # tokens[0] is the root object
            # Expecting quote (string key)
            if tokens[childIndex].kind != JSMN_STRING:
                raise newException(InvalidDataError, "Expected quote (string key).")
            let quote = getString(readFile(filePath), tokens[childIndex])
            inc childIndex

            # Expecting author (string value)
            if tokens[childIndex].kind != JSMN_STRING:
                raise newException(InvalidDataError, "Expected author (string value).")
            let author = getString(readFile(filePath), tokens[childIndex])
            inc childIndex

            result.quotes.add(quote)
            result.authors.add(author)
            inc pairCount
