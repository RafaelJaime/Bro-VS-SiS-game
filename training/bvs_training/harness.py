"""The acceptance harness (design D15, D16): plays the model in Godot and applies the gates.

    uv run python -m bvs_training.harness --model out/bvs_default/model.onnx
    uv run python -m bvs_training.harness --model out/bvs_default/model.onnx \
        --matchups mvm,m_vs_cpu_easy --matches 20 --seed 1
    uv run python -m bvs_training.harness --baseline                    # shield-raise baseline (design D15)

Launches `tests/smoke/combat_harness.gd` with the shipped GDScript interpreter, one launch per group of
matchups that share a match count (kits `rm` by default: both kits on both sides):

- regulation matchups (full matches): `mvm` and `cpu_hard_vs_cpu_hard` (the two share matchups, 40 matches),
  `m_vs_cpu_easy`, `m_vs_cpu_hard` and `cpu_normal_vs_cpu_normal` (24 matches each), and
- a forced sudden-death run of `mvm` (20 matches, every match starts in sudden death):
  172 matches in all.

It renders `reports/<name>-harness.json` and `.md`, applies the `[acceptance]` gates of the config and
exits non-zero when a gate fails (or a matchup a gate needs was not played):

| Gate | Source | Threshold key |
|------|--------|---------------|
| sudden death ends | forced-SD `mvm` mean SD seconds | `max_mean_sd_seconds` |
| food is picked up | every regulation matchup with the model: pickups per fighter-minute | `min_pickups_per_fighter_minute` |
| blocking is not the plan | every regulation matchup with the model: blocked share | `max_blocked_share` |
| it wins by KO | regulation `m_vs_cpu_easy` KO win rate | `min_ko_win_rate_easy` |
| shields are not spammed | `mvm` and `m_vs_cpu_hard`: shield raises per fighter-minute | `max_shield_raises_per_fighter_minute` (recorded by `--baseline`; a missing value fails the gate) |
| combos stay short | every matchup: longest combo | `max_combo` |
| no long stun | every matchup: longest continuous Hurt (s) | `max_hurt_seconds` |
| combos happen | `mvm`, `cpu_normal_vs_cpu_normal`, `cpu_hard_vs_cpu_hard`: 2+ hit combos | `min_multi_hit_combos` |
| kits are balanced | `mvm`, `cpu_hard_vs_cpu_hard`: Rafael's win share | `kit_win_share_min`, `kit_win_share_max` |
| combo damage is balanced | all regulation matchups pooled: gap of the mean multi-hit combo damage between kits | `max_combo_damage_gap` |
| enough matches | every played matchup | `min_matches`, `min_matches_share`, `min_matches_forced_sd` (not enforced with `--smoke`) |

`--baseline` measures the shield-raise reference instead (design D15): CPU Hard against itself and the bundled
model (or `--model`) in `mvm` and `m_vs_cpu_hard`, then writes `reports/shield-baseline.{json,md}` with
`R_cpu`, `R_old` and the threshold `T`, to be set in `[acceptance]`.

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
BUNDLED_MODEL = schema.REPO_ROOT / "game" / "ai" / "models" / "bvs_default" / "model.onnx"
REPORT_DIR = TRAINING_DIR / "reports"
REGULATION_MATCHUPS = ("mvm", "cpu_hard_vs_cpu_hard", "m_vs_cpu_easy", "m_vs_cpu_hard", "cpu_normal_vs_cpu_normal")
FORCED_SD_MATCHUPS = ("mvm",)
# The matchups that decide the kit balance and the shield and combo gates (design D16).
SHARE_MATCHUPS = ("mvm", "cpu_hard_vs_cpu_hard")
SHIELD_MATCHUPS = ("mvm", "m_vs_cpu_hard")
COMBO_MATCHUPS = ("mvm", "cpu_normal_vs_cpu_normal", "cpu_hard_vs_cpu_hard")
KIT_NAMES = ("rafael", "matilde")
BASELINE_NAME = "shield-baseline"
BASELINE_CPU = ("cpu_hard_vs_cpu_hard", 40)
BASELINE_MODEL = (("mvm", "m_vs_cpu_hard"), 24)
# Keys the report fields of a gate are read from (the JSON of combat_harness.gd).
REQUIRED_ACCEPTANCE = (
    "max_mean_sd_seconds",
    "min_pickups_per_fighter_minute",
    "max_blocked_share",
    "min_ko_win_rate_easy",
    "min_matches",
    "min_matches_share",
    "min_matches_forced_sd",
    "max_combo",
    "max_hurt_seconds",
    "min_multi_hit_combos",
    "kit_win_share_min",
    "kit_win_share_max",
    "max_combo_damage_gap",
)
# Recorded by `--baseline` before the retrain; until then the shield gate fails with that reason.
SHIELD_THRESHOLD_KEY = "max_shield_raises_per_fighter_minute"


@dataclass(frozen=True)
class GateResult:
    """One acceptance gate: its measured value, its threshold and the verdict."""

    name: str
    passed: bool
    value: float | None
    threshold: float | None
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

    results += shield_gate(regulation, acceptance)
    results += combo_gates(regulation, forced, acceptance)
    results += balance_gates(regulation, acceptance)

    if enforce_min_matches:
        results.append(min_matches_gate(regulation, forced, acceptance))
    return results


def shield_gate(regulation: dict, acceptance: dict) -> list[GateResult]:
    """Shield raises per fighter-minute at or under the recorded threshold in `mvm` and `m_vs_cpu_hard`."""
    if SHIELD_THRESHOLD_KEY not in acceptance:
        return [GateResult("shield_raises", False, None, None, "no threshold is recorded in [acceptance]; run the harness with --baseline first")]
    limit = float(acceptance[SHIELD_THRESHOLD_KEY])
    played = {name: regulation[name] for name in SHIELD_MATCHUPS if name in regulation}
    missing = [name for name in SHIELD_MATCHUPS if name not in regulation]
    if missing:
        return [GateResult("shield_raises", False, None, limit, f"matchup {', '.join(missing)} was not played")]
    worst = max(played, key=lambda name: float(played[name]["shield_raises_per_fighter_minute"]))
    value = float(played[worst]["shield_raises_per_fighter_minute"])
    return [GateResult("shield_raises", value <= limit, value, limit, f"highest {value:.2f} raises per fighter-minute in {worst} (limit {limit:.2f})")]


def combo_gates(regulation: dict, forced: dict, acceptance: dict) -> list[GateResult]:
    """Maximum combo, longest Hurt and the 2+ hit combos that must occur."""
    results: list[GateResult] = []
    everything = {f"regulation/{n}": m for n, m in regulation.items()} | {f"forced_sd/{n}": m for n, m in forced.items()}
    combo_cap = float(acceptance["max_combo"])
    if not everything:
        results.append(GateResult("max_combo", False, None, combo_cap, "nothing was played"))
    else:
        worst = max(everything, key=lambda name: int(everything[name]["max_combo"]))
        value = float(everything[worst]["max_combo"])
        results.append(GateResult("max_combo", value <= combo_cap, value, combo_cap, f"longest combo {value:g} hits in {worst} (limit {combo_cap:g})"))
    hurt_cap = float(acceptance["max_hurt_seconds"])
    if not everything:
        results.append(GateResult("max_hurt_seconds", False, None, hurt_cap, "nothing was played"))
    else:
        worst = max(everything, key=lambda name: float(everything[name]["max_hurt_seconds"]))
        value = float(everything[worst]["max_hurt_seconds"])
        results.append(GateResult("max_hurt_seconds", value <= hurt_cap, value, hurt_cap, f"longest continuous Hurt {value:.2f} s in {worst} (limit {hurt_cap:g} s)"))
    floor = float(acceptance["min_multi_hit_combos"])
    missing = [name for name in COMBO_MATCHUPS if name not in regulation]
    if missing:
        results.append(GateResult("multi_hit_combos", False, None, floor, f"matchup {', '.join(missing)} was not played"))
    else:
        worst = min(COMBO_MATCHUPS, key=lambda name: int(regulation[name]["multi_hit_combos"]))
        value = float(regulation[worst]["multi_hit_combos"])
        results.append(GateResult("multi_hit_combos", value >= floor, value, floor, f"fewest 2+ hit combos {value:g} in {worst} (floor {floor:g})"))
    return results


def combo_damage_gap(regulation: dict) -> float | None:
    """abs(R - M) / max(R, M) of the mean multi-hit combo damage, pooled over the regulation matchups."""
    sums = {kit: 0.0 for kit in KIT_NAMES}
    counts = {kit: 0 for kit in KIT_NAMES}
    for metrics in regulation.values():
        for kit in KIT_NAMES:
            sums[kit] += float(metrics.get("combo_damage_sum_by_kit", {}).get(kit, 0.0))
            counts[kit] += int(metrics.get("combo_count_by_kit", {}).get(kit, 0))
    if not all(counts.values()):
        return None
    rafael, matilde = (sums[kit] / counts[kit] for kit in KIT_NAMES)
    top = max(rafael, matilde)
    return abs(rafael - matilde) / top if top > 0.0 else 0.0


def balance_gates(regulation: dict, acceptance: dict) -> list[GateResult]:
    """Rafael's win share in the share matchups and the combo damage gap between the kits."""
    results: list[GateResult] = []
    low, high = float(acceptance["kit_win_share_min"]), float(acceptance["kit_win_share_max"])
    shares: dict[str, float] = {}
    problems: list[str] = []
    for name in SHARE_MATCHUPS:
        metrics = regulation.get(name)
        if metrics is None:
            problems.append(f"matchup {name} was not played")
        elif metrics.get("kit_win_share") is None:
            problems.append(f"no decided match with different kits in {name}")
        else:
            shares[name] = float(metrics["kit_win_share"])
    if problems:
        results.append(GateResult("kit_win_share", False, None, low, "; ".join(problems)))
    else:
        worst = max(shares, key=lambda name: abs(shares[name] - 0.5))
        value = shares[worst]
        results.append(GateResult("kit_win_share", low <= value <= high, value, low, f"Rafael wins {value:.2f} in {worst} (band {low:g}-{high:g}; " + ", ".join(f"{n} {v:.2f}" for n, v in shares.items()) + ")"))
    gap_cap = float(acceptance["max_combo_damage_gap"])
    gap = combo_damage_gap(regulation)
    if gap is None:
        results.append(GateResult("combo_damage_gap", False, None, gap_cap, "a kit has no multi-hit combo in the regulation matchups"))
    else:
        results.append(GateResult("combo_damage_gap", gap <= gap_cap, gap, gap_cap, f"mean multi-hit combo damage differs by {gap:.2%} between kits (limit {gap_cap:.0%})"))
    return results


def min_matches_gate(regulation: dict, forced: dict, acceptance: dict) -> GateResult:
    """Every played matchup has its required matches (more for the share matchups, fewer for forced sudden death)."""
    base = int(acceptance["min_matches"])
    share = int(acceptance["min_matches_share"])
    forced_min = int(acceptance["min_matches_forced_sd"])
    played = [(f"regulation/{n}", m, share if n in SHARE_MATCHUPS else base) for n, m in regulation.items()]
    played += [(f"forced_sd/{n}", m, forced_min) for n, m in forced.items()]
    short = [f"{name} ({int(m['matches'])} of {need})" for name, m, need in played if int(m["matches"]) < need]
    ok = bool(played) and not short
    value = float(min(int(m["matches"]) for _, m, _ in played)) if played else None
    detail = "every matchup has at least the required matches" if ok else f"too few matches: {', '.join(short) or 'nothing was played'}"
    return GateResult("min_matches", ok, value, float(base), detail)


def compute_threshold(r_cpu: float, r_old: float) -> tuple[float, str]:
    """The shield-raise threshold T of design D15 and the note on how it was reached.

    T = min(0.5 * R_old, max(1.5 * R_cpu, R_cpu + 2.0)); when 0.5 * R_old is below R_cpu (the old model is not
    spammy on the new rules) T = max(1.5 * R_cpu, R_cpu + 2.0).
    """
    cpu_ceiling = max(1.5 * r_cpu, r_cpu + 2.0)
    if 0.5 * r_old < r_cpu:
        return cpu_ceiling, "0.5 * R_old is below R_cpu (the old model does not spam on the new rules): T = max(1.5 * R_cpu, R_cpu + 2.0)"
    return min(0.5 * r_old, cpu_ceiling), "T = min(0.5 * R_old, max(1.5 * R_cpu, R_cpu + 2.0))"


def run_godot(
    model: Path | None,
    matchups: tuple[str, ...],
    matches: int,
    seed: int,
    force_sd: bool,
    work_dir: Path,
    kits: str = "rm",
) -> dict:
    """One launch of combat_harness.gd; returns its parsed JSON (`matchups` table and `schema_version`)."""
    out = work_dir.resolve() / ("harness_sd.json" if force_sd else f"harness_{matches}_{'_'.join(matchups)}.json")
    env = dict(os.environ)
    env.update(
        BVS_HARNESS_MATCHUPS=",".join(matchups),
        BVS_HARNESS_MATCHES=str(matches),
        BVS_HARNESS_SEED=str(seed),
        BVS_HARNESS_FORCE_SD="1" if force_sd else "0",
        BVS_HARNESS_KITS=kits,
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
        f"# Acceptance harness: {name}",
        "",
        f"Seed {report['seed']}, kits `{report.get('kits', 'rm')}`, played in Godot with the shipped GDScript interpreter "
        f"({sum(int(m['matches']) for table in (report.get('regulation', {}), report.get('forced_sd', {})) for m in table.values())} matches).",
        "",
        "## Gates",
        "",
        "| Gate | Verdict | Measured | Threshold | Detail |",
        "|------|---------|----------|-----------|--------|",
    ]
    for gate in gates:
        measured = "n/a" if gate.value is None else f"{gate.value:.2f}"
        limit = "n/a" if gate.threshold is None else f"{gate.threshold:g}"
        lines.append(f"| {gate.name} | {'PASS' if gate.passed else 'FAIL'} | {measured} | {limit} | {gate.detail} |")
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
    lines += render_kit_tables(report)
    verdict = "PASS" if all(g.passed for g in gates) else "FAIL"
    lines += ["", f"Overall: **{verdict}**", ""]
    return "\n".join(lines)


def _share(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.2f}"


def render_kit_tables(report: dict) -> list[str]:
    """Shield raises, combo histogram, longest Hurt, win share by kit and side, and combo damage by kit."""
    lines: list[str] = []
    for title, key in (("Regulation", "regulation"), ("Forced sudden death", "forced_sd")):
        table = report.get(key, {})
        if not table:
            continue
        lines += ["", f"## Combos, shields and kits: {title.lower()}", "",
                  "| Matchup | Shield raises / fighter-min | Max combo | 2+ hit combos | Combo histogram (1..6, 7+) | Longest Hurt (s) | Hurt runs over 90 ticks | Rafael win share | Fighter1 win share | Combo damage Rafael | Matilde |",
                  "|---------|-----------------------------|-----------|---------------|----------------------------|------------------|--------------------------|------------------|--------------------|---------------------|---------|"]
        for matchup, m in table.items():
            histogram = m.get("combo_histogram", {})
            buckets = " / ".join(str(histogram.get(bucket, 0)) for bucket in ("1", "2", "3", "4", "5", "6", "7+"))
            damage = m.get("combo_damage_by_kit", {})
            lines.append(
                f"| {matchup} | {m.get('shield_raises_per_fighter_minute', 0.0):.2f} | {m.get('max_combo', 0)} | {m.get('multi_hit_combos', 0)} | "
                f"{buckets} | {m.get('max_hurt_seconds', 0.0):.2f} | {m.get('hurt_over_cap', 0)} | {_share(m.get('kit_win_share'))} | "
                f"{_share(m.get('side_win_share'))} | {damage.get('rafael', 0.0):.1f} | {damage.get('matilde', 0.0):.1f} |"
            )
    return lines


def plan_matchups(matchups: tuple[str, ...], acceptance: dict, override: int | None) -> dict[int, tuple[str, ...]]:
    """Matchups grouped by the number of matches each one plays (the share matchups play more)."""
    groups: dict[int, list[str]] = {}
    for name in matchups:
        count = override if override is not None else int(acceptance["min_matches_share"] if name in SHARE_MATCHUPS else acceptance["min_matches"])
        groups.setdefault(count, []).append(name)
    return {count: tuple(names) for count, names in groups.items()}


def _display_path(path: Path) -> str:
    """The path relative to the repository when it lies inside it (reports never carry an absolute home path)."""
    try:
        return str(path.resolve().relative_to(schema.REPO_ROOT))
    except ValueError:
        return path.name


def run_baseline(model: Path, seed: int, kits: str, work: Path) -> dict:
    """The shield-raise baseline (design D15): R_cpu from CPU Hard against itself, R_old from the model."""
    cpu_name, cpu_matches = BASELINE_CPU
    model_names, model_matches = BASELINE_MODEL
    cpu = run_godot(None, (cpu_name,), cpu_matches, seed, False, work, kits)["matchups"][cpu_name]
    old = run_godot(model, model_names, model_matches, seed, False, work, kits)
    r_cpu = float(cpu["shield_raises_per_fighter_minute"])
    per_matchup = {name: float(old["matchups"][name]["shield_raises_per_fighter_minute"]) for name in model_names}
    r_old = max(per_matchup.values())
    threshold, note = compute_threshold(r_cpu, r_old)
    return {
        "seed": seed,
        "kits": kits,
        "model": _display_path(model),
        "model_schema_version": old.get("schema_version", 0),
        "R_cpu": r_cpu,
        "R_cpu_matchup": {"name": cpu_name, "matches": int(cpu["matches"]), "shield_raises": int(cpu["shield_raises"]), "seconds_per_match": float(cpu["mean_match_seconds"])},
        "R_old": r_old,
        "R_old_matchups": {name: {"rate": per_matchup[name], "matches": int(old["matchups"][name]["matches"])} for name in model_names},
        "T": threshold,
        "T_rule": note,
        "max_shield_raises_per_fighter_minute": round(threshold, 2),
    }


def render_baseline(baseline: dict) -> str:
    old = baseline["R_old_matchups"]
    lines = [
        "# Shield-raise baseline (design D15)",
        "",
        f"Measured with the final gameplay and kits at seed {baseline['seed']}, `BVS_HARNESS_KITS={baseline['kits']}`, before any retrain. "
        "Raises are `Fighter.shield_raises` deltas per fighter-minute of game time (MatchMetrics).",
        "",
        "| Quantity | Value | Source |",
        "|----------|-------|--------|",
        f"| R_cpu | {baseline['R_cpu']:.2f} | `{baseline['R_cpu_matchup']['name']}`, {baseline['R_cpu_matchup']['matches']} matches ({baseline['R_cpu_matchup']['shield_raises']} raises) |",
    ]
    for name, entry in old.items():
        lines.append(f"| R_old ({name}) | {entry['rate']:.2f} | bundled model (schema {baseline['model_schema_version']}), {entry['matches']} matches |")
    lines += [
        f"| R_old | {baseline['R_old']:.2f} | maximum of the model matchups |",
        f"| **T** | **{baseline['max_shield_raises_per_fighter_minute']:.2f}** | {baseline['T_rule']} |",
        "",
        f"The gate `max_shield_raises_per_fighter_minute` in `training/configs/default.toml` is set to {baseline['max_shield_raises_per_fighter_minute']:.2f}. "
        "It applies to the retrained model in `mvm` and `m_vs_cpu_hard`. It is not changed afterwards except by a re-measurement that a report explains "
        "(for example after a kit-data change: `uv run python -m bvs_training.harness --baseline`).",
        "",
    ]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", type=Path, help="model.onnx to play (its sidecar names the schema); --baseline defaults to the bundled model")
    parser.add_argument("--name", help="report name (default: the model's folder or stem)")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG, help="training config holding [acceptance]")
    parser.add_argument("--matches", type=int, help="matches per matchup, replacing the per-matchup counts of [acceptance]")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--kits", choices=("rm", "character", "rotate4"), default="rm", help="BVS_HARNESS_KITS (default rm: both kits on both sides)")
    parser.add_argument("--matchups", help="comma list replacing the regulation matchups")
    parser.add_argument("--report-dir", type=Path, default=REPORT_DIR)
    parser.add_argument("--baseline", action="store_true", help="measure the shield-raise baseline and write shield-baseline.{json,md}")
    parser.add_argument("--smoke", action="store_true", help="allow fewer than the required matches (pipeline checks only)")
    args = parser.parse_args(argv)

    args.report_dir.mkdir(parents=True, exist_ok=True)
    if args.baseline:
        model = args.model or BUNDLED_MODEL
        if not model.exists():
            parser.error(f"model {model} does not exist")
        with tempfile.TemporaryDirectory() as tmp:
            baseline = run_baseline(model, args.seed, args.kits, Path(tmp))
        (args.report_dir / f"{BASELINE_NAME}.json").write_text(json.dumps(baseline, indent=2) + "\n")
        (args.report_dir / f"{BASELINE_NAME}.md").write_text(render_baseline(baseline))
        print(f"R_cpu={baseline['R_cpu']:.2f} R_old={baseline['R_old']:.2f} T={baseline['T']:.2f} ({baseline['T_rule']})")
        print(f"report: {args.report_dir / f'{BASELINE_NAME}.md'}")
        return 0
    if args.model is None:
        parser.error("--model is required (or use --baseline)")

    acceptance = load_acceptance(args.config)
    if args.matches is not None and args.matches < int(acceptance["min_matches_forced_sd"]) and not args.smoke:
        parser.error(f"--matches must be at least {acceptance['min_matches_forced_sd']} (use --smoke for pipeline checks)")
    matchups = tuple(part.strip() for part in args.matchups.split(",") if part.strip()) if args.matchups else REGULATION_MATCHUPS
    forced = tuple(name for name in FORCED_SD_MATCHUPS if name in matchups) or FORCED_SD_MATCHUPS
    model = args.model
    name = args.name or (model.parent.name if model.name == "model.onnx" else model.stem)

    regulation: dict = {}
    schema_version = 0
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for count, names in plan_matchups(matchups, acceptance, args.matches).items():
            launched = run_godot(model, names, count, args.seed, False, work, args.kits)
            schema_version = launched.get("schema_version", schema_version)
            regulation.update(launched["matchups"])
        forced_count = args.matches if args.matches is not None else int(acceptance["min_matches_forced_sd"])
        forced_sd = run_godot(model, forced, forced_count, args.seed, True, work, args.kits)
    report = {
        "name": name,
        "model": str(model),
        "seed": args.seed,
        "kits": args.kits,
        "schema_version": schema_version,
        "acceptance": acceptance,
        "regulation": {key: regulation[key] for key in matchups if key in regulation},
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
