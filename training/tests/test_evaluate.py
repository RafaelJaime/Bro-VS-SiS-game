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
