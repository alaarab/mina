#!/usr/bin/env python3
"""Archive an XcodeGen iOS app and upload it to TestFlight.

Works for any project laid out like this one (project.yml, automatic signing).
Signing and upload credentials come from ~/.config/ios-release.json:

    {
      "team": "ABCDE12345",
      "key_id": "ABC123DEFG",
      "issuer_id": "00000000-0000-0000-0000-000000000000",
      "key_path": "~/.private_keys/AuthKey_ABC123DEFG.p8"
    }

The App Store Connect API key (Users and Access > Integrations > App Store
Connect API, role App Manager) lets xcodebuild upload without an Xcode login.
Build numbers auto-increment per app in ~/.config/ios-release/<scheme>.build.
"""
import argparse
import json
import plistlib
import subprocess
import sys
from datetime import datetime
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--dir", type=Path, default=Path(__file__).resolve().parents[1], help="Project directory (has project.yml)")
parser.add_argument("--scheme", help="Scheme and .xcodeproj name (default: name: in project.yml)")
parser.add_argument("--build-number", type=int, help="Override the auto-incremented build number")
parser.add_argument("--marketing-version", help="Override CFBundleShortVersionString for this build")
parser.add_argument("--config", type=Path, default=Path("~/.config/ios-release.json").expanduser())
parser.add_argument("--export-only", action="store_true", help="Make the IPA but don't upload")
parser.add_argument("--skip-tests", action="store_true")
parser.add_argument("--extra", action="append", default=[], help="Extra xcodebuild argument (repeatable)")
args = parser.parse_args()

root = args.dir.resolve()
if not (root / "project.yml").exists():
    sys.exit(f"No project.yml in {root}")

try:
    config = json.loads(args.config.read_text())
except FileNotFoundError:
    sys.exit(f"Missing {args.config}. See the docstring at the top of {__file__} for its shape.")
for key in ("team", "key_id", "issuer_id", "key_path"):
    if not config.get(key):
        sys.exit(f"{args.config} needs a \"{key}\" value.")
key_path = Path(config["key_path"]).expanduser()
if not key_path.exists():
    sys.exit(f"API key file not found: {key_path}")

scheme = args.scheme
if not scheme:
    for line in (root / "project.yml").read_text().splitlines():
        if line.startswith("name:"):
            scheme = line.split(":", 1)[1].strip()
            break
if not scheme:
    sys.exit("Pass --scheme; project.yml has no top-level name.")

counter = Path("~/.config/ios-release").expanduser() / f"{scheme}.build"
counter.parent.mkdir(parents=True, exist_ok=True)
build_number = args.build_number or (int(counter.read_text().strip() or 0) + 1 if counter.exists() else 1)


def run(command, **kwargs):
    print("+", " ".join(str(part) for part in command), flush=True)
    return subprocess.run(command, cwd=root, check=True, **kwargs)


run(["xcodegen", "generate"])
project = f"{scheme}.xcodeproj"
settings = [f"CURRENT_PROJECT_VERSION={build_number}", f"DEVELOPMENT_TEAM={config['team']}", "CODE_SIGN_STYLE=Automatic"]
if args.marketing_version:
    settings.append(f"MARKETING_VERSION={args.marketing_version}")

if not args.skip_tests:
    run(["xcodebuild", "-project", project, "-scheme", scheme, "-destination", "platform=iOS Simulator,name=iPhone 17 Pro",
         "-derivedDataPath", "./.dd", "-quiet", "test"] + args.extra)

stamp = datetime.now().strftime("%Y%m%d-%H%M")
output = Path("~/Library/Developer/Xcode/Archives").expanduser() / scheme / f"{build_number}-{stamp}"
output.mkdir(parents=True, exist_ok=True)
archive = output / f"{scheme}.xcarchive"
run(["xcodebuild", "-project", project, "-scheme", scheme, "-configuration", "Release", "-destination", "generic/platform=iOS",
     "-archivePath", str(archive), "-allowProvisioningUpdates", "-quiet",
     "-authenticationKeyPath", str(key_path), "-authenticationKeyID", config["key_id"], "-authenticationKeyIssuerID", config["issuer_id"],
     "archive"] + settings + args.extra)

options = output / "ExportOptions.plist"
with options.open("wb") as handle:
    plistlib.dump({
        "method": "app-store-connect",
        "destination": "export" if args.export_only else "upload",
        "signingStyle": "automatic",
        "teamID": config["team"],
        "uploadSymbols": True,
        "manageAppVersionAndBuildNumber": False,
    }, handle)
run(["xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportPath", str(output / "export"),
     "-exportOptionsPlist", str(options), "-allowProvisioningUpdates",
     "-authenticationKeyPath", str(key_path), "-authenticationKeyID", config["key_id"], "-authenticationKeyIssuerID", config["issuer_id"]])

counter.write_text(str(build_number))
where = f"exported to {output / 'export'}" if args.export_only else "uploaded; it appears in TestFlight once App Store Connect finishes processing (10–30 min)"
print(f"\n{scheme} build {build_number} {where}.")
