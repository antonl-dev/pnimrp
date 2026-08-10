# SPDX-License-Identifier: MPL-2.0
import json
from ../link/linkbase import normalizeUrl

import utilstypes

proc loadStationStdLib*(filePath: string): tuple[names, urls: seq[string]] =
  let jsonData = parseJson(readFile(filePath))

  if not jsonData.hasKey("stations"):
    raise newException(JSONParseError, "Missing 'stations' key in JSON file.")

  let stations = jsonData["stations"]
  result = (names: newSeq[string](), urls: newSeq[string]())

  var countCap: uint8
  for stationName, stationUrlNode in stations.pairs:
    if countCap == 20: break #exceed too much

    let stationNameStr = stationName
    let stationUrlStr = stationUrlNode.getStr

    # Normalize the URL using linkbase.normalizeUrl
    let normalizedUrl = normalizeUrl(stationUrlStr)

    result.names.add(stationNameStr)
    result.urls.add(normalizedUrl)
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

  result = QuoteData(quotes: newSeqOfCap[string](32), authors: newSeqOfCap[string](32))
    # Initialize empty sequences

    # Iterate over the key-value pairs in the JSON object
  for quote, author in jsonData.pairs:
    result.quotes.add(quote) # Add the quote (key)
    result.authors.add(author.getStr) # Add the author (value, converted to string)

    # Validate quotes and authors
  for i in 0 ..< result.quotes.len:
    if result.quotes[i].len == 0:
      raise newException(InvalidDataError, "Empty quote found at index " & $i)
    if result.authors[i].len == 0:
      raise newException(InvalidDataError, "Empty author found for quote at index " & $i)

