#!/usr/bin/env python3
"""Compare the localizable keys the Swift compiler actually extracted against
the string catalog, and fail if they have drifted apart.

`xcodebuild` does not write newly discovered keys back into the source
`.xcstrings` the way Xcode's GUI does. So someone can add a `Text("…")`, build
clean, ship, and have that string render in English under every other language
forever, with nothing anywhere reporting a problem. This is the thing that
reports it.

Ground truth is the `.stringsdata` the compiler emits per source file under
`SWIFT_EMIT_LOC_STRINGS`, not a grep over the sources. A grep misses `.help()`
tooltips, `Picker` labels that are later `.labelsHidden()`, `TextField`
placeholders, ternaries inside a view builder, and bare interpolation like
`Text("\\(count)")` — which extracts as the key `%lld` and is not a string a
grep would think to look for.

Exits non-zero on any finding. A check that reports a gap and exits zero is a
check CI ignores.
"""

import argparse
import json
import os
import sys

# Only this table. `InfoPlist.xcstrings` is a separate table with its own
# catalog and is deliberately out of scope here.
TABLE = "Localizable"


def collect_extracted(root):
    """Every key the compiler extracted into the Localizable table, mapped to
    the source locations it came from."""
    keys = {}
    files_seen = 0
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            if not name.endswith(".stringsdata"):
                continue
            path = os.path.join(dirpath, name)
            try:
                with open(path, encoding="utf-8") as handle:
                    data = json.load(handle)
            except (OSError, json.JSONDecodeError) as error:
                print(f"warning: could not read {path}: {error}", file=sys.stderr)
                continue
            entries = data.get("tables", {}).get(TABLE)
            if not entries:
                continue
            files_seen += 1
            source = os.path.basename(data.get("source", path))
            for entry in entries:
                key = entry.get("key")
                if key is None:
                    continue
                line = entry.get("location", {}).get("startingLine")
                where = f"{source}:{line}" if line else source
                # One .stringsdata per architecture, so the same source
                # location arrives once per arch in a universal build. Report
                # the place, not the number of times the compiler saw it.
                locations = keys.setdefault(key, [])
                if where not in locations:
                    locations.append(where)
    return keys, files_seen


def load_catalog(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def translation_missing(entry, language):
    """True when this catalog entry has no usable value in `language`.

    `shouldTranslate: false` is an explicit decision, not a gap. Plural and
    device variations count as present if any of their cases carries a value —
    checking every case individually is a stricter rule than this project has
    agreed to, and would fail on a legitimately partial plural set.
    """
    if entry.get("shouldTranslate") is False:
        return False
    localization = entry.get("localizations", {}).get(language)
    if not localization:
        return True
    unit = localization.get("stringUnit")
    if unit is not None:
        return not (unit.get("value") or "").strip()
    variations = localization.get("variations")
    if variations:
        for cases in variations.values():
            for case in cases.values():
                value = case.get("stringUnit", {}).get("value") or ""
                if value.strip():
                    return False
        return True
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stringsdata-root", required=True,
                        help="directory to search for .stringsdata (the build's derived data)")
    parser.add_argument("--catalog", required=True, help="path to Localizable.xcstrings")
    parser.add_argument("--language", default="tr", help="language code to require (default: tr)")
    args = parser.parse_args()

    if not os.path.isdir(args.stringsdata_root):
        print(f"error: no such directory: {args.stringsdata_root}", file=sys.stderr)
        print("       Build first — `make build` — so the compiler emits .stringsdata.",
              file=sys.stderr)
        return 2

    if not os.path.isfile(args.catalog):
        print(f"error: no such catalog: {args.catalog}", file=sys.stderr)
        return 2

    extracted, files_seen = collect_extracted(args.stringsdata_root)

    # A check that finds nothing to check must fail rather than pass. Without
    # this, a renamed build directory or SWIFT_EMIT_LOC_STRINGS being turned
    # off would make every run green while checking nothing at all.
    if files_seen == 0 or not extracted:
        print(f"error: found no '{TABLE}' keys under {args.stringsdata_root}", file=sys.stderr)
        print("       Expected .stringsdata from the app target. Either the build did not run,",
              file=sys.stderr)
        print("       or SWIFT_EMIT_LOC_STRINGS is no longer YES. Not treating this as a pass.",
              file=sys.stderr)
        return 2

    catalog = load_catalog(args.catalog)
    entries = catalog.get("strings", {})

    missing = sorted(set(extracted) - set(entries))
    untranslated = sorted(k for k, v in entries.items()
                          if translation_missing(v, args.language))
    stale = sorted(set(entries) - set(extracted))

    print(f"Localization check — {args.language}")
    print(f"  {len(extracted)} keys extracted from {files_seen} source files")
    print(f"  {len(entries)} keys in {args.catalog}")

    if missing:
        print()
        print(f"  {len(missing)} key(s) in the build but NOT in the catalog "
              f"— these render in English under '{args.language}':")
        for key in missing:
            print(f"    {key!r}")
            for where in extracted[key]:
                print(f"        at {where}")

    if untranslated:
        print()
        print(f"  {len(untranslated)} catalog key(s) with no '{args.language}' value:")
        for key in untranslated:
            print(f"    {key!r}")

    if stale:
        print()
        print(f"  note: {len(stale)} catalog key(s) no longer appear in the build. "
              f"Not a failure — harmless, but removable:")
        for key in stale:
            print(f"    {key!r}")

    print()
    print("  What this check cannot see:")
    print("    - Keys that are not static literals. `Text(someVariable)` or")
    print("      `String(localized: someVariable)` is invisible to the compiler's")
    print("      extraction, so it is invisible here too.")
    print(f"    - Any table but '{TABLE}'. InfoPlist.xcstrings — the app name and")
    print("      usage descriptions — has its own catalog and is not checked.")
    print("    - Strings added inside the LedgeCore package, which would belong to")
    print("      that package's bundle rather than to this catalog.")
    print("    - Whether a translation is *correct*, or whether it fits the layout.")

    if missing or untranslated:
        print()
        print("FAILED: the catalog and the build have drifted apart.")
        print("Add the missing keys to Ledge/Resources/Localizable.xcstrings with a")
        print(f"value for '{args.language}', then run this again.")
        return 1

    print()
    print("OK: every extracted key is in the catalog and has a "
          f"'{args.language}' value.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
