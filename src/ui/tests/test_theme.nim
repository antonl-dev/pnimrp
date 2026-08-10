# SPDX-License-Identifier: MPL-2.0
# Unit tests for theme.nim
import terminal

import ../theme, ../../utils/utils

when isMainModule:
  import unittest, os

  suite "Theme Tests":
    test "loadThemeConfig":
      let testJson = """
      {
        "themes": {
          "default": {
            "header": "fgBlue",
            "separator": "fgGreen",
            "menu": "fgYellow",
            "footer": "fgCyan",
            "error": "fgRed",
            "warning": "fgMagenta",
            "success": "fgGreen",
            "nowPlaying": "fgWhite",
            "volumeLow": "fgBlue",
            "volumeMedium": "fgYellow",
            "volumeHigh": "fgRed"
          }
        },
        "currentTheme": "default"
      }
      """
      writeFile("test_theme.json", testJson)
      let config = loadThemeConfig("test_theme.json")
      check config.currentTheme == "default"
      #check (config.themes["default"].header == fgBlue)
      removeFile("test_theme.json")

    test "getCurrentTheme":
      let testJson = """
      {
        "themes": {
          "default": {
            "header": "fgBlue",
            "separator": "fgGreen",
            "menu": "fgYellow",
            "footer": "fgCyan",
            "error": "fgRed",
            "warning": "fgMagenta",
            "success": "fgGreen",
            "nowPlaying": "fgWhite",
            "volumeLow": "fgBlue",
            "volumeMedium": "fgYellow",
            "volumeHigh": "fgRed"
          }
        },
        "currentTheme": "default"
      }
      """
      writeFile("test_theme.json", testJson)
      let config = loadThemeConfig("test_theme.json")
      let theme = getCurrentTheme(config)
      check theme.header == fgBlue
      removeFile("test_theme.json")

    test "setCurrentTheme":
      let testJson = """
      {
        "themes": {
          "default": {
            "header": "fgBlue",
            "separator": "fgGreen",
            "menu": "fgYellow",
            "footer": "fgCyan",
            "error": "fgRed",
            "warning": "fgMagenta",
            "success": "fgGreen",
            "nowPlaying": "fgWhite",
            "volumeLow": "fgBlue",
            "volumeMedium": "fgYellow",
            "volumeHigh": "fgRed"
          },
          "dark": {
            "header": "fgBlack",
            "separator": "fgWhite",
            "menu": "fgGreen",
            "footer": "fgBlack",
            "error": "fgRed",
            "warning": "fgYellow",
            "success": "fgGreen",
            "nowPlaying": "fgWhite",
            "volumeLow": "fgBlue",
            "volumeMedium": "fgYellow",
            "volumeHigh": "fgRed"
          }
        },
        "currentTheme": "default"
      }
      """
      writeFile("test_theme.json", testJson)
      var config = loadThemeConfig("test_theme.json")
      setCurrentTheme(config, "dark")
      check config.currentTheme == "dark"
      removeFile("test_theme.json")
