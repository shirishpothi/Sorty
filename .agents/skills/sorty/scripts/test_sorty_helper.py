#!/usr/bin/env python3

import errno
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import sorty_helper


class SortyHelperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name)
        self.root = self.base / "root"
        self.state = self.base / "state"
        self.root.mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def write_plan(self, mode, operations, **extra):
        plan = {
            "version": 1,
            "source_root": str(self.root),
            "mode": mode,
            "operations": operations,
            "tags": [],
            "exclusions": [],
            "duplicate_groups": [],
            "unorganized": [],
            "warnings": [],
            **extra,
        }
        path = self.base / f"plan-{len(list(self.base.glob('plan-*')))}.json"
        path.write_text(json.dumps(plan), encoding="utf-8")
        return path

    def test_scan_skips_hidden_excluded_and_package_contents(self):
        (self.root / "visible.txt").write_text("visible", encoding="utf-8")
        (self.root / ".hidden.txt").write_text("hidden", encoding="utf-8")
        (self.root / "skip.tmp").write_text("skip", encoding="utf-8")
        package = self.root / "Demo.app"
        package.mkdir()
        (package / "inside").write_text("inside", encoding="utf-8")
        result = sorty_helper.scan(self.root, ["*.tmp"], False, False)
        paths = [item["path"] for item in result["items"]]
        self.assertEqual(paths, ["Demo.app", "visible.txt"])

    def test_exact_duplicates_distinguish_hard_links(self):
        first = self.root / "first.txt"
        second = self.root / "second.txt"
        hard_link = self.root / "hard.txt"
        first.write_text("same", encoding="utf-8")
        second.write_text("same", encoding="utf-8")
        hard_link.hardlink_to(first)
        result = sorty_helper.exact_duplicates(self.root, [], False)
        self.assertEqual(len(result["duplicate_groups"]), 1)
        self.assertEqual(result["duplicate_groups"][0]["stored_objects"], 2)
        self.assertEqual(len(result["hard_link_groups"]), 1)

    def test_modes_reject_scope_changes(self):
        (self.root / "a.txt").write_text("a", encoding="utf-8")
        organize = self.write_plan("organize", [{"source": "a.txt", "destination": "Docs/b.txt"}])
        self.assertFalse(sorty_helper.validate_plan(organize)["valid"])
        rename = self.write_plan("renameOnly", [{"source": "a.txt", "destination": "Docs/a.txt"}])
        self.assertFalse(sorty_helper.validate_plan(rename)["valid"])

    def test_symlink_item_moves_without_following_target(self):
        outside = self.base / "outside.txt"
        outside.write_text("outside", encoding="utf-8")
        link = self.root / "link.txt"
        link.symlink_to(outside)
        plan = self.write_plan("renameOnly", [{"source": "link.txt", "destination": "renamed.txt"}])
        result = sorty_helper.apply_plan(plan, self.state)
        renamed = self.root / "renamed.txt"
        self.assertTrue(renamed.is_symlink())
        self.assertEqual(renamed.readlink(), outside)
        self.assertEqual(outside.read_text(encoding="utf-8"), "outside")
        sorty_helper.rollback(Path(result["journal"]))
        self.assertTrue(link.is_symlink())

    def test_collision_and_nested_overlap_are_rejected(self):
        folder = self.root / "folder"
        folder.mkdir()
        (folder / "a.txt").write_text("a", encoding="utf-8")
        (self.root / "occupied").write_text("x", encoding="utf-8")
        plan = self.write_plan("organizeAndRename", [
            {"source": "folder", "destination": "moved"},
            {"source": "folder/a.txt", "destination": "occupied"},
        ])
        result = sorty_helper.validate_plan(plan)
        self.assertFalse(result["valid"])
        self.assertTrue(any("overlapping sources" in error for error in result["errors"]))
        self.assertTrue(any("destination already exists" in error for error in result["errors"]))

    def test_plan_cannot_move_an_excluded_item(self):
        (self.root / "private.txt").write_text("private", encoding="utf-8")
        plan = self.write_plan(
            "organize",
            [{"source": "private.txt", "destination": "Archive/private.txt"}],
            exclusions=["private.txt"],
        )
        result = sorty_helper.validate_plan(plan)
        self.assertFalse(result["valid"])
        self.assertTrue(any("matches an exclusion" in error for error in result["errors"]))

    def test_apply_and_rollback(self):
        source = self.root / "Inbox" / "draft.txt"
        source.parent.mkdir()
        source.write_text("draft", encoding="utf-8")
        plan = self.write_plan("organizeAndRename", [
            {"source": "Inbox/draft.txt", "destination": "Documents/report.txt"}
        ])
        result = sorty_helper.apply_plan(plan, self.state)
        destination = self.root / "Documents" / "report.txt"
        self.assertFalse(source.exists())
        self.assertEqual(destination.read_text(encoding="utf-8"), "draft")
        rollback = sorty_helper.rollback(Path(result["journal"]))
        self.assertEqual(rollback["status"], "completed")
        self.assertEqual(source.read_text(encoding="utf-8"), "draft")
        self.assertFalse(destination.exists())

    def test_cross_volume_fallback_verifies_and_moves(self):
        source = self.root / "a.txt"
        destination = self.root / "elsewhere" / "a.txt"
        source.write_text("payload", encoding="utf-8")
        real_rename = sorty_helper.os.rename
        calls = 0

        def exdev_once(old, new):
            nonlocal calls
            calls += 1
            if calls == 1:
                raise OSError(errno.EXDEV, "cross-device")
            return real_rename(old, new)

        with patch.object(sorty_helper.os, "rename", side_effect=exdev_once):
            method = sorty_helper.guarded_move(source, destination)
        self.assertEqual(method, "verified-copy")
        self.assertEqual(destination.read_text(encoding="utf-8"), "payload")
        self.assertFalse(source.exists())

    def test_interrupted_apply_leaves_pending_journal(self):
        first = self.root / "one.txt"
        second = self.root / "two.txt"
        first.write_text("one", encoding="utf-8")
        second.write_text("two", encoding="utf-8")
        plan = self.write_plan("organize", [
            {"source": "one.txt", "destination": "A/one.txt"},
            {"source": "two.txt", "destination": "B/two.txt"},
        ])
        real_move = sorty_helper.guarded_move
        calls = 0

        def stop_second(source, destination):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("simulated interruption")
            return real_move(source, destination)

        with patch.object(sorty_helper, "guarded_move", side_effect=stop_second):
            with self.assertRaises(OSError):
                sorty_helper.apply_plan(plan, self.state)
        journal = next((self.state / "journals").glob("*.jsonl"))
        rows = sorty_helper.read_journal(journal)
        statuses = [row.get("status") for row in rows if row.get("record") == "operation"]
        self.assertEqual(statuses, ["pending", "completed", "pending"])


if __name__ == "__main__":
    unittest.main()
