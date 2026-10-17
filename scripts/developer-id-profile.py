#!/usr/bin/env python3
"""Make sure the Developer ID (direct distribution) provisioning profile is on this Mac.

    python3 scripts/developer-id-profile.py [--check]

Clip needs iCloud/CloudKit, so its signature needs a provisioning profile. A release for any Mac
uses the Developer ID kind (App Store Connect type MAC_APP_DIRECT): it carries the capabilities
and no device list. Xcode cannot create that kind unattended (with an API key it insists on a
cloud-managed certificate), so this script fetches a compatible existing profile through the
read-only App Store Connect API and stores it where Xcode's manual signing looks. It never creates
or changes account profiles/certificates. --check only reads this Mac. Prints JSON; never prints keys.
"""
import base64, datetime, hashlib, json, pathlib, plistlib, re, subprocess, sys, urllib.parse

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


def signing_identities(team):
    result = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                            check=True, capture_output=True, text=True)
    return re.findall(r'\b([0-9A-Fa-f]{40})\s+"Developer ID Application: [^"\n]+\('
                      + re.escape(team) + r'\)"', result.stdout)


def matching_identity(profile, identities):
    certificates = {hashlib.sha1(cert).hexdigest().upper()
                    for cert in profile.get("DeveloperCertificates", [])}
    return next((identity for identity in identities if identity.upper() in certificates), None)


def usable(profile, name, bundle_id, team, identities):
    entitlements = profile.get("Entitlements") or {}
    services = entitlements.get("com.apple.developer.icloud-services")
    # Apple's direct-distribution profiles may authorize every iCloud service
    # with the string "*", rather than an explicit array containing CloudKit.
    cloudkit = services == "*" or (isinstance(services, list)
                                   and ("CloudKit" in services or "*" in services))
    identifier = entitlements.get("com.apple.application-identifier") or entitlements.get("application-identifier")
    expires = profile.get("ExpirationDate")
    now = datetime.datetime.now(expires.tzinfo) if isinstance(expires, datetime.datetime) else None
    return (profile.get("Name") == name and identifier == f"{team}.{bundle_id}"
            and team in (profile.get("TeamIdentifier") or [])
            and entitlements.get("com.apple.developer.team-identifier") == team
            and entitlements.get("com.apple.developer.icloud-container-environment") == "Production"
            and entitlements.get("com.apple.developer.icloud-container-identifiers") == ["iCloud.cyou.tianli.clip"]
            and cloudkit
            and "ProvisionedDevices" not in profile and profile.get("ProvisionsAllDevices") is True
            and now is not None and expires > now + datetime.timedelta(days=7)
            and matching_identity(profile, identities) is not None)


def installed(name, bundle_id, team, identities):
    for store in STORES:
        for path in sorted(store.glob("*.provisionprofile")) if store.is_dir() else []:
            profile = decode(path)
            if usable(profile, name, bundle_id, team, identities):
                return path, profile
    return None, None


def fetch(name, bundle_id, team, identities):
    sys.path.insert(0, str(pathlib.Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
    import asc  # read-only GET; an API refusal exits with Apple's own message
    listed = asc.get("/profiles", {"filter[name]": urllib.parse.quote(name), "filter[profileType]": KIND, "limit": 50})
    for item in listed.get("data", []):
        attributes = item["attributes"]
        if attributes.get("name") == name and attributes.get("profileState") == "ACTIVE":
            raw = base64.b64decode(attributes["profileContent"])
            result = subprocess.run(["security", "cms", "-D"], input=raw, capture_output=True)
            try:
                profile = plistlib.loads(result.stdout)
            except (ValueError, plistlib.InvalidFileException):
                continue
            if usable(profile, name, bundle_id, team, identities):
                return attributes
    return None


def main():
    name = setting("cloud-project.yml", "PROVISIONING_PROFILE_SPECIFIER")
    team = setting("cloud-project.yml", "DEVELOPMENT_TEAM")
    bundle_id = setting("project.yaml", "bundle_id")
    identities = signing_identities(team)
    if not identities:
        print(json.dumps({"error": "signing_identity_missing", "team": team,
                          "detail": "No valid local Developer ID Application signing identity"}), file=sys.stderr)
        return 4
    path, profile = installed(name, bundle_id, team, identities)
    source = "installed"
    if path is None:
        attributes = None if "--check" in sys.argv[1:] else fetch(name, bundle_id, team, identities)
        if attributes is None:
            print(json.dumps({"error": "signing_profile_unavailable", "profile": name,
                              "bundle_id": bundle_id, "signing_identities": identities,
                              "detail": "No compatible all-device Production profile includes a valid local signing certificate; account profiles were not changed"}), file=sys.stderr)
            return 4
        source = "fetched"
        STORES[0].mkdir(parents=True, exist_ok=True)
        target = STORES[0] / f"{attributes['uuid']}.provisionprofile"
        target.write_bytes(base64.b64decode(attributes["profileContent"]))
        path, profile = installed(name, bundle_id, team, identities)
        if path is None:
            target.unlink()
            sys.exit(f"The account's profile '{name}' is not a usable Developer ID profile for {team}.{bundle_id}")
    print(json.dumps({"profile": name, "uuid": profile.get("UUID"), "source": source,
                      "signing_identity": matching_identity(profile, identities),
                      "expires": profile["ExpirationDate"].date().isoformat(),
                      "all_devices": profile.get("ProvisionsAllDevices"),
                      "device_list": "ProvisionedDevices" in profile,
                      "entitlements": sorted(profile.get("Entitlements") or {})}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
