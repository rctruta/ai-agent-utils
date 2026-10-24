#!/usr/bin/env python3
"""Refuse a distribution that contains anything which is not this package.

    python3 scripts/dev/check_wheel.py            # newest wheel in dist/
    python3 scripts/dev/check_wheel.py path.whl

Runs in release.yml BEFORE the upload step, because the rule it enforces was
already written down and still broken.

The failure mode. `include-package-data` defaults to true, and without a
MANIFEST.in setuptools packages whatever is in the working directory: build
trees, virtualenvs, tests, local scripts. The build still exits 0, and the
stray share tends to grow release over release, because nobody looks inside a
wheel when the build succeeding looks like success.

Two assertions, both about the artifact rather than the build:

  1. every path sits under the package directory or the .dist-info
  2. no file carries a home-directory path

A third thing this deliberately does NOT do: decide what SHOULD be present.
That is the manifest's job, and a missing-file check that duplicates the
manifest would drift from it. What catches a missing file is installing the
wheel and calling a tool -- see the smoke test.
"""
import glob
import os
import re
import sys
import zipfile

PACKAGE = "sql_benchmarks"
# Split so this file is not itself a finding. It is installed into every
# seeded project, and gitleaks' home-path rule scans it -- a detector
# that trips its sibling detector blocks the first commit of a fresh repo.
HOME_PATH = re.compile(rb"/U" rb"sers/[A-Za-z0-9._-]+|/h" rb"ome/[A-Za-z0-9._-]+")
TEXT_EXT = (".py", ".md", ".txt", ".yaml", ".yml", ".json", ".sh", ".cfg", ".toml")


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        wheels = sorted(glob.glob("dist/*.whl"), key=os.path.getmtime)
        if not wheels:
            sys.exit("no wheel in dist/ — run `uv build` first")
        path = wheels[-1]

    z = zipfile.ZipFile(path)
    names = z.namelist()
    tops = {}
    for n in names:
        tops.setdefault(n.split("/")[0], 0)
        tops[n.split("/")[0]] += 1

    allowed = {PACKAGE} | {t for t in tops if t.endswith(".dist-info")}
    stray = {t: c for t, c in tops.items() if t not in allowed}

    print(f"{os.path.basename(path)}: {len(names)} files")
    for t, c in sorted(tops.items(), key=lambda kv: -kv[1]):
        mark = "  <-- NOT PART OF THIS PACKAGE" if t in stray else ""
        print(f"  {t}: {c}{mark}")

    failures = []
    if stray:
        failures.append(
            f"{sum(stray.values())} file(s) outside {PACKAGE}/: "
            f"{', '.join(sorted(stray))}.\n"
            f"    include-package-data must stay false and package-data must "
            f"name every file that ships.")

    leaked = []
    for n in names:
        if not n.endswith(TEXT_EXT):
            continue
        m = HOME_PATH.search(z.read(n))
        if m:
            leaked.append((n, m.group(0).decode()))
    if leaked:
        failures.append(f"{len(leaked)} file(s) carry a home-directory path, "
                        f"e.g. {leaked[0][0]} -> {leaked[0][1]}")

    if failures:
        print("\nREFUSING TO PUBLISH:\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        print(f"\nInspect it yourself: python3 -c \"import zipfile; "
              f"print(zipfile.ZipFile('{path}').namelist())\"\n", file=sys.stderr)
        return 1

    print(f"\nclean: every path is under {PACKAGE}/ or .dist-info, "
          f"no home-directory paths.")
    return 0


sys.exit(main())
