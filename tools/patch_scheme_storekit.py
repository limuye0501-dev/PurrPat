#!/usr/bin/env python3
"""Attach Products.storekit to every scheme's Run and Test actions.

Xcode only serves the configuration file for a test or run started from a
scheme that names it. simctl launch ignores it, which is why the paywall
button stayed on "Unlock".
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDENTIFIER = "../../PurrPat/Products.storekit"


def snippet(identifier: str) -> str:
    return f"""      <StoreKitConfigurationFileReference
         identifier = "{identifier}">
      </StoreKitConfigurationFileReference>
"""


def patch(path: Path) -> None:
    text = path.read_text()
    identifier = IDENTIFIER
    marker = 'identifier = "'
    found = text.find(marker)
    if found != -1:
        end = text.find('"', found + len(marker))
        if end != -1:
            identifier = text[found + len(marker) : end]
    block = snippet(identifier)
    updated = text
    for closing in ("</LaunchAction>", "</TestAction>"):
        start = 0
        pieces = []
        while True:
            index = updated.find(closing, start)
            if index == -1:
                pieces.append(updated[start:])
                break
            element_open = "<LaunchAction" if "Launch" in closing else "<TestAction"
            open_at = updated.rfind(element_open, 0, index)
            element = updated[open_at:index] if open_at != -1 else ""
            pieces.append(updated[start:index])
            if "StoreKitConfigurationFileReference" not in element:
                pieces.append(block)
            pieces.append(closing)
            start = index + len(closing)
        updated = "".join(pieces)
    if updated == text:
        print(f"{path.name}: already attached")
        return
    path.write_text(updated)
    print(f"{path.name}: attached {identifier}")


def main() -> None:
    schemes = list((ROOT / "PurrPat.xcodeproj/xcshareddata/xcschemes").glob("*.xcscheme"))
    if not schemes:
        raise SystemExit("no schemes found; run xcodegen first")
    for scheme in schemes:
        patch(scheme)


if __name__ == "__main__":
    main()
