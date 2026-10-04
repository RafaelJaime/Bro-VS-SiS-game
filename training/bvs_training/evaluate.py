"""Evaluate a model inside Godot with the shipped GDScript interpreter (design D12).

    uv run python -m bvs_training.evaluate --model out/bvs_default/model.onnx \
        --level easy --level normal --matches 20 --min-win-rate 0.60

Launches `tests/smoke/policy_eval.gd` once per level, renders
`reports/<name>-eval.md` (and keeps `<name>-eval.json`), and exits non-zero when the
win rate versus CPU Easy (the gate level) is below `--min-win-rate`. The report also
carries the combat-depth metrics (sudden-death length, pickups and throws per
fighter-minute, blocked share, damage by source, shield breaks) and the character-kits
metrics (shield raises per fighter-minute, combo histogram and maximum, longest Hurt,
combo damage by kit, and the model's results by kit). `--kits rm` (default) plays both
kits on both sides, `--kits character` keeps the scene kits.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

from bvs_training import schema

DEFAULT_GODOT = Path.home() / "Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot"
REPORT_DIR = Path(__file__).resolve().parents[1] / "reports"
MIN_REPORT_MATCHES = 20
LEVELS = ("easy", "normal", "hard")


def godot_bin() -> str:
    return os.environ.get("GODOT_BIN", str(DEFAULT_GODOT))


def run_level(model: Path, level: str, matches: int, work_dir: Path, dump: Path | None, kits: str = "rm") -> dict:
    out = work_dir.resolve() / f"eval_{level}.json"
    env = dict(os.environ)
    env.update(
        BVS_EVAL_MODEL=str(model.resolve()),
        BVS_EVAL_LEVEL=level,
        BVS_EVAL_MATCHES=str(matches),
        BVS_EVAL_KITS=kits,
        BVS_EVAL_OUT=str(out),
    )
    if dump is not None:
        env["BVS_EVAL_OBS_DUMP"] = str(dump.resolve())
    cmd = [
        godot_bin(), "--headless", "--path", str(schema.REPO_ROOT),
        "--fixed-fps", "60", "--script", "res://tests/smoke/policy_eval.gd",
    ]
    proc = subprocess.run(cmd, env=env, capture_output=True, text=True)
    log = proc.stdout + proc.stderr
    if "SCRIPT ERROR" in log or proc.returncode != 0 or not out.exists():
        print(log[-3000:], file=sys.stderr)
        raise SystemExit(f"policy_eval.gd failed for level {level} (exit {proc.returncode})")
    return json.loads(out.read_text())


def render_combat_depth(reports: dict[str, dict]) -> list[str]:
    """The combat-depth table: sudden-death length, food use, blocking, damage by source, shield breaks.

    Reports written before combat depth lack these fields; those levels are skipped.
    """
    lines = ["", "## Combat depth", "",
             "| Level | SD matches | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage: punch | ledge | food | bomb |",
             "|-------|------------|-------------|------------|-----------------------|----------------------|---------------|---------------|---------------|-------|------|------|"]
    rows = 0
    for level, r in reports.items():
        if "pickups_per_fighter_minute" not in r:
            continue
        damage = r.get("damage_by_source", {})
        lines.append(
            f"| {level} | {r.get('sd_matches', 0)} | {r.get('mean_sd_seconds', 0.0):.1f} | {r.get('max_sd_seconds', 0.0):.1f} | "
            f"{r['pickups_per_fighter_minute']:.2f} | {r.get('throws_per_fighter_minute', 0.0):.2f} | {r.get('blocked_share', 0.0):.2f} | "
            f"{r.get('shield_breaks', 0)} | {damage.get('punch', 0.0):.0f} | {damage.get('ledge', 0.0):.0f} | "
            f"{damage.get('food', 0.0):.0f} | {damage.get('bomb', 0.0):.0f} |"
        )
        rows += 1
    return lines if rows else []


def render_kits(reports: dict[str, dict]) -> list[str]:
    """Combos, shield raises and the model's results by kit. Reports written before the kits lack these fields."""
    lines = ["", "## Kits and combos", "",
             "| Level | Kits | Shield raises / fighter-min | Max combo | 2+ hit combos | Combo histogram (1..6, 7+) | Longest Hurt (s) | Combo damage: Rafael | Matilde |",
             "|-------|------|-----------------------------|-----------|---------------|----------------------------|------------------|----------------------|---------|"]
    rows = 0
    for level, r in reports.items():
        if "shield_raises_per_fighter_minute" not in r:
            continue
        histogram = r.get("combo_histogram", {})
        buckets = " / ".join(str(histogram.get(bucket, 0)) for bucket in ("1", "2", "3", "4", "5", "6", "7+"))
        damage = r.get("combo_damage_by_kit", {})
        lines.append(
            f"| {level} | {r.get('kits_mode', 'n/a')} | {r['shield_raises_per_fighter_minute']:.2f} | {r.get('max_combo', 0)} | "
            f"{r.get('multi_hit_combos', 0)} | {buckets} | {r.get('max_hurt_seconds', 0.0):.2f} | "
            f"{damage.get('rafael', 0.0):.1f} | {damage.get('matilde', 0.0):.1f} |"
        )
        rows += 1
    if not rows:
        return []
    lines += ["", "### Model results by kit played", "",
              "| Level | Kit | Matches | Wins | Losses | Draws |",
              "|-------|-----|---------|------|--------|-------|"]
    for level, r in reports.items():
        for kit, entry in sorted(r.get("by_kit", {}).items()):
            lines.append(f"| {level} | {kit} | {entry['matches']} | {entry['wins']} | {entry['losses']} | {entry['draws']} |")
    return lines


def render_markdown(name: str, reports: dict[str, dict], gate: dict) -> str:
    lines = [f"# Evaluation: {name}", "", "Played in Godot with the shipped GDScript ONNX interpreter, full matches versus the scripted CPU, sides alternating.", ""]
    lines += [
        "| Level | Matches | Win rate | Wins | Losses | Draws | Stocks taken (mean) | Stocks lost (mean) |",
        "|-------|---------|----------|------|--------|-------|---------------------|--------------------|",
    ]
    for level, r in reports.items():
        lines.append(
            f"| {level} | {r['matches']} | {r['win_rate']:.2f} | {r['wins']} | {r['losses']} | {r['draws']} | "
            f"{r['stocks_taken_mean']:.2f} | {r['stocks_lost_mean']:.2f} |"
        )
    lines += ["", "## Behavior indicators", "",
              "| Level | Approach ratio | Attacks thrown | Recoveries | Self-KO share of stocks lost | Idle share | Mean match (s) |",
              "|-------|----------------|----------------|------------|------------------------------|------------|----------------|"]
    for level, r in reports.items():
        lines.append(
            f"| {level} | {r['approach_ratio']:.2f} | {r['attack_presses']} | {r['recoveries']} | "
            f"{r['self_ko_share']:.2f} | {r['idle_ratio']:.2f} | {r['mean_match_seconds']:.1f} |"
        )
    lines += ["", "## Play quality", "",
              "| Level | KO wins | Timeout wins | KO losses | Timeout losses | Off-stage events | Recovery success | Specials | Mean gap (px) |",
              "|-------|---------|--------------|-----------|----------------|------------------|------------------|----------|---------------|"]
    for level, r in reports.items():
        lines.append(
            f"| {level} | {r.get('ko_wins', 0)} | {r.get('timeout_wins', 0)} | {r.get('ko_losses', 0)} | {r.get('timeout_losses', 0)} | "
            f"{r.get('off_stage_events', 0)} | {r.get('recovery_success_rate', 0.0):.2f} | {r.get('special_presses', 0)} | {r.get('mean_distance', 0.0):.0f} |"
        )
    lines += render_combat_depth(reports)
    lines += render_kits(reports)
    for level, r in reports.items():
        lines += ["", f"## Action distribution vs {level} (share of decisions per branch index, entropy in bits)", "",
                  "| Branch | Shares | Entropy |", "|--------|--------|---------|"]
        for branch in r.get("action_distribution", []):
            shares = ", ".join(f"{share:.2f}" for share in branch["shares"])
            lines.append(f"| {branch['name']} | {shares} | {branch['entropy_bits']:.2f} |")
    verdict = "PASS" if gate["passed"] else "FAIL"
    lines += ["", f"Gate: win rate versus CPU {gate['level'].title()} at least {gate['min_win_rate']:.2f} over at least "
              f"{MIN_REPORT_MATCHES} matches: **{verdict}** ({gate['win_rate']:.2f} over {gate['matches']}).", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--level", action="append", choices=LEVELS, help="repeatable; default easy")
    parser.add_argument("--matches", type=int, default=MIN_REPORT_MATCHES)
    parser.add_argument("--min-win-rate", type=float, default=0.60)
    parser.add_argument("--name", help="report name (default: the model's folder or stem)")
    parser.add_argument("--report-dir", type=Path, default=REPORT_DIR)
    parser.add_argument("--obs-dump", type=Path, help="write recorded observations (first level only)")
    parser.add_argument("--kits", choices=("rm", "character"), default="rm", help="BVS_EVAL_KITS (default rm: both kits on both sides)")
    parser.add_argument("--smoke", action="store_true", help="allow fewer than 20 matches (pipeline checks only)")
    args = parser.parse_args(argv)

    levels = args.level or ["easy"]
    if args.matches < MIN_REPORT_MATCHES and not args.smoke:
        parser.error(f"--matches must be at least {MIN_REPORT_MATCHES} (use --smoke for pipeline checks)")
    model = args.model
    name = args.name or (model.parent.name if model.name == "model.onnx" else model.stem)
    args.report_dir.mkdir(parents=True, exist_ok=True)

    reports: dict[str, dict] = {}
    for position, level in enumerate(levels):
        dump = args.obs_dump if position == 0 else None
        reports[level] = run_level(model, level, args.matches, args.report_dir, dump, args.kits)
        r = reports[level]
        print(f"{level}: win_rate={r['win_rate']:.2f} ({r['wins']}W {r['losses']}L {r['draws']}D over {r['matches']})")
        (args.report_dir / f"eval_{level}.json").unlink(missing_ok=True)

    gate_level = "easy" if "easy" in reports else levels[0]
    gate_rate = reports[gate_level]["win_rate"]
    gate = {
        "level": gate_level,
        "min_win_rate": args.min_win_rate,
        "win_rate": gate_rate,
        "matches": reports[gate_level]["matches"],
        "passed": gate_rate >= args.min_win_rate and reports[gate_level]["matches"] >= MIN_REPORT_MATCHES,
    }
    (args.report_dir / f"{name}-eval.json").write_text(json.dumps({"reports": reports, "gate": gate}, indent=2) + "\n")
    (args.report_dir / f"{name}-eval.md").write_text(render_markdown(name, reports, gate))
    print(f"report: {args.report_dir / f'{name}-eval.md'}")
    if gate_rate < args.min_win_rate:
        print(f"win rate {gate_rate:.2f} versus {gate_level} is below {args.min_win_rate:.2f}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
