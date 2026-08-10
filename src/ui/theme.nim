# SPDX-License-Identifier: MPL-2.0
# theme.nim

import
  ../utils/utils

import
  json, strutils,
  terminal, tables

proc loadThemeConfig*(configPath: string): ThemeConfig =
  try:
    let jsonData = parseFile(configPath)
    result.themes = initTable[string, Theme]()

    for themeName, themeData in jsonData["themes"]:
      var theme: Theme
      theme.header       =  parseEnum[ForegroundColor](themeData["header"]      .getStr())
      theme.separator    =  parseEnum[ForegroundColor](themeData["separator"]   .getStr())
      theme.menu         =  parseEnum[ForegroundColor](themeData["menu"]        .getStr())
      theme.footer       =  parseEnum[ForegroundColor](themeData["footer"]      .getStr())
      theme.error        =  parseEnum[ForegroundColor](themeData["error"]       .getStr())
      theme.warning      =  parseEnum[ForegroundColor](themeData["warning"]     .getStr())
      theme.success      =  parseEnum[ForegroundColor](themeData["success"]     .getStr())
      theme.nowPlaying   =  parseEnum[ForegroundColor](themeData["nowPlaying"]  .getStr())
      theme.volumeLow    =  parseEnum[ForegroundColor](themeData["volumeLow"]   .getStr())
      theme.volumeMedium =  parseEnum[ForegroundColor](themeData["volumeMedium"].getStr())
      theme.volumeHigh   =  parseEnum[ForegroundColor](themeData["volumeHigh"]  .getStr())

      result.themes[themeName] = theme

    result.currentTheme = jsonData["currentTheme"].getStr()
  except IOError:
    raise newException(ValueError, "Failed to load theme config: File not found")
  except JsonParsingError:
    raise newException(ValueError, "Failed to parse theme config: Invalid JSON format")

proc getCurrentTheme*(config: ThemeConfig): Theme =
  if config.currentTheme in config.themes:
    return config.themes[config.currentTheme]
  else:
    raise newException(ValueError, "Current theme not found in config")

proc setCurrentTheme*(config: var ThemeConfig, themeName: string) =
  if themeName in config.themes:
    config.currentTheme = themeName
  else:
    raise newException(ValueError, "Theme not found: " & themeName)
