#!/usr/bin/env python3
"""Unit tests for the public server release tag selector."""
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "scripts" / "next_release_tag.py"
spec = importlib.util.spec_from_file_location("next_release_tag", MODULE)
next_release_tag = importlib.util.module_from_spec(spec)
spec.loader.exec_module(next_release_tag)

# The real repository has no candidate tags yet, so the candidate lane is
# seeded synthetically rather than assumed from history.
PUBLISHED = [f"server-v0.1.{patch}" for patch in range(2, 10)]


class ParseVersionTest(unittest.TestCase):
    def test_parses_stable_tag(self):
        self.assertEqual(next_release_tag.parse_version("server-v0.1.9"), (0, 1, 9, None))

    def test_parses_candidate_tag(self):
        self.assertEqual(next_release_tag.parse_version("server-v0.1.9-rc.3"), (0, 1, 9, 3))

    def test_rejects_unrelated_tags(self):
        for tag in ("v0.1.9", "server-v0.1", "server-v0.1.9-rc", "release-1", ""):
            self.assertIsNone(next_release_tag.parse_version(tag), tag)

    def test_rejects_malformed_version_parts(self):
        for tag in ("server-v0.1.9-rc.x", "server-vx.1.9", "server-v0.1.9-rc.1.2",
                    "server-v0.01.9", "server-1.2.3"):
            self.assertIsNone(next_release_tag.parse_version(tag), tag)


class NextTagTest(unittest.TestCase):
    def test_main_advances_past_newest_stable(self):
        self.assertEqual(next_release_tag.next_tag("main", PUBLISHED), "server-v0.1.10")

    def test_main_first_stable_when_no_tags_exist(self):
        self.assertEqual(next_release_tag.next_tag("main", []), "server-v0.1.0")

    def test_main_ignores_candidate_tags(self):
        # A candidate opens the next stable version, not the one after it.
        tags = PUBLISHED + ["server-v0.2.0-rc.7"]
        self.assertEqual(next_release_tag.next_tag("main", tags), "server-v0.2.0")

    def test_main_advances_past_a_candidate_of_the_same_series(self):
        # The stable release completes the tested candidate series.
        tags = PUBLISHED + ["server-v0.1.10-rc.1"]
        self.assertEqual(next_release_tag.next_tag("main", tags), "server-v0.1.10")

    def test_develop_starts_the_series_above_the_newest_stable(self):
        # A candidate must sort above the stable tag it supersedes, because the
        # private selector refuses any release older than its current lock.
        self.assertEqual(next_release_tag.next_tag("develop", PUBLISHED), "server-v0.1.10-rc.1")
        self.assertGreater(
            next_release_tag.version_key(
                next_release_tag.parse_version("server-v0.1.10-rc.1")),
            next_release_tag.version_key(next_release_tag.parse_version("server-v0.1.9")))

    def test_develop_advances_existing_candidate(self):
        # An older candidate cannot outrank the newest stable release.
        tags = PUBLISHED + ["server-v0.1.9-rc.1", "server-v0.1.9-rc.2"]
        self.assertEqual(next_release_tag.next_tag("develop", tags), "server-v0.1.10-rc.1")
        tags = PUBLISHED + ["server-v0.1.10-rc.1", "server-v0.1.10-rc.2"]
        self.assertEqual(next_release_tag.next_tag("develop", tags), "server-v0.1.10-rc.3")

    def test_develop_opens_a_new_series_when_the_candidate_falls_behind(self):
        # The newest candidate is below the newest stable, so the next
        # candidate opens a series above that stable instead of continuing a
        # series that would sort below it.
        tags = PUBLISHED + ["server-v0.1.9-rc.1", "server-v0.1.10"]
        self.assertEqual(next_release_tag.next_tag("develop", tags), "server-v0.1.11-rc.1")

    def test_develop_continues_a_candidate_series_that_ties_its_stable(self):
        # A stable tag closes its candidate series.
        tags = PUBLISHED + ["server-v0.1.10-rc.4", "server-v0.1.10"]
        self.assertEqual(next_release_tag.next_tag("develop", tags), "server-v0.1.11-rc.1")

    def test_develop_opens_the_next_series_after_a_stable_promotion(self):
        tags = PUBLISHED + ["server-v0.1.9-rc.1", "server-v0.1.10"]
        self.assertEqual(next_release_tag.next_tag("develop", tags), "server-v0.1.11-rc.1")

    def test_develop_ignores_unrelated_tags(self):
        tags = PUBLISHED + ["v9.9.9", "server-v0.1.9-rc", "release-2026"]
        self.assertEqual(next_release_tag.next_tag("develop", tags), "server-v0.1.10-rc.1")

    def test_next_tag_sorts_above_every_existing_tag(self):
        for lane in ("develop", "main"):
            for tags in (PUBLISHED, PUBLISHED + ["server-v0.1.10-rc.1"],
                         PUBLISHED + ["server-v0.1.10"]):
                selected = next_release_tag.next_tag(lane, tags)
                for existing in tags:
                    self.assertGreater(
                        next_release_tag.version_key(next_release_tag.parse_version(selected)),
                        next_release_tag.version_key(next_release_tag.parse_version(existing)),
                        f"{lane}: {selected} must outrank {existing}")

    def test_stable_ranks_above_its_candidates(self):
        stable = next_release_tag.parse_version("server-v0.1.10")
        candidate = next_release_tag.parse_version("server-v0.1.10-rc.9")
        self.assertGreater(next_release_tag.version_key(stable),
                           next_release_tag.version_key(candidate))

    def test_rerun_of_the_same_sha_does_not_change_the_tag(self):
        first = next_release_tag.next_tag("develop", PUBLISHED)
        second = next_release_tag.next_tag("develop", PUBLISHED)
        self.assertEqual(first, second)

    def test_rejects_unknown_lane(self):
        for lane in ("", "release", "staging", "DEVELOP"):
            with self.assertRaises(ValueError):
                next_release_tag.next_tag(lane, PUBLISHED)


class StableForTest(unittest.TestCase):
    def test_promotes_a_candidate_to_its_stable_form(self):
        self.assertEqual(next_release_tag.stable_for("server-v0.1.10-rc.3"), "server-v0.1.10")

    def test_stable_tags_have_no_promotion(self):
        self.assertIsNone(next_release_tag.stable_for("server-v0.1.10"))
        self.assertIsNone(next_release_tag.stable_for("not-a-release"))


class SelectTest(unittest.TestCase):
    def test_publishes_when_the_tested_tree_has_no_tag(self):
        selected = next_release_tag.select("main", PUBLISHED, {}, "tree")
        self.assertEqual(selected, "server-v0.1.10")

    def test_skips_when_the_tested_tree_already_carries_the_next_tag(self):
        tags = PUBLISHED + ["server-v0.1.10"]
        selected = next_release_tag.select("main", tags,
                                           {"tree": ["server-v0.1.10"]}, "tree")
        self.assertIsNone(selected)

    def test_publishes_when_the_tree_is_not_yet_tagged(self):
        # A tag exists for a different tree, so this content still needs one.
        selected = next_release_tag.select("main", PUBLISHED,
                                           {"other": ["server-v0.1.9"]}, "tree")
        self.assertEqual(selected, "server-v0.1.10")

    def test_a_candidate_never_suppresses_the_stable_promotion(self):
        # Promoting the tree `develop` already tagged as a candidate must still
        # create the stable release, otherwise `main` would never publish it.
        tags = PUBLISHED + ["server-v0.1.10-rc.1"]
        selected = next_release_tag.select("main", tags,
                                           {"tree": ["server-v0.1.10-rc.1"]}, "tree")
        self.assertEqual(selected, "server-v0.1.10")

    def test_existing_candidate_tree_does_not_publish_another_rc(self):
        tags = PUBLISHED + ["server-v0.1.10-rc.1"]
        self.assertIsNone(next_release_tag.select(
            "develop", tags, {"tree": ["server-v0.1.10-rc.1"]}, "tree"))

    def test_existing_stable_tree_does_not_publish_another_stable(self):
        tags = PUBLISHED + ["server-v0.1.10"]
        self.assertIsNone(next_release_tag.select(
            "main", tags, {"tree": ["server-v0.1.10"]}, "tree"))

    def test_develop_still_deduplicates_against_its_own_candidates(self):
        # Unchanged content on `develop` stays a no-op: the tag that already
        # carries this tree is the one this lane would publish next.
        tags = PUBLISHED + ["server-v0.1.10-rc.1"]
        selected = next_release_tag.select("develop", tags,
                                           {"tree": ["server-v0.1.10-rc.1"]}, "tree")
        self.assertIsNone(selected)

    def test_rejects_unknown_lane(self):
        with self.assertRaises(ValueError):
            next_release_tag.select("staging", PUBLISHED, {}, "tree")


class RepositoryStateTest(unittest.TestCase):
    """Guards against the tests drifting from the real tag history."""

    def test_real_stable_tags_are_parsed_as_stable(self):
        real = [f"server-v0.1.{patch}" for patch in range(2, 10)]
        for tag in real:
            version = next_release_tag.parse_version(tag)
            self.assertIsNotNone(version)
            self.assertIsNone(version[3])

    def test_next_stable_after_the_real_history(self):
        self.assertEqual(next_release_tag.next_tag("main", PUBLISHED), "server-v0.1.10")


class CliDecisionTest(unittest.TestCase):
    def test_existing_rc_is_idempotent_and_promotable(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.run(["git", *args], cwd=directory, check=True,
                                      capture_output=True, text=True).stdout.strip()

            git("init", "-q")
            git("config", "user.email", "test@example.test")
            git("config", "user.name", "Test")
            server = Path(directory) / "server"
            server.mkdir()
            (server / "README.md").write_text("stable\n")
            git("add", "server")
            git("commit", "-qm", "stable")
            git("tag", "server-v0.1.9")
            (server / "README.md").write_text("candidate\n")
            git("add", "server")
            git("commit", "-qm", "candidate")
            sha = git("rev-parse", "HEAD")
            git("tag", "server-v0.1.10-rc.1")

            def decision(lane):
                result = subprocess.run(
                    ["python3", str(MODULE), "--lane", lane, "--sha", sha],
                    cwd=directory, check=True, capture_output=True, text=True)
                return json.loads(result.stdout)

            self.assertEqual(decision("develop")["published"], False)
            self.assertEqual(decision("main")["tag"], "server-v0.1.10")
            self.assertEqual(decision("main")["published"], True)


if __name__ == "__main__":
    unittest.main()
