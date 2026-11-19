#!/usr/bin/env python3
"""
tools/curate_catalog.py
Autonomous Radio-Browser API query, verification, and catalog curator for pnimrp.

Usage:
    python3 tools/curate_catalog.py [genre1 genre2 ...]
    python3 tools/curate_catalog.py all

Supported genres:
    pop, rock, jazz, classical, blues, metal, reggae, country,
    decades, chill, urban, news, world
"""

import urllib.request
import urllib.parse
import ssl
import json
import os
import shutil
import sys
import time
import socket
from typing import Dict, List, Tuple, Optional

MIRRORS = [
    "https://de1.api.radio-browser.info",
    "https://nl1.api.radio-browser.info",
    "https://at1.api.radio-browser.info"
]

SSL_CTX = ssl.create_default_context()
SSL_CTX.check_hostname = False
SSL_CTX.verify_mode = ssl.CERT_NONE

socket.setdefaulttimeout(5.0)

EXCLUDE_NAME_KEYWORDS = [
    "christmas", "xmas", "holiday", "noel", "navidad", "weihnacht"
]

VALID_AUDIO_TYPES = {
    "audio/mpeg", "audio/mp3", "audio/aac", "audio/aacp", "audio/x-aac",
    "audio/ogg", "application/ogg", "audio/opus", "audio/flac", "audio/x-flac",
    "audio/x-mpegurl", "audio/x-scpls", "application/vnd.apple.mpegurl"
}

def query_radio_browser(params: Dict[str, str], limit: int = 35) -> List[Dict]:
    params["limit"] = str(limit)
    query_str = urllib.parse.urlencode(params)
    
    for mirror in MIRRORS:
        url = f"{mirror}/json/stations/search?{query_str}"
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "pnimrp/0.2 (https://github.com/antonloyed/pnimrp)"}
        )
        try:
            with urllib.request.urlopen(req, context=SSL_CTX, timeout=6.0) as resp:
                if resp.status == 200:
                    return json.loads(resp.read().decode("utf-8", errors="ignore"))
        except Exception:
            continue
    return []

def verify_stream(url: str, timeout: float = 3.5) -> Tuple[bool, str]:
    if not url or not (url.startswith("http://") or url.startswith("https://")):
        return False, ""
        
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "mpv/0.38.0",
            "Icy-MetaData": "1",
            "Range": "bytes=0-1024"
        }
    )
    try:
        with urllib.request.urlopen(req, context=SSL_CTX, timeout=timeout) as resp:
            status = resp.status
            content_type = (resp.headers.get("Content-Type") or "").lower().split(";")[0].strip()
            has_icy = any(k.lower().startswith("icy-") for k in resp.headers.keys())
            
            if status in [200, 206]:
                if content_type in VALID_AUDIO_TYPES or has_icy or "audio" in content_type:
                    return True, resp.geturl() or url
    except Exception:
        pass
    return False, ""

def clean_station_name(raw_name: str, max_len: int = 22) -> str:
    name = raw_name.strip()
    
    for suffix in [
        "[128k]", "(128k)", "[64k]", "(64k)", "[320k]", "(320k)",
        "(AAC)", "[AAC]", "(MP3)", "[MP3]", " - MP3", " - AAC", " 128k", " 320k"
    ]:
        if name.endswith(suffix):
            name = name[:-len(suffix)].strip()
            
    prefixes = [
        ("Radio Caprice - ", "radcap "),
        ("Radio Caprice: ", "radcap "),
        ("Radio Caprice ", "radcap "),
        ("181.FM - ", "181.fm "),
        ("181.fm - ", "181.fm "),
        ("Concertzender - ", "CZ "),
        ("Concertzender ", "CZ "),
        ("Radio ", "R "),
        ("SomaFM - ", "SomaFM "),
    ]
    for pfx, rep in prefixes:
        if name.startswith(pfx):
            name = rep + name[len(pfx):].strip()
            break
            
    name = name.rstrip("-|:, ").strip()
    if len(name) > max_len:
        name = name[:max_len].strip()
    if name.endswith("(") or name.endswith("["):
        name = name[:-1].strip()
    elif "(" in name and ")" not in name:
        name = name.split("(")[0].strip()
    return name

def curate_category(
    existing_stations: Optional[Dict[str, str]],
    queries: List[Dict[str, str]],
    target_count: int = 16,
    max_count: int = 22
) -> Dict[str, str]:
    stations: Dict[str, str] = {}
    seen_urls = set()
    
    if existing_stations:
        for name, url in existing_stations.items():
            if any(bad in name.lower() for bad in EXCLUDE_NAME_KEYWORDS):
                continue
            clean_n = clean_station_name(name)
            ok, final_url = verify_stream(url, timeout=3.5)
            if ok:
                stations[clean_n] = final_url or url
                seen_urls.add((final_url or url).lower())

    candidates = []
    for q in queries:
        res = query_radio_browser(q, limit=40)
        for item in res:
            url = item.get("url_resolved") or item.get("url")
            if not url or url.lower() in seen_urls:
                continue
            name = item.get("name", "").strip()
            if any(bad in name.lower() for bad in EXCLUDE_NAME_KEYWORDS):
                continue
            votes = item.get("votes", 0)
            bitrate = item.get("bitrate", 0)
            candidates.append((votes, bitrate, name, url))

    candidates.sort(key=lambda x: (x[0], x[1]), reverse=True)
    
    for votes, bitrate, raw_name, url in candidates:
        if len(stations) >= target_count:
            break
        if url.lower() in seen_urls:
            continue
            
        clean_n = clean_station_name(raw_name)
        if clean_n in stations:
            continue
            
        ok, final_url = verify_stream(url, timeout=3.5)
        if ok:
            stations[clean_n] = final_url or url
            seen_urls.add((final_url or url).lower())
            
    if len(stations) > max_count:
        stations = dict(list(stations.items())[:max_count])
        
    return stations

def save_json(path: str, stations: Dict[str, str]):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fp:
        json.dump({"stations": stations}, fp, indent=2, ensure_ascii=False)
        fp.write("\n")
    print(f"  [OK] Saved {len(stations)} stations to {path}")

def load_json(path: str) -> Dict[str, str]:
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as fp:
                return json.load(fp).get("stations", {})
        except Exception:
            pass
    return {}

# Full catalog specs for all major genres
GENRE_SPECS = {
    "pop": {
        "dir": "assets/stations/pop",
        "files": {
            "!main_pop.json": [
                {"tag": "pop", "order": "votes", "reverse": "true"},
                {"tag": "top 40", "order": "votes", "reverse": "true"},
                {"name": "BBC Radio 1", "order": "votes", "reverse": "true"},
                {"name": "Capital FM", "order": "votes", "reverse": "true"},
                {"name": "NRJ", "order": "votes", "reverse": "true"}
            ],
            "dance_pop.json": [
                {"tag": "dance pop", "order": "votes", "reverse": "true"},
                {"tag": "eurodance", "order": "votes", "reverse": "true"},
                {"tag": "dance", "order": "votes", "reverse": "true"}
            ],
            "indie_pop.json": [
                {"tag": "indie pop", "order": "votes", "reverse": "true"},
                {"tag": "dream pop", "order": "votes", "reverse": "true"},
                {"name": "Radio Paradise", "order": "votes", "reverse": "true"}
            ],
            "kpop_asianpop.json": [
                {"tag": "k-pop", "order": "votes", "reverse": "true"},
                {"tag": "kpop", "order": "votes", "reverse": "true"},
                {"tag": "j-pop", "order": "votes", "reverse": "true"}
            ],
            "latin_pop.json": [
                {"tag": "latin pop", "order": "votes", "reverse": "true"},
                {"tag": "pop latino", "order": "votes", "reverse": "true"},
                {"tag": "reggaeton pop", "order": "votes", "reverse": "true"}
            ],
            "acoustic_pop.json": [
                {"tag": "acoustic pop", "order": "votes", "reverse": "true"},
                {"tag": "singer-songwriter", "order": "votes", "reverse": "true"},
                {"tag": "coffeehouse", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "rock": {
        "dir": "assets/stations/rock",
        "files": {
            "!main_rock.json": [
                {"tag": "classic rock", "order": "votes", "reverse": "true"},
                {"name": "Rock Antenne", "order": "votes", "reverse": "true"},
                {"name": "Radio Caroline", "order": "votes", "reverse": "true"},
                {"name": "Virgin Rock", "order": "votes", "reverse": "true"}
            ],
            "indie_alt.json": [
                {"tag": "indie rock", "order": "votes", "reverse": "true"},
                {"tag": "alternative rock", "order": "votes", "reverse": "true"},
                {"name": "KEXP", "order": "votes", "reverse": "true"},
                {"name": "BBC 6 Music", "order": "votes", "reverse": "true"},
                {"name": "The Current", "order": "votes", "reverse": "true"}
            ],
            "prog_rock.json": [
                {"tag": "prog rock", "order": "votes", "reverse": "true"},
                {"tag": "progressive rock", "order": "votes", "reverse": "true"},
                {"name": "Morow", "order": "votes", "reverse": "true"}
            ],
            "punk_postpunk.json": [
                {"tag": "punk", "order": "votes", "reverse": "true"},
                {"tag": "post-punk", "order": "votes", "reverse": "true"},
                {"tag": "goth", "order": "votes", "reverse": "true"},
                {"tag": "darkwave", "order": "votes", "reverse": "true"}
            ],
            "psychedelic.json": [
                {"tag": "psychedelic rock", "order": "votes", "reverse": "true"},
                {"tag": "psych rock", "order": "votes", "reverse": "true"},
                {"tag": "space rock", "order": "votes", "reverse": "true"}
            ],
            "hard_rock.json": [
                {"tag": "hard rock", "order": "votes", "reverse": "true"},
                {"tag": "heavy rock", "order": "votes", "reverse": "true"}
            ],
            "grunge_90s.json": [
                {"tag": "grunge", "order": "votes", "reverse": "true"},
                {"tag": "90s rock", "order": "votes", "reverse": "true"},
                {"tag": "90s alternative", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "jazz": {
        "dir": "assets/stations/jazz",
        "files": {
            "!main_jazz.json": [
                {"tag": "jazz", "order": "votes", "reverse": "true"},
                {"name": "WBGO", "order": "votes", "reverse": "true"},
                {"name": "Jazz24", "order": "votes", "reverse": "true"},
                {"name": "TSF Jazz", "order": "votes", "reverse": "true"},
                {"name": "Radio Swiss Jazz", "order": "votes", "reverse": "true"},
                {"name": "WCLK", "order": "votes", "reverse": "true"}
            ],
            "bebop.json": [
                {"tag": "bebop", "order": "votes", "reverse": "true"},
                {"tag": "bop", "order": "votes", "reverse": "true"}
            ],
            "hardbop.json": [
                {"tag": "hardbop", "order": "votes", "reverse": "true"},
                {"tag": "hard bop", "order": "votes", "reverse": "true"},
                {"tag": "post-bop", "order": "votes", "reverse": "true"}
            ],
            "avantgarde.json": [
                {"tag": "avantgarde jazz", "order": "votes", "reverse": "true"},
                {"tag": "free jazz", "order": "votes", "reverse": "true"},
                {"tag": "avant-garde", "order": "votes", "reverse": "true"}
            ],
            "fusion.json": [
                {"tag": "jazz fusion", "order": "votes", "reverse": "true"},
                {"tag": "fusion", "order": "votes", "reverse": "true"}
            ],
            "latin.json": [
                {"tag": "latin jazz", "order": "votes", "reverse": "true"},
                {"tag": "bossa nova", "order": "votes", "reverse": "true"}
            ],
            "smooth.json": [
                {"tag": "smooth jazz", "order": "votes", "reverse": "true"},
                {"tag": "contemporary jazz", "order": "votes", "reverse": "true"}
            ],
            "traditional.json": [
                {"name": "dixieland", "order": "votes", "reverse": "true"},
                {"tag": "dixieland", "order": "votes", "reverse": "true"},
                {"name": "traditional jazz", "order": "votes", "reverse": "true"},
                {"name": "new orleans jazz", "order": "votes", "reverse": "true"}
            ],
            "gypsy.json": [
                {"name": "django", "order": "votes", "reverse": "true"},
                {"name": "gypsy jazz", "order": "votes", "reverse": "true"},
                {"name": "manouche", "order": "votes", "reverse": "true"},
                {"tag": "gypsy jazz", "order": "votes", "reverse": "true"}
            ],
            "vocal.json": [
                {"tag": "vocal jazz", "order": "votes", "reverse": "true"},
                {"tag": "jazz vocal", "order": "votes", "reverse": "true"}
            ],
            "bigband.json": [
                {"tag": "big band", "order": "votes", "reverse": "true"},
                {"tag": "swing", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "classical": {
        "dir": "assets/stations/classical",
        "files": {
            "!main_classical.json": [
                {"tag": "classical", "order": "votes", "reverse": "true"},
                {"name": "Classic FM", "order": "votes", "reverse": "true"},
                {"name": "BBC Radio 3", "order": "votes", "reverse": "true"},
                {"name": "France Musique", "order": "votes", "reverse": "true"},
                {"name": "WQXR", "order": "votes", "reverse": "true"},
                {"name": "Radio Swiss Classic", "order": "votes", "reverse": "true"}
            ],
            "baroque.json": [
                {"tag": "baroque", "order": "votes", "reverse": "true"},
                {"name": "Baroque", "order": "votes", "reverse": "true"}
            ],
            "romantic.json": [
                {"name": "chopin", "order": "votes", "reverse": "true"},
                {"name": "tchaikovsky", "order": "votes", "reverse": "true"},
                {"name": "brahms", "order": "votes", "reverse": "true"},
                {"name": "rachmaninoff", "order": "votes", "reverse": "true"},
                {"name": "liszt", "order": "votes", "reverse": "true"},
                {"name": "romantic", "tag": "classical", "order": "votes", "reverse": "true"}
            ],
            "contemporary.json": [
                {"tag": "contemporary classical", "order": "votes", "reverse": "true"},
                {"tag": "modern classical", "order": "votes", "reverse": "true"}
            ],
            "piano.json": [
                {"tag": "solo piano", "order": "votes", "reverse": "true"},
                {"tag": "classical piano", "order": "votes", "reverse": "true"},
                {"tag": "piano", "order": "votes", "reverse": "true"}
            ],
            "opera.json": [
                {"tag": "opera", "order": "votes", "reverse": "true"},
                {"name": "Operavore", "order": "votes", "reverse": "true"}
            ],
            "early_music.json": [
                {"tag": "early music", "order": "votes", "reverse": "true"},
                {"tag": "medieval", "order": "votes", "reverse": "true"},
                {"tag": "renaissance", "order": "votes", "reverse": "true"},
                {"tag": "gregorian", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "blues": {
        "dir": "assets/stations/blues",
        "files": {
            "!main_blues.json": [
                {"tag": "blues", "order": "votes", "reverse": "true"},
                {"name": "WWOZ", "order": "votes", "reverse": "true"},
                {"name": "Blues Radio UK", "order": "votes", "reverse": "true"},
                {"name": "Joint Radio Blues", "order": "votes", "reverse": "true"}
            ],
            "delta_acoustic.json": [
                {"tag": "delta blues", "order": "votes", "reverse": "true"},
                {"tag": "acoustic blues", "order": "votes", "reverse": "true"},
                {"tag": "country blues", "order": "votes", "reverse": "true"}
            ],
            "chicago_electric.json": [
                {"tag": "chicago blues", "order": "votes", "reverse": "true"},
                {"tag": "electric blues", "order": "votes", "reverse": "true"}
            ],
            "blues_rock.json": [
                {"tag": "blues rock", "order": "votes", "reverse": "true"},
                {"tag": "blues-rock", "order": "votes", "reverse": "true"}
            ],
            "jump_piano.json": [
                {"tag": "jump blues", "order": "votes", "reverse": "true"},
                {"name": "piano blues", "order": "votes", "reverse": "true"},
                {"name": "jump blues", "order": "votes", "reverse": "true"},
                {"name": "boogie", "order": "votes", "reverse": "true"},
                {"tag": "piano blues", "order": "votes", "reverse": "true"}
            ],
            "texas_louisiana.json": [
                {"name": "texas blues", "order": "votes", "reverse": "true"},
                {"name": "louisiana", "tag": "blues", "order": "votes", "reverse": "true"},
                {"name": "texas", "tag": "blues", "order": "votes", "reverse": "true"},
                {"name": "zydeco", "order": "votes", "reverse": "true"},
                {"tag": "swamp blues", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "metal": {
        "dir": "assets/stations/metal",
        "files": {
            "!main_metal.json": [
                {"tag": "heavy metal", "order": "votes", "reverse": "true"},
                {"tag": "metal", "order": "votes", "reverse": "true"},
                {"name": "Metal", "order": "votes", "reverse": "true"}
            ],
            "thrash_speed.json": [
                {"tag": "thrash metal", "order": "votes", "reverse": "true"},
                {"tag": "speed metal", "order": "votes", "reverse": "true"}
            ],
            "death_black.json": [
                {"tag": "death metal", "order": "votes", "reverse": "true"},
                {"tag": "black metal", "order": "votes", "reverse": "true"}
            ],
            "doom_sludge.json": [
                {"tag": "doom metal", "order": "votes", "reverse": "true"},
                {"tag": "stoner rock", "order": "votes", "reverse": "true"},
                {"tag": "sludge", "order": "votes", "reverse": "true"}
            ],
            "power_symphonic.json": [
                {"tag": "power metal", "order": "votes", "reverse": "true"},
                {"tag": "symphonic metal", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "reggae": {
        "dir": "assets/stations/reggae",
        "files": {
            "!main_reggae.json": [
                {"tag": "reggae", "order": "votes", "reverse": "true"},
                {"name": "Irie", "order": "votes", "reverse": "true"},
                {"name": "Joint Radio Reggae", "order": "votes", "reverse": "true"}
            ],
            "roots.json": [
                {"tag": "roots reggae", "order": "votes", "reverse": "true"},
                {"tag": "roots", "order": "votes", "reverse": "true"}
            ],
            "dub.json": [
                {"tag": "dub", "order": "votes", "reverse": "true"},
                {"tag": "dub reggae", "order": "votes", "reverse": "true"}
            ],
            "dancehall.json": [
                {"tag": "dancehall", "order": "votes", "reverse": "true"},
                {"tag": "ragga", "order": "votes", "reverse": "true"}
            ],
            "ska_rocksteady.json": [
                {"tag": "ska", "order": "votes", "reverse": "true"},
                {"tag": "rocksteady", "order": "votes", "reverse": "true"},
                {"tag": "2-tone", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "country": {
        "dir": "assets/stations/country",
        "files": {
            "!main_country.json": [
                {"tag": "country", "order": "votes", "reverse": "true"},
                {"name": "181.fm Country", "order": "votes", "reverse": "true"},
                {"name": "Country", "order": "votes", "reverse": "true"}
            ],
            "classic_outlaw.json": [
                {"tag": "classic country", "order": "votes", "reverse": "true"},
                {"tag": "outlaw country", "order": "votes", "reverse": "true"},
                {"tag": "honky tonk", "order": "votes", "reverse": "true"}
            ],
            "bluegrass.json": [
                {"tag": "bluegrass", "order": "votes", "reverse": "true"},
                {"name": "FreshGrass", "order": "votes", "reverse": "true"},
                {"name": "Bluegrass", "order": "votes", "reverse": "true"}
            ],
            "americana_folk.json": [
                {"tag": "americana", "order": "votes", "reverse": "true"},
                {"tag": "folk", "order": "votes", "reverse": "true"},
                {"tag": "alt-country", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "decades": {
        "dir": "assets/stations/decades",
        "files": {
            "!main_decades.json": [
                {"tag": "oldies", "order": "votes", "reverse": "true"},
                {"tag": "classic hits", "order": "votes", "reverse": "true"},
                {"tag": "retro", "order": "votes", "reverse": "true"}
            ],
            "50s_60s.json": [
                {"tag": "60s", "order": "votes", "reverse": "true"},
                {"tag": "50s", "order": "votes", "reverse": "true"},
                {"tag": "motown", "order": "votes", "reverse": "true"}
            ],
            "70s.json": [
                {"tag": "70s", "order": "votes", "reverse": "true"},
                {"tag": "disco", "order": "votes", "reverse": "true"},
                {"tag": "glam rock", "order": "votes", "reverse": "true"}
            ],
            "80s.json": [
                {"tag": "80s", "order": "votes", "reverse": "true"},
                {"tag": "new wave", "order": "votes", "reverse": "true"},
                {"tag": "synthpop", "order": "votes", "reverse": "true"}
            ],
            "90s.json": [
                {"tag": "90s", "order": "votes", "reverse": "true"},
                {"tag": "eurodance", "order": "votes", "reverse": "true"}
            ],
            "2000s.json": [
                {"tag": "2000s", "order": "votes", "reverse": "true"},
                {"tag": "y2k", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "chill": {
        "dir": "assets/stations/chill",
        "files": {
            "!main_chill.json": [
                {"tag": "chillout", "order": "votes", "reverse": "true"},
                {"tag": "ambient", "order": "votes", "reverse": "true"},
                {"tag": "relax", "order": "votes", "reverse": "true"},
                {"name": "SomaFM Groove Salad", "order": "votes", "reverse": "true"}
            ],
            "lofi_beats.json": [
                {"tag": "lofi", "order": "votes", "reverse": "true"},
                {"tag": "lo-fi", "order": "votes", "reverse": "true"},
                {"name": "Lofi Girl", "order": "votes", "reverse": "true"},
                {"name": "Chillhop", "order": "votes", "reverse": "true"}
            ],
            "ambient_drone.json": [
                {"tag": "ambient", "order": "votes", "reverse": "true"},
                {"tag": "drone", "order": "votes", "reverse": "true"},
                {"name": "Drone Zone", "order": "votes", "reverse": "true"}
            ],
            "downtempo_lounge.json": [
                {"tag": "lounge", "order": "votes", "reverse": "true"},
                {"tag": "downtempo", "order": "votes", "reverse": "true"},
                {"tag": "easy listening", "order": "votes", "reverse": "true"}
            ],
            "synthwave.json": [
                {"tag": "synthwave", "order": "votes", "reverse": "true"},
                {"tag": "retrowave", "order": "votes", "reverse": "true"},
                {"tag": "chillwave", "order": "votes", "reverse": "true"}
            ],
            "soundscapes.json": [
                {"tag": "soundscapes", "order": "votes", "reverse": "true"},
                {"tag": "nature sounds", "order": "votes", "reverse": "true"},
                {"tag": "meditation", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "urban": {
        "dir": "assets/stations/urban",
        "files": {
            "!main_hiphop.json": [
                {"tag": "hip hop", "order": "votes", "reverse": "true"},
                {"tag": "hiphop", "order": "votes", "reverse": "true"},
                {"name": "Hot 97", "order": "votes", "reverse": "true"},
                {"name": "Power 105.1", "order": "votes", "reverse": "true"}
            ],
            "golden_era_90s.json": [
                {"tag": "classic hip hop", "order": "votes", "reverse": "true"},
                {"tag": "old school hip hop", "order": "votes", "reverse": "true"},
                {"tag": "boom bap", "order": "votes", "reverse": "true"}
            ],
            "motown_soul.json": [
                {"tag": "soul", "order": "votes", "reverse": "true"},
                {"tag": "motown", "order": "votes", "reverse": "true"},
                {"tag": "classic soul", "order": "votes", "reverse": "true"}
            ],
            "funk_groove.json": [
                {"tag": "funk", "order": "votes", "reverse": "true"},
                {"tag": "groove", "order": "votes", "reverse": "true"},
                {"tag": "p-funk", "order": "votes", "reverse": "true"}
            ],
            "rnb_neosoul.json": [
                {"tag": "rnb", "order": "votes", "reverse": "true"},
                {"tag": "r&b", "order": "votes", "reverse": "true"},
                {"tag": "neo soul", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "news": {
        "dir": "assets/stations/news",
        "files": {
            "!main_news.json": [
                {"name": "BBC World Service", "order": "votes", "reverse": "true"},
                {"name": "NPR News", "order": "votes", "reverse": "true"},
                {"name": "France 24", "order": "votes", "reverse": "true"},
                {"name": "Deutsche Welle", "order": "votes", "reverse": "true"},
                {"name": "Al Jazeera", "order": "votes", "reverse": "true"},
                {"tag": "news", "order": "votes", "reverse": "true"}
            ],
            "public_radio.json": [
                {"name": "WNYC", "order": "votes", "reverse": "true"},
                {"name": "KQED", "order": "votes", "reverse": "true"},
                {"name": "WBEZ", "order": "votes", "reverse": "true"},
                {"name": "Minnesota Public Radio", "order": "votes", "reverse": "true"},
                {"name": "WFMU", "order": "votes", "reverse": "true"},
                {"tag": "public radio", "order": "votes", "reverse": "true"}
            ],
            "sports_talk.json": [
                {"tag": "sports", "order": "votes", "reverse": "true"},
                {"name": "talkSPORT", "order": "votes", "reverse": "true"},
                {"name": "ESPN Radio", "order": "votes", "reverse": "true"}
            ]
        }
    }
}

def curate_world(base_dir: str):
    print("\n=======================================================")
    print(" Curating & Enriching WORLD directory")
    print("=======================================================")
    
    world_base = os.path.join(base_dir, "assets/stations/world")
    
    # 1. Harvest existing stations to preserve user's hand-crafted work
    existing_world = {}
    for root, _, files in os.walk(world_base):
        for f in files:
            if f.endswith(".json"):
                full_p = os.path.join(root, f)
                rel_p = os.path.relpath(full_p, world_base)
                existing_world[rel_p] = load_json(full_p)

    # A) Balkan & East Euro
    balkan_dir = os.path.join(world_base, "balkan_euro")
    os.makedirs(balkan_dir, exist_ok=True)
    
    balkan_folk_merged = {}
    for k in [
        "balkan_euro/balkan_folk.json",
        "euro/easteuro/balkan/balkanfolk.json",
        "euro/easteuro/balkan/balkanfolk2.json",
        "euro/easteuro/balkan/balkanfolk3.json"
    ]:
        balkan_folk_merged.update(existing_world.get(k, {}))
        
    curated_balkan_folk = curate_category(balkan_folk_merged, [{"tag": "balkan folk"}, {"tag": "balkan"}], target_count=20)
    save_json(os.path.join(balkan_dir, "balkan_folk.json"), curated_balkan_folk)
    
    balkan_pop_exist = existing_world.get("balkan_euro/balkan_pop.json", existing_world.get("euro/easteuro/balkan/balkanpop.json", {}))
    curated_balkan_pop = curate_category(balkan_pop_exist, [{"tag": "balkan pop"}, {"name": "balkan pop"}], target_count=14)
    save_json(os.path.join(balkan_dir, "balkan_pop.json"), curated_balkan_pop)
    
    greek_exist = existing_world.get("balkan_euro/greek_folk.json", existing_world.get("euro/easteuro/greekfolk.json", {}))
    curated_greek = curate_category(greek_exist, [{"tag": "greek folk"}, {"tag": "rebetiko"}], target_count=16)
    save_json(os.path.join(balkan_dir, "greek_folk.json"), curated_greek)
    
    drap_exist = existing_world.get("balkan_euro/deutschrap.json", existing_world.get("euro/germany/deutschrap.json", {}))
    save_json(os.path.join(balkan_dir, "deutschrap.json"), drap_exist)
    
    dpop_exist = existing_world.get("balkan_euro/deutschpop.json", existing_world.get("euro/germany/deutschpop.json", {}))
    save_json(os.path.join(balkan_dir, "deutschpop.json"), dpop_exist)

    # B) Latin
    latin_dir = os.path.join(world_base, "latin")
    os.makedirs(latin_dir, exist_ok=True)
    
    latin_main = curate_category(load_json(os.path.join(latin_dir, "!main_latin.json")), [{"tag": "latin", "order": "votes", "reverse": "true"}], target_count=16)
    save_json(os.path.join(latin_dir, "!main_latin.json"), latin_main)
    
    salsa = curate_category(load_json(os.path.join(latin_dir, "salsa.json")), [{"tag": "salsa", "order": "votes", "reverse": "true"}], target_count=16)
    save_json(os.path.join(latin_dir, "salsa.json"), salsa)
    
    cumbia = curate_category(load_json(os.path.join(latin_dir, "cumbia.json")), [{"tag": "cumbia", "order": "votes", "reverse": "true"}], target_count=16)
    save_json(os.path.join(latin_dir, "cumbia.json"), cumbia)
    
    tango = curate_category(load_json(os.path.join(latin_dir, "tango.json")), [{"name": "tango", "order": "votes", "reverse": "true"}], target_count=14)
    save_json(os.path.join(latin_dir, "tango.json"), tango)
    
    flamenco = curate_category(load_json(os.path.join(latin_dir, "flamenco.json")), [{"tag": "flamenco", "order": "votes", "reverse": "true"}], target_count=14)
    save_json(os.path.join(latin_dir, "flamenco.json"), flamenco)
    
    mariachi = curate_category(load_json(os.path.join(latin_dir, "mariachi_ranchera.json")), [{"tag": "mariachi", "order": "votes", "reverse": "true"}], target_count=14)
    save_json(os.path.join(latin_dir, "mariachi_ranchera.json"), mariachi)
    
    bossa_exist = existing_world.get("latin/bossa_samba.json", existing_world.get("latin/bossa.json", {}))
    curated_bossa = curate_category(bossa_exist, [{"tag": "bossa nova", "order": "votes", "reverse": "true"}, {"tag": "samba", "order": "votes", "reverse": "true"}], target_count=16)
    save_json(os.path.join(latin_dir, "bossa_samba.json"), curated_bossa)
    
    reggaeton_exist = existing_world.get("latin/reggaeton.json", {})
    save_json(os.path.join(latin_dir, "reggaeton.json"), reggaeton_exist)

    # C) Asia
    asia_dir = os.path.join(world_base, "asia")
    os.makedirs(asia_dir, exist_ok=True)
    
    bollywood_exist = existing_world.get("asia/bollywood_desi.json", existing_world.get("bollywood.json", {}))
    curated_bollywood = curate_category(bollywood_exist, [{"tag": "bollywood", "order": "votes", "reverse": "true"}, {"tag": "hindi", "order": "votes", "reverse": "true"}], target_count=16)
    save_json(os.path.join(asia_dir, "bollywood_desi.json"), curated_bollywood)
    
    indian_classical = curate_category(load_json(os.path.join(asia_dir, "indian_classical.json")), [{"name": "classical", "tag": "indian", "order": "votes", "reverse": "true"}], target_count=12)
    save_json(os.path.join(asia_dir, "indian_classical.json"), indian_classical)
    
    punjabi = curate_category(load_json(os.path.join(asia_dir, "punjabi_bhangra.json")), [{"tag": "punjabi", "order": "votes", "reverse": "true"}, {"tag": "bhangra", "order": "votes", "reverse": "true"}], target_count=14)
    save_json(os.path.join(asia_dir, "punjabi_bhangra.json"), punjabi)
    
    citypop = curate_category(load_json(os.path.join(asia_dir, "japanese_citypop.json")), [{"name": "city pop", "order": "votes", "reverse": "true"}], target_count=12)
    save_json(os.path.join(asia_dir, "japanese_citypop.json"), citypop)

    # D) Celtic
    celtic_dir = os.path.join(world_base, "celtic")
    os.makedirs(celtic_dir, exist_ok=True)
    
    celtic = curate_category(load_json(os.path.join(celtic_dir, "celtic_irish.json")), [{"tag": "celtic", "order": "votes", "reverse": "true"}, {"tag": "irish folk", "order": "votes", "reverse": "true"}], target_count=16)
    save_json(os.path.join(celtic_dir, "celtic_irish.json"), celtic)
    
    pipes = curate_category(load_json(os.path.join(celtic_dir, "scottish_bagpipes.json")), [{"tag": "bagpipes", "order": "votes", "reverse": "true"}], target_count=10)
    save_json(os.path.join(celtic_dir, "scottish_bagpipes.json"), pipes)

def run_genre(genre_key: str, base_dir: str):
    if genre_key == "world":
        curate_world(base_dir)
        return
        
    if genre_key not in GENRE_SPECS:
        print(f"Unknown genre: {genre_key}")
        return
        
    spec = GENRE_SPECS[genre_key]
    target_dir = os.path.join(base_dir, spec["dir"])
    print(f"\n=======================================================")
    print(f" Processing Genre: {genre_key.upper()} -> {target_dir}")
    print(f"=======================================================")
    
    os.makedirs(target_dir, exist_ok=True)
    for filename, queries in spec["files"].items():
        file_path = os.path.join(target_dir, filename)
        src_stations = load_json(file_path)
        print(f"  * Curating {genre_key}/{filename} ...")
        stations = curate_category(src_stations, queries, target_count=16, max_count=22)
        save_json(file_path, stations)

def main():
    base = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    args = sys.argv[1:]
    
    all_keys = list(GENRE_SPECS.keys()) + ["world"]
    
    if not args or "-h" in args or "--help" in args:
        print("Usage: python3 tools/curate_catalog.py [genre1 genre2 ... | all]")
        print("\nAvailable genres:")
        for g in all_keys:
            print(f"  - {g}")
        sys.exit(0)
        
    if "all" in args:
        for g in all_keys:
            run_genre(g, base)
    else:
        for g in args:
            run_genre(g.lower(), base)

if __name__ == "__main__":
    main()
