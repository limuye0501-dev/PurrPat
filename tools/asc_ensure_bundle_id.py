#!/usr/bin/env python3
"""Register com.limuye.purrpat on App Store Connect when it is missing.

Reads ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID. Does not print secrets.
The TestFlight workflow treats a failure here as non-fatal: automatic signing
still runs, and upload needs the App Store Connect app record either way.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

BUNDLE = "com.limuye.purrpat"
APP_ID = os.environ.get("ASC_APP_ID", "6838995846")
APP_NAME = "Purr Pat"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    if not der or der[0] != 0x30:
        raise ValueError("bad signature")
    i = 2

    def read_int() -> bytes:
        nonlocal i
        if der[i] != 0x02:
            raise ValueError("bad signature")
        length = der[i + 1]
        i += 2
        val = der[i : i + length]
        i += length
        return val.lstrip(b"\x00")

    return read_int().rjust(32, b"\x00") + read_int().rjust(32, b"\x00")


def make_jwt(key_path: str, key_id: str, issuer: str) -> str:
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = b64url(
        json.dumps({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode()
    )
    signing = f"{header}.{payload}".encode()
    der = subprocess.check_output(["openssl", "dgst", "-sha256", "-sign", key_path], input=signing)
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


def request(token: str, url: str, payload: dict | None = None, method: str | None = None) -> dict:
    data = None if payload is None else json.dumps(payload).encode()
    verb = method or ("GET" if payload is None else "POST")
    req = urllib.request.Request(
        url,
        data=data,
        method=verb,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    last_error = None
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=40) as res:
                body = res.read()
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:400]
            raise RuntimeError(f"ASC {exc.code} {verb} {url.split('?')[0]} {detail}") from None
        except urllib.error.URLError as exc:
            last_error = exc
            print(f"network {attempt + 1}: {exc}")
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"ASC network {verb} {url.split('?')[0]} {last_error}")


def token() -> str:
    return make_jwt(os.environ["ASC_KEY_PATH"], os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"])


def bundle_id_record(auth: str) -> dict:
    found = request(auth, f"https://api.appstoreconnect.apple.com/v1/bundleIds?filter[identifier]={BUNDLE}")
    if found.get("data"):
        print("bundle id already registered")
        return found["data"][0]
    created = request(
        auth,
        "https://api.appstoreconnect.apple.com/v1/bundleIds",
        {
            "data": {
                "type": "bundleIds",
                "attributes": {"name": APP_NAME, "identifier": BUNDLE, "platform": "IOS"},
            }
        },
    )
    print("bundle id created" if created.get("data") else "bundle id response had no data")
    return created.get("data") or {}


def ensure_profile(auth: str, bundle: dict) -> None:
    """Create an App Store profile when automatic signing has nothing to reuse."""
    bundle_key = bundle.get("id")
    if not bundle_key:
        print("profile skipped: no bundle id")
        return
    existing = request(
        auth,
        f"https://api.appstoreconnect.apple.com/v1/profiles?filter[name]=Purr%20Pat%20App%20Store&filter[profileType]=IOS_APP_STORE",
    )
    profile = (existing.get("data") or [None])[0]
    if profile:
        print("app store profile already exists")
        detail = request(auth, f"https://api.appstoreconnect.apple.com/v1/profiles/{profile['id']}")
        install_profile((detail.get("data") or {}).get("attributes", {}).get("profileContent"))
        return
    certs = request(auth, "https://api.appstoreconnect.apple.com/v1/certificates?limit=50")
    today = time.strftime("%Y-%m-%d")
    cert_ids = []
    for item in certs.get("data", []):
        attrs = item.get("attributes") or {}
        kind = attrs.get("certificateType")
        expires = str(attrs.get("expirationDate") or "")
        print("certificate", kind, attrs.get("displayName", ""), expires[:10])
        if kind in {"IOS_DISTRIBUTION", "DISTRIBUTION", "APPLE_DISTRIBUTION"} and expires[:10] >= today:
            cert_ids.append(item["id"])
    cert_ids = cert_ids[:3]
    if not cert_ids:
        print("profile skipped: no iOS distribution certificate in App Store Connect")
        return
    created = request(
        auth,
        "https://api.appstoreconnect.apple.com/v1/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {"name": "Purr Pat App Store", "profileType": "IOS_APP_STORE"},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_key}},
                    "certificates": {"data": [{"type": "certificates", "id": item} for item in cert_ids]},
                },
            }
        },
    )
    install_profile((created.get("data") or {}).get("attributes", {}).get("profileContent"))
    print("app store profile created")


def install_profile(content: str | None) -> None:
    if not content:
        print("profile response had no content")
        return
    folder = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    os.makedirs(folder, exist_ok=True)
    raw = base64.b64decode(content)
    path = os.path.join(folder, "PurrPatAppStore.mobileprovision")
    with open(path, "wb") as handle:
        handle.write(raw)
    decoded = subprocess.check_output(["security", "cms", "-D", "-i", path])
    import plistlib

    info = plistlib.loads(decoded)
    uuid = info.get("UUID", "PurrPatAppStore")
    installed = os.path.join(folder, f"{uuid}.mobileprovision")
    if installed != path:
        with open(installed, "wb") as handle:
            handle.write(raw)
    print("installed profile", info.get("Name", ""), uuid)


def ensure() -> None:
    auth = token()
    app = request(auth, f"https://api.appstoreconnect.apple.com/v1/apps/{APP_ID}")
    attributes = (app.get("data") or {}).get("attributes") or {}
    print(f"app {APP_ID} {attributes.get('bundleId', '')} {attributes.get('name', '')}")
    bundle = bundle_id_record(auth)
    try:
        ensure_profile(auth, bundle)
    except Exception as exc:
        print("profile step skipped:", type(exc).__name__, str(exc)[:200])


def builds(auth: str) -> list[dict]:
    found = request(
        auth,
        f"https://api.appstoreconnect.apple.com/v1/builds?filter[app]={APP_ID}&sort=-uploadedDate&limit=20",
    )
    return found.get("data") or []


def publish() -> None:
    build_number = os.environ["BUILD_NUMBER"]
    deadline = time.time() + 35 * 60
    match = None
    while time.time() < deadline:
        auth = token()
        for item in builds(auth):
            if str((item.get("attributes") or {}).get("version")) == str(build_number):
                match = item
                break
        if match:
            state = (match.get("attributes") or {}).get("processingState")
            print(f"build {build_number} {match['id']} {state}")
            try:
                request(
                    auth,
                    f"https://api.appstoreconnect.apple.com/v1/builds/{match['id']}",
                    {
                        "data": {
                            "type": "builds",
                            "id": match["id"],
                            "attributes": {"usesNonExemptEncryption": False},
                        }
                    },
                    method="PATCH",
                )
                print("export compliance set: no non-exempt encryption")
            except Exception as exc:
                print("compliance not set yet:", str(exc)[:200])
            if state == "VALID":
                add_to_internal_group(auth, match["id"])
                print(f"VALID version 1.0 build {build_number}")
                return
            if state in {"FAILED", "INVALID"}:
                raise RuntimeError(f"build {build_number} is {state}")
        else:
            print(f"waiting for build {build_number}")
        match = None
        time.sleep(30)
    raise RuntimeError(f"build {build_number} was not valid before the wait ended")


def add_to_internal_group(auth: str, build_id: str) -> None:
    groups = request(auth, f"https://api.appstoreconnect.apple.com/v1/apps/{APP_ID}/betaGroups")
    internal = [item for item in groups.get("data") or [] if (item.get("attributes") or {}).get("isInternalGroup")]
    if internal:
        group_id = internal[0]["id"]
        print("internal group", (internal[0].get("attributes") or {}).get("name", group_id))
    else:
        created = request(
            auth,
            "https://api.appstoreconnect.apple.com/v1/betaGroups",
            {
                "data": {
                    "type": "betaGroups",
                    "attributes": {"name": "Purr Pat Internal", "isInternalGroup": True},
                    "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
                }
            },
        )
        group_id = created["data"]["id"]
        print("internal group created")
    try:
        request(
            auth,
            f"https://api.appstoreconnect.apple.com/v1/betaGroups/{group_id}/relationships/builds",
            {"data": [{"type": "builds", "id": build_id}]},
        )
        print("build added to internal testing")
    except RuntimeError as exc:
        if "409" in str(exc):
            print("build already in internal testing")
        else:
            raise


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "ensure"
    if command == "ensure":
        ensure()
    elif command == "publish":
        publish()
    else:
        raise SystemExit(f"unknown command {command}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("asc step failed:", type(exc).__name__, str(exc)[:300])
        sys.exit(1)
