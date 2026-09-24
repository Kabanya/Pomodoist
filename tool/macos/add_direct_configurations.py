#!/usr/bin/env python3
"""Adds the macOS direct-download build configurations to Runner.xcodeproj.

The direct-download DMG needs an app that is not sandboxed and that bills
through Stripe, which the App Store configurations cannot express. Rather than a
new target - which would duplicate the app's sources, plugin wiring and the
focus-widget dependency, and then drift - this adds one XCBuildConfiguration per
existing `Release-<Environment>` block, named `Release-Direct-<Environment>`,
differing only in the entitlements it selects.

No scheme is added. `flutter build macos` has no build-configuration flag: it
takes `--flavor`, selects the Xcode scheme of that name and reads the
configuration out of the scheme's actions, so a flavor of its own could only
ever reach these configurations second-hand - and a flavor such as
`Direct-Staging` breaks the build outright, because Flutter derives the output
path from the raw flavor string and would look in
`Build/Products/Release-Direct-Staging/`. Instead `tool/macos/build.sh` keeps the
ordinary environment name as `--flavor` and overrides the one setting that
decides whether the app is sandboxed, through the `FLUTTER_XCODE_` prefix that
Flutter forwards to xcodebuild as a build setting.

The configurations here are therefore not what the build selects - they are the
description of the direct-download app, in the file that owns the signing
settings, and the contract test checks them against `build.sh` so the two cannot
drift.

`project.pbxproj` is a machine-readable file with no generator in this
repository (no XcodeGen, no project.yml), so it is edited programmatically here
instead of by hand. Running this twice is a no-op.

Usage:
    python3 tool/macos/add_direct_configurations.py [--check] [path/to/project.pbxproj]

`--check` reports whether the configurations are present and exits non-zero when
any is missing, which is what `test_build_contract.sh` relies on.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

FLAVORS = ("Development", "Staging", "Production")

# The source block per flavor. Every Direct configuration is a copy of the
# matching App Store release configuration with entitlements and signing
# overridden below.
SOURCE_MODE = "Release"

# The middle segment of a Direct configuration's name, e.g.
# `Release-Direct-Staging`. It is what `tool/macos/build.sh` exports for
# xcodebuild to use as its `-configuration`.
DIRECT_MODE = "Direct"

# The Direct configuration of a flavor, e.g. `Release-Direct-Staging`.
def configuration_name(flavor: str) -> str:
    return f"{SOURCE_MODE}-{DIRECT_MODE}-{flavor}"

DEFAULT_PROJECT = (
    Path(__file__).resolve().parents[2]
    / "apps"
    / "flutter"
    / "macos"
    / "Runner.xcodeproj"
    / "project.pbxproj"
)

# The direct-download app is signed ad-hoc so it builds without a paid
# Developer ID certificate in CI; tool/macos/build.sh re-signs it properly when
# credentials are available.
DIRECT_IDENTITY = '"-"'

# The xcconfig that tells Flutter a Direct-* configuration is a release build.
# Its object id is allocated and registered when the project is edited.
DIRECT_XCCONFIG_NAME = "Direct.xcconfig"

BLOCK_RE = re.compile(
    r"\t\t(?P<id>[0-9A-F]{24}) /\* (?P<name>[^*]+?) \*/ = \{\n"
    r"\t\t\tisa = XCBuildConfiguration;\n"
    r"(?P<body>.*?)\n"
    r"\t\t\tname = \"(?P=name)\";\n"
    r"\t\t\};\n",
    re.DOTALL,
)


def parse_blocks(text: str):
    """Yields (match, id, name, body) for every XCBuildConfiguration."""
    for match in BLOCK_RE.finditer(text):
        yield match, match.group("id"), match.group("name"), match.group("body")


def block_end_offset(block, text: str) -> int:
    """Returns the end offset of a parsed block within its source text."""
    return block[0].end()


TARGET_LIST_RE = re.compile(
    r"/\* Build configuration list for (?P<kind>\w+) \"(?P<target>[^\"]+)\" \*/ = \{\n"
    r"\t\t\tisa = XCConfigurationList;\n"
    r"\t\t\tbuildConfigurations = \(\n"
    r"(?P<entries>(?:\t{4}[0-9A-F]{24} /\* [^*]+ \*/,\n)+)"
    r"\t\t\t\);"
)


def target_owners_by_configuration(text: str, configuration: str) -> dict[str, str]:
    """Maps each configuration block id to the target that owns it.

    The block bodies do not say which target they belong to - several of them
    look alike - so ownership is read from the configuration lists, which name
    both the target and the blocks it builds with.
    """
    owners: dict[str, str] = {}
    for match in TARGET_LIST_RE.finditer(text):
        for line in match.group("entries").strip().split("\n"):
            entry = line.strip()
            if not entry.endswith(f"/* {configuration} */,"):
                continue
            block_id = entry.split(" ", 1)[0]
            owners[block_id] = match.group("target")
    return owners


def highest_object_id(text: str) -> int:
    """Returns the largest 24-hex object id, so new ids do not collide."""
    ids = re.findall(r"\b([0-9A-F]{24})\b", text)
    return max((int(value, 16) for value in ids), default=0)


def rewrite_settings(body: str, entitlements: str) -> str:
    """Applies the direct-download overrides to a copied build settings body."""
    lines = body.split("\n")
    out: list[str] = []
    seen_entitlements = False
    seen_identity = False

    for line in lines:
        stripped = line.strip()

        if stripped.startswith("CODE_SIGN_ENTITLEMENTS = "):
            out.append(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = {entitlements};")
            seen_entitlements = True
            continue
        if stripped.startswith("CODE_SIGN_IDENTITY = "):
            out.append(f"\t\t\t\tCODE_SIGN_IDENTITY = {DIRECT_IDENTITY};")
            seen_identity = True
            continue
        if stripped.startswith("CODE_SIGN_STYLE = "):
            # Ad-hoc signing needs manual style; Automatic asks Xcode to resolve
            # a provisioning profile the direct-download build has none of.
            out.append("\t\t\t\tCODE_SIGN_STYLE = Manual;")
            continue
        if stripped.startswith("POMODOIST_APP_GROUP = "):
            # An application group is granted by a provisioning profile, so
            # declaring it here makes Xcode demand one. The direct-download
            # build has no profile and does not need the group.
            continue
        if stripped.startswith("POMODOIST_BUILD_ENTITLEMENTS = "):
            out.append(f'\t\t\t\tPOMODOIST_BUILD_ENTITLEMENTS = "{entitlements}";')
            continue
        if stripped.startswith("DEVELOPMENT_TEAM = "):
            # Without a certificate there is no team to attribute the build to.
            # The line is dropped rather than blanked so an empty value cannot
            # be mistaken for a configured team.
            continue

        out.append(line)

    if not seen_entitlements:
        out.append(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = {entitlements};")
    if not seen_identity:
        out.append(f"\t\t\t\tCODE_SIGN_IDENTITY = {DIRECT_IDENTITY};")

    return "\n".join(out)


def ensure_configurations(path: Path, check: bool) -> int:
    text = path.read_text(encoding="utf-8")

    existing = {name for _, _, name, _ in parse_blocks(text)}
    missing = [
        name for name in (configuration_name(flavor) for flavor in FLAVORS)
        if name not in existing
    ]

    if check:
        if missing:
            for name in missing:
                print(f"FAIL: Xcode configuration {name} is missing from project.pbxproj")
            return 1
        print("macOS direct-download Xcode configurations are present.")
        return 0

    if not missing:
        print("Direct configurations already present; nothing to add.")
        return 0

    project_text = text
    next_id = highest_object_id(text) + 1
    added: list[str] = []
    insertions: list[tuple[int, str]] = []
    # Pairs each new block's id with the id of the block it copies and its name.
    replacements: list[tuple[str, str, str]] = []

    # The Direct.xcconfig file reference has to exist before any block can point
    # at it, so its id is allocated first.
    xcconfig_id = f"{next_id:024X}"
    next_id += 1
    xcconfig_reference = f"{xcconfig_id} /* {DIRECT_XCCONFIG_NAME} */"

    # Map every Release-<flavor> block to the target that owns it. Which target
    # a block belongs to decides its entitlements and whether Flutter needs a
    # build mode from it, and the answer is only in the configuration lists -
    # the block bodies alone cannot distinguish, for example, the aggregate
    # Flutter Assemble block from the app block.
    #
    # Ownership is keyed by the source block id, because that is what identifies
    # the block being copied; the new block is only created later.
    target_owners: dict[str, str] = {}
    for flavor in FLAVORS:
        target_owners.update(
            target_owners_by_configuration(text, f"{SOURCE_MODE}-{flavor}")
        )

    for flavor in FLAVORS:
        source_name = f"{SOURCE_MODE}-{flavor}"
        # The Direct configuration of a flavor is always the release one: a
        # directly downloaded app is a release artifact, and a `Debug-Direct-*`
        # configuration that also bills through Stripe would only invite a
        # sandboxed-looking debug build to ship.
        configuration = configuration_name(flavor)
        # Every block named after the release configuration is cloned: the
        # project-level block, the app target, the test target, the aggregate
        # Flutter Assemble target and the focus widget. Cloning all of them keeps
        # every configuration list complete, so `xcodebuild -configuration`
        # resolves for each target.
        sources = [b for b in parse_blocks(text) if b[2] == source_name]
        if not sources:
            print(f"FAIL: no {source_name} block to copy", file=sys.stderr)
            return 1

        for parsed in sources:
            source_body = parsed[3]
            owner = target_owners.get(parsed[1], "")
            is_widget = owner == "PomodoistFocusWidgetExtension"
            is_aggregate = owner == "Flutter Assemble"

            if is_widget:
                # The widget keeps its own Direct entitlements: the App Store
                # ones need an application-group the direct build cannot have,
                # and without a profile the extension would not build at all.
                entitlements = "PomodoistFocusWidget/Direct.entitlements"
            elif "CODE_SIGN_ENTITLEMENTS" in source_body:
                entitlements = "Runner/Direct.entitlements"
            else:
                # The project-level, test and aggregate blocks carry no
                # entitlements; they inherit and only need the renamed
                # configuration.
                entitlements = None  # type: ignore[assignment]

            if entitlements is None:
                body = source_body
            else:
                body = rewrite_settings(source_body, entitlements)

            new_id = f"{next_id:024X}"
            next_id += 1
            # Flutter's assemble script reads FLUTTER_BUILD_MODE from the build
            # settings and refuses a configuration whose name it does not know.
            # The aggregate target runs that script, so its Direct block is the
            # one that has to carry Direct.xcconfig; the other blocks keep the
            # base configuration they were copied with.
            base_reference = ""
            if is_aggregate:
                base_reference = (
                    f"\t\t\tbaseConfigurationReference = {xcconfig_reference};\n"
                )

            new_block = (
                f"\t\t{new_id} /* {configuration} */ = {{\n"
                f"\t\t\tisa = XCBuildConfiguration;\n"
                f"{base_reference}"
                f"{body}\n"
                f"\t\t\tname = \"{configuration}\";\n"
                f"\t\t}};\n"
            )
            # Each new block goes directly after the source block it copies, so
            # related configurations stay adjacent and the offsets recorded here
            # stay meaningful. Edits are applied in a single pass below rather
            # than here, because every later offset would otherwise be invalidated
            # by the insertion that preceded it.
            insertions.append((block_end_offset(parsed, text), new_block))
            # Remember which block this one copies, so it can be registered in
            # exactly the same configuration list below.
            replacements.append((parsed[1], new_id, configuration))
            added.append(configuration)

    for offset, new_block in sorted(insertions, key=lambda item: item[0], reverse=True):
        text = text[:offset] + new_block + text[offset:]

    text = register_xcconfig_file_reference(text, xcconfig_reference)

    # Register each new block in the configuration list that holds the block it
    # was copied from. A configuration that is not listed is unreachable:
    # `xcodebuild -list` would not offer it and no target could select it.
    #
    # The pairing is per block, not per flavor, because a flavor has five blocks
    # (project, app, tests, aggregate, widget) living in five different lists.
    # Adding them all to the first matching list leaves every other target
    # without the configuration, which silently builds the wrong settings.
    text = register_in_configuration_lists(text, replacements)

    path.write_text(text, encoding="utf-8")
    print(f"Added {len(added)} macOS direct-download configuration blocks: {', '.join(added)}")
    return 0


LIST_RE = re.compile(
    r"buildConfigurations = \(\n(?P<entries>(?:\t{4}[0-9A-F]{24} /\* [^*]+ \*/,\n)+)\t{3}\);"
)


def register_xcconfig_file_reference(text: str, reference: str) -> str:
    """Declares Direct.xcconfig as a file reference and files it under Configs.

    A baseConfigurationReference pointing at an id with no PBXFileReference is a
    dangling reference: Xcode would not resolve the build settings and the
    build mode would fall back to nothing.
    """
    match = re.search(r"([0-9A-F]{24}) /\* Release\.xcconfig \*/ = \{", text)
    if match is None:
        return text

    declaration = (
        f"\t\t{reference} = {{isa = PBXFileReference; "
        f"lastKnownFileType = text.xcconfig; path = {DIRECT_XCCONFIG_NAME}; "
        f'sourceTree = "<group>"; }};\n'
    )
    text = text[: match.start()] + declaration + text[match.start() :]

    # Join the same group that holds Release.xcconfig.
    group_re = re.compile(
        r"(children = \(\n(?P<entries>(?:\t{4}[0-9A-F]{24} /\* [^*]+ \*/,\n)+)\t{3}\);)"
    )
    release_id = match.group(1)
    edits: list[tuple[int, str]] = []
    for group_match in group_re.finditer(text):
        entries = group_match.group("entries")
        if f"{release_id} /* Release.xcconfig */," not in entries:
            continue
        position = entries.index(f"{release_id} /* Release.xcconfig */,")
        line_end = entries.index("\n", position) + 1
        edits.append(
            (
                group_match.start("entries") + line_end,
                f"\t\t\t\t{reference},\n",
            )
        )

    for offset, entry in sorted(edits, reverse=True):
        text = text[:offset] + entry + text[offset:]

    return text


def register_in_configuration_lists(
    text: str, replacements: list[tuple[str, str, str]]
) -> str:
    """Adds each new configuration to the list holding the block it copies.

    Every replacement is tried against every list, so a flavor's five blocks
    each land in their own list. The source entry is a unique object id, which
    is what makes the pairing unambiguous even though all five lists contain a
    configuration with the same visible name.
    """
    edits: list[tuple[int, str]] = []

    for list_match in LIST_RE.finditer(text):
        entries = list_match.group("entries")
        for source_id, new_id, label in replacements:
            if f"{source_id} /* " not in entries:
                continue
            # Append after the source entry so the configuration sits next to
            # the one it mirrors.
            position = entries.index(f"{source_id} /* ")
            line_end = entries.index("\n", position) + 1
            edits.append(
                (
                    list_match.start("entries") + line_end,
                    f"\t\t\t\t{new_id} /* {label} */,\n",
                )
            )

    for offset, entry in sorted(edits, reverse=True):
        text = text[:offset] + entry + text[offset:]

    return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", nargs="?", type=Path, default=DEFAULT_PROJECT)
    parser.add_argument(
        "--check",
        action="store_true",
        help="report whether the configurations exist instead of adding them",
    )
    args = parser.parse_args()

    if not args.project.is_file():
        print(f"FAIL: {args.project} does not exist", file=sys.stderr)
        return 1

    return ensure_configurations(args.project, check=args.check)


if __name__ == "__main__":
    sys.exit(main())
