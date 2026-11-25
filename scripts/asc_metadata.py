#!/usr/bin/env python3
"""Platina's App Store page in App Store Connect, from appstore/metadata.json (docs/app-store.md).

Through the App Store Connect API with the repository's key (Actions → App Store): the name,
subtitle and privacy policy of each language, the categories, the version's description, keywords,
promotional text and links, the screenshots (scripts/store_frames.py's frames), the age rating
answers and the notes for App Review. Without --apply it only reads App Store Connect and prints
what it would change.

What the API cannot do stays in App Store Connect's web pages: App Privacy, the review contact and
the test account, the content rights answer, the price and the build to submit.

Usage:
    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=AuthKey.p8 \\
      python3 scripts/asc_metadata.py [--apply] [--parts info,texts,screenshots,age,review] \\
      [--frames screenshots/store]
"""

import argparse
import hashlib
import json
import os
import sys
import time

import jwt
import requests

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.appstoreconnect.apple.com"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
ALL_PARTS = ["info", "texts", "screenshots", "age", "review"]


class ASC:
    def __init__(self, key_id, issuer, key_path, apply):
        self.key_id, self.issuer = key_id, issuer
        self.key = open(key_path).read()
        self.apply = apply
        self.token, self.expires = None, 0
        self.failures = []

    def _auth(self):
        if time.time() > self.expires - 60:
            now = int(time.time())
            self.expires = now + 15 * 60
            self.token = jwt.encode(
                {"iss": self.issuer, "iat": now, "exp": self.expires, "aud": "appstoreconnect-v1"},
                self.key, algorithm="ES256", headers={"kid": self.key_id, "typ": "JWT"},
            )
        return {"Authorization": f"Bearer {self.token}"}

    def request(self, method, path, body=None, params=None):
        url = path if path.startswith("http") else API + path
        for attempt in range(3):
            r = requests.request(method, url, headers=self._auth(), json=body, params=params, timeout=60)
            if r.status_code == 429 or r.status_code >= 500:
                time.sleep(2 ** attempt * 5)
                continue
            break
        if r.status_code >= 400:
            try:
                errors = r.json().get("errors", [])
                detail = "; ".join(f"{e.get('code')}: {e.get('detail') or e.get('title')}" for e in errors)
            except ValueError:
                detail = r.text[:300]
            raise RuntimeError(f"{method} {path} → {r.status_code} {detail}")
        return r.json() if r.content else {}

    def get(self, path, **params):
        return self.request("GET", path, params=params or None)

    def write(self, method, path, body, what):
        """A change: made with --apply, printed either way."""
        print(f"    {'→' if self.apply else '(would)'} {what}")
        if not self.apply:
            return None
        return self.request(method, path, body)

    def step(self, name, fn):
        print(f"\n━━ {name}")
        try:
            fn()
        except Exception as error:  # one part failing does not stop the others
            print(f"  ✗ {error}")
            self.failures.append(f"{name}: {error}")


def changed(current, wanted):
    return {k: v for k, v in wanted.items() if current.get(k) != v}


def show(value, limit=70):
    text = json.dumps(value, ensure_ascii=False)
    return text if len(text) <= limit else text[:limit] + "…"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="write to App Store Connect (otherwise only show)")
    parser.add_argument("--parts", default=",".join(ALL_PARTS), help="comma-separated: " + ",".join(ALL_PARTS))
    parser.add_argument("--frames", default=os.path.join(ROOT, "screenshots/store"))
    parser.add_argument("--metadata", default=os.path.join(ROOT, "appstore/metadata.json"))
    args = parser.parse_args()
    parts = [p.strip() for p in args.parts.split(",") if p.strip()]
    meta = json.load(open(args.metadata, encoding="utf-8"))

    asc = ASC(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_PATH"], args.apply)
    print("Mode:", "APPLY" if args.apply else "dry run (nothing is written)")

    apps = asc.get("/v1/apps", **{"filter[bundleId]": meta["bundleId"]})["data"]
    if not apps:
        sys.exit(f"No app with the bundle id {meta['bundleId']} in App Store Connect")
    app = apps[0]
    print(f"App: {app['attributes']['name']} ({app['id']}), primary language {app['attributes'].get('primaryLocale')}, "
          f"content rights: {app['attributes'].get('contentRightsDeclaration')}")

    infos = asc.get(f"/v1/apps/{app['id']}/appInfos")["data"]
    info = next((i for i in infos if (i["attributes"].get("state") or i["attributes"].get("appStoreState")) != "READY_FOR_DISTRIBUTION"), infos[0])
    print(f"App info: {info['id']} ({info['attributes'].get('state') or info['attributes'].get('appStoreState')})")

    versions = asc.get(f"/v1/apps/{app['id']}/appStoreVersions", **{"filter[platform]": "IOS", "limit": 20})["data"]
    for v in versions:
        print(f"Version {v['attributes']['versionString']}: {v['attributes'].get('appStoreState')} / {v['attributes'].get('appVersionState')}")
    version = next((v for v in versions if v["attributes"].get("appStoreState") in EDITABLE), None)
    if version is None:
        version = asc.write("POST", "/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": meta["versionString"]},
            "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}},
        }}, f"create version {meta['versionString']}")
        version = version["data"] if version else None

    # MARK: Names, privacy policy, categories

    def info_part():
        current = {l["attributes"]["locale"]: l for l in asc.get(f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]}
        for locale, m in meta["locales"].items():
            wanted = {"name": m["name"], "subtitle": m["subtitle"], "privacyPolicyUrl": m["privacyPolicyUrl"]}
            if locale in current:
                diff = changed(current[locale]["attributes"], wanted)
                print(f"  {locale}: " + (", ".join(f"{k} {show(current[locale]['attributes'].get(k), 40)} → {show(v, 40)}" for k, v in diff.items()) or "as wanted"))
                if diff:
                    asc.write("PATCH", f"/v1/appInfoLocalizations/{current[locale]['id']}",
                              {"data": {"type": "appInfoLocalizations", "id": current[locale]["id"], "attributes": diff}},
                              f"{locale} app info")
            else:
                print(f"  {locale}: missing")
                asc.write("POST", "/v1/appInfoLocalizations", {"data": {
                    "type": "appInfoLocalizations", "attributes": {"locale": locale, **wanted},
                    "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}},
                }}, f"add {locale} app info")
        primary = asc.get(f"/v1/appInfos/{info['id']}/primaryCategory").get("data")
        secondary = asc.get(f"/v1/appInfos/{info['id']}/secondaryCategory").get("data")
        cats = meta["categories"]
        print(f"  categories: {primary and primary['id']} / {secondary and secondary['id']} → {cats['primary']} / {cats['secondary']}")
        if (primary or {}).get("id") != cats["primary"] or (secondary or {}).get("id") != cats["secondary"]:
            asc.write("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
                "primaryCategory": {"data": {"type": "appCategories", "id": cats["primary"]}},
                "secondaryCategory": {"data": {"type": "appCategories", "id": cats["secondary"]}},
            }}}, "categories")

    # MARK: The version's texts

    version_localizations = {}

    def load_version_localizations():
        if version and not version_localizations:
            for l in asc.get(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]:
                version_localizations[l["attributes"]["locale"]] = l
        return version_localizations

    def texts_part():
        if not version:
            print("  no version to edit")
            return
        current = load_version_localizations()
        for locale, m in meta["locales"].items():
            wanted = {k: m[k] for k in ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl")}
            if locale in current:
                diff = changed(current[locale]["attributes"], wanted)
                print(f"  {locale}: " + (", ".join(f"{k} {show(current[locale]['attributes'].get(k), 30)} → {show(v, 30)}" for k, v in diff.items()) or "as wanted"))
                if diff:
                    asc.write("PATCH", f"/v1/appStoreVersionLocalizations/{current[locale]['id']}",
                              {"data": {"type": "appStoreVersionLocalizations", "id": current[locale]["id"], "attributes": diff}},
                              f"{locale} texts")
            else:
                print(f"  {locale}: missing")
                made = asc.write("POST", "/v1/appStoreVersionLocalizations", {"data": {
                    "type": "appStoreVersionLocalizations", "attributes": {"locale": locale, **wanted},
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}},
                }}, f"add {locale} texts")
                if made:
                    current[locale] = made["data"]

    # MARK: Screenshots

    def upload(set_id, path):
        data = open(path, "rb").read()
        made = asc.request("POST", "/v1/appScreenshots", {"data": {
            "type": "appScreenshots",
            "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
        }})["data"]
        for op in made["attributes"]["uploadOperations"]:
            chunk = data[op["offset"]:op["offset"] + op["length"]]
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            r = requests.request(op["method"], op["url"], headers=headers, data=chunk, timeout=120)
            if r.status_code >= 300:
                raise RuntimeError(f"upload {os.path.basename(path)}: {r.status_code}")
        asc.request("PATCH", f"/v1/appScreenshots/{made['id']}", {"data": {
            "type": "appScreenshots", "id": made["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()},
        }})

    def screenshots_part():
        if not version:
            print("  no version to edit")
            return
        current = load_version_localizations()
        for locale, m in meta["locales"].items():
            if locale not in current:
                print(f"  {locale}: no texts yet (run texts first)")
                continue
            loc_id = current[locale]["id"]
            sets = {s["attributes"]["screenshotDisplayType"]: s
                    for s in asc.get(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")["data"]}
            for device, display in meta["screenshotDisplayTypes"].items():
                folder = os.path.join(args.frames, device, m["screenshots"])
                files = sorted(f for f in os.listdir(folder) if f.endswith(".png")) if os.path.isdir(folder) else []
                if not files:
                    print(f"  {locale} {display}: no frames in {folder}")
                    continue
                existing = []
                if display in sets:
                    existing = asc.get(f"/v1/appScreenshotSets/{sets[display]['id']}/appScreenshots")["data"]
                print(f"  {locale} {display}: {len(existing)} in App Store Connect → {len(files)} ({', '.join(files)})")
                if not asc.apply:
                    print(f"    (would) replace them")
                    continue
                if display in sets:
                    set_id = sets[display]["id"]
                else:
                    set_id = asc.request("POST", "/v1/appScreenshotSets", {"data": {
                        "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
                        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}},
                    }})["data"]["id"]
                for shot in existing:
                    asc.request("DELETE", f"/v1/appScreenshots/{shot['id']}")
                for name in files:
                    upload(set_id, os.path.join(folder, name))
                    print(f"    → {name}")

    # MARK: Age rating

    def age_part():
        declaration = asc.get(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
        wanted = {k: v for k, v in meta["ageRating"].items() if not k.startswith("_")}
        diff = changed(declaration["attributes"], wanted)
        print("  " + (", ".join(f"{k} {declaration['attributes'].get(k)} → {v}" for k, v in diff.items()) or "as wanted"))
        if diff:
            asc.write("PATCH", f"/v1/ageRatingDeclarations/{declaration['id']}",
                      {"data": {"type": "ageRatingDeclarations", "id": declaration["id"], "attributes": diff}}, "age rating")

    # MARK: App Review

    def review_part():
        if not version:
            print("  no version to edit")
            return
        try:
            detail = asc.get(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
        except RuntimeError as error:
            if "404" not in str(error):
                raise
            detail = None
        wanted = {"notes": meta["review"]["notes"], "demoAccountRequired": meta["review"]["demoAccountRequired"]}
        if detail:
            a = detail["attributes"]
            print(f"  contact: {'set' if a.get('contactEmail') and a.get('contactPhone') else 'missing'}, "
                  f"test account: {'set' if a.get('demoAccountName') else 'missing'}")
            diff = changed(a, wanted)
            print("  " + (", ".join(f"{k} → {show(v, 50)}" for k, v in diff.items()) or "notes as wanted"))
            if diff:
                asc.write("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}",
                          {"data": {"type": "appStoreReviewDetails", "id": detail["id"], "attributes": diff}}, "review notes")
        else:
            print("  no review information yet")
            asc.write("POST", "/v1/appStoreReviewDetails", {"data": {
                "type": "appStoreReviewDetails", "attributes": wanted,
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}},
            }}, "review notes")

    steps = {"info": ("Names, privacy policy, categories", info_part), "texts": ("Description, keywords, links", texts_part),
             "screenshots": ("Screenshots", screenshots_part), "age": ("Age rating", age_part), "review": ("App Review", review_part)}
    for part in parts:
        asc.step(*steps[part])

    print()
    if asc.failures:
        print("✗ Not done:\n  " + "\n  ".join(asc.failures))
        sys.exit(1)
    print("✓ Done" if args.apply else "✓ Dry run: run with apply to write these changes")


if __name__ == "__main__":
    main()
