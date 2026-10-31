"""Check Xcode's resolved identities, including target overrides, without changing macOS permissions."""
import json
import argparse
from pathlib import Path
import plistlib
import subprocess

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--debug-app", type=Path)
parser.add_argument("--release-app", type=Path)
args = parser.parse_args()
for configuration, identifier, name in [
    ("Debug", "com.deepk.app.dev", "deepK Dev"),
    ("Release", "com.deepk.app", "deepK"),
]:
    result = subprocess.run(
        ["xcodebuild", "-project", str(root / "DeepK.xcodeproj"), "-scheme", "DeepK",
         "-configuration", configuration, "-showBuildSettings", "-json"],
        check=True, capture_output=True, text=True,
    )
    settings = next(item["buildSettings"] for item in json.loads(result.stdout) if item["target"] == "DeepK")
    assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == identifier, settings["PRODUCT_BUNDLE_IDENTIFIER"]
    assert settings["INFOPLIST_KEY_CFBundleDisplayName"] == name, settings["INFOPLIST_KEY_CFBundleDisplayName"]
    assert settings["PRODUCT_NAME"] == name, settings["PRODUCT_NAME"]
    app = args.debug_app if configuration == "Debug" else args.release_app
    if app is not None:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        expected = {"CFBundleIdentifier": identifier, "CFBundleName": name,
                    "CFBundleDisplayName": name, "CFBundleExecutable": name}
        for key, value in expected.items():
            assert info.get(key) == value, (configuration, key, info.get(key), value)
        # macOS의 대소문자 구분 없는 경로 조회가 기존 DeepK 이름을 가리는 것도 잡는다.
        assert f"{name}.app" in {item.name for item in app.parent.iterdir()}
        assert name in {item.name for item in (app / "Contents/MacOS").iterdir()}
        print(f"Built {configuration}: wrapper, executable and Info.plist names verified")
    print(f"{configuration}: {identifier}, {name}")
print("Resolved development/distribution identity isolation passed")
