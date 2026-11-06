#!/usr/bin/env python3
"""Seed a disposable store-capture database with fixed English demo work."""

import argparse
from datetime import date, datetime, time, timedelta
import json
from pathlib import Path
import sqlite3
import tempfile
from zoneinfo import ZoneInfo

PREFIX = "store-demo-"
USER = "local-user"
ZONE = ZoneInfo("Europe/Moscow")
PROJECTS = [
    ("website", "Website Redesign", "#8B5CF6"),
    ("work", "Work", "#3B82F6"),
    ("personal", "Personal", "#F59E0B"),
    ("learning", "Learning", "#10B981"),
]
# title, project, day offset (None = unscheduled), hour, priority, focus estimate
OPEN = [
    ("Review homepage wireframes", "website", 0, None, 1, 3),
    ("Prepare client presentation", "work", 0, 11, 2, 2),
    ("Book dentist appointment", "personal", 0, 14, 3, 1),
    ("Read the next chapter", "learning", 0, 17, 2, 1),
    ("Reply to project feedback", "work", 0, None, 1, 1),
    ("Plan weekend groceries", "personal", 0, 18, 4, 1),
    ("Explore homepage color options", "website", 1, 10, 2, 2),
    ("Update the project roadmap", "work", 1, 11, 2, 2),
    ("Go for a morning run", "personal", 1, 9, 4, 1),
    ("Practice conversational Spanish", "learning", 1, 12, 2, 1),
    ("Design the mobile navigation", "website", 2, 10, 2, 3),
    ("Send the weekly progress update", "work", 2, 16, 3, 1),
    ("Pick up a birthday gift", "personal", 3, None, 3, 1),
    ("Finish the typography lesson", "learning", 3, 18, 2, 2),
    ("Test the homepage prototype", "website", 4, 11, 1, 2),
    ("Plan next week's priorities", "work", 4, 15, 2, 1),
    ("Try a new dinner recipe", "personal", 5, 18, 4, 1),
    ("Summarize this month's reading", "learning", 6, None, 4, 2),
    ("Collect homepage inspiration", "website", None, None, 4, 1),
    ("Sketch the pricing page", "website", None, None, 2, 3),
    ("Organize reference files", "work", None, None, 4, 1),
    ("Refresh the portfolio case study", "work", None, None, 2, 3),
    ("Find a weekend hiking route", "personal", None, None, 4, 1),
    ("Choose the next book", "learning", None, None, 4, 1),
]
DONE = [
    ("Review the project brief", "website", -12),
    ("Organize the research notes", "learning", -10),
    ("Share the first design direction", "website", -8),
    ("Send the proposal", "work", -6),
    ("Plan the monthly budget", "personal", -4),
    ("Complete the first course module", "learning", -2),
    ("Sort the client research notes", "website", 0),
    ("Send the meeting recap", "work", 0),
]


def ident(value):
    return PREFIX + str(value)


def stamp(value):
    return int(value.timestamp())


def at(day, hour=9, minute=0):
    return datetime.combine(day, time(hour, minute), ZONE)


def put(db, table, **values):
    columns = ", ".join(values)
    placeholders = ", ".join("?" for _ in values)
    db.execute(f"INSERT INTO {table} ({columns}) VALUES ({placeholders}) "
               "ON CONFLICT DO NOTHING", tuple(values.values()))


def validate(db):
    assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    assert not db.execute("PRAGMA foreign_key_check").fetchall()
    assert db.execute("SELECT COUNT(*) FROM tasks WHERE id LIKE ?", (PREFIX + "%",)).fetchone()[0] == 36
    assert not db.execute("SELECT t.id FROM tasks t LEFT JOIN projects p ON p.id=t.project_id WHERE p.id IS NULL").fetchall()
    assert not db.execute("SELECT i.id FROM focus_intervals i LEFT JOIN focus_runs r ON r.id=i.run_id LEFT JOIN tasks t ON t.id=i.task_id WHERE r.id IS NULL OR t.id IS NULL").fetchall()
    assert not db.execute("SELECT t.id FROM tasks t LEFT JOIN tasks p ON p.id=t.parent_id WHERE t.parent_id IS NOT NULL AND p.id IS NULL").fetchall()
    assert not db.execute("SELECT tl.task_id FROM task_labels tl LEFT JOIN tasks t ON t.id=tl.task_id LEFT JOIN labels l ON l.id=tl.label_id WHERE t.id IS NULL OR l.id IS NULL").fetchall()
    assert not db.execute("SELECT c.id FROM task_completions c LEFT JOIN tasks t ON t.id=c.task_id WHERE t.id IS NULL").fetchall()
    assert not db.execute("SELECT task_id FROM task_labels WHERE kind='kanbanStatus' GROUP BY task_id HAVING COUNT(*)>1").fetchall()
    assert not db.execute("SELECT t.id FROM tasks t WHERE t.id LIKE ? AND (t.completed_focus_intervals != (SELECT COUNT(*) FROM focus_intervals i WHERE i.task_id=t.id AND i.type='work' AND i.status='completed') OR t.total_focus_seconds != COALESCE((SELECT SUM(completed_at-started_at-paused_total_seconds) FROM focus_intervals i WHERE i.task_id=t.id AND i.type='work' AND i.status='completed'),0))", (PREFIX + "%",)).fetchall()


def seed(db, today):
    assert db.execute("PRAGMA user_version").fetchone()[0] == 16, "Expected schema 16; review the fixture when the app schema changes"
    owner = db.execute("SELECT cursor FROM sync_state WHERE id='pomodoist-account-owner-v1'").fetchone()
    assert owner is None or owner[0] == "guest", "Refusing an account-owned database"
    if owner is None:
        assert db.execute("SELECT id FROM users").fetchall() == [(USER,)]
        assert not db.execute("SELECT id FROM sync_state WHERE id!='primary'").fetchone()
        assert not db.execute("SELECT owner_id FROM account_recovery_snapshots LIMIT 1").fetchone()
    assert not db.execute("SELECT id FROM tasks WHERE id NOT LIKE ? LIMIT 1", (PREFIX + "%",)).fetchone(), "Use a dedicated empty simulator"
    # The UI queues stop commands even in guest mode; preserve only fixture-owned ones.
    for kind, payload in db.execute("SELECT type, payload_json FROM sync_commands"):
        run = db.execute("SELECT task_id FROM focus_runs WHERE id=?", (json.loads(payload).get("id"),)).fetchone()
        assert kind == "focus.run.stop" and run and run[0].startswith(PREFIX), "Unexpected pending sync command"
    existing = db.execute("SELECT due_json FROM tasks WHERE id=?", (ident("task-00"),)).fetchone()
    if existing and json.loads(existing[0])["date"] != today.isoformat():
        # Rebuild only this disposable fixture when the capture day changes.
        db.execute("DELETE FROM sync_commands")
        db.execute("DELETE FROM focus_events WHERE run_id IN (SELECT id FROM focus_runs WHERE task_id LIKE ?)", (PREFIX + "%",))
        db.execute("DELETE FROM focus_intervals WHERE task_id LIKE ?", (PREFIX + "%",))
        db.execute("DELETE FROM focus_runs WHERE task_id LIKE ?", (PREFIX + "%",))
        for table, column in [("task_completions", "task_id"), ("task_labels", "task_id"),
                              ("habit_check_ins", "habit_id"), ("habits", "id"),
                              ("tasks", "id"), ("projects", "id"), ("labels", "id")]:
            db.execute(f"DELETE FROM {table} WHERE {column} LIKE ?", (PREFIX + "%",))
    created = stamp(at(today - timedelta(days=15)))
    now = stamp(at(today, 8))
    put(db, "sync_state", id="pomodoist-account-owner-v1", device_id="appstore-simulator",
        cursor="guest", created_at=created, updated_at=now)
    for order, (key, name, color) in enumerate(PROJECTS):
        put(db, "projects", id=ident(key), user_id=USER, name=name,
            color=color, is_favorite=1, order_key=f"b{order}",
            created_at=created, updated_at=now)
    for order, (key, name, color) in enumerate([
        ("deep-work", "Deep work", "#8B5CF6"),
        ("quick-win", "Quick win", "#F59E0B"),
        ("creative", "Creative", "#EC4899"),
        ("errands", "Errands", "#10B981"),
    ]):
        put(db, "labels", id=ident(key), user_id=USER, name=name,
            color=color, kind="user", order_key=f"b{order}",
            created_at=created, updated_at=now)

    def task(key, title, project, order, priority=4, estimate=1,
             due=None, parent=None, completed=None, status="todo"):
        task_id = ident(key)
        description = None
        if key == "task-00":
            description = ("Review the latest homepage concepts before the client call.\n\n"
                           "Check the content hierarchy, mobile layout and primary call to action. "
                           "Collect clear feedback for the next design iteration.")
        put(db, "tasks", id=task_id, user_id=USER, created_by=USER,
            content=title, description=description, project_id=ident(project),
            parent_id=ident(parent) if parent else None, priority=priority,
            due_json=json.dumps(due) if due else None,
            duration_seconds=estimate * 1500 if due and due["type"] == "timed" else None,
            estimated_focus_intervals=estimate, is_focus_estimate_manual=1,
            status="completed" if completed else "open",
            completed_at=completed, completed_by=USER if completed else None,
            order_key=f"a{order:04d}", day_order=order,
            created_at=created, updated_at=completed or now)
        workflow = "done" if completed else status
        put(db, "task_labels", task_id=task_id,
            label_id=f"kanban-status-{'in-progress' if workflow == 'inProgress' else workflow}-v1",
            kind="kanbanStatus", created_at=created)
        label = "deep-work" if project in ("work", "learning") else "creative" if project == "website" else "errands"
        put(db, "task_labels", task_id=task_id, label_id=ident(label), kind="user", created_at=created)
        if completed:
            put(db, "task_completions", id=ident("completion-" + key), task_id=task_id,
                user_id=USER, completed_at=completed, created_at=completed,
                snapshot_json=json.dumps({"version": 1, "kanban": {"previousStatusLabelId": "kanban-status-in-progress-v1"}}))
        return task_id

    for i, (title, project, offset, hour, priority, estimate) in enumerate(OPEN):
        due = None
        if offset is not None:
            day = today + timedelta(days=offset)
            due = {"type": "allDay", "date": day.isoformat()}
            if hour is not None:
                start = at(day, hour)
                due = {"type": "timed", "start": start.isoformat(),
                       "end": (start + timedelta(minutes=estimate * 25)).isoformat(),
                       "timeZone": ZONE.key}
        task(f"task-{i:02d}", title, project, i, priority, estimate, due,
             status="inProgress" if i in (0, 1, 4, 10) else "backlog" if offset is None else "todo")
    for i, title in enumerate(["Check the mobile layout", "Review the call to action", "Add notes for the designer", "Compare the two hero concepts"]):
        task(f"subtask-{i}", title, "website", 40 + i, priority=2,
             parent="task-00", completed=stamp(at(today, 8, 20)) if i == 3 else None)
    for i, (title, project, offset) in enumerate(DONE):
        task(f"done-{i}", title, project, 50 + i, estimate=8,
             completed=stamp(at(today + timedelta(days=offset), 8 if offset == 0 else 17, 30)),
             due={"type": "allDay", "date": (today + timedelta(days=offset)).isoformat()})

    # Historical intervals stay attached to real fixture tasks and projects.
    for offset in range(-13, 1):
        day = today + timedelta(days=offset)
        count = 3 if offset == 0 else [4, 6, 3, 5, 2, 4, 1][day.weekday()]
        for n in range(count):
            i = (n + offset) % 4
            project = PROJECTS[i][0]
            started = at(day, 6 if offset == 0 else 9) + timedelta(minutes=n * 35)
            ended = started + timedelta(minutes=25)
            run_id = ident(f"run-{offset + 13:02d}-{n}")
            if db.execute("SELECT id FROM focus_runs WHERE id=?", (run_id,)).fetchone():
                continue
            candidates = db.execute("SELECT id FROM tasks t WHERE project_id=? AND parent_id IS NULL AND (completed_at IS NULL OR completed_at>=?) AND (SELECT COUNT(*) FROM focus_intervals i WHERE i.task_id=t.id)<estimated_focus_intervals ORDER BY status='open', order_key", (ident(project), stamp(ended))).fetchall()
            assert candidates, f"No task with remaining focus estimate in {project}"
            task_id = candidates[0][0]
            put(db, "focus_runs", id=run_id, user_id=USER, task_id=task_id,
                project_id=ident(project), preset_id="classic", status="completed",
                started_at=stamp(started), ended_at=stamp(ended),
                target_work_intervals=1, completed_work_intervals=1,
                created_at=stamp(started), updated_at=stamp(ended))
            put(db, "focus_intervals", id=ident(f"interval-{offset + 13:02d}-{n}"),
                run_id=run_id, task_id=task_id, project_id=ident(project),
                type="work", status="completed", planned_seconds=1500,
                started_at=stamp(started), completed_at=stamp(ended),
                sequence_number=0, created_at=stamp(started), updated_at=stamp(ended))
    db.execute("UPDATE tasks SET completed_focus_intervals=(SELECT COUNT(*) FROM focus_intervals i WHERE i.task_id=tasks.id AND i.type='work' AND i.status='completed'), total_focus_seconds=COALESCE((SELECT SUM(completed_at-started_at-paused_total_seconds) FROM focus_intervals i WHERE i.task_id=tasks.id AND i.type='work' AND i.status='completed'),0) WHERE id LIKE ?", (PREFIX + "%",))
    db.execute("UPDATE kanban_settings SET selected_project_ids_json=? WHERE id='kanban-settings-primary-v1'", (json.dumps([ident("website")]),))
    for index, (title, icon, project, period, target) in enumerate([
        ("Read for 20 minutes", "bookOpen", "learning", "morning", 1),
        ("Drink water", "glassWater", "personal", "anytime", 6),
        ("Morning stretch", "sun", "personal", "morning", 1),
        ("Complete one focus session", "target", "work", "afternoon", 1),
        ("Take an evening walk", "footprints", "personal", "evening", 1),
    ]):
        habit_id = ident(f"habit-{index}")
        start = today - timedelta(days=13)
        schedule = [{"effectiveFrom": start.isoformat(), "startDate": start.isoformat(),
                     "endDate": None, "weekdays": list(range(1, 8)),
                     "targetPerDay": target, "dayPeriod": period}]
        put(db, "habits", id=habit_id, user_id=USER, title=title, icon=icon,
            project_id=ident(project), schedule_history_json=json.dumps(schedule),
            created_at=created, updated_at=now)
        for offset in range(-13, 1):
            day = today + timedelta(days=offset)
            count = (3 + (offset % 4)) if target == 6 else int((offset + index) % 5 != 0)
            if offset == 0:
                count = [1, 3, 1, 1, 0][index]
            for n in range(count):
                moment = stamp(at(day, 8, index * 5 + n))
                put(db, "habit_check_ins", id=ident(f"check-{index}-{offset + 13}-{n}"),
                    user_id=USER, habit_id=habit_id, day=day.isoformat(),
                    day_period=period, created_at=moment, updated_at=moment)
    validate(db)
    assert db.execute("SELECT COUNT(*) FROM habits WHERE id LIKE ?", (PREFIX + "%",)).fetchone()[0] == 5
    assert not db.execute("SELECT c.id FROM habit_check_ins c LEFT JOIN habits h ON h.id=c.habit_id WHERE h.id IS NULL").fetchall()
    assert db.execute("SELECT COUNT(DISTINCT day) FROM habit_check_ins WHERE habit_id LIKE ?", (PREFIX + "%",)).fetchone()[0] == 14


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("--date", type=date.fromisoformat, required=True)
    args = parser.parse_args()
    assert args.database.is_file(), "Launch the guest app first"
    assert args.database.resolve().parent.name.startswith("pomodoist-store-"), "Only disposable capture databases are supported"
    with sqlite3.connect(args.database) as db:
        db.execute("PRAGMA foreign_keys=ON")
        with tempfile.TemporaryDirectory() as temporary:
            with sqlite3.connect(Path(temporary) / "check.sqlite") as probe:
                db.backup(probe)
                seed(probe, args.date)
                first = list(probe.iterdump())
                seed(probe, args.date)
                assert first == list(probe.iterdump()), "Seed is not idempotent"
        with db:
            seed(db, args.date)
        print(json.dumps({"date": args.date.isoformat(), "tasks": 36,
                          "habits": 5, "intervals": db.execute("SELECT COUNT(*) FROM focus_intervals").fetchone()[0],
                          "integrity": "ok", "idempotent": True}))


if __name__ == "__main__":
    main()
