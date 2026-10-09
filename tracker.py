#!/usr/bin/env python3
"""HEY owns timer state; this adapter never persists a local timer."""
import json
import os
import subprocess
import sys
from datetime import datetime, timezone


class TrackerError(Exception):
    pass


def instant(value):
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.astimezone()
        return parsed.astimezone(timezone.utc)
    except (ValueError, TypeError, OverflowError):
        raise TrackerError("Enter a valid date and time, for example 2026-10-08T14:30:00.")


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def hey(args, account=""):
    command = ["hey"] + (["--account", account] if account else []) + ["timetrack"] + args + ["--json"]
    try:
        proc = subprocess.run(command, capture_output=True, text=True, timeout=45,
                              env={**os.environ, "HEY_NONINTERACTIVE": "1"})
    except FileNotFoundError:
        raise TrackerError("The HEY CLI is missing. Install hey, then try again.")
    except subprocess.TimeoutExpired:
        raise TrackerError("HEY did not respond in time. Sync with HEY before retrying.")
    try:
        result = json.loads(proc.stdout)
    except ValueError:
        raise TrackerError("HEY returned an unreadable response. Sync with HEY before retrying.")
    if proc.returncode or not result.get("ok"):
        raise TrackerError(str(result.get("error") or proc.stderr.strip() or "HEY request failed."))
    return result.get("data")


def recording_id(record):
    value = record.get("id") if isinstance(record, dict) else None
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        return None
    return value


class Tracker:
    def __init__(self, client=hey):
        self.client = client
        self.state = None

    def sync(self, account):
        current = self.client(["current"], account)
        identifier = recording_id(current)
        if not identifier:
            self.state = {"mode": "idle", "account": account}
        else:
            start = instant(current.get("starts_at")).isoformat(timespec="seconds")
            category = current.get("category") or current.get("time_track_category") or {}
            if isinstance(category, dict):
                category = category.get("title") or category.get("name") or ""
            self.state = {"mode": "running", "remoteId": identifier, "start": start, "end": "",
                          "category": str(category), "notes": str(current.get("notes") or current.get("description") or ""),
                          "account": account}
        return self.state

    def dispatch(self, action, draft):
        account = str(draft.get("account", ""))
        self.sync(account)
        if action in ("status", "resume"):
            return
        if action == "start":
            if self.state["mode"] != "idle":
                raise TrackerError("A timer is already running in HEY.")
            self.client(["start"], account)
            self.sync(account)
            return
        if action not in ("review", "save", "delete"):
            raise TrackerError("Unknown timer action.")
        if self.state["mode"] != "running":
            raise TrackerError("This timer has already stopped in HEY. Sync to see the current timer.")
        if draft.get("remoteId") != self.state["remoteId"]:
            raise TrackerError("The current HEY timer has changed. Review it again before making changes.")
        if action == "review":
            # The review is an ephemeral form; HEY keeps tracking until Save or Delete.
            self.state.update(mode="review", end=now())
            return
        identifier = str(self.state["remoteId"])
        if action == "delete":
            self.client(["delete", identifier], account)
        else:
            start = instant(draft.get("start", self.state["start"]))
            end = instant(draft.get("end"))
            if end <= start:
                raise TrackerError("End time must be later than start time.")
            if end > datetime.now(timezone.utc):
                raise TrackerError("End time cannot be in the future.")
            args = ["edit", identifier, "--start", start.isoformat(timespec="seconds"),
                    "--end", end.isoformat(timespec="seconds")]
            # CLI 1.7 refuses blank notes/category flags.
            for key in ("notes", "category"):
                value = str(draft.get(key, ""))
                if value.strip():
                    args += ["--" + key, value]
            self.client(args, account)
        self.sync(account)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    draft = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    tracker = Tracker()
    try:
        if action == "categories":
            print(json.dumps({"ok": True, "categories": hey(["categories"], str(draft.get("account", ""))) or []}))
            return
        tracker.dispatch(action, draft)
        result = {"ok": True, "state": tracker.state}
    except TrackerError as error:
        # Do not return a pre-mutation snapshot after an ambiguous write failure.
        result = {"ok": False, "error": str(error)}
    print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"ok": False, "error": "Timer error: " + str(error)}))
        sys.exit(1)
