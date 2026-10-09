import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("tracker", ROOT / "tracker.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FakeHey:
    def __init__(self):
        self.calls = []
        self.current = None
        self.fail = None

    def __call__(self, args, account=""):
        self.calls.append((args, account))
        if args[0] == self.fail:
            raise module.TrackerError("Connection lost")
        if args[0] == "current":
            return self.current
        if args[0] == "start":
            self.current = {"id": 123, "starts_at": "2026-01-01T14:00:00Z"}
        if args[0] in ("edit", "delete"):
            self.current = None
        return self.current


class TrackerTests(unittest.TestCase):
    def setUp(self):
        self.fake = FakeHey()
        self.tracker = module.Tracker(self.fake)

    def start(self):
        self.tracker.dispatch("start", {"account": "456"})

    def draft(self, **fields):
        return {"account": "456", "remoteId": 123,
                "start": "2026-01-01T14:00:00Z", "end": "2026-01-01T15:00:00Z", **fields}

    def test_start_immediately_creates_hey_timer(self):
        self.start()
        self.assertEqual([args[0] for args, _ in self.fake.calls], ["current", "start", "current"])
        self.assertEqual(self.tracker.state["remoteId"], 123)
        self.assertTrue(all(account == "456" for _, account in self.fake.calls))

    def test_restart_reads_existing_remote_timer(self):
        self.start()
        restored = module.Tracker(self.fake)
        restored.dispatch("status", {"account": "456"})
        self.assertEqual(restored.state, self.tracker.state)

    def test_external_changes_are_synced(self):
        self.start()
        self.fake.current.update(starts_at="2026-01-01T13:00:00Z", notes="HEY notes", category={"title": "Work"})
        self.tracker.dispatch("status", {})
        self.assertEqual(self.tracker.state["start"], "2026-01-01T13:00:00+00:00")
        self.assertEqual(self.tracker.state["notes"], "HEY notes")
        self.assertEqual(self.tracker.state["category"], "Work")
        self.fake.current = None
        self.tracker.dispatch("status", {})
        self.assertEqual(self.tracker.state["mode"], "idle")

    def test_review_and_dismiss_keep_same_remote_timer_running(self):
        self.start()
        self.tracker.dispatch("review", self.draft())
        self.assertEqual(self.tracker.state["mode"], "review")
        self.tracker.dispatch("resume", self.draft())
        self.assertEqual(self.tracker.state["mode"], "running")
        self.assertEqual(self.tracker.state["remoteId"], 123)
        self.assertEqual([args[0] for args, _ in self.fake.calls].count("start"), 1)
        self.assertNotIn("edit", [args[0] for args, _ in self.fake.calls])

    def test_save_completes_existing_entry_without_creating_another(self):
        self.start()
        notes = "Review `code`\n$(touch /tmp/never)"
        self.tracker.dispatch("save", self.draft(category="Client work", notes=notes))
        command = next(args for args, _ in self.fake.calls if args[0] == "edit")
        self.assertEqual(command[1], "123")
        self.assertIn(notes, command)
        self.assertIn("Client work", command)
        self.assertEqual(self.tracker.state["mode"], "idle")
        self.assertEqual([args[0] for args, _ in self.fake.calls].count("start"), 1)

    def test_delete_removes_remote_entry(self):
        self.start()
        self.tracker.dispatch("delete", self.draft())
        self.assertIn((["delete", "123"], "456"), self.fake.calls)
        self.assertEqual(self.tracker.state["mode"], "idle")

    def test_stale_form_cannot_modify_replacement_timer(self):
        self.start()
        self.fake.current["id"] = 999
        for action in ("save", "delete", "review"):
            with self.assertRaisesRegex(module.TrackerError, "changed"):
                self.tracker.dispatch(action, self.draft())
        self.assertFalse(any(args[0] in ("edit", "delete") for args, _ in self.fake.calls))

    def test_already_stopped_timer_is_not_recreated_on_save(self):
        self.start()
        self.fake.current = None
        with self.assertRaisesRegex(module.TrackerError, "already stopped"):
            self.tracker.dispatch("save", self.draft())
        self.assertEqual([args[0] for args, _ in self.fake.calls].count("start"), 1)

    def test_double_start_does_not_create_duplicate(self):
        self.start()
        with self.assertRaisesRegex(module.TrackerError, "already running"):
            self.start()
        self.assertEqual([args[0] for args, _ in self.fake.calls].count("start"), 1)

    def test_validation_happens_before_writes(self):
        self.start()
        for end in ("invalid", "2025-01-01T14:00:00Z", "2099-01-01T00:00:00Z"):
            with self.assertRaises(module.TrackerError):
                self.tracker.dispatch("save", self.draft(end=end))
        self.assertFalse(any(args[0] == "edit" for args, _ in self.fake.calls))

    def test_retry_after_edit_failure_reuses_remote_timer(self):
        self.start()
        self.fake.fail = "edit"
        with self.assertRaises(module.TrackerError):
            self.tracker.dispatch("save", self.draft())
        self.fake.fail = None
        restored = module.Tracker(self.fake)
        restored.dispatch("save", self.draft())
        self.assertEqual(restored.state["mode"], "idle")
        self.assertEqual([args[0] for args, _ in self.fake.calls].count("start"), 1)

    def test_lost_start_response_recovered_by_sync(self):
        self.fake.current = {"id": 123, "starts_at": "2026-01-01T14:00:00Z"}
        self.tracker.dispatch("status", {})
        self.assertEqual(self.tracker.state["remoteId"], 123)
        self.assertEqual(len(self.fake.calls), 1)

    def test_blank_optional_flags_are_omitted(self):
        self.start()
        self.tracker.dispatch("save", self.draft(notes="", category=""))
        command = next(args for args, _ in self.fake.calls if args[0] == "edit")
        self.assertNotIn("--notes", command)
        self.assertNotIn("--category", command)

    def test_timezone_offsets(self):
        self.assertEqual(module.instant("2026-10-08T09:30:00-04:00").isoformat(), "2026-10-08T13:30:00+00:00")


if __name__ == "__main__":
    unittest.main()
