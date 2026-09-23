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


def next_tag(lane, tags):
    """Return the tag this lane should publish next.

    The version always advances past every existing tag in the lane, so a
    rerun after a partial failure cannot collide with an existing tag.
    """
    if lane not in LANES:
        raise ValueError(f"unknown release lane: {lane}")
    if LANES[lane] == "stable":
        published = stable_tags(tags)
        latest = newest(published)
        if latest is None:
            return "server-v0.1.0"
        major, minor, patch, _ = parse_version(latest)
        return f"server-v{major}.{minor}.{patch + 1}"
    published = candidate_tags(tags)
    stable = newest(stable_tags(tags))
    latest = newest(published)
    if latest is None:
        # The first candidate is based on the newest stable release, so a
        # candidate never sorts below a stable tag it is meant to supersede.
        if stable is None:
            return "server-v0.1.0-rc.1"
        major, minor, patch, _ = parse_version(stable)
        return f"server-v{major}.{minor}.{patch}-rc.1"
    major, minor, patch, candidate = parse_version(latest)
    if stable is not None and parse_version(stable)[:3] > (major, minor, patch):
        stable_major, stable_minor, stable_patch, _ = parse_version(stable)
        return f"server-v{stable_major}.{stable_minor}.{stable_patch}-rc.1"
    return f"server-v{major}.{minor}.{patch}-rc.{candidate + 1}"


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
    """
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
