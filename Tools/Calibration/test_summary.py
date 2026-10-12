"""Check cost extraction, censoring, profile separation and table compatibility."""
import json
import tempfile
import unittest
from pathlib import Path

from summarize import candidate_table, overlap, summarize, tuning_signature


class SummaryTests(unittest.TestCase):
    def fixture(self, outcome="success", assisted=False):
        config = {"puzzle": "fuzz", "difficulty": 2, "ic": [],
                  "resolved_puzzle": {"target_points": 100}, "runner_speed": .15}
        common = {"session": "test", "trial": 1, "tester": "alice", "skill": "novice"}
        events = []
        for name, when in [("signal_visible", 0), ("scan_started", 1),
                           ("connected", 2), ("puzzle_opened", 3),
                           ("scan_complete", 6), ("puzzle_solved", 13)]:
            events.append({**common, "event": name, "t": when / 2, "wall_t": when})
        events.append({**common, "event": "trial_ended", "t": 7, "wall_t": 14,
                       "config": config, "outcome": outcome, "case_key": "puzzle.fuzz.2",
                       "visible_to_clear_sec": 14, "interaction_to_clear_sec": 13,
                       "spawn_to_end_sec": 14, "programs_used": ["key"] if assisted else []})
        return events

    def report(self, events):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "session.jsonl"
            path.write_text("\n".join(json.dumps(e) for e in events), encoding="utf-8")
            return summarize([path])

    def test_real_time_and_scan_overlap(self):
        report = self.report(self.fixture())
        puzzle = next(row for row in report["components"] if row["key"] == "puzzle.fuzz.2")
        self.assertEqual(puzzle["median"], 10)
        self.assertEqual(report["groups"][0]["background"]["median"], 2)
        self.assertEqual(overlap(0, 10, [(1, 5), (3, 7)]), 6)

    def test_failures_and_assistance_are_not_solve_costs(self):
        report = self.report(self.fixture("breached"))
        self.assertEqual(report["components"], [])
        self.assertEqual(report["groups"][0]["clear"]["samples"], 0)
        self.assertEqual(report["groups"][0]["failure_elapsed"]["median"], 14)
        self.assertEqual(self.report(self.fixture(assisted=True))["components"], [])

    def test_tuning_signature_ignores_secrets_but_preserves_tuning(self):
        one = {"resolved": {"callback_sequence": "abc", "tick_sec": 1}, "shuffle_seed": 3}
        two = {"resolved": {"callback_sequence": "xyz", "tick_sec": 1}, "shuffle_seed": 8}
        self.assertEqual(tuning_signature(one), tuning_signature(two))
        two["resolved"]["tick_sec"] = 2
        self.assertNotEqual(tuning_signature(one), tuning_signature(two))

    def test_candidates_preserve_guesses_and_flat_fallbacks(self):
        table = {"version": 1, "ic": {"callback": {"blocking": 3, "background": 0, "source": "guess"}}}
        row = {"key": "ic.callback.2", "signature": "a", "channel": "blocking",
               "median": 6, "p25": 5, "p75": 7, "p90": 8, "samples": 4}
        self.assertEqual(candidate_table(table, {"components": [row]}, 5), table)
        row["samples"] = 5
        candidate = candidate_table(table, {"components": [row]}, 5)
        self.assertEqual(candidate["ic"]["callback"]["1"]["source"], "guess")
        self.assertEqual(candidate["ic"]["callback"]["2"]["blocking"], 6)
        self.assertEqual(candidate["ic"]["callback"]["3"]["source"], "guess")
        self.assertEqual(table["ic"]["callback"]["blocking"], 3)
        other = {**row, "signature": "b"}
        self.assertEqual(candidate_table(table, {"components": [row, other]}, 5), table)

    def test_incomplete_trials_do_not_become_completed(self):
        report = self.report(self.fixture()[:-1])
        self.assertEqual(report["incomplete_trials"], 1)
        self.assertEqual(report["groups"], [])

    def connection_trial(self, trial, config, ready=True):
        common = {"session": "mixed", "trial": trial, "tester": "alice", "skill": "novice"}
        phases = [("signal_visible", 0), ("scan_started", 1), ("scan_complete", 2),
                  ("connected", 2)]
        if ready:
            phases.append(("connection_ready", 3))
        phases.append(("command_started", 5))
        if any(module["ic"] == "callback" for module in config["ic"]):
            phases.append(("ic_neutralized", 7))
        events = [{**common, "event": name, "t": when, "wall_t": when,
                   "ic": "callback", "difficulty": 2} for name, when in phases]
        events.append({**common, "event": "trial_ended", "t": 8, "wall_t": 8,
                       "outcome": "success", "case_key": str(config), "config": config,
                       "interaction_to_clear_sec": 7, "visible_to_clear_sec": 8})
        return events

    def test_mixed_matrix_updates_base_only_from_baselines(self):
        baseline = {"puzzle": "none", "difficulty": 0, "ic": [], "runner_speed": .15}
        puzzle = {**baseline, "puzzle": "sniff", "difficulty": 2}
        callback = {**baseline, "ic": [{"ic": "callback", "difficulty": 2}]}
        events = []
        for index, config in enumerate([baseline, puzzle, callback] * 5):
            events += self.connection_trial(index + 1, config)
        report = self.report(events)
        table = candidate_table({"version": 1, "base": {}}, report, 5)
        for key, value in [("notice", 1), ("connect", 1), ("command", 2)]:
            self.assertEqual(table["base"][key]["source"], "telemetry")
            self.assertEqual(table["base"][key]["samples"], 5)
            self.assertEqual(table["base"][key]["blocking"], value)
        # Callback begins after the reveal, so it does not include connect.
        self.assertEqual(table["ic"]["callback"]["2"]["blocking"], 4)

    def test_legacy_connection_logs_do_not_double_count_reveal(self):
        baseline = {"puzzle": "none", "difficulty": 0, "ic": []}
        callback = {**baseline, "ic": [{"ic": "callback", "difficulty": 2}]}
        report = self.report(self.connection_trial(1, baseline, ready=False)
                             + self.connection_trial(2, callback, ready=False))
        keys = {row["key"] for row in report["components"]}
        self.assertNotIn("base.connect", keys)
        self.assertNotIn("base.command", keys)
        self.assertNotIn("ic.callback.2", keys)
        self.assertEqual(len(report["warnings"]), 2)

    def test_different_baseline_tuning_is_still_kept_separate(self):
        one = {"puzzle": "none", "difficulty": 0, "ic": [], "runner_speed": .15}
        two = {**one, "runner_speed": .3}
        report = self.report(self.connection_trial(1, one) + self.connection_trial(2, two))
        table = {"version": 1, "base": {"command": {"blocking": 9, "source": "guess"}}}
        candidate = candidate_table(table, report, 1)
        self.assertEqual(candidate["base"]["command"], table["base"]["command"])

    def element(self, trial, outcome, lead=-1.0, warmup=False, predicted=3.0, case="baseline"):
        config = {"puzzle": "none", "difficulty": 0, "ic": [], "runner_speed": .15, "lead_cells": lead,
                  "window_sec": 20.0 if lead < 0 else lead / .15, "warmup": warmup, "session_index": trial,
                  "predicted": {"total": predicted}, "exposure": {"puzzle.sniff": trial}}
        common = {"session": "s", "trial": trial, "tester": "alice", "skill": "novice"}
        return [{**common, "event": "signal_visible", "t": 0, "wall_t": 0},
                {**common, "event": "scan_started", "t": 1, "wall_t": 1},
                {**common, "event": "trial_ended", "t": 6, "wall_t": 6, "config": config, "outcome": outcome,
                 "case_key": case, "visible_to_clear_sec": 6 if outcome == "success" else None,
                 "interaction_to_clear_sec": 5 if outcome == "success" else None, "spawn_to_end_sec": 6}]

    def test_bookkeeping_does_not_split_signatures(self):
        one = {"puzzle": "none", "ic": [], "predicted": {"total": 3}, "exposure": {"a": 1}, "warmup": True, "session_index": 1}
        two = {"puzzle": "none", "ic": [], "predicted": {"total": 9}, "exposure": {"a": 7}, "warmup": False, "session_index": 9}
        self.assertEqual(tuning_signature(one), tuning_signature(two))

    def test_disruption_counts_are_aggregated_without_double_counting_events(self):
        config = {"puzzle": "none", "difficulty": 0,
                  "ic": [{"ic": "lag", "difficulty": 2, "resolved": {"delay_sec": .3}}]}
        events = []
        for trial in [1, 2]:
            rows = self.connection_trial(trial, config)
            friction = [{**rows[0], "event": "ic_disruption", "ic": "lag", "phase": "queued"}] * 2
            if trial == 1:
                rows[-1]["disruption_counts"] = {"lag.queued": 8}
            events += rows[:-1] + friction + rows[-1:]
        report = self.report(events)
        self.assertEqual(report["groups"][0]["disruption_counts"], {"lag.queued": 10})
        # Friction counters do not invent a cognitive blocking/background cost.
        self.assertNotIn("ic.lag.2", {row["key"] for row in report["components"]})

    def test_encounters_keep_added_ic_profiles_and_host_roles_separate(self):
        events = []
        for index, (delay, role) in enumerate([(None, ""), (.3, "door"), (.5, "door"), (.3, "cam_watch")]):
            added = [] if delay is None else [{"ic": "lag", "difficulty": 2, "resolved": {"delay_sec": delay}}]
            events.append({"event": "encounter_ended", "session": "s", "encounter": str(index),
                           "tester": "alice", "skill": "novice", "template": "watched_door",
                           "difficulty": 1, "wildcard": {}, "lead_cells": 3, "outcome": "clean",
                           "visible_to_pass_sec": 20, "added_ic": added, "ic_host_role": role,
                           "disruption_counts": {"lag.queued": 4} if added else {}})
        report = self.report(events)
        self.assertEqual(len(report["encounters"]), 4)
        rows = report["encounters"]
        self.assertEqual(len({row["ic_signature"] for row in rows}), 3)
        self.assertEqual(sum(row["disruption_counts"].get("lag.queued", 0) for row in rows), 12)
        self.assertEqual(next(row for row in rows if not row["added_ic"])["ic_host_role"], "")
        self.assertEqual(report["components"], [])

    def test_warmup_does_not_contaminate_disruption_counts(self):
        config = {"puzzle": "none", "difficulty": 0, "ic": [{"ic": "glitch", "difficulty": 1}], "warmup": True}
        rows = self.connection_trial(1, config)
        rows[-1]["disruption_counts"] = {"glitch.fake_clicked": 12}
        self.assertEqual(self.report(rows)["groups"], [])

    def test_warmup_is_skipped_unless_requested(self):
        events = self.element(1, "success", warmup=True) + self.element(2, "success")
        report = self.report(events)
        self.assertEqual(report["warmup_trials_skipped"], 1)
        self.assertEqual(report["groups"][0]["trials"], 1)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "session.jsonl"
            path.write_text("\n".join(json.dumps(e) for e in events), encoding="utf-8")
            self.assertEqual(summarize([path], include_warmup=True)["groups"][0]["trials"], 2)

    def test_window_curve_and_prediction(self):
        events = []
        for index, (lead, outcome) in enumerate([(3.0, "breached"), (3.0, "success"), (6.0, "success"), (6.0, "success")]):
            events += self.element(index + 1, outcome, lead)
        report = self.report(events)
        rates = {row["lead_cells"]: row["success_rate"] for row in report["window_curve"]}
        self.assertEqual(rates, {3.0: 0.5, 6.0: 1.0})
        self.assertEqual(report["prediction"][0]["residual"]["median"], 2)

    def test_host_and_window_baselines_are_not_mixed(self):
        events = []
        # Same case/tier, but passing a camera is a different endpoint from OP
        # on a door; comparing different approach windows is also misleading.
        for index, (host, lead, ic, duration) in enumerate([
            ("door", 3, False, 2), ("camera", 3, False, 12),
            ("door", 6, False, 22), ("door", 3, True, 5),
        ]):
            config = {"puzzle": "none", "difficulty": 0, "runner_speed": .15,
                      "breach_delay_sec": 3, "host": host, "lead_cells": lead,
                      "predicted": {"total": 3},
                      "ic": [{"ic": "lag", "difficulty": 1}] if ic else []}
            rows = self.connection_trial(index + 1, config)
            if host == "camera":
                # Existing ordinary-play logs lack config.host, but expose
                # the actual signal type on each event.
                config.pop("host")
                rows[-1]["sig_type"] = "CAMERA"
            rows[-1].update({"case_key": "ic.lag.1" if ic else "baseline",
                             "interaction_to_clear_sec": duration})
            events += rows
        report = self.report(events)
        self.assertEqual(report["ic_overhead"][0]["median"], 3)
        baseline_prediction = [row for row in report["prediction"] if row["case_key"] == "baseline"]
        self.assertEqual({row["host"] for row in baseline_prediction}, {"door", "camera"})
        self.assertEqual(len([row for row in report["window_curve"] if row["case_key"] == "baseline"]), 3)

    def test_encounters_are_grouped_rated_and_kept_out_of_costs(self):
        events = []
        member = {"puzzle": "none", "difficulty": 0, "ic": [], "template": "watched_door", "role": "cam_watch", "encounter": "enc_0001"}
        common = {"session": "s", "trial": 1, "tester": "alice", "skill": "novice"}
        events += [{**common, "event": "signal_visible", "t": 0, "wall_t": 0},
                   {**common, "event": "scan_started", "t": 1, "wall_t": 1},
                   {**common, "event": "trial_ended", "t": 4, "wall_t": 4, "config": member, "outcome": "success",
                    "case_key": "enc.watched_door.cam_watch", "visible_to_clear_sec": 4, "interaction_to_clear_sec": 3, "spawn_to_end_sec": 4}]
        for index, (outcome, heat) in enumerate([("clean", 0), ("heated", 120), ("warm", 0)]):
            events.append({"event": "encounter_ended", "session": "s", "tester": "alice", "skill": "novice", "encounter": f"enc_{index:04d}",
                           "template": "watched_door", "wildcard": {}, "difficulty": 1, "lead_cells": -1, "outcome": outcome if outcome != "warm" else "clean",
                           "visible_to_pass_sec": 20 + index, "heat": heat, "damage": 0, "predicted_total": 8, "warmup": outcome == "warm", "info": {}})
        events.append({"event": "rating", "session": "s", "encounter": "enc_0001", "rating": 3})
        report = self.report(events)
        self.assertEqual(report["components"], [])
        row = report["encounters"][0]
        self.assertEqual(row["encounters"], 2)
        self.assertEqual(row["clean_rate"], 0.5)
        self.assertEqual(row["rating"], 3)
        self.assertEqual(row["visible_to_pass"]["median"], 20.5)


if __name__ == "__main__":
    unittest.main()
