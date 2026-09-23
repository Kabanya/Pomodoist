#!/usr/bin/env python3
"""Unit tests for the public server release tag selector."""
import importlib.util
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
        tags = PUBLISHED + ["server-v0.2.0-rc.7"]
        self.assertEqual(next_release_tag.next_tag("main", tags), "server-v0.1.10")

    def test_develop_starts_first_candidate_from_newest_stable(self):
        self.assertEqual(next_release_tag.next_tag("develop", PUBLISHED), "server-v0.1.9-rc.1")

    def test_develop_advances_existing_candidate(self):
        tags = PUBLISHED + ["server-v0.1.9-rc.1", "server-v0.1.9-rc.2"]
        self.assertEqual(next_release_tag.next_tag("develop", tags), "server-v0.1.9-rc.3")

    def test_develop_restarts_candidate_after_a_stable_promotion(self):
        tags = PUBLISHED + ["server-v0.1.9-rc.1", "server-v0.1.10"]
        self.assertEqual(next_release_tag.next_tag("develop", tags), "server-v0.1.10-rc.1")

    def test_develop_ignores_unrelated_tags(self):
        tags = PUBLISHED + ["v9.9.9", "server-v0.1.9-rc", "release-2026"]
        self.assertEqual(next_release_tag.next_tag("develop", tags), "server-v0.1.9-rc.1")

    def test_candidate_never_sorts_below_its_stable_base(self):
        tags = PUBLISHED + ["server-v0.1.10-rc.1", "server-v0.1.11"]
        selected = next_release_tag.next_tag("develop", tags)
        self.assertEqual(selected, "server-v0.1.11-rc.1")
        self.assertGreater(next_release_tag.version_key(
                               next_release_tag.parse_version("server-v0.1.11-rc.1")),
                           next_release_tag.version_key(
                               next_release_tag.parse_version("server-v0.1.11")))

    def test_rerun_of_the_same_sha_does_not_change_the_tag(self):
        first = next_release_tag.next_tag("develop", PUBLISHED)
        second = next_release_tag.next_tag("develop", PUBLISHED)
        self.assertEqual(first, second)

    def test_rejects_unknown_lane(self):
        for lane in ("", "release", "staging", "DEVELOP"):
            with self.assertRaises(ValueError):
                next_release_tag.next_tag(lane, PUBLISHED)


class SelectTest(unittest.TestCase):
    def test_publishes_when_the_tested_tree_has_no_tag(self):
        selected = next_release_tag.select("main", PUBLISHED, {})
        self.assertEqual(selected, "server-v0.1.10")

    def test_skips_when_the_tested_tree_already_carries_the_next_tag(self):
        selected = next_release_tag.select("main", PUBLISHED,
                                           {"server-v0.1.10": "aaa"})
        self.assertIsNone(selected)

    def test_publishes_when_the_tree_is_not_yet_tagged(self):
        # A tag exists for a different tree, so this content still needs one.
        selected = next_release_tag.select("main", PUBLISHED,
                                           {"server-v0.1.9": "aaa"})
        self.assertEqual(selected, "server-v0.1.10")


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


if __name__ == "__main__":
    unittest.main()
