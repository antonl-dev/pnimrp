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
import re
import shutil
import sys
import time
import socket
from typing import Dict, List, Tuple, Optional
from concurrent.futures import ThreadPoolExecutor

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
    
    # Strip bitrate and codec suffixes in brackets/parentheses or at end
    name = re.sub(r'\s*[\(\[]\s*\d*\s*k?(?:bps)?\s*(?:mp3|aac|aacp|aac\+|ogg|flac|opus)?\s*[\)\]]', '', name, flags=re.IGNORECASE)
    name = re.sub(r'\s*-\s*\d+\s*k?(?:bps)?\s*(?:mp3|aac|aacp|aac\+|ogg|flac|opus)?$', '', name, flags=re.IGNORECASE)
    name = re.sub(r'\s+\d+k\b', '', name, flags=re.IGNORECASE)
    
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

def get_station_match_key(name: str) -> str:
    n = name.lower()
    n = re.sub(r'[\(\[].*?[\)\]]', '', n)
    for prefix in [
        "radio caprice - ", "radio caprice: ", "radio caprice ", "radcap ",
        "181.fm - ", "181.fm ", "181fm ", "somafm - ", "somafm ",
        "concertzender - ", "concertzender ", "cz ",
        "radio ", "r. ", "r "
    ]:
        if n.startswith(prefix):
            n = n[len(prefix):]
            break
    return re.sub(r'[^a-z0-9]', '', n)

GENERIC_SLUGS = {
    "stream", "live", "radio", "listen", "autodj", "broadcast", "1", "2", "3", "audio", "online", "main", "hq"
}

GENRE_NEGATIVE_TAGS: Dict[str, List[str]] = {
    "blues_rock": [
        "death metal", "prog rock", "progressive rock", "metalcore", "hair metal",
        "edm", "techno", "house", "trance", "hip hop", "rap", "eurodance",
        "talk", "news", "luxembourg", "disco", "pop rock", "italiana"
    ],
    "dancehall": [
        "techno", "trance", "house", "edm", "hypertechno", "eurodance",
        "ambient", "charts", "mashup", "deep house", "heavy metal", "rock",
        "classical", "talk", "news", "peru", "huancayo", "surf"
    ],
    "ambient_drone": [
        "hard rock", "metal", "techno", "trance", "edm", "hip hop", "dance",
        "pop rock", "punk", "talk", "news"
    ],
    "dub": [
        "dubstep", "house", "techno", "trance", "pop", "rock", "metal",
        "hair metal", "talk"
    ],
    "roots": [
        "techno", "house", "edm", "pop", "metal", "talk", "news"
    ],
    "death_black": [
        "pop", "dance", "edm", "hip hop", "r&b", "country", "reggae", "disco", "talk"
    ],
    "thrash_speed": [
        "pop", "dance", "edm", "hip hop", "r&b", "country", "reggae", "disco", "talk"
    ],
    "doom_sludge": [
        "pop", "dance", "edm", "hip hop", "r&b", "country", "synthwave", "disco"
    ],
    "delta_acoustic": [
        "heavy metal", "hard rock", "techno", "edm", "dance", "synth", "pop"
    ],
    "chicago_electric": [
        "death metal", "techno", "edm", "dance", "pop", "talk"
    ]
}

def score_purity(item: Dict, target_keywords: List[str], genre_key: str = "") -> float:
    name = (item.get("name") or "").lower()
    raw_tags = (item.get("tags") or "").lower()
    tags = [t.strip() for t in raw_tags.split(",") if t.strip()]
    votes = item.get("votes", 0)
    country = (item.get("countrycode") or "").upper()
    
    # Negative tags check
    negs = GENRE_NEGATIVE_TAGS.get(genre_key, [])
    for neg in negs:
        if neg in tags or neg in name:
            return -999.0
            
    # Tag spam check (> 20 tags is tag soup spammer)
    if len(tags) > 20:
        return -500.0
        
    score = 0.0
    
    # 1. Name match bonus (very strong signal)
    for kw in target_keywords:
        if kw in name:
            score += 60.0
            break
            
    # 2. Tag position bonus
    if tags:
        for kw in target_keywords:
            if kw == tags[0]:
                score += 40.0
                break
            elif len(tags) > 1 and kw == tags[1]:
                score += 25.0
                break
            elif kw in tags:
                score += 15.0
                break
                
    # 3. RadCap format-strict bonus
    if name.startswith("radcap ") or name.startswith("radio caprice"):
        score += 50.0
        
    # 4. Regional authenticity (e.g. Jamaica for dancehall)
    if genre_key == "dancehall" and country == "JM":
        score += 25.0
        
    # 5. Tag count penalty (stations with > 10 tags get penalized for dilution)
    if len(tags) > 10:
        score -= (len(tags) - 10) * 3.0
        
    # 6. Capped vote bonus (votes only act as tie-breakers between pure stations)
    score += min(votes, 50) * 0.2
    return score

def extract_mountpoint(url: str) -> str:
    path = url.split("?")[0].rstrip("/")
    seg = path.split("/")[-1]
    seg = re.sub(r"\.(?:mp3|aac|aacp|ogg|opus|flac|m3u8|pls)$", "", seg, flags=re.IGNORECASE)
    seg = re.sub(r"[-_]\d+k?$", "", seg, flags=re.IGNORECASE)
    seg = re.sub(r"[-_]\d+[-_](?:mp3|aac|aacp|ogg|opus|flac)$", "", seg, flags=re.IGNORECASE)
    seg = seg.lower()
    return seg if (len(seg) >= 4 and seg not in GENERIC_SLUGS) else ""

def infer_bitrate_codec(name: str, url: str) -> Tuple[int, str]:
    text = (name + " " + url).lower()
    bitrate = 0
    for br in [320, 256, 192, 160, 128, 96, 64, 48, 32]:
        if f"{br}k" in text or f"-{br}-" in text or f"_{br}_" in text or f"_{br}k" in text or f"/{br}" in text or f"-{br}." in text or f"/{br}." in text or f"-{br}-" in text:
            bitrate = br
            break
    codec = ""
    for cod in ["aacp", "aac", "opus", "ogg", "flac", "mp3"]:
        if cod in text:
            codec = cod
            break
    return bitrate, codec

def curate_category(
    existing_stations: Optional[Dict[str, Any]],
    queries: List[Dict[str, str]],
    target_count: int = 16,
    max_count: int = 22,
    subgenre_key: str = ""
) -> Dict[str, Any]:
    station_streams: Dict[str, List[Dict[str, Any]]] = {}
    key_to_name: Dict[str, str] = {}
    slug_to_name: Dict[str, str] = {}
    seen_urls = set()
    
    # 1. Parallel preflight of existing stations
    if existing_stations:
        valid_items = []
        for name, val in existing_stations.items():
            if any(bad in name.lower() for bad in EXCLUDE_NAME_KEYWORDS):
                continue
            if subgenre_key and subgenre_key in GENRE_NEGATIVE_TAGS:
                negs = GENRE_NEGATIVE_TAGS[subgenre_key]
                if any(neg in name.lower() for neg in negs):
                    continue
            clean_n = clean_station_name(name)
            match_k = get_station_match_key(clean_n)
            
            # Determine target_name by match_k or stream slug
            target_name = ""
            if match_k in key_to_name:
                target_name = key_to_name[match_k]
            
            if isinstance(val, str):
                slug = extract_mountpoint(val)
                if not target_name and slug and slug in slug_to_name:
                    target_name = slug_to_name[slug]
                if not target_name:
                    target_name = clean_n
                    key_to_name[match_k] = target_name
                    station_streams[target_name] = []
                if slug:
                    slug_to_name[slug] = target_name
                br, cod = infer_bitrate_codec(name, val)
                valid_items.append((target_name, match_k, slug, val, br, cod, ""))
            elif isinstance(val, dict):
                streams = val.get("streams", [])
                if not streams:
                    def_u = val.get("default") or val.get("url") or ""
                    if def_u:
                        slug = extract_mountpoint(def_u)
                        if not target_name and slug and slug in slug_to_name:
                            target_name = slug_to_name[slug]
                        if not target_name:
                            target_name = clean_n
                            key_to_name[match_k] = target_name
                            station_streams[target_name] = []
                        if slug:
                            slug_to_name[slug] = target_name
                        br, cod = infer_bitrate_codec(name, def_u)
                        valid_items.append((target_name, match_k, slug, def_u, br, cod, ""))
                else:
                    first_u = ""
                    for s in streams:
                        u = s.get("url", "") if isinstance(s, dict) else (s if isinstance(s, str) else "")
                        if u:
                            first_u = u
                            break
                    slug = extract_mountpoint(first_u) if first_u else ""
                    if not target_name and slug and slug in slug_to_name:
                        target_name = slug_to_name[slug]
                    if not target_name:
                        target_name = clean_n
                        key_to_name[match_k] = target_name
                        station_streams[target_name] = []
                    if slug:
                        slug_to_name[slug] = target_name
                    for s in streams:
                        if isinstance(s, dict) and s.get("url"):
                            s_url = s["url"]
                            s_br = s.get("bitrate", 0)
                            s_cod = s.get("codec", "")
                            s_reg = s.get("region", "")
                            s_slug = extract_mountpoint(s_url)
                            if s_slug:
                                slug_to_name[s_slug] = target_name
                            if s_br == 0:
                                inf_br, inf_cod = infer_bitrate_codec(name, s_url)
                                s_br = inf_br
                                if not s_cod: s_cod = inf_cod
                            valid_items.append((target_name, match_k, s_slug, s_url, s_br, s_cod, s_reg))
                        elif isinstance(s, str):
                            s_slug = extract_mountpoint(s)
                            if s_slug:
                                slug_to_name[s_slug] = target_name
                            br, cod = infer_bitrate_codec(name, s)
                            valid_items.append((target_name, match_k, s_slug, s, br, cod, ""))
            
        with ThreadPoolExecutor(max_workers=8) as executor:
            futures = [
                (target_name, match_k, slug, url, br, cod, reg, executor.submit(verify_stream, url, 3.5))
                for target_name, match_k, slug, url, br, cod, reg in valid_items
            ]
            for target_name, match_k, slug, url, br, cod, reg, fut in futures:
                try:
                    ok, final_url = fut.result()
                    if ok:
                        u = final_url or url
                        if u.lower() not in seen_urls:
                            seen_urls.add(u.lower())
                            if target_name not in station_streams:
                                station_streams[target_name] = []
                            station_streams[target_name].append({
                                "url": u,
                                "bitrate": br,
                                "codec": cod,
                                "region": reg
                            })
                except Exception:
                    pass

    # 2. Query Radio-Browser to discover additional bitrates and new stations
    if queries:
        target_keywords = set()
        for q in queries:
            if "tag" in q:
                target_keywords.add(q["tag"].lower())
            if "name" in q:
                target_keywords.add(q["name"].lower())
        if subgenre_key:
            target_keywords.add(subgenre_key.replace("_", " "))
        target_keywords_list = list(target_keywords)

        candidates = []
        for q in queries:
            res = query_radio_browser(q, limit=60)
            for item in res:
                url = item.get("url_resolved") or item.get("url")
                if not url or url.lower() in seen_urls:
                    continue
                name = item.get("name", "").strip()
                if any(bad in name.lower() for bad in EXCLUDE_NAME_KEYWORDS):
                    continue
                purity = score_purity(item, target_keywords_list, subgenre_key)
                if purity <= 0:
                    continue
                votes = item.get("votes", 0)
                bitrate = item.get("bitrate", 0)
                codec = (item.get("codec") or "").lower()
                region = (item.get("countrycode") or "").upper()
                candidates.append((purity, votes, bitrate, name, url, codec, region))

        candidates.sort(key=lambda x: (x[0], x[1]), reverse=True)
        
        to_check = []
        for purity, votes, bitrate, raw_name, url, codec, region in candidates:
            if url.lower() in seen_urls:
                continue
            clean_n = clean_station_name(raw_name)
            match_k = get_station_match_key(clean_n)
            
            if match_k in key_to_name:
                target_name = key_to_name[match_k]
                if bitrate <= 0:
                    inf_br, _ = infer_bitrate_codec(raw_name, url)
                    if inf_br <= 0:
                        continue
                    bitrate = inf_br
                if len(station_streams.get(target_name, [])) >= 4:
                    continue
            else:
                if len(station_streams) >= target_count:
                    continue
                target_name = clean_n
                
            to_check.append((target_name, match_k, url, bitrate, codec, region))
            if len(to_check) >= 40:
                break
                
        with ThreadPoolExecutor(max_workers=8) as executor:
            cand_futures = [
                (target_name, match_k, url, br, cod, reg, executor.submit(verify_stream, url, 3.5))
                for target_name, match_k, url, br, cod, reg in to_check
            ]
            for target_name, match_k, url, br, cod, reg, fut in cand_futures:
                try:
                    ok, final_url = fut.result()
                    if ok:
                        u = final_url or url
                        if u.lower() not in seen_urls:
                            seen_urls.add(u.lower())
                            if target_name not in station_streams:
                                if len(station_streams) < max_count:
                                    station_streams[target_name] = []
                                    key_to_name[match_k] = target_name
                                else:
                                    continue
                            if len(station_streams[target_name]) < 4:
                                station_streams[target_name].append({
                                    "url": u,
                                    "bitrate": br,
                                    "codec": cod,
                                    "region": reg
                                })
                except Exception:
                    pass
            
    stations: Dict[str, Any] = {}
    for name, s_list in list(station_streams.items())[:max_count]:
        if not s_list:
            continue
        seen_base_urls = set()
        bitrate_map: Dict[int, str] = {}
        default_url = s_list[0]["url"]
        
        for s in s_list:
            full_u = s.get("url", "")
            if not full_u:
                continue
            base_u = full_u.split("?")[0].lower().rstrip("/")
            if base_u in seen_base_urls:
                continue
            seen_base_urls.add(base_u)
            
            br = s.get("bitrate", 0)
            if br <= 0:
                inf_br, _ = infer_bitrate_codec(name, full_u)
                br = inf_br
                
            if br > 0 and br not in bitrate_map:
                bitrate_map[br] = full_u
                
        if len(bitrate_map) >= 2:
            sorted_bitrates = sorted(bitrate_map.keys(), reverse=True)
            stations[name] = {
                "default": bitrate_map[sorted_bitrates[0]],
                "streams": [{"url": bitrate_map[b], "bitrate": b} for b in sorted_bitrates]
            }
        elif len(bitrate_map) == 1:
            stations[name] = list(bitrate_map.values())[0]
        else:
            stations[name] = default_url
        
    return stations

def save_json(path: str, stations: Dict[str, Any]):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fp:
        json.dump({"stations": stations}, fp, indent=2, ensure_ascii=False)
        fp.write("\n")
    print(f"  [OK] Saved {len(stations)} stations to {path}")

def load_json(path: str) -> Dict[str, Any]:
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
            ],
            "fm_hits.json": [
                {"tag": "hits", "order": "votes", "reverse": "true"},
                {"tag": "top40", "order": "votes", "reverse": "true"}
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
            ],
            "classic_rock.json": [
                {"tag": "classic rock", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "electronic": {
        "dir": "assets/stations/electronic",
        "files": {
            "!main_edm.json": [
                {"tag": "edm", "order": "votes", "reverse": "true"},
                {"tag": "electronic", "order": "votes", "reverse": "true"},
                {"tag": "dance", "order": "votes", "reverse": "true"}
            ],
            "house.json": [
                {"tag": "house", "order": "votes", "reverse": "true"},
                {"tag": "deep house", "order": "votes", "reverse": "true"},
                {"tag": "tech house", "order": "votes", "reverse": "true"}
            ],
            "techno.json": [
                {"tag": "techno", "order": "votes", "reverse": "true"},
                {"tag": "minimal techno", "order": "votes", "reverse": "true"}
            ],
            "trance.json": [
                {"tag": "trance", "order": "votes", "reverse": "true"},
                {"tag": "psytrance", "order": "votes", "reverse": "true"},
                {"tag": "vocal trance", "order": "votes", "reverse": "true"}
            ],
            "drumandbass.json": [
                {"tag": "drum and bass", "order": "votes", "reverse": "true"},
                {"tag": "dnb", "order": "votes", "reverse": "true"},
                {"tag": "jungle", "order": "votes", "reverse": "true"}
            ],
            "dubstep.json": [
                {"tag": "dubstep", "order": "votes", "reverse": "true"},
                {"tag": "riddim", "order": "votes", "reverse": "true"}
            ],
            "ambient.json": [
                {"tag": "ambient", "order": "votes", "reverse": "true"},
                {"tag": "drone ambient", "order": "votes", "reverse": "true"},
                {"name": "Drone Zone", "order": "votes", "reverse": "true"}
            ],
            "downtempo.json": [
                {"tag": "downtempo", "order": "votes", "reverse": "true"},
                {"tag": "trip hop", "order": "votes", "reverse": "true"}
            ],
            "synth.json": [
                {"tag": "synthwave", "order": "votes", "reverse": "true"},
                {"tag": "darksynth", "order": "votes", "reverse": "true"},
                {"tag": "spacesynth", "order": "votes", "reverse": "true"}
            ],
            "chiptune.json": [
                {"tag": "chiptune", "order": "votes", "reverse": "true"},
                {"tag": "8-bit", "order": "votes", "reverse": "true"},
                {"tag": "bitpop", "order": "votes", "reverse": "true"}
            ],
            "breakbeat.json": [
                {"tag": "breakbeat", "order": "votes", "reverse": "true"},
                {"tag": "big beat", "order": "votes", "reverse": "true"}
            ],
            "disco.json": [
                {"tag": "disco", "order": "votes", "reverse": "true"},
                {"tag": "nu-disco", "order": "votes", "reverse": "true"},
                {"tag": "italo disco", "order": "votes", "reverse": "true"}
            ],
            "garage.json": [
                {"tag": "uk garage", "order": "votes", "reverse": "true"},
                {"tag": "future garage", "order": "votes", "reverse": "true"}
            ],
            "hardstyle.json": [
                {"tag": "hardstyle", "order": "votes", "reverse": "true"},
                {"tag": "hardcore", "order": "votes", "reverse": "true"}
            ],
            "idm.json": [
                {"tag": "idm", "order": "votes", "reverse": "true"},
                {"tag": "glitch", "order": "votes", "reverse": "true"}
            ],
            "electrohouse.json": [
                {"tag": "electro house", "order": "votes", "reverse": "true"},
                {"tag": "club dance", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "religious": {
        "dir": "assets/stations/religious",
        "files": {
            "!main_religious.json": [
                {"tag": "religious", "order": "votes", "reverse": "true"},
                {"tag": "christian", "order": "votes", "reverse": "true"}
            ],
            "gospel.json": [
                {"tag": "gospel", "order": "votes", "reverse": "true"},
                {"tag": "black gospel", "order": "votes", "reverse": "true"},
                {"tag": "southern gospel", "order": "votes", "reverse": "true"}
            ],
            "catholic.json": [
                {"tag": "catholic", "order": "votes", "reverse": "true"},
                {"name": "Vatican", "order": "votes", "reverse": "true"}
            ],
            "orthodox.json": [
                {"tag": "orthodox", "order": "votes", "reverse": "true"},
                {"tag": "byzantine", "order": "votes", "reverse": "true"}
            ],
            "islamic.json": [
                {"tag": "islamic", "order": "votes", "reverse": "true"},
                {"tag": "quran", "order": "votes", "reverse": "true"}
            ],
            "jewish.json": [
                {"tag": "jewish", "order": "votes", "reverse": "true"},
                {"name": "Jewish", "order": "votes", "reverse": "true"}
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
            ],
            "easy_listening.json": [
                {"tag": "easy listening", "order": "votes", "reverse": "true"},
                {"tag": "lounge", "order": "votes", "reverse": "true"}
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
    },
    "soma": {
        "dir": "assets/stations/soma",
        "files": {
            "soma1.json": [
                {"name": "SomaFM", "order": "votes", "reverse": "true"},
                {"tag": "somafm", "order": "votes", "reverse": "true"}
            ],
            "soma2.json": [
                {"name": "SomaFM", "order": "votes", "reverse": "true"},
                {"tag": "somafm", "order": "votes", "reverse": "true"}
            ],
            "soma3.json": [
                {"name": "SomaFM", "order": "votes", "reverse": "true"},
                {"tag": "somafm", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "radioparadise": {
        "dir": "assets/stations/radioparadise",
        "files": {
            "radioparadise.json": [
                {"name": "Radio Paradise", "order": "votes", "reverse": "true"}
            ]
        }
    },
    "fip": {
        "dir": "assets/stations/fip",
        "files": {
            "fip.json": [
                {"name": "FIP", "order": "votes", "reverse": "true"}
            ]
        }
    }
}

def curate_world(stations_dir: str):
    print("\n=======================================================")
    print(" Curating & Enriching WORLD directory")
    print("=======================================================")
    
    world_base = os.path.join(stations_dir, "world")
    
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

def run_genre(genre_key: str, stations_dir: str):
    if genre_key == "world":
        curate_world(stations_dir)
        return
        
    if genre_key not in GENRE_SPECS:
        print(f"Unknown genre: {genre_key}")
        return
        
    spec = GENRE_SPECS[genre_key]
    subdir = os.path.basename(spec.get("dir", genre_key))
    target_dir = os.path.join(stations_dir, subdir)
    print(f"\n=======================================================")
    print(f" Processing Genre: {genre_key.upper()} -> {target_dir}")
    print(f"=======================================================")
    
    os.makedirs(target_dir, exist_ok=True)
    for filename, queries in spec["files"].items():
        file_path = os.path.join(target_dir, filename)
        src_stations = load_json(file_path)
        sub_key = filename.replace(".json", "").lstrip("!")
        print(f"  * Curating {genre_key}/{filename} (purity: {sub_key}) ...")
        stations = curate_category(src_stations, queries, target_count=16, max_count=22, subgenre_key=sub_key)
        save_json(file_path, stations)

def audit_catalog(stations_dir: str) -> bool:
    print("\n=======================================================")
    print(f" Catalog Audit: {stations_dir}")
    print("=======================================================")
    
    total_files = 0
    total_stations = 0
    name_violations = []
    count_violations = []
    json_errors = []
    genre_counts = {}
    
    for root, dirs, files in os.walk(stations_dir):
        if "deadStation" in root:
            continue
        rel_dir = os.path.relpath(root, stations_dir)
        genre = rel_dir.split(os.sep)[0]
        if genre == ".":
            genre = "root"
            
        for f in sorted(files):
            if not f.endswith(".json"):
                continue
            total_files += 1
            fpath = os.path.join(root, f)
            rel_file = os.path.relpath(fpath, stations_dir)
            try:
                with open(fpath, "r", encoding="utf-8") as fp:
                    data = json.load(fp)
            except Exception as e:
                json_errors.append((rel_file, str(e)))
                continue
                
            stations = data.get("stations", {})
            st_len = len(stations)
            total_stations += st_len
            genre_counts[genre] = genre_counts.get(genre, 0) + st_len
            
            if st_len > 22:
                count_violations.append((rel_file, st_len))
                
            for name, url in stations.items():
                if len(name) > 22:
                    name_violations.append((rel_file, name, len(name)))
                    
    print(f"\nAudit Summary:")
    print(f"  Total JSON files:    {total_files}")
    print(f"  Total Live stations: {total_stations}")
    print(f"\nGenre Breakdown:")
    for g, count in sorted(genre_counts.items()):
        print(f"  - {g:<16}: {count} stations")
        
    print("\nValidation Results:")
    has_issues = False
    if json_errors:
        has_issues = True
        print(f"  [FAIL] {len(json_errors)} JSON syntax error(s):")
        for f, err in json_errors:
            print(f"    * {f}: {err}")
    else:
        print("  [PASS] 0 JSON syntax errors")
        
    if count_violations:
        has_issues = True
        print(f"  [FAIL] {len(count_violations)} file(s) exceed 22 stations limit:")
        for f, count in count_violations:
            print(f"    * {f}: {count} stations (max 22)")
    else:
        print("  [PASS] 0 station count violations (all <= 22 stations)")
        
    if name_violations:
        has_issues = True
        print(f"  [FAIL] {len(name_violations)} station name(s) exceed 22 chars:")
        for f, name, l in name_violations[:10]:
            print(f"    * [{f}] '{name}' ({l} chars)")
        if len(name_violations) > 10:
            print(f"    ... and {len(name_violations) - 10} more")
    else:
        print("  [PASS] 0 station name length violations (all <= 22 chars)")
        
    if not has_issues:
        print("\nAll constraints PASSED: catalog is 100% compliant with pnimrp UI constraints!\n")
    return not has_issues

def search_stations(query: str, limit: int = 10):
    print(f"\n[Search] Querying Radio-Browser for '{query}'...")
    results = query_radio_browser({"name": query, "limit": limit * 2, "order": "votes", "reverse": "true"})
    if not results:
        results = query_radio_browser({"tag": query, "limit": limit * 2, "order": "votes", "reverse": "true"})
    
    if not results:
        print(f"  No stations found matching '{query}'.")
        return
        
    print(f"Found {len(results)} candidate(s). Preflighting streams...\n")
    print(f"{'Clean Name (<=22)':<24} | {'Status':<6} | {'Bitrate':<7} | Stream URL")
    print("-" * 80)
    count = 0
    for item in results:
        if count >= limit:
            break
        raw_name = item.get("name", "").strip()
        url = item.get("url_resolved") or item.get("url")
        bitrate = item.get("bitrate", 0)
        clean_n = clean_station_name(raw_name)
        ok, final_url = verify_stream(url, timeout=2.5)
        status_str = "OK" if ok else "DEAD"
        if ok:
            print(f"{clean_n:<24} | {status_str:<6} | {bitrate:<7} | {final_url or url}")
            count += 1
    print()

def resolve_stations_dir(custom_path: str = None) -> str:
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    if not custom_path:
        return os.path.join(repo_root, "assets", "stations")
    
    p = os.path.abspath(custom_path)
    if os.path.basename(p) == "stations":
        return p
    if os.path.isdir(os.path.join(p, "stations")):
        return os.path.join(p, "stations")
    if os.path.isdir(os.path.join(p, "assets", "stations")):
        return os.path.join(p, "assets", "stations")
    return p

def clean_catalog(stations_dir: str):
    print(f"\n[Cleanup] Cleaning, pruning duplicates, and stripping codec/region from: {stations_dir}")
    total_cleaned = 0
    multi_count = 0
    single_count = 0
    
    for root, dirs, files in os.walk(stations_dir):
        if "deadStation" in root:
            continue
        for f in sorted(files):
            if not f.endswith(".json"):
                continue
            path = os.path.join(root, f)
            try:
                with open(path, "r", encoding="utf-8") as fp:
                    data = json.load(fp)
            except Exception:
                continue
            stations = data.get("stations", {})
            cleaned = {}
            for name, val in stations.items():
                if isinstance(val, dict):
                    streams = val.get("streams", [])
                    seen_base_urls = set()
                    bitrate_map: Dict[int, str] = {}
                    default_url = val.get("default") or (streams[0].get("url") if streams and isinstance(streams[0], dict) else "")
                    
                    for s in streams:
                        if isinstance(s, dict):
                            full_u = s.get("url", "")
                            br = s.get("bitrate", 0)
                        elif isinstance(s, str):
                            full_u = s
                            br = 0
                        else:
                            continue
                        if not full_u:
                            continue
                        # Deduplicate by base audio path (ignoring query params)
                        base_u = full_u.split("?")[0].lower().rstrip("/")
                        if base_u in seen_base_urls:
                            continue
                        seen_base_urls.add(base_u)
                        
                        # Infer bitrate from URL/name if 0
                        if br <= 0:
                            inf_br, _ = infer_bitrate_codec(name, full_u)
                            br = inf_br
                            
                        if br > 0 and br not in bitrate_map:
                            bitrate_map[br] = full_u
                            
                    if len(bitrate_map) >= 2:
                        sorted_bitrates = sorted(bitrate_map.keys(), reverse=True)
                        cleaned[name] = {
                            "default": bitrate_map[sorted_bitrates[0]],
                            "streams": [{"url": bitrate_map[b], "bitrate": b} for b in sorted_bitrates]
                        }
                        multi_count += 1
                    elif len(bitrate_map) == 1:
                        cleaned[name] = list(bitrate_map.values())[0]
                        single_count += 1
                    else:
                        cleaned[name] = default_url or (streams[0].get("url") if streams and isinstance(streams[0], dict) else "")
                        single_count += 1
                else:
                    cleaned[name] = val
                    single_count += 1
                    
            with open(path, "w", encoding="utf-8") as fp:
                json.dump({"stations": cleaned}, fp, indent=2, ensure_ascii=False)
                fp.write("\n")
            total_cleaned += 1
            
    print(f"  [OK] Successfully cleaned {total_cleaned} JSON files.")
    print(f"  [OK] Multi-bitrate stations: {multi_count}")
    print(f"  [OK] Single-stream stations: {single_count}\n")

def main():
    import argparse
    all_keys = list(GENRE_SPECS.keys()) + ["world"]
    
    parser = argparse.ArgumentParser(
        description="Poor Man's Radio Player (pnimrp) Catalog Curation Engine",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Available genres:\n  " + "\n  ".join(f"- {k}" for k in all_keys) + "\n\nExamples:\n"
               "  python3 tools/curate_catalog.py jazz\n"
               "  python3 tools/curate_catalog.py soma fm181\n"
               "  python3 tools/curate_catalog.py --dir assets/stations pop rock\n"
               "  python3 tools/curate_catalog.py --audit\n"
               "  python3 tools/curate_catalog.py --clean\n"
               "  python3 tools/curate_catalog.py --search \"lofi\"\n"
               "  python3 tools/curate_catalog.py all\n"
    )
    parser.add_argument("genres", nargs="*", help="Genres to curate (e.g. jazz, pop, rock, soma, fm181, world, all)")
    parser.add_argument("--dir", "-d", dest="custom_dir", default=None, help="Custom stations or assets directory (defaults to repo assets/stations)")
    parser.add_argument("--list", "-l", action="store_true", help="List all available genres and exit")
    parser.add_argument("--audit", "-a", action="store_true", help="Audit catalog for pnimrp UI constraints (<=22 stations, <=22 name chars, valid JSON)")
    parser.add_argument("--clean", "-c", action="store_true", help="Clean all station JSONs: prune duplicates/0k bitrates, strip codec/region, flatten 1-stream stations")
    parser.add_argument("--search", "-s", dest="search_query", default=None, help="Search Radio-Browser for stations by name/tag and test live stream")
    
    args = parser.parse_args()
    
    stations_dir = resolve_stations_dir(args.custom_dir)
    
    if args.clean:
        clean_catalog(stations_dir)
        sys.exit(0)
        
    if args.audit:
        ok = audit_catalog(stations_dir)
        sys.exit(0 if ok else 1)
        
    if args.search_query:
        search_stations(args.search_query)
        sys.exit(0)
        
    if args.list or not args.genres:
        parser.print_help()
        sys.exit(0)
        
    print(f"[Engine] Target stations directory: {stations_dir}")
    
    targets = all_keys if "all" in [g.lower() for g in args.genres] else [g.lower() for g in args.genres]
    for g in targets:
        run_genre(g, stations_dir)

if __name__ == "__main__":
    main()
