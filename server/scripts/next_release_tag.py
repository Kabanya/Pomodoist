#!/usr/bin/env python3
"""Choose the next immutable public server release tag for a branch.

`main` publishes stable tags (`server-vX.Y.Z`); `develop` publishes release
candidates (`server-vX.Y.Z-rc.N`). The next tag must always sort above its
lane's prior tag and must never be reused for different content, so the caller
passes the tree ID of the tested `server/` directory and skips publishing when
that tree already carries the newest lane-appropriate tag.
"""
import argparse
import json
import re
import subprocess
import sys

STABLE_PATTERN = re.compile(r"server-v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
CANDIDATE_PATTERN = re.compile(
    r"server-v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)-rc\.(0|[1-9]\d*)$")
LANES = {"develop": "candidate", "main": "stable"}


def parse_version(tag):
    """Return `(major, minor, patch, candidate)` for a tag, or None."""
    stable = STABLE_PATTERN.fullmatch(tag)
    if stable:
        return (int(stable.group(1)), int(stable.group(2)), int(stable.group(3)), None)
    candidate = CANDIDATE_PATTERN.fullmatch(tag)
    if candidate:
        return (int(candidate.group(1)), int(candidate.group(2)),
                int(candidate.group(3)), int(candidate.group(4)))
    return None


def stable_tags(tags):
    return [(tag, parse_version(tag)) for tag in tags
            if (version := parse_version(tag)) and version[3] is None]


def candidate_tags(tags):
    return [(tag, parse_version(tag)) for tag in tags
            if (version := parse_version(tag)) and version[3] is not None]


def version_key(version):
    """Return a sort key that ranks a stable release above its candidates.

    `parse_version` puts None in the candidate slot for stable tags, which is
    not orderable. A stable release sorts above every candidate of the same
    version, so it gets the higher sentinel in that slot.
    """
    major, minor, patch, candidate = version
    return (major, minor, patch, 0 if candidate is None else candidate)


def newest(tagged):
    """Return the tag with the highest version, or None for an empty input."""
    if not tagged:
        return None
    return max(tagged, key=lambda item: version_key(item[1]))[0]


def newest_version(tags):
    """Return the highest version in `tags`, including candidate tags."""
    versions = [version for tag in tags if (version := parse_version(tag))]
    return max(versions, key=version_key) if versions else None


def next_tag(lane, tags):
    """Return the tag this lane should publish next.

    "Next" means the lowest tag that sorts strictly above every existing tag,
    so the series advances one step at a time and a rerun after a partial
    failure cannot collide with an existing tag.
    """
    if lane not in LANES:
        raise ValueError(f"unknown release lane: {lane}")
    published = stable_tags(tags) if LANES[lane] == "stable" else candidate_tags(tags)
    latest = newest_version(tags)
    # Every version is 0.x, so the major component never breaks a tie here.
    major = latest[0] if latest else 0
    if LANES[lane] == "stable":
        minor = latest[1] if latest else 1
        patch = latest[2] + 1 if latest else 0
        return f"server-v{major}.{minor}.{patch}"
    candidate = 1
    if latest is not None and latest[3] is not None:
        minor, patch = latest[1], latest[2]
        candidate += latest[3]
    else:
        # The newest tag is stable, so the candidate series opens one patch
        # above it: a candidate never sorts below the stable release it is
        # meant to supersede, and the matching stable promotion is one step up.
        minor = latest[1] if latest else 1
        patch = latest[2] + 1 if latest else 0
    return f"server-v{major}.{minor}.{patch}-rc.{candidate}"


def stable_for(tag):
    """Return the stable release a candidate tag promotes to.

    `main` publishes the stable form of the same server tree that `develop`
    already published as a candidate.
    """
    version = parse_version(tag)
    if version is None or version[3] is None:
        return None
    major, minor, patch, _ = version
    return f"server-v{major}.{minor}.{patch}"


def head_is_current(sha, branch, run=subprocess.run):
    """Return True when `sha` is still the remote head of `branch`."""
    result = run(["git", "ls-remote", "origin", f"refs/heads/{branch}"],
                 capture_output=True, text=True, check=True)
    remote = result.stdout.split()[0] if result.stdout.split() else ""
    return remote == sha


def server_tree(sha, run=subprocess.run):
    """Return the Git tree ID of `server/` at `sha`."""
    result = run(["git", "rev-parse", f"{sha}:server"],
                 capture_output=True, text=True, check=True)
    return result.stdout.strip()


def tag_target(tag, run=subprocess.run):
    """Return the commit a tag resolves to, or None when it does not exist."""
    result = run(["git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}"],
                 capture_output=True, text=True, check=False)
    return result.stdout.strip() if result.returncode == 0 else None


def select(lane, tags, tagged_trees):
    """Return the tag to publish, or None when the tested tree already has one.

    `tagged_trees` maps a `server/` tree ID to the tags that already point at
    it, so a rerun against unchanged content publishes nothing.

    The `main` lane compares against stable tags only: after `develop` publishes
    `server-v0.1.10-rc.1`, promoting that same tree must still create the stable
    `server-v0.1.10`. A candidate is never a released version on its own.
    """
    if lane not in LANES:
        raise ValueError(f"unknown release lane: {lane}")
    if LANES[lane] == "stable":
        candidate = next_tag(lane, tags)
        existing = tagged_trees.get(candidate, [])
        if isinstance(existing, str):
            existing = [existing]
        eligible = [tag for tag in existing if tag in {name for name, _ in stable_tags(tags)}]
        return None if eligible else candidate
    candidate = next_tag(lane, tags)
    return None if tagged_trees.get(candidate) else candidate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lane", required=True, choices=sorted(LANES))
    parser.add_argument("--sha", help="tested commit; must still be the branch head")
    parser.add_argument("--branch", help="branch whose head must equal --sha")
    parser.add_argument("--tags", help="newline-separated existing tags")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the tag without checking the branch head")
    args = parser.parse_args()
    if args.tags is not None:
        tags = [line.strip() for line in args.tags.splitlines() if line.strip()]
    else:
        result = subprocess.run(["git", "tag", "--list", "server-v*"],
                                capture_output=True, text=True, check=True)
        tags = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if args.sha and args.branch and not head_is_current(args.sha, args.branch):
        print("branch head moved past the tested commit; not tagging", file=sys.stderr)
        return 0
    tag = next_tag(args.lane, tags)
    print(json.dumps({"lane": args.lane, "tag": tag,
                      "tree": server_tree(args.sha) if args.sha else None}))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print(f"release tag selection failed: {error}", file=sys.stderr)
        sys.exit(1)
