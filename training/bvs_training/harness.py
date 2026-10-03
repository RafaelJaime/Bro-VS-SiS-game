"""The combat-depth acceptance harness (design D15): plays the model in Godot and applies the gates.

    uv run python -m bvs_training.harness --model out/bvs_default/model.onnx
    uv run python -m bvs_training.harness --model out/bvs_default/model.onnx \
        --matchups mvm,m_vs_cpu_easy --matches 20 --seed 1

Launches `tests/smoke/combat_harness.gd` twice with the shipped GDScript interpreter:

- a regulation run (full matches: `mvm`, `m_vs_cpu_easy`, `m_vs_cpu_normal`, and the CPU-only
  reference `cpu_hard_vs_cpu_hard`), and
- a forced sudden-death run (`mvm` and the CPU reference, every match starts in sudden death).

It renders `reports/<name>-harness.json` and `.md`, applies the `[acceptance]` gates of the config and
exits non-zero when a gate fails (or a matchup a gate needs was not played):

| Gate | Source | Threshold key |
|------|--------|---------------|
| sudden death ends | forced-SD `mvm` mean SD seconds | `max_mean_sd_seconds` |
| food is picked up | every regulation matchup with the model: pickups per fighter-minute | `min_pickups_per_fighter_minute` |
| blocking is not the plan | every regulation matchup with the model: blocked share | `max_blocked_share` |
| it wins by KO | regulation `m_vs_cpu_easy` KO win rate | `min_ko_win_rate_easy` |
| enough matches | every played matchup | `min_matches` (not enforced with `--smoke`) |

Godot is found through `GODOT_BIN` (default: the Steam install on macOS). The command is a list (no shell),
the flags are fixed and every input reaches Godot through environment variables.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import tomllib
from dataclasses import dataclass
from pathlib import Path

from bvs_training import schema
from bvs_training.evaluate import godot_bin

TRAINING_DIR = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = TRAINING_DIR / "configs" / "default.toml"
REPORT_DIR = TRAINING_DIR / "reports"
REGULATION_MATCHUPS = ("mvm", "m_vs_cpu_easy", "m_vs_cpu_normal", "cpu_hard_vs_cpu_hard")
FORCED_SD_MATCHUPS = ("mvm", "cpu_hard_vs_cpu_hard")
# Keys the report fields of a gate are read from (the JSON of combat_harness.gd).
REQUIRED_ACCEPTANCE = (
    "max_mean_sd_seconds",
    "min_pickups_per_fighter_minute",
    "max_blocked_share",
    "min_ko_win_rate_easy",
    "min_matches",
)


@dataclass(frozen=True)
class GateResult:
    """One acceptance gate: its measured value, its threshold and the verdict."""

    name: str
    passed: bool
    value: float | None
    threshold: float
    detail: str

    def as_dict(self) -> dict:
        return {"name": self.name, "passed": self.passed, "value": self.value, "threshold": self.threshold, "detail": self.detail}


def uses_model(matchup: str) -> bool:
    return matchup == "mvm" or matchup.startswith("m_vs_cpu_")


def load_acceptance(config_path: Path) -> dict:
    """The `[acceptance]` table of a training config; a missing key is an error naming it."""
    with config_path.open("rb") as handle:
        table = tomllib.load(handle).get("acceptance", {})
    missing = [key for key in REQUIRED_ACCEPTANCE if key not in table]
    if missing:
        raise SystemExit(f"{config_path}: [acceptance] is missing {', '.join(missing)}")
    return dict(table)


def evaluate_gates(report: dict, acceptance: dict, enforce_min_matches: bool = True) -> list[GateResult]:
    """Applies the gates to a harness report `{"regulation": {matchup: metrics}, "forced_sd": {...}}`.

    A gate whose matchup was not played fails with a reason: a missing measurement is never a pass.
    """
    regulation: dict = report.get("regulation", {})
    forced: dict = report.get("forced_sd", {})
    results: list[GateResult] = []

    def need(table: dict, matchup: str) -> dict | None:
        return table.get(matchup)

    sd_limit = float(acceptance["max_mean_sd_seconds"])
    sd = need(forced, "mvm")
    if sd is None:
        results.append(GateResult("sudden_death_length", False, None, sd_limit, "forced sudden-death matchup mvm was not played"))
    elif int(sd.get("sd_matches", 0)) == 0:
        results.append(GateResult("sudden_death_length", False, None, sd_limit, "no forced match reached sudden death"))
    else:
        value = float(sd["mean_sd_seconds"])
        results.append(GateResult("sudden_death_length", value <= sd_limit, value, sd_limit, f"mean sudden death {value:.1f} s (limit {sd_limit:g} s)"))

    model_matchups = {name: metrics for name, metrics in regulation.items() if uses_model(name)}

    pickup_floor = float(acceptance["min_pickups_per_fighter_minute"])
    if not model_matchups:
        results.append(GateResult("pickups", False, None, pickup_floor, "no regulation matchup with the model was played"))
    else:
        worst = min(model_matchups, key=lambda name: float(model_matchups[name]["pickups_per_fighter_minute"]))
        value = float(model_matchups[worst]["pickups_per_fighter_minute"])
        results.append(GateResult("pickups", value > pickup_floor, value, pickup_floor, f"lowest {value:.2f} per fighter-minute in {worst} (must exceed {pickup_floor:g})"))

    blocked_cap = float(acceptance["max_blocked_share"])
    if not model_matchups:
        results.append(GateResult("blocked_share", False, None, blocked_cap, "no regulation matchup with the model was played"))
    else:
        worst = max(model_matchups, key=lambda name: float(model_matchups[name]["blocked_share"]))
        value = float(model_matchups[worst]["blocked_share"])
        results.append(GateResult("blocked_share", value <= blocked_cap, value, blocked_cap, f"highest {value:.2f} in {worst} (limit {blocked_cap:g})"))

    ko_floor = float(acceptance["min_ko_win_rate_easy"])
    easy = need(regulation, "m_vs_cpu_easy")
    if easy is None:
        results.append(GateResult("ko_win_rate_easy", False, None, ko_floor, "matchup m_vs_cpu_easy was not played"))
    else:
        value = float(easy["ko_win_rate"])
        results.append(GateResult("ko_win_rate_easy", value >= ko_floor, value, ko_floor, f"{value:.2f} KO wins over {int(easy['matches'])} matches (floor {ko_floor:g})"))

    min_matches = int(acceptance["min_matches"])
    if enforce_min_matches:
        played = [(f"regulation/{n}", m) for n, m in regulation.items()] + [(f"forced_sd/{n}", m) for n, m in forced.items()]
        short = [f"{name} ({int(m['matches'])})" for name, m in played if int(m["matches"]) < min_matches]
        results.append(GateResult("min_matches", not short and bool(played), float(min(int(m["matches"]) for _, m in played)) if played else None, float(min_matches), "every matchup has at least the required matches" if not short and played else f"too few matches: {', '.join(short) or 'nothing was played'}"))
    return results


def run_godot(model: Path | None, matchups: tuple[str, ...], matches: int, seed: int, force_sd: bool, work_dir: Path) -> dict:
    """One launch of combat_harness.gd; returns its parsed JSON `matchups` table."""
    out = work_dir.resolve() / ("harness_sd.json" if force_sd else "harness.json")
    env = dict(os.environ)
    env.update(
        BVS_HARNESS_MATCHUPS=",".join(matchups),
        BVS_HARNESS_MATCHES=str(matches),
        BVS_HARNESS_SEED=str(seed),
        BVS_HARNESS_FORCE_SD="1" if force_sd else "0",
        BVS_HARNESS_OUT=str(out),
    )
    if model is not None:
        env["BVS_HARNESS_MODEL"] = str(model.resolve())
    cmd = [
        godot_bin(), "--headless", "--path", str(schema.REPO_ROOT),
        "--fixed-fps", "60", "--script", "res://tests/smoke/combat_harness.gd",
    ]
    proc = subprocess.run(cmd, env=env, capture_output=True, text=True)
    log = proc.stdout + proc.stderr
    if "SCRIPT ERROR" in log or proc.returncode != 0 or not out.exists():
        print(log[-3000:], file=sys.stderr)
        raise SystemExit(f"combat_harness.gd failed (exit {proc.returncode}, force_sd={force_sd})")
    return json.loads(out.read_text())


def render_markdown(name: str, report: dict, gates: list[GateResult]) -> str:
    lines = [
        f"# Combat-depth harness: {name}",
        "",
        f"Seed {report['seed']}, {report['matches']} matches per matchup, played in Godot with the shipped GDScript interpreter.",
        "",
        "## Gates",
        "",
        "| Gate | Verdict | Measured | Threshold | Detail |",
        "|------|---------|----------|-----------|--------|",
    ]
    for gate in gates:
        measured = "n/a" if gate.value is None else f"{gate.value:.2f}"
        lines.append(f"| {gate.name} | {'PASS' if gate.passed else 'FAIL'} | {measured} | {gate.threshold:g} | {gate.detail} |")
    for title, key in (("Regulation matches", "regulation"), ("Forced sudden death", "forced_sd")):
        table = report.get(key, {})
        if not table:
            continue
        lines += ["", f"## {title}", "",
                  "| Matchup | Matches | KO results | KO win rate | Mean match (s) | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage punch | food | bomb |",
                  "|---------|---------|------------|-------------|----------------|-------------|------------|-----------------------|----------------------|---------------|---------------|--------------|------|------|"]
        for matchup, m in table.items():
            damage = m.get("damage_by_source", {})
            lines.append(
                f"| {matchup} | {m['matches']} | {m['ko_results']} | {m['ko_win_rate']:.2f} | {m['mean_match_seconds']:.1f} | "
                f"{m['mean_sd_seconds']:.1f} | {m['max_sd_seconds']:.1f} | {m['pickups_per_fighter_minute']:.2f} | "
                f"{m['throws_per_fighter_minute']:.2f} | {m['blocked_share']:.2f} | {m['shield_breaks']} | "
                f"{damage.get('punch', 0.0):.0f} | {damage.get('food', 0.0):.0f} | {damage.get('bomb', 0.0):.0f} |"
            )
    verdict = "PASS" if all(g.passed for g in gates) else "FAIL"
    lines += ["", f"Overall: **{verdict}**", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", type=Path, required=True, help="model.onnx to play (its sidecar names the schema)")
    parser.add_argument("--name", help="report name (default: the model's folder or stem)")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG, help="training config holding [acceptance]")
    parser.add_argument("--matches", type=int, help="matches per matchup (default: [acceptance].min_matches)")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--matchups", help="comma list replacing the regulation matchups (the CPU-only reference is optional)")
    parser.add_argument("--report-dir", type=Path, default=REPORT_DIR)
    parser.add_argument("--smoke", action="store_true", help="allow fewer than min_matches (pipeline checks only)")
    args = parser.parse_args(argv)

    acceptance = load_acceptance(args.config)
    matches = args.matches if args.matches is not None else int(acceptance["min_matches"])
    if matches < int(acceptance["min_matches"]) and not args.smoke:
        parser.error(f"--matches must be at least {acceptance['min_matches']} (use --smoke for pipeline checks)")
    matchups = tuple(part.strip() for part in args.matchups.split(",") if part.strip()) if args.matchups else REGULATION_MATCHUPS
    forced = tuple(name for name in FORCED_SD_MATCHUPS if name in matchups) or FORCED_SD_MATCHUPS
    model = args.model
    name = args.name or (model.parent.name if model.name == "model.onnx" else model.stem)
    args.report_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        regulation = run_godot(model, matchups, matches, args.seed, False, work)
        forced_sd = run_godot(model, forced, matches, args.seed, True, work)
    report = {
        "name": name,
        "model": str(model),
        "seed": args.seed,
        "matches": matches,
        "schema_version": regulation.get("schema_version", 0),
        "acceptance": acceptance,
        "regulation": regulation["matchups"],
        "forced_sd": forced_sd["matchups"],
    }
    gates = evaluate_gates(report, acceptance, enforce_min_matches=not args.smoke)
    report["gates"] = [gate.as_dict() for gate in gates]
    report["passed"] = all(gate.passed for gate in gates)
    (args.report_dir / f"{name}-harness.json").write_text(json.dumps(report, indent=2) + "\n")
    (args.report_dir / f"{name}-harness.md").write_text(render_markdown(name, report, gates))
    for gate in gates:
        print(f"{'PASS' if gate.passed else 'FAIL'} {gate.name}: {gate.detail}")
    print(f"report: {args.report_dir / f'{name}-harness.md'}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
