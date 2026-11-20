# SPDX-License-Identifier: MPL-2.0
# equalizer.nim - Audio Equalizer & Preset Manager

import json, os, strutils, tables
import ../utils/utilstypes

export IsoBands

proc defaultFlatPreset*(): EqPreset =
    result = EqPreset(
        id: "flat",
        name: "Flat",
        description: "Neutral uncolored sound",
        preamp: 0.0,
        bands: initTable[string, float]()
    )
    for b in IsoBands:
        result.bands[b] = 0.0

proc defaultEqualizerConfig*(): EqualizerConfig =
    result = EqualizerConfig(
        enabled: true,
        activePreset: "flat",
        presetOrder: @["flat"],
        presets: initTable[string, EqPreset]()
    )
    let flat = defaultFlatPreset()
    result.presets["flat"] = flat

proc toFilterString*(preset: EqPreset): string =
    ## Generates an FFmpeg/MPV audio filter string for this preset.
    var filters: seq[string] = @[]

    if preset.preamp != 0.0:
        filters.add("volume=volume=" & $preset.preamp & "dB")

    for freq in IsoBands:
        if freq in preset.bands:
            let gain = preset.bands[freq]
            if gain != 0.0:
                filters.add("equalizer=f=" & freq & ":width_type=o:w=1:g=" & $gain)

    if filters.len == 0:
        return ""
    return "lavfi=[" & filters.join(",") & "]"

proc loadEqualizerConfig*(configPath: string): EqualizerConfig =
    ## Loads equalizer presets from JSON configuration file with robust fallbacks.
    result = defaultEqualizerConfig()
    if not fileExists(configPath):
        return result

    try:
        let root = parseFile(configPath)
        if root.hasKey("enabled"):
            result.enabled = root["enabled"].getBool(true)

        if root.hasKey("activePreset"):
            result.activePreset = root["activePreset"].getStr("flat")

        if root.hasKey("presets") and root["presets"].kind == JObject:
            result.presets.clear()
            result.presetOrder = @[]

            for presetId, presetNode in root["presets"].pairs:
                var preset = EqPreset(
                    id: presetId,
                    name: presetNode.getOrDefault("name").getStr(presetId.capitalizeAscii),
                    description: presetNode.getOrDefault("description").getStr(""),
                    preamp: presetNode.getOrDefault("preamp").getFloat(0.0),
                    bands: initTable[string, float]()
                )

                if presetNode.hasKey("bands") and presetNode["bands"].kind == JObject:
                    for freq, gainNode in presetNode["bands"].pairs:
                        preset.bands[freq] = gainNode.getFloat(0.0)

                for b in IsoBands:
                    if not (b in preset.bands):
                        preset.bands[b] = 0.0

                result.presets[presetId] = preset
                result.presetOrder.add(presetId)

            if result.presetOrder.len == 0:
                let flat = defaultFlatPreset()
                result.presets["flat"] = flat
                result.presetOrder.add("flat")
                result.activePreset = "flat"
            elif not (result.activePreset in result.presets):
                result.activePreset = result.presetOrder[0]
    except Exception:
        result = defaultEqualizerConfig()

proc getActivePreset*(config: EqualizerConfig): EqPreset =
    if config.activePreset in config.presets:
        return config.presets[config.activePreset]
    return defaultFlatPreset()

proc cycleNextPreset*(config: var EqualizerConfig): EqPreset =
    ## Cycles to the next preset in order and returns it.
    if config.presetOrder.len == 0:
        return defaultFlatPreset()

    var curIdx = config.presetOrder.find(config.activePreset)
    if curIdx == -1:
        curIdx = 0

    let nextIdx = (curIdx + 1) mod config.presetOrder.len
    config.activePreset = config.presetOrder[nextIdx]
    return config.presets[config.activePreset]
