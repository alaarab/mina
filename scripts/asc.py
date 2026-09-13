"""App Store Connect API helper for the Mina 1.0 submission."""
import hashlib, json, pathlib, sys, time, urllib.request, urllib.error
import jwt

cfg = json.load(open(pathlib.Path.home() / ".config/ios-release.json"))
KEY = pathlib.Path(cfg["key_path"]).expanduser().read_text()
APP = "6811499089"
S = pathlib.Path(__file__).parent.parent / "docs" / "store"

def token():
    return jwt.encode({"iss": cfg["issuer_id"], "iat": int(time.time()), "exp": int(time.time()) + 1100, "aud": "appstoreconnect-v1"}, KEY, algorithm="ES256", headers={"kid": cfg["key_id"]})

def call(method, path, body=None, raw=False):
    url = path if path.startswith("http") else "https://api.appstoreconnect.apple.com/v1" + path
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}, method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        resp = urllib.request.urlopen(req, timeout=120)
        data = resp.read()
        return json.loads(data) if data and not raw else (data if raw else {})
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:500]
        raise SystemExit(f"{method} {path}: HTTP {e.code} {detail}")

def upload(path: pathlib.Path, create_path: str, relationships: dict, extra_attrs=None):
    """Reserve, upload the parts, commit. Returns the created resource."""
    data = path.read_bytes()
    body = {"data": {"type": create_path.strip("/"), "attributes": {"fileName": path.name, "fileSize": len(data), **(extra_attrs or {})}, "relationships": relationships}}
    res = call("POST", create_path, body)["data"]
    for op in res["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]: op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"], headers={h["name"]: h["value"] for h in op["requestHeaders"]})
        urllib.request.urlopen(req, timeout=300).read()
    call("PATCH", f"{create_path}/{res['id']}", {"data": {"type": create_path.strip("/"), "id": res["id"], "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    return res
