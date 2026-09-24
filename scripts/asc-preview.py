#!/usr/bin/env python3
"""Upload the reviewed Sarah preview; retain existing assets, never submit."""
import argparse
import hashlib
from pathlib import Path
from asc import APP, call, upload

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("path", type=Path)
args = parser.parse_args()
path = args.path.resolve()
versions = call("GET", f"/apps/{APP}/appStoreVersions?limit=50")["data"]
version = next(v for v in versions if v["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION")
localizations = call("GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
localization = next(item for item in localizations if item["attributes"]["locale"] == "en-US")
sets = call("GET", f"/appStoreVersionLocalizations/{localization['id']}/appPreviewSets")["data"]
preview_set = next(item for item in sets if item["attributes"]["previewType"] == "IPHONE_67")
sid = preview_set["id"]
previews = call("GET", f"/appPreviewSets/{sid}/appPreviews")["data"]
digest = hashlib.md5(path.read_bytes()).hexdigest()
existing = next((item for item in previews if item["attributes"].get("sourceFileChecksum") == digest), None)
if existing is None:
    if len(previews) >= 3:
        raise SystemExit("All preview slots are occupied; no existing assets were removed.")
    existing = upload(path, "/appPreviews", {"appPreviewSet": {"data": {"type": "appPreviewSets", "id": sid}}},
        {"mimeType": "video/mp4", "previewFrameTimeCode": "00:00:01:00"})
pid = existing["id"]
state = call("GET", f"/appPreviews/{pid}")["data"]["attributes"]["assetDeliveryState"]
print("Preview", pid, "state", state, flush=True)
if state["state"] == "COMPLETE":
    # Make Sarah primary without deleting the earlier uploaded preview.
    ordered = [{"type": "appPreviews", "id": pid}] + [
        {"type": "appPreviews", "id": item["id"]} for item in previews if item["id"] != pid]
    call("PATCH", f"/appPreviewSets/{sid}/relationships/appPreviews", {"data": ordered})
    print("Sarah is the primary preview; earlier assets retained.")
else:
    print("Run this command again after processing to set the verified preview first.")
