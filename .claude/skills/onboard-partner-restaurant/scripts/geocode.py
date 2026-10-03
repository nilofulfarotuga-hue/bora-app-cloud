"""Geocodifica a morada do info.yaml → lat/lng via Google Maps Geocoding API.

Se info.yaml já tiver lat/lng válidos, respeita-os (não chama API).
Valida o resultado contra a bounding box do continente PT.

Uso:
    python geocode.py --dir ".claude/.ai/onboard/belmonte-grill"
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import requests
import yaml  # type: ignore

from _shared import Ctx, log

PT_BOX = (36.9, 42.2, -9.6, -6.2)  # lat_min, lat_max, lng_min, lng_max


def geocode_address(address: str, key: str) -> tuple[float, float]:
    r = requests.get(
        "https://maps.googleapis.com/maps/api/geocode/json",
        params={"address": address, "region": "pt", "key": key},
        timeout=30,
    )
    r.raise_for_status()
    data = r.json()
    if data.get("status") != "OK" or not data.get("results"):
        raise RuntimeError(f"Geocoding falhou: {data.get('status')}")
    loc = data["results"][0]["geometry"]["location"]
    return float(loc["lat"]), float(loc["lng"])


def in_pt(lat: float, lng: float) -> bool:
    a, b, c, d = PT_BOX
    return a <= lat <= b and c <= lng <= d


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    args = ap.parse_args()
    onboard_dir = Path(args.dir)
    ctx = Ctx.load()

    info_path = onboard_dir / "info.yaml"
    data = yaml.safe_load(info_path.read_text(encoding="utf-8")) or {}
    r = data.get("restaurant", data)

    lat, lng = r.get("lat"), r.get("lng")
    if lat and lng and in_pt(float(lat), float(lng)):
        log(f"lat/lng já presentes e válidos: {lat},{lng}")
        return 0

    if not ctx.google_maps_key:
        log("GOOGLE_MAPS_API_KEY ausente — não é possível geocodificar.", "ERROR")
        return 1
    try:
        lat, lng = geocode_address(str(r["address"]), ctx.google_maps_key)
    except Exception as e:  # noqa: BLE001
        log(f"Erro a geocodificar: {e}", "ERROR")
        return 1
    if not in_pt(lat, lng):
        log(f"Coordenadas fora do continente PT: {lat},{lng}", "ERROR")
        return 1

    r["lat"], r["lng"] = lat, lng
    if "restaurant" in data:
        data["restaurant"] = r
    else:
        data = r
    info_path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False),
                         encoding="utf-8")
    log(f"Geocodificado: {lat},{lng} (escrito em info.yaml)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
