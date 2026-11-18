# SPDX-License-Identifier: MPL-2.0
import os
import strutils
import unicode

# Function to check if a character is valid (ASCII-only)
proc isValidChar(c: Rune): bool =
    # Valid characters are within the ASCII range (0x00 to 0x7F)
    return ord(c) <= 0x7F

# Function to check a file
proc checkFile(filename: string) =
    var file = open(filename, fmRead)
    defer: file.close()

    var lineNumber = 0
    for line in file.lines:
        lineNumber += 1
        for c in line.runes:
            if not isValidChar(c):
                echo "Invalid character found in file: ", filename,
                        ", line number: ", lineNumber
                echo "Line content: ", line
                break # Only report the first invalid character in the line

# Function to recursively read files in a directory
proc readFiles(dirPath: string) =
    for kind, path in walkDir(dirPath):
        case kind
        of pcDir:
            # Recursively check directories
            readFiles(path)
        of pcFile:
            # Check JSON files
            if path.endsWith(".json"):
                checkFile(path)
        else:
            discard

# Main function
proc main() =
    if paramCount() != 1:
        stderr.writeLine("Usage: jsonAsciiValidator <directory>")
        quit(1)

    let dirPath = paramStr(1)
    readFiles(dirPath)

when isMainModule:
    main()
