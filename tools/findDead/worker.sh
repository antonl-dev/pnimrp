#!/bin/bash

# SPDX-License-Identifier: MPL-2.0

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/data/data/com.termux/files/usr/bin/"

# Function to make a curl request
make_request() {
    local extra_opts=("$@")
    curl "${CURL_OPTS[@]}" "${extra_opts[@]}" "$URL" 2>/dev/null
}

# Function to check file type using mediainfo
check_with_mediainfo() {
    MEDIAINFO_OUTPUT=$(mediainfo "$TEMP_FILE")
    for keyword in "${KEYWORDS[@]}"; do
        if echo "$MEDIAINFO_OUTPUT" | grep -iq "$keyword"; then
            FOUND=1
            MATCHED_KEYWORD="$keyword (detected by mediainfo)"
            return
        fi
    done

    # Additional check for generic MPEG Audio detection in mediainfo
    if echo "$MEDIAINFO_OUTPUT" | grep -iq "mpeg"; then
        FOUND=1
        MATCHED_KEYWORD="mpeg audio (detected by mediainfo)"
        return
    fi
}

# Function to check file type using file command
check_with_file() {
    WHAT_FILE_SAID=$(file "$TEMP_FILE")

    # REJECT HTML/XML WEBPAGES IMMEDIATELY
    if echo "$WHAT_FILE_SAID" | grep -iq -e "HTML document" -e "XHTML document" -e "XML 1.0 document"; then
        return
    fi

    for keyword in "${KEYWORDS[@]}"; do
        if echo "$WHAT_FILE_SAID" | grep -iq "$keyword"; then
            FOUND=1
            MATCHED_KEYWORD="$keyword (detected by file)"
            return
        fi
    done

    if echo "$WHAT_FILE_SAID" | grep -iq "mpeg"; then
        FOUND=1
        MATCHED_KEYWORD="mpeg audio (detected by file)"
        return
    fi

    if echo "$WHAT_FILE_SAID" | grep -iq "pls"; then
        FOUND=1
        MATCHED_KEYWORD="PLS file (detected by file)"
        return
    fi

    if echo "$WHAT_FILE_SAID" | grep -iq "data"; then
        FOUND=1
        MATCHED_KEYWORD="ℹ️ GENERIC DATA file (detected by file) assuming success"
        return
    fi
}

_echo() {
    echo "$1" >> result.txt
}

log_echo() {
    echo "$1" >> error.txt
}

# Check if STATION_NAME, URL, and JSON_FILE are provided
if [[ -z "$1" || -z "$2" ]]; then
    echo "Error: STATION_NAME or URL not provided."
    exit 1
fi

# Define arguments
STATION_NAME="$1"
URL="$2"
JSON_FILE="$3"

# Define the target keywords (case-insensitive)
KEYWORDS=("flac" "aac" "mp3" "adts" "mpeg" "hls" "layer iii" "layer 3" "dash" "pls" "mpd" "m3u" "ogg" "vorbis" "opus")

# Create a randomly named temporary file with unique identifier for concurrent runs
TEMP_FILE="$(mktemp)"

# Ensure temp file cleanup on exit
trap 'rm -f "$TEMP_FILE"' EXIT

# Common curl options
CURL_OPTS_CORE=(
    --silent
    --insecure
    --max-time 10
    --http0.9
    --limit-rate 128
    --connect-timeout 6
    --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
    --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"
    --header "Accept-Language: en-US,en;q=0.9"
    --header "Connection: keep-alive"
    --output "$TEMP_FILE"
)

CURL_OPTS=(
    -L
    "${CURL_OPTS_CORE[@]}"
)

# Special case for m3u / m3u8 files
if echo "$URL" | grep -iq "m3u"; then
  curl_output=$(curl "${CURL_OPTS[@]}" "$URL" 2>/dev/null)
  curl_status=$?
  
  if (( curl_status != 0 && curl_status != 28 )); then
    log_echo "❌ $JSON_FILE | $STATION_NAME | $URL | CurlError $curl_status"
    _echo "❌ $JSON_FILE | $STATION_NAME | $URL | CurlError $curl_status"
    exit 1
  fi

  if grep -q -e "#EXTM3U" -e "http" "$TEMP_FILE"; then
     _echo "✅ $JSON_FILE | $STATION_NAME | $URL | (M3U/M3U8 PLAYLIST)"
     log_echo "✅ $JSON_FILE | $STATION_NAME | $URL | (M3U/M3U8 PLAYLIST)"
     exit 0
  fi
fi

# Try curl normally first
curl_output=$(make_request)
curl_status="$?"

if (( curl_status != 0 && curl_status != 28 )); then
  log_echo "❌ $JSON_FILE | $STATION_NAME | $URL | CurlError $curl_status"
  _echo "❌ $JSON_FILE | $STATION_NAME | $URL | CurlError $curl_status"
  log_echo "START curloutp-----------------------------------------"
  log_echo "$curl_output"
  log_echo "END curloutp-----------------------------------------"
  exit 1
fi

# Check if the temporary file exists and is not empty
if [[ -s "$TEMP_FILE" ]]; then
    FOUND=0
    MATCHED_KEYWORD=""

    # 1. Try detecting with mediainfo
    check_with_mediainfo

    # 2. If mediainfo didn't find keywords, try file command
    if [[ $FOUND -eq 0 ]]; then
        check_with_file
    fi

    # Return success or error based on whether a keyword was found
    if [[ $FOUND -eq 1 ]]; then
        _echo "✅ $JSON_FILE | $STATION_NAME | $URL | ($MATCHED_KEYWORD)"
        exit 0
    else
        log_echo "❌ $JSON_FILE | $STATION_NAME | $URL | No matching keywords found."
        _echo "❌ $JSON_FILE | $STATION_NAME | $URL | No matching keywords found."
        log_echo "START-----------------------------------------"
        log_echo "file said:"
        file "$TEMP_FILE" >> error.txt
        log_echo "mediainfo said:"
        mediainfo "$TEMP_FILE" >> error.txt
        log_echo "$STATION_NAME: $TEMP_FILE"
        log_echo "$URL"
        log_echo "END-----------------------------------------"
        exit 1
    fi
else
    # Temporary file is empty or does not exist
    exit 1
fi
