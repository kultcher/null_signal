"""Summarize gauntlet JSONL; optionally produce a reviewable CostTable candidate.

Usage: python Tools/Calibration/summarize.py path/to/telemetry --table Resources/Analysis/cost_table.json
Only the Python standard library is required. Canonical tables are never overwritten.
"""
from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import json
from collections import defaultdict
from pathlib import Path
from statistics import median


def percentile(values, fraction):
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    index = int(position)
    return ordered[index] + (ordered[min(index + 1, len(ordered) - 1)] - ordered[index]) * (position - index)


def stats(values):
    if not values:
        return {"samples": 0, "median": None, "p25": None, "p75": None, "p90": None}
    return {"samples": len(values), "median": median(values), "p25": percentile(values, .25), "p75": percentile(values, .75), "p90": percentile(values, .9)}


def tuning_signature(config):
    # Generated secrets vary by instance, not tuning. Preserve them in raw logs.
    def clean(value):
        if isinstance(value, dict):
            return {key: clean(item) for key, item in value.items()
                    if key not in {"cipher_text", "mapping_offset", "callback_sequence", "shuffle_seed", "coverage"}}
        if isinstance(value, list):
            return [clean(item) for item in value]
        return value
    raw = json.dumps(clean(config), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode()).hexdigest()[:12]


def overlap(start, end, intervals):
    spans = sorted((max(start, a), min(end, b)) for a, b in intervals if min(end, b) > max(start, a))
    total, last = 0.0, start
    for a, b in spans:
        total += max(0.0, b - max(a, last))
        last = max(last, b)
    return total


def summarize(paths, tester=None, skill=None):
    trials, sessions, incomplete, warnings = [], [], [], []
    for path in paths:
        current = {}
        with path.open(encoding="utf-8") as stream:
            for line_number, line in enumerate(stream, 1):
                if not line.strip():
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    warnings.append(f"{path}:{line_number}: incomplete or invalid JSON line ignored")
                    continue
                if event.get("event") == "run_started":
                    sessions.append(event)
                if "trial" not in event:
                    continue
                key = (event.get("session"), event["trial"])
                current.setdefault(key, []).append(event)
                if event.get("event") == "trial_ended":
                    trials.append((event, current.pop(key)))
        incomplete.extend(current.values())
    groups, components, residuals = {}, defaultdict(list), []
    for result, events in trials:
        if tester and result.get("tester") != tester or skill and result.get("skill") != skill:
            continue
        config = result["config"]
        signature = tuning_signature(config)
        key = (result["case_key"], signature, result.get("tester", ""), result.get("skill", ""))
        group = groups.setdefault(key, {"case_key": key[0], "signature": signature, "tester": key[2], "skill": key[3], "config": config, "outcomes": defaultdict(int), "clear": [], "interaction": [], "failure_elapsed": [], "failed_commands": 0, "heat": 0.0})
        outcome = result["outcome"]
        group["outcomes"][outcome] += 1
        group["failed_commands"] += result.get("failed_commands", 0)
        group["heat"] += result.get("heat", 0)
        if outcome == "success":
            if result.get("visible_to_clear_sec") is not None:
                group["clear"].append(result["visible_to_clear_sec"])
            if result.get("interaction_to_clear_sec") is not None:
                group["interaction"].append(result["interaction_to_clear_sec"])
        elif outcome == "breached":
            group["failure_elapsed"].append(result["spawn_to_end_sec"])
        # Cost candidates use unassisted successes only. Failure durations are
        # censored observations, not solve times; retain them in group outcomes.
        if outcome != "success" or result.get("null_spike_used") or result.get("programs_used"):
            continue
        clock = lambda event: float(event.get("wall_t", event["t"]))
        blocking, scans = [], []
        opened, scan_start, connected, visible = None, None, None, None
        puzzle = config.get("puzzle", "none")
        modules = config.get("ic", [])
        isolated = (puzzle != "none" and not modules) or (puzzle == "none" and len(modules) == 1) or (puzzle == "none" and not modules)
        def sample(component, duration, channel="blocking"):
            if isolated and duration >= 0:
                components[(component, signature, channel)].append(duration)
        first_command = False
        for event in events:
            name, when = event["event"], clock(event)
            if name == "signal_visible":
                visible = when
            elif name == "scan_started":
                scan_start = when
                if visible is not None:
                    sample("base.notice", max(0, when - visible))
                    visible = None
            elif name in {"scan_complete", "scan_cancelled"} and scan_start is not None:
                scans.append((scan_start, when))
                scan_start = None
            elif name == "connected" and connected is None:
                connected = when
            elif name == "command_started" and connected is not None and not first_command:
                # Connection-to-first-command includes reading and deciding;
                # don't double count Callback response as base command work.
                if not any(module["ic"] == "callback" for module in modules):
                    sample("base.command", when - connected)
                first_command = True
            elif name == "puzzle_opened":
                opened = when
            elif name == "puzzle_solved" and opened is not None:
                sample(f"puzzle.{puzzle}.{config['difficulty']}", when - opened)
                blocking.append((opened, when))
                opened = None
            elif name == "puzzle_closed" and opened is not None:
                blocking.append((opened, when))
                opened = None
            elif name == "ic_neutralized" and event.get("ic") == "callback" and connected is not None:
                sample(f"ic.callback.{event['difficulty']}", when - connected)
                blocking.append((connected, when))
        scan_duration = sum(b - a for a, b in scans)
        scan_background = sum((b - a) - overlap(a, b, blocking) for a, b in scans)
        group.setdefault("scan", []).append(scan_duration)
        group.setdefault("background", []).append(scan_background)
        if scan_start is not None:
            warnings.append(f"{result['session']} trial {result['trial']}: unfinished scan excluded from background duration")
        if puzzle == "none" and len(modules) <= 1 and result.get("interaction_to_clear_sec") is not None:
            residuals.append({"result": result, "duration": result["interaction_to_clear_sec"], "scan": scan_duration})
    group_rows = []
    for group in groups.values():
        group_rows.append({"case_key": group["case_key"], "signature": group["signature"], "tester": group["tester"], "skill": group["skill"], "trials": sum(group["outcomes"].values()), "outcomes": dict(group["outcomes"]), "clear": stats(group["clear"]), "interaction": stats(group["interaction"]), "failure_elapsed": stats(group["failure_elapsed"]), "scan": stats(group.get("scan", [])), "background": stats(group.get("background", [])), "failed_commands": group["failed_commands"], "heat": group["heat"], "config": group["config"]})
    component_rows = [{"key": key[0], "signature": key[1], "channel": key[2], **stats(values)} for key, values in sorted(components.items())]
    # IC residuals are whole-task overhead, not a defensible attention split.
    # Match baselines by tester, skill, speed and breach window.
    baseline = defaultdict(list)
    context = lambda r: (r.get("tester"), r.get("skill"), r["config"].get("runner_speed"), r["config"].get("breach_delay_sec"))
    for row in residuals:
        if not row["result"]["config"].get("ic"):
            baseline[context(row["result"])].append(row)
    overhead = defaultdict(list)
    for row in residuals:
        result = row["result"]
        if not result["config"].get("ic") or not baseline[context(result)]:
            continue
        base = baseline[context(result)]
        key = result["case_key"]
        # Remove extra scanning before estimating attention/interaction overhead.
        delta = row["duration"] - row["scan"] - median([item["duration"] - item["scan"] for item in base])
        overhead[(key, tuning_signature(result["config"]))].append(delta)
    overhead_rows = [{"key": key[0], "signature": key[1], "classification": "unattributed_baseline_delta", **stats(values)} for key, values in sorted(overhead.items())]
    return {"version": 1, "sessions": len(sessions), "incomplete_trials": len(incomplete), "groups": group_rows, "components": component_rows, "ic_overhead": overhead_rows, "warnings": warnings, "notes": ["Clear percentiles include successful trials only; consult breach counts and failure elapsed times for censoring.", "Component samples use unassisted successful isolated trials. Keep tester/skill filters consistent.", "Puzzle open-to-solve and Callback response are observed elapsed times, classified as blocking per ThreatAndCost; they are not measured cognitive attention.", "IC baseline deltas are descriptive overhead and are not automatically assigned to blocking/background.", "Same difficulty can have multiple tuning signatures; candidates require a single signature per component."]}


def candidate_table(table, report, min_samples):
    result = copy.deepcopy(table)
    grouped = defaultdict(list)
    for row in report["components"]:
        grouped[row["key"]].append(row)
    for key, rows in grouped.items():
        if len(rows) != 1 or rows[0]["samples"] < min_samples:
            continue
        row = rows[0]
        parts = key.split(".")
        if parts[0] == "puzzle":
            entry = result.setdefault("puzzles", {}).setdefault(parts[1], {}).setdefault(parts[2], {})
        elif parts[0] == "ic":
            old = result.setdefault("ic", {}).get(parts[1], {})
            if "blocking" in old or "background" in old:
                # Preserve the flat guess at every unmeasured gauntlet tier;
                # CostTable otherwise propagates the nearest lower entry.
                old = {str(tier): copy.deepcopy(old) for tier in range(1, max(20, int(parts[2])) + 1)}
                result["ic"][parts[1]] = old
            entry = old.setdefault(parts[2], {})
            result["ic"][parts[1]] = old
        else:
            entry = result.setdefault("base", {}).setdefault(parts[1], {})
        entry.update({row["channel"]: row["median"], "source": "telemetry", "samples": row["samples"], "p25": row["p25"], "p75": row["p75"], "p90": row["p90"], "signature": row["signature"], "notes": "Observed elapsed time; isolated, unassisted successful trials. Review failure counts before adopting."})
        entry.setdefault("blocking", 0.0)
        entry.setdefault("background", 0.0)
    return result


def write_csv(path, rows):
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    flattened = [{k: json.dumps(v, sort_keys=True) if isinstance(v, (dict, list)) else v for k, v in row.items()} for row in rows]
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(flattened[0]))
        writer.writeheader()
        writer.writerows(flattened)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--table", type=Path)
    parser.add_argument("--min-samples", type=int, default=5)
    parser.add_argument("--tester")
    parser.add_argument("--skill")
    args = parser.parse_args()
    paths = sorted({p for item in args.inputs for p in (item.glob("*.jsonl") if item.is_dir() else [item])})
    if not paths:
        parser.error("No JSONL session files found")
    output = args.out or paths[0].parent / "summary"
    output.mkdir(parents=True, exist_ok=True)
    report = summarize(paths, args.tester, args.skill)
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    write_csv(output / "trials_summary.csv", report["groups"])
    write_csv(output / "component_costs.csv", report["components"])
    write_csv(output / "ic_overhead.csv", report["ic_overhead"])
    if args.table:
        table = json.loads(args.table.read_text(encoding="utf-8"))
        candidate = candidate_table(table, report, max(1, args.min_samples))
        (output / "cost_table_candidate.json").write_text(json.dumps(candidate, indent=2) + "\n", encoding="utf-8")
    print(f"Summarized {len(paths)} sessions, {len(report['groups'])} groups; output: {output}")
    for warning in report["warnings"]:
        print("Warning:", warning)


if __name__ == "__main__":
    main()
