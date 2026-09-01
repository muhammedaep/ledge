#!/usr/bin/env python3
"""Two localization checks, reported separately, failing on either.

CHECK 1 — catalog coverage. `xcodebuild` does not write newly discovered keys
back into the source `.xcstrings` the way Xcode's GUI does. So someone can add
a `Text("…")`, build clean, ship, and have that string render in English under
every other language forever, with nothing anywhere reporting a problem.

Ground truth is the `.stringsdata` the compiler emits per source file under
`SWIFT_EMIT_LOC_STRINGS`, not a grep over the sources. A grep misses `.help()`
tooltips, `Picker` labels that are later `.labelsHidden()`, `TextField`
placeholders, ternaries inside a view builder, and bare interpolation like
`Text("\\(count)")` — which extracts as the key `%lld` and is not a string a
grep would think to look for.

CHECK 2 — no localization APIs in the core package. `LedgeCore` is a separate
SPM package with no string catalog, so a user-facing sentence written there
cannot be translated and renders English under every other language. The
architectural rule that keeps this containable is that core types carry the
*values* and the app target composes the *sentence*: `RuleSet.Unusable` carries
the offending names, `AppState` supplies the wording around them. Someone will
eventually add a `LocalizedError` conformance to a core type because it is the
natural Swift thing to do. This is the thing that stops them.

Check 2 is a source scan, not an extraction — unavoidably, because a
`LocalizedError` conformance emits no `.stringsdata` to read. It looks only for
localization APIs, never for string literals in general: the package is full of
legitimate non-user-facing strings — filenames, JSON keys, category names,
extension lists — and only these APIs indicate a sentence meant for a person.

Exits non-zero on any finding. A check that reports a gap and exits zero is a
check CI ignores.
"""

import argparse
import json
import os
import re
import sys

# Only this table. `InfoPlist.xcstrings` is a separate table with its own
# catalog and is deliberately out of scope here.
TABLE = "Localizable"

# The APIs that mean "this string is a sentence for a person". Not a general
# string-literal rule — see the module docstring.
LOCALIZATION_APIS = [
    ("String(localized:)", re.compile(r"\bString\s*\(\s*localized\s*:")),
    ("NSLocalizedString", re.compile(r"\bNSLocalizedString\b")),
    ("LocalizedError", re.compile(r"\bLocalizedError\b")),
    ("LocalizedStringResource", re.compile(r"\bLocalizedStringResource\b")),
    ("LocalizedStringKey", re.compile(r"\bLocalizedStringKey\b")),
]

BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
LINE_COMMENT = re.compile(r"//[^\n]*")


# --------------------------------------------------------------------------
# Check 1 — catalog coverage
# --------------------------------------------------------------------------

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


def check_catalog(stringsdata_root, catalog_path, language):
    """Returns (ok, fatal). `fatal` means the check could not run at all."""
    print("CHECK 1 — catalog coverage")

    if not os.path.isdir(stringsdata_root):
        print(f"  error: no such directory: {stringsdata_root}")
        print("  Build first — `make build` — so the compiler emits .stringsdata.")
        return False, True

    if not os.path.isfile(catalog_path):
        print(f"  error: no such catalog: {catalog_path}")
        return False, True

    extracted, files_seen = collect_extracted(stringsdata_root)

    # A check that finds nothing to check must fail rather than pass. Without
    # this, a renamed build directory or SWIFT_EMIT_LOC_STRINGS being turned
    # off would make every run green while checking nothing at all.
    if files_seen == 0 or not extracted:
        print(f"  error: found no '{TABLE}' keys under {stringsdata_root}")
        print("  Expected .stringsdata from the app target. Either the build did not")
        print("  run, or SWIFT_EMIT_LOC_STRINGS is no longer YES. Not a pass.")
        return False, True

    catalog = load_catalog(catalog_path)
    entries = catalog.get("strings", {})

    missing = sorted(set(extracted) - set(entries))
    untranslated = sorted(k for k, v in entries.items()
                          if translation_missing(v, language))
    stale = sorted(set(entries) - set(extracted))

    print(f"  {len(extracted)} keys extracted from {files_seen} source files")
    print(f"  {len(entries)} keys in {catalog_path}")

    if missing:
        print()
        print(f"  {len(missing)} key(s) in the build but NOT in the catalog "
              f"— these render in English under '{language}':")
        for key in missing:
            print(f"    {key!r}")
            for where in extracted[key]:
                print(f"        at {where}")

    if untranslated:
        print()
        print(f"  {len(untranslated)} catalog key(s) with no '{language}' value:")
        for key in untranslated:
            print(f"    {key!r}")

    if stale:
        print()
        print(f"  note: {len(stale)} catalog key(s) no longer appear in the build. "
              "Not a failure — harmless, but removable:")
        for key in stale:
            print(f"    {key!r}")

    if missing or untranslated:
        print()
        print("  FAILED: the catalog and the build have drifted apart.")
        print(f"  Add the missing keys to {catalog_path} with a value for "
              f"'{language}', then run this again.")
        return False, False

    print(f"  OK: every extracted key is in the catalog and has a '{language}' value.")
    return True, False


# --------------------------------------------------------------------------
# Check 2 — no localization APIs in the core package
# --------------------------------------------------------------------------

def strip_comments(source):
    """Blank out comments so a doc comment naming an API is not a violation.

    Replaces rather than deletes so line numbers survive.
    """
    source = BLOCK_COMMENT.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), source)
    return LINE_COMMENT.sub(lambda m: " " * len(m.group(0)), source)


def check_core_package(core_sources):
    """Returns (ok, fatal)."""
    print("CHECK 2 — no localization APIs in the core package")

    if not os.path.isdir(core_sources):
        print(f"  error: no such directory: {core_sources}")
        return False, True

    findings = []
    files_scanned = 0
    for dirpath, _, filenames in os.walk(core_sources):
        for name in sorted(filenames):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            try:
                with open(path, encoding="utf-8") as handle:
                    source = handle.read()
            except OSError as error:
                print(f"  warning: could not read {path}: {error}")
                continue
            files_scanned += 1
            code = strip_comments(source)
            for number, line in enumerate(code.split("\n"), start=1):
                for label, pattern in LOCALIZATION_APIS:
                    if pattern.search(line):
                        findings.append((path, number, label,
                                         source.split("\n")[number - 1].strip()))

    # Same vacuous-pass guard as check 1: finding no files to scan is not a pass.
    if files_scanned == 0:
        print(f"  error: no .swift files found under {core_sources}. Not a pass.")
        return False, True

    print(f"  {files_scanned} Swift files scanned under {core_sources}")

    if findings:
        print()
        print(f"  {len(findings)} localization API use(s) in the core package:")
        for path, number, label, text in findings:
            print(f"    {path}:{number}  ({label})")
            print(f"        {text}")
        print()
        print("  FAILED: LedgeCore has no string catalog, so a sentence written here")
        print("  cannot be translated and renders English under every other language.")
        print("  The value belongs in core; the wording belongs in the app target —")
        print("  as RuleSet.Unusable carries the offending names and AppState supplies")
        print("  the sentence around them.")
        return False, False

    print("  OK: no localization APIs in the core package.")
    return True, False


# --------------------------------------------------------------------------

def check_source_language(catalog_path):
    """CHECK 3 — no English localization that contradicts its own key.

    The catalog's sourceLanguage is `en` and its keys *are* the English text,
    so an explicit `en` entry is only ever a restatement of the key. When the
    two disagree, the key is what the source code says and the entry is what
    the app renders — and the app wins, silently.

    Written after renaming two keys to uppercase changed nothing on screen: the
    rebuilt app still drew "Filing into:" because the `en` value had been left
    behind at the old wording, and Check 1 was satisfied the whole time because
    it only ever asks about the translation language.
    """
    print("CHECK 3 — English values agree with their keys")
    catalog = load_catalog(catalog_path)
    source_language = catalog.get("sourceLanguage", "en")
    strings = catalog.get("strings", {})

    mismatched = []
    for key, entry in strings.items():
        unit = (entry.get("localizations", {})
                     .get(source_language, {})
                     .get("stringUnit", {}))
        value = unit.get("value")
        if value is not None and value != key:
            mismatched.append((key, value))

    print(f"  {len(strings)} keys checked against their '{source_language}' value")
    if mismatched:
        print(f"  FAILED: {len(mismatched)} key(s) render as something other than themselves.")
        for key, value in sorted(mismatched):
            print(f"    key:      {key!r}")
            print(f"    renders:  {value!r}")
        print("  The source code says one thing and the app shows another. Either")
        print(f"  update the '{source_language}' value to match the key, or delete it —")
        print("  a missing source-language entry falls back to the key, which is right.")
        return False, False

    print(f"  OK: every '{source_language}' value matches its key.")
    return True, False


# --------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stringsdata-root", required=True,
                        help="directory to search for .stringsdata (the build's derived data)")
    parser.add_argument("--catalog", required=True, help="path to Localizable.xcstrings")
    parser.add_argument("--core-sources", required=True,
                        help="the core package's Sources directory")
    parser.add_argument("--language", default="tr", help="language code to require (default: tr)")
    args = parser.parse_args()

    # Both checks always run, so one command reports every problem rather than
    # hiding the second behind the first.
    catalog_ok, catalog_fatal = check_catalog(
        args.stringsdata_root, args.catalog, args.language)
    print()
    core_ok, core_fatal = check_core_package(args.core_sources)
    print()
    source_ok, source_fatal = check_source_language(args.catalog)

    print()
    print("What these checks cannot see:")
    print("  - Check 1 sees only static literals. `Text(someVariable)` or")
    print("    `String(localized: someVariable)` is invisible to the compiler's")
    print("    extraction, so it is invisible here too.")
    print(f"  - Check 1 covers only the '{TABLE}' table. InfoPlist.xcstrings — the")
    print("    app name and usage descriptions — has its own catalog and is not checked.")
    print("  - Check 2 is a source scan, not an extraction, because a LocalizedError")
    print("    conformance emits no .stringsdata to read. It ignores comments, so a")
    print("    doc comment naming one of these APIs is not flagged; equally, a use")
    print("    built by string concatenation at runtime would not be caught.")
    print("  - Check 3 compares the catalog against itself. It cannot tell whether")
    print("    a key is good English, only that the app renders what the source says.")
    print("  - None of them says whether a translation is correct, or whether it fits")
    print("    the layout at Turkish length.")

    if catalog_fatal or core_fatal or source_fatal:
        return 2
    return 0 if (catalog_ok and core_ok and source_ok) else 1


if __name__ == "__main__":
    sys.exit(main())
