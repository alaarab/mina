#!/usr/bin/env python3
"""Check Python syntax and exercise dependency-backed tools without credentials."""
import ast
from pathlib import Path
import tempfile
import time

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from PIL import Image


repo = Path(__file__).resolve().parent.parent
scripts = sorted(repo.rglob("*.py"))
scripts = [p for p in scripts if not any(part.startswith(".") for part in p.relative_to(repo).parts)]
for path in scripts:
    ast.parse(path.read_text(), filename=str(path))
print(f"Python syntax: {len(scripts)} scripts pass")

# Execute the real icon generator in a scratch repo so checked-in artwork is untouched.
with tempfile.TemporaryDirectory(prefix="mina-tooling-") as directory:
    root = Path(directory)
    script = root / "scripts" / "make-appicon.py"
    script.parent.mkdir()
    exec(compile((repo / "scripts/make-appicon.py").read_text(), str(script), "exec"), {"__file__": str(script)})
    with Image.open(root / "Mina/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png") as icon:
        icon.load()
        assert icon.size == (1024, 1024) and icon.mode == "RGB"
        assert icon.getpixel((0, 0)) == (0xE4, 0x82, 0x6F)
        assert icon.getpixel((470, 700)) == (0xFF, 0xF4, 0xE6)
print("Pillow icon generation: valid image, sky and moon pixels pass")

# Compile only ASC's actual token function; module initialization reads owner credentials.
module = ast.parse((repo / "scripts/asc.py").read_text())
token = next(node for node in module.body if isinstance(node, ast.FunctionDef) and node.name == "token")
key = ec.generate_private_key(ec.SECP256R1())
namespace = {
    "jwt": jwt, "time": time,
    "cfg": {"issuer_id": "offline-test", "key_id": "ephemeral"},
    "KEY": key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()),
}
exec(compile(ast.Module(body=[token], type_ignores=[]), "asc-token", "exec"), namespace)
encoded = namespace["token"]()
claims = jwt.decode(encoded, key.public_key(), algorithms=["ES256"], audience="appstoreconnect-v1", issuer="offline-test")
assert claims["exp"] - claims["iat"] == 1100
assert jwt.get_unverified_header(encoded)["kid"] == "ephemeral"
print("ASC token: actual ES256 signing, verification and claims pass")
