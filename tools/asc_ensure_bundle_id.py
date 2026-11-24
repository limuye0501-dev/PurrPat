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
import urllib.request

BUNDLE = "com.limuye.purrpat"


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


def request(token: str, url: str, payload: dict | None = None) -> dict:
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        url,
        data=data,
        method="GET" if payload is None else "POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=40) as res:
        return json.load(res)


def main() -> None:
    token = make_jwt(os.environ["ASC_KEY_PATH"], os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"])
    found = request(token, f"https://api.appstoreconnect.apple.com/v1/bundleIds?filter[identifier]={BUNDLE}")
    if found.get("data"):
        print("bundle id already registered")
        return
    created = request(
        token,
        "https://api.appstoreconnect.apple.com/v1/bundleIds",
        {
            "data": {
                "type": "bundleIds",
                "attributes": {"name": "Purr Pat", "identifier": BUNDLE, "platform": "IOS"},
            }
        },
    )
    print("bundle id created" if created.get("data") else "bundle id response had no data")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("bundle id step failed:", type(exc).__name__)
        sys.exit(1)
