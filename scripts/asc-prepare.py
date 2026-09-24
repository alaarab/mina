#!/usr/bin/env python3
"""Fill Mina's free price and review metadata without submitting for review."""
import argparse
import json
from decimal import Decimal
from pathlib import Path
from asc import APP, call

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--contact-phone", help="Owner-approved review contact, including country code")
parser.add_argument("--public-distribution", action="store_true", help="Enable public distribution in Apple's available territories")
args = parser.parse_args()

versions = call("GET", f"/apps/{APP}/appStoreVersions?limit=50")["data"]
version = next(v for v in versions if v["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION")
vid = version["id"]
existing = call("GET", f"/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
notes = (Path(__file__).resolve().parents[1] / "docs/store/listing.md").read_text().split("**Review notes**:", 1)[1].strip()
attributes = {
    "contactFirstName": "Ala", "contactLastName": "Arab", "contactEmail": "alaarab@gmail.com",
    "demoAccountRequired": False, "notes": notes,
}
if args.contact_phone:
    attributes["contactPhone"] = args.contact_phone
if existing:
    call("PATCH", f"/appStoreReviewDetails/{existing['id']}", {"data": {
        "type": "appStoreReviewDetails", "id": existing["id"], "attributes": attributes,
    }})
else:
    call("POST", "/appStoreReviewDetails", {"data": {
        "type": "appStoreReviewDetails", "attributes": attributes,
        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}},
    }})
print("Review record verified:", json.dumps(call("GET", f"/appStoreVersions/{vid}/appStoreReviewDetail")["data"]["attributes"]))

try:
    current = call("GET", f"/apps/{APP}/appPriceSchedule?include=baseTerritory,manualPrices")
except SystemExit as error:
    if "HTTP 404" not in str(error):
        raise
    current = {}
if current.get("data"):
    print("Existing price schedule retained:", current["data"]["id"])
else:
    path = f"/apps/{APP}/appPricePoints?filter[territory]=USA&limit=200"
    free = None
    while path and free is None:
        page = call("GET", path)
        free = next((p for p in page["data"] if Decimal(p["attributes"]["customerPrice"]) == 0), None)
        path = page.get("links", {}).get("next")
    if free is None:
        raise SystemExit("Apple returned no free US price point; no pricing change made.")
    body = {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": APP}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${mina-free}"}]},
        }},
        "included": [{"type": "appPrices", "id": "${mina-free}",
            "attributes": {"startDate": None, "endDate": None},
            "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}},
        }],
    }
    call("POST", "/appPriceSchedules", body)
    schedule = call("GET", f"/apps/{APP}/appPriceSchedule")["data"]
    prices = call("GET", f"/appPriceSchedules/{schedule['id']}/manualPrices?include=appPricePoint")
    print("Price schedule verified:", json.dumps(prices))

schedule = call("GET", f"/apps/{APP}/appPriceSchedule")["data"]
prices = call("GET", f"/appPriceSchedules/{schedule['id']}/manualPrices?include=appPricePoint")
print("Current prices:", json.dumps(prices.get("included", [])))

if args.public_distribution:
    try:
        availability = call("GET", f"/apps/{APP}/appAvailabilityV2").get("data")
    except SystemExit as error:
        if "HTTP 404" not in str(error):
            raise
        availability = None
    if availability:
        print("Existing distribution availability retained:", availability["id"])
    else:
        territories = []
        path = "/territories?limit=200"
        while path:
            page = call("GET", path)
            territories.extend(page["data"])
            path = page.get("links", {}).get("next")
        items = [{"type": "territoryAvailabilities", "id": "${" + t["id"] + "}",
            "attributes": {"available": True, "preOrderEnabled": False},
            "relationships": {"territory": {"data": {"type": "territories", "id": t["id"]}}},
        } for t in territories]
        body = {"data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP}},
                "territoryAvailabilities": {"data": [{"type": i["type"], "id": i["id"]} for i in items]},
            }}, "included": items}
        call("POST", "https://api.appstoreconnect.apple.com/v2/appAvailabilities", body)
        verified = call("GET", f"/apps/{APP}/appAvailabilityV2")["data"]
        print("Public availability configured:", verified["id"], "territories:", len(items))
