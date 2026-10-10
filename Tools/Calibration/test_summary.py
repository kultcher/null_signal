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


if __name__ == "__main__":
    unittest.main()
