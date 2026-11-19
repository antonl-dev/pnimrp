#!/usr/bin/env python3
"""
tools/curate_catalog.py
Autonomous Radio-Browser API query, verification, and catalog generator for pnimrp.
"""

import urllib.request
import urllib.parse
import ssl
import json
import os
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

VALID_AUDIO_TYPES = {
    "audio/mpeg", "audio/mp3", "audio/aac", "audio/aacp", "audio/x-aac",
    "audio/ogg", "application/ogg", "audio/opus", "audio/flac", "audio/x-flac",
    "audio/x-mpegurl", "audio/x-scpls", "application/vnd.apple.mpegurl"
}

def verify_stream(url: str, timeout: float = 4.0) -> Tuple[bool, str]:
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

EXCLUDE_NAME_KEYWORDS = [
    "christmas", "xmas", "holiday", "noel", "navidad", "weihnacht"
]

def clean_station_name(raw_name: str, max_len: int = 22) -> str:
    name = raw_name.strip()
    
    # Strip tech suffixes
    for suffix in [
        "[128k]", "(128k)", "[64k]", "(64k)", "[320k]", "(320k)",
        "(AAC)", "[AAC]", "(MP3)", "[MP3]", " - MP3", " - AAC", " 128k", " 320k"
    ]:
        if name.endswith(suffix):
            name = name[:-len(suffix)].strip()
            
    # Shorten well-known prefixes
    prefixes = [
        ("Radio Caprice - ", "radcap "),
        ("Radio Caprice: ", "radcap "),
        ("Radio Caprice ", "radcap "),
        ("181.FM - ", "181.fm "),
        ("181.fm - ", "181.fm "),
        ("Concertzender - ", "Concertzender "),
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
    # If cut off at '(' or '[', strip it cleanly
    if name.endswith("(") or name.endswith("["):
        name = name[:-1].strip()
    elif "(" in name and ")" not in name:
        name = name.split("(")[0].strip()
    return name

def curate_category(
    existing_file: Optional[str],
    queries: List[Dict[str, str]],
    target_count: int = 15,
    max_count: int = 22
) -> Dict[str, str]:
    stations: Dict[str, str] = {}
    seen_urls = set()
    
    # Check existing file
    if existing_file and os.path.exists(existing_file):
        try:
            with open(existing_file, "r", encoding="utf-8") as fp:
                data = json.load(fp)
                for name, url in data.get("stations", {}).items():
                    if any(bad in name.lower() for bad in EXCLUDE_NAME_KEYWORDS):
                        continue
                    clean_n = clean_station_name(name)
                    ok, final_url = verify_stream(url, timeout=3.5)
                    if ok:
                        stations[clean_n] = final_url or url
                        seen_urls.add((final_url or url).lower())
        except Exception:
            pass

    # Query Radio-Browser
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

    # Prefer votes then bitrate
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

# Plan definitions
GENRE_SPECS = {
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
    "blues": {
        "dir": "assets/stations/blues",
        "migrate_from": "assets/stations/blues.json",
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
    "classical": {
        "dir": "assets/stations/classical",
        "migrate_from": "assets/stations/classical.json",
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
    "rock": {
        "dir": "assets/stations/rock",
        "migrate_from": "assets/stations/rock.json",
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
    "metal": {
        "dir": "assets/stations/metal",
        "migrate_from": "assets/stations/metal.json",
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
        "migrate_from": "assets/stations/reggae.json",
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
        "migrate_from": "assets/stations/country.json",
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
    }
}

def run_genre(genre_key: str, base_dir: str):
    spec = GENRE_SPECS[genre_key]
    target_dir = os.path.join(base_dir, spec["dir"])
    migrate_from = spec.get("migrate_from")
    if migrate_from:
        migrate_path = os.path.join(base_dir, migrate_from)
    else:
        migrate_path = None
        
    print(f"\n=======================================================")
    print(f" Processing Genre: {genre_key.upper()} -> {target_dir}")
    print(f"=======================================================")
    
    os.makedirs(target_dir, exist_ok=True)
    
    for filename, queries in spec["files"].items():
        file_path = os.path.join(target_dir, filename)
        # Use existing sub-file or migrate_path if this is the main file
        src_file = file_path if os.path.exists(file_path) else (migrate_path if filename.startswith("!main") else None)
        print(f"\n* Curating {genre_key}/{filename} (target: 14-18 stations) ...")
        
        stations = curate_category(src_file, queries, target_count=16, max_count=22)
        save_json(file_path, stations)
        
    # If there was a flat file that was transformed into a directory, clean up flat file
    if migrate_path and os.path.exists(migrate_path):
        os.remove(migrate_path)
        print(f"  [Migration Complete] Removed legacy flat file {migrate_path}")

if __name__ == "__main__":
    base = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    genres = sys.argv[1:] if len(sys.argv) > 1 else list(GENRE_SPECS.keys())
    for g in genres:
        if g in GENRE_SPECS:
            run_genre(g, base)
