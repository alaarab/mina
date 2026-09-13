"""Pushes docs/store/listing.md into App Store Connect for the current version. Needs ~/.config/ios-release.json (see release.py)."""
from asc import *
t = (pathlib.Path(__file__).parent.parent / "docs/store/listing.md").read_text()
def between(start, end):
    a = t.index(start) + len(start); b = t.index(end, a); return t[a:b].strip()
desc = between("**Description** (4000):", "**Keywords**"); promo = between("**Promotional text** (170):", "**Description**")
kw = between("**Keywords** (100):", "**What's new**"); notes = t.split("**Review notes**:")[1].strip()
changelog = (pathlib.Path(__file__).parent.parent / "CHANGELOG.md").read_text()
newest = changelog.split("\n## ")[1]
whats_new = "\n".join(l[2:] for l in newest.split("\n") if l.startswith("- "))[:4000]
VERSION = "d8bace76-8047-4f98-8c82-5e8466535ea2"; INFO = "d77a3162-b64b-45bc-9409-7929b0cd566e"

locs = call("GET", f"/appStoreVersions/{VERSION}/appStoreVersionLocalizations")["data"]
loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
attrs = {"description": desc, "keywords": kw, "promotionalText": promo, "whatsNew": whats_new,
         "supportUrl": "https://alaarab.github.io/mina/", "marketingUrl": "https://alaarab.github.io/mina/"}
if loc:
    try:
        call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": attrs}})
    except SystemExit:
        attrs.pop("whatsNew", None)   # a first version has no What's New field
        call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": attrs}})
else:
    loc = call("POST", "/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations", "attributes": dict(locale="en-US", **attrs),
               "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION}}}}})["data"]
print("version localization:", loc["id"])

call("PATCH", f"/appStoreVersions/{VERSION}", {"data": {"type": "appStoreVersions", "id": VERSION, "attributes": {"copyright": "2026 Ala Arab", "releaseType": "AFTER_APPROVAL"}}})
print("copyright + release type set")

ilocs = call("GET", f"/appInfos/{INFO}/appInfoLocalizations")["data"]
iloc = next((l for l in ilocs if l["attributes"]["locale"] == "en-US"), None)
iattrs = {"subtitle": "Newborn log for two phones", "privacyPolicyUrl": "https://alaarab.github.io/mina/privacy.html"}
if iloc:
    call("PATCH", f"/appInfoLocalizations/{iloc['id']}", {"data": {"type": "appInfoLocalizations", "id": iloc["id"], "attributes": iattrs}})
else:
    call("POST", "/appInfoLocalizations", {"data": {"type": "appInfoLocalizations", "attributes": dict(locale="en-US", name="Mina Tracker", **iattrs),
         "relationships": {"appInfo": {"data": {"type": "appInfos", "id": INFO}}}}})
print("subtitle + privacy URL set")

call("PATCH", f"/appInfos/{INFO}", {"data": {"type": "appInfos", "id": INFO, "relationships": {
    "primaryCategory": {"data": {"type": "appCategories", "id": "HEALTH_AND_FITNESS"}},
    "secondaryCategory": {"data": {"type": "appCategories", "id": "LIFESTYLE"}}}}})
print("categories set")

decl = call("GET", f"/appInfos/{INFO}/ageRatingDeclaration")["data"]
none_fields = ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes", "matureOrSuggestiveThemes",
               "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity",
               "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"]
rating = {f: "NONE" for f in none_fields}
rating.update({"gambling": False, "unrestrictedWebAccess": False})
call("PATCH", f"/ageRatingDeclarations/{decl['id']}", {"data": {"type": "ageRatingDeclarations", "id": decl["id"], "attributes": rating}})
print("age rating set")

rd = call("GET", f"/appStoreVersions/{VERSION}/appStoreReviewDetail")
review = {"contactFirstName": "Ala", "contactLastName": "Arab", "contactEmail": "alaarab@gmail.com", "demoAccountRequired": False, "notes": notes}
if rd.get("data"):
    call("PATCH", f"/appStoreReviewDetails/{rd['data']['id']}", {"data": {"type": "appStoreReviewDetails", "id": rd["data"]["id"], "attributes": review}})
else:
    call("POST", "/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": review,
         "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION}}}}})
print("review details set")
