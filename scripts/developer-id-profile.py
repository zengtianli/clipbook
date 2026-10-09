#!/usr/bin/env python3
"""Make sure the Developer ID (direct distribution) provisioning profile is on this Mac.

    python3 scripts/developer-id-profile.py [--check]

Clip needs iCloud/CloudKit, so its signature needs a provisioning profile. A release for any Mac
uses the Developer ID kind (App Store Connect type MAC_APP_DIRECT): it carries the capabilities
and no device list. Xcode cannot create that kind unattended (with an API key it insists on a
cloud-managed certificate), so this script fetches the profile named in cloud-project.yml through
the App Store Connect API, creating it once if the account does not have it, and stores it where
Xcode's manual signing looks. --check only reads this Mac. Prints one JSON line; never prints keys.
"""
import base64, datetime, json, pathlib, plistlib, re, subprocess, sys, urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
KIND = "MAC_APP_DIRECT"
STORES = [pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
          pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles"]


def setting(path, key):
    found = re.search(rf"^\s*{key}:\s*([^#\n]+)", (ROOT / path).read_text(encoding="utf-8"), re.M)
    if not found:
        sys.exit(f"{path} has no {key}")
    return found.group(1).strip().strip("'\"")


def decode(path):
    raw = subprocess.run(["security", "cms", "-D", "-i", str(path)], capture_output=True).stdout
    try:
        return plistlib.loads(raw)
    except Exception:
        return {}


def usable(profile, name, bundle_id, team):
    entitlements = profile.get("Entitlements") or {}
    identifier = entitlements.get("com.apple.application-identifier") or entitlements.get("application-identifier")
    expires = profile.get("ExpirationDate")
    return (profile.get("Name") == name and identifier == f"{team}.{bundle_id}"
            and "ProvisionedDevices" not in profile and profile.get("ProvisionsAllDevices") is True
            and expires is not None and expires > datetime.datetime.now() + datetime.timedelta(days=7))


def installed(name, bundle_id, team):
    for store in STORES:
        for path in sorted(store.glob("*.provisionprofile")) if store.is_dir() else []:
            profile = decode(path)
            if usable(profile, name, bundle_id, team):
                return path, profile
    return None, None


def fetch(name, bundle_id):
    sys.path.insert(0, str(pathlib.Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
    import asc  # the maintainer's App Store Connect API key; an API refusal exits with Apple's own message
    listed = asc.get("/profiles", {"filter[name]": urllib.parse.quote(name), "filter[profileType]": KIND, "limit": 50})
    for item in listed.get("data", []):
        attributes = item["attributes"]
        if attributes.get("name") == name and attributes.get("profileState") == "ACTIVE":
            return attributes, "fetched"
    bundles = [b for b in asc.get("/bundleIds", {"filter[identifier]": bundle_id, "limit": 50}).get("data", [])
               if b["attributes"]["identifier"] == bundle_id]
    if not bundles:
        sys.exit(f"Bundle ID {bundle_id} is not registered in the developer account")
    today = datetime.datetime.now(datetime.timezone.utc).isoformat()
    certificates = [c for c in asc.get("/certificates", {"limit": 200}).get("data", [])
                    if c["attributes"].get("certificateType", "").startswith("DEVELOPER_ID_APPLICATION")
                    and (c["attributes"].get("expirationDate") or "") > today]
    if not certificates:
        sys.exit("The developer account has no valid Developer ID Application certificate")
    created = asc.post("/profiles", {"data": {"type": "profiles",
        "attributes": {"name": name, "profileType": KIND},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundles[0]["id"]}},
                          "certificates": {"data": [{"type": "certificates", "id": c["id"]} for c in certificates]}}}})
    return created["data"]["attributes"], "created"


def main():
    name = setting("cloud-project.yml", "PROVISIONING_PROFILE_SPECIFIER")
    team = setting("cloud-project.yml", "DEVELOPMENT_TEAM")
    bundle_id = setting("project.yaml", "bundle_id")
    path, profile = installed(name, bundle_id, team)
    source = "installed"
    if path is None:
        if "--check" in sys.argv[1:]:
            sys.exit(f"Developer ID profile '{name}' for {bundle_id} is not on this Mac")
        attributes, source = fetch(name, bundle_id)
        STORES[0].mkdir(parents=True, exist_ok=True)
        target = STORES[0] / f"{attributes['uuid']}.provisionprofile"
        target.write_bytes(base64.b64decode(attributes["profileContent"]))
        path, profile = installed(name, bundle_id, team)
        if path is None:
            target.unlink()
            sys.exit(f"The account's profile '{name}' is not a usable Developer ID profile for {team}.{bundle_id}")
    print(json.dumps({"profile": name, "uuid": profile.get("UUID"), "source": source,
                      "expires": profile["ExpirationDate"].date().isoformat(),
                      "all_devices": profile.get("ProvisionsAllDevices"),
                      "device_list": "ProvisionedDevices" in profile,
                      "entitlements": sorted(profile.get("Entitlements") or {})}, ensure_ascii=False))


if __name__ == "__main__":
    main()
