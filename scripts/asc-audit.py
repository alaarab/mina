#!/usr/bin/env python3
"""Read Mina's current submission, price, availability and uploaded assets."""
import json
from asc import APP, call


def read(label, path):
    try:
        result = call("GET", path)
    except SystemExit as error:
        print(json.dumps({label: {"error": str(error)}}))
        return []
    data = result.get("data") or []
    items = data if isinstance(data, list) else [data]
    print(json.dumps({label: [
        {"id": item["id"], "attributes": item.get("attributes", {}), "relationships": {
            key: value["data"] for key, value in item.get("relationships", {}).items() if "data" in value
        }} for item in items
    ]}, indent=2))
    return items


versions = read("versions", f"/apps/{APP}/appStoreVersions?limit=50&include=build")
for version in versions:
    vid = version["id"]
    read("reviewDetails", f"/appStoreVersions/{vid}/appStoreReviewDetail")
    localizations = read("localizations", f"/appStoreVersions/{vid}/appStoreVersionLocalizations")
    for localization in localizations:
        lid = localization["id"]
        sets = read("screenshotSets", f"/appStoreVersionLocalizations/{lid}/appScreenshotSets")
        for item in sets:
            read("screenshots", f"/appScreenshotSets/{item['id']}/appScreenshots")
        previews = read("previewSets", f"/appStoreVersionLocalizations/{lid}/appPreviewSets")
        for item in previews:
            read("previews", f"/appPreviewSets/{item['id']}/appPreviews")
read("priceSchedule", f"/apps/{APP}/appPriceSchedule?include=baseTerritory,manualPrices")
read("availability", f"/apps/{APP}/appAvailabilityV2")
read("reviewSubmissions", f"/apps/{APP}/reviewSubmissions")
