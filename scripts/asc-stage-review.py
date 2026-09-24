#!/usr/bin/env python3
"""Stage the current Mina version for review; never submits it to Apple."""
import json
from asc import APP, call

versions = call("GET", f"/apps/{APP}/appStoreVersions?limit=50")["data"]
version = next(v for v in versions if v["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION")
submissions = call("GET", f"/apps/{APP}/reviewSubmissions")["data"]
submission = next((s for s in submissions if s["attributes"]["state"] == "READY_FOR_REVIEW"), None)
if submission is None:
    submission = call("POST", "/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}},
    }})["data"]
sid = submission["id"]
items = call("GET", f"/reviewSubmissions/{sid}/items?include=appStoreVersion")["data"]
if not any(i.get("relationships", {}).get("appStoreVersion", {}).get("data", {}).get("id") == version["id"] for i in items):
    call("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}},
    }}})
print(json.dumps(call("GET", f"/reviewSubmissions/{sid}?include=items"), indent=2))
