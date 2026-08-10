import
  net, httpclient, uri,
  json, strutils, std/cmdline

const apiEndPoint = "https://all.api.radio-browser.info/"
const maxStationCap = 20

proc sanitizeEscapedQuotesFromRB(str: string): string =
  var tempStr = str
  tempStr.removePrefix("\"")
  tempStr.removeSuffix("\"")
  return tempStr

template debug: bool =
  not(
    defined(release) or
    defined(danger)
  ) or
  defined(debug)

template didFindInStr(res: int): bool = res != -1

func sanitizeStationName(str: string): string =
  var tempStr = str
  var findFoundAtThisIndex: int = -1
  var charToStartSearchingFrom: int
  while true:
    findFoundAtThisIndex = tempStr.find('_', start = charToStartSearchingFrom)
    if findFoundAtThisIndex.didFindInStr():
      tempStr.delete(findFoundAtThisIndex .. findFoundAtThisIndex)
      charToStartSearchingFrom = findFoundAtThisIndex
    else: break
  return tempStr

template skipThisLoopIfTooLong =
  if ($name in nameItems):
    echo "skipped reason name in arr: ", name
    echo "url: ", url
    echo "---"
    continue

  if ($url in urlItems):
    echo "skipped reason url in arr: ", url
    echo "name url: ", name
    echo "---"
    continue

  if (name.getStr.len > 40):
    echo "skipped name too long: ", name
    echo "skipped reason in arr url: ", url
    echo "---"
    continue

  if url.getStr.len > 70:
    echo "skpped url too long: ", url
    echo "---"
    continue
  echo "end-------------------------------"

proc getStyleToProcessFromFileName(fileName: string): string =
  var styleFromFilename = fileName
  styleFromFileName.removeSuffix(".json")
  result = styleFromFilename

proc apiRequest(client: HttpClient, styleToProcess: string): string =
  let encodedStyleToProcess = encodeUrl(styleToProcess, usePlus = false)
  client.getContent(
    apiEndPoint &
    "json/stations/bytag/" &
    encodedStyleToProcess &
    "?" &
    "order=votes"     & "&" &
    "reverse=true"    & "&" &
    "hidebroken=true" & "&" &
    "limit=70"        & "&" &
    "lastcheckok=1"
  )

proc constructExpectedJsonFromNamesAndUrlItem(nameItems, urlItems: seq[string]): string =
  var jsonObject = %* {"stations": {}}
  var stationList = newJObject()

  var cleanedStationName, cleanedStationUrl: string
  for key in 0 .. nameItems.len - 1:
    cleanedStationName = nameItems[key].sanitizeEscapedQuotesFromRB().sanitizeStationName()
    cleanedStationUrl  =  urlItems[key].sanitizeEscapedQuotesFromRB()
    stationList[cleanedStationName] = %* cleanedStationUrl

  jsonObject["stations"] = stationList
  return jsonObject.pretty

proc getFormattingJsonFromFileName*(fileName: string): string =
  let client =
    newHttpClient(
      sslContext = newContext(verifyMode=CVerifyNone),
      userAgent = "pnimrp/0.1"
    )

  var name, url:  JsonNode
  var nameItems, urlItems: seq[string]

  let styleToGoGet = getStyleToProcessFromFileName(fileName)
  let resultJson = client.apiRequest(styleToGoGet).parseJson()

  for station in 0 .. (resultJson.len - 1):
    if nameItems.len == maxStationCap: break
    name = resultJson[station]["name"]
    url  = resultJson[station]["url"]

    when not defined(release) or
      not defined(danger):
      skipThisLoopIfTooLong()
    nameItems.add ($name).sanitizeStationName()

    urlItems.add $url

  return constructExpectedJsonFromNamesAndUrlItem(nameItems, urlItems)

when isMainModule:
  let paramList = commandLineParams()
  var fileName: string
  try:
    fileName = paramList[0]
  except IndexDefect:
    stderr.writeLine "please enter genre next time"
    echo "selecting default.."

  echo getFormattingJsonFromFileName(fileName)
