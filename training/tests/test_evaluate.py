"""The combat-depth table of the evaluation report (evaluate.py)."""

from __future__ import annotations

from bvs_training import evaluate


def level_report(**over) -> dict:
    report = {
        "matches": 20, "wins": 14, "losses": 5, "draws": 1, "win_rate": 0.7,
        "stocks_taken_mean": 2.5, "stocks_lost_mean": 1.5, "approach_ratio": 0.4, "attack_presses": 300,
        "recoveries": 10, "self_ko_share": 0.1, "idle_ratio": 0.05, "mean_match_seconds": 60.0,
        "action_distribution": [],
    }
    report.update(over)
    return report


COMBAT = {
    "sd_matches": 4, "mean_sd_seconds": 12.5, "max_sd_seconds": 30.0, "pickups_per_fighter_minute": 3.25,
    "throws_per_fighter_minute": 2.5, "blocked_share": 0.4, "shield_breaks": 7,
    "damage_by_source": {"punch": 900.0, "ledge": 10.0, "food": 600.0, "bomb": 24.0},
}
GATE = {"passed": True, "level": "easy", "min_win_rate": 0.6, "win_rate": 0.7, "matches": 20}


def test_the_combat_depth_table_lists_every_metric() -> None:
    lines = evaluate.render_combat_depth({"easy": level_report(**COMBAT)})
    text = "\n".join(lines)
    assert "## Combat depth" in text
    assert "| easy | 4 | 12.5 | 30.0 | 3.25 | 2.50 | 0.40 | 7 | 900 | 10 | 600 | 24 |" in text


def test_reports_without_combat_fields_are_skipped() -> None:
    assert evaluate.render_combat_depth({"easy": level_report()}) == []


def test_the_markdown_report_holds_the_combat_table_after_play_quality() -> None:
    markdown = evaluate.render_markdown("demo", {"easy": level_report(**COMBAT)}, GATE)
    assert markdown.index("## Play quality") < markdown.index("## Combat depth")
    assert "Gate: win rate versus CPU Easy" in markdown


def test_the_markdown_report_of_an_old_json_still_renders() -> None:
    markdown = evaluate.render_markdown("old", {"easy": level_report()}, GATE)
    assert "## Combat depth" not in markdown


KITS = {
    "kits_mode": "rm", "shield_raises_per_fighter_minute": 3.5, "max_combo": 4, "multi_hit_combos": 11,
    "combo_histogram": {"1": 30, "2": 8, "3": 2, "4": 1, "5": 0, "6": 0, "7+": 0}, "max_hurt_seconds": 1.1,
    "combo_damage_by_kit": {"rafael": 12.5, "matilde": 10.0},
    "by_kit": {"rafael": {"matches": 10, "wins": 7, "losses": 3, "draws": 0}, "matilde": {"matches": 10, "wins": 6, "losses": 4, "draws": 0}},
}


def test_the_kits_table_lists_combos_shields_and_the_results_by_kit() -> None:
    text = "\n".join(evaluate.render_kits({"easy": level_report(**KITS)}))
    assert "## Kits and combos" in text
    assert "| easy | rm | 3.50 | 4 | 11 | 30 / 8 / 2 / 1 / 0 / 0 / 0 | 1.10 | 12.5 | 10.0 |" in text
    assert "| easy | rafael | 10 | 7 | 3 | 0 |" in text and "| easy | matilde | 10 | 6 | 4 | 0 |" in text


def test_reports_without_kit_fields_skip_the_kits_table() -> None:
    assert evaluate.render_kits({"easy": level_report()}) == []


def test_the_markdown_report_holds_the_kits_table_after_the_combat_table() -> None:
    markdown = evaluate.render_markdown("demo", {"easy": level_report(**COMBAT, **KITS)}, GATE)
    assert markdown.index("## Combat depth") < markdown.index("## Kits and combos")
