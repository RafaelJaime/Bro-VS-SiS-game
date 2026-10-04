"""The acceptance gates and the harness flow (Godot is replaced by synthetic metrics)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from bvs_training import harness

ACCEPTANCE = {
    "max_mean_sd_seconds": 45,
    "min_pickups_per_fighter_minute": 1.0,
    "max_blocked_share": 0.70,
    "min_ko_win_rate_easy": 0.60,
    "min_matches": 24,
    "min_matches_share": 40,
    "min_matches_forced_sd": 20,
    "max_combo": 6,
    "max_hurt_seconds": 1.5,
    "min_multi_hit_combos": 5,
    "kit_win_share_min": 0.40,
    "kit_win_share_max": 0.60,
    "max_combo_damage_gap": 0.20,
}
THRESHOLD = 6.0
GATED = ACCEPTANCE | {"max_shield_raises_per_fighter_minute": THRESHOLD}


def metrics(**over) -> dict:
    base = {
        "matches": 20, "ko_results": 20, "ko_wins": 15, "ko_win_rate": 0.75, "draws": 0,
        "mean_match_seconds": 60.0, "mean_sd_seconds": 10.0, "max_sd_seconds": 20.0, "sd_matches": 20,
        "pickups_per_fighter_minute": 5.0, "throws_per_fighter_minute": 4.0, "blocked_share": 0.3,
        "damage_by_source": {"punch": 100.0, "ledge": 0.0, "food": 80.0, "bomb": 12.0}, "shield_breaks": 3,
        "shield_raises_per_fighter_minute": 3.0, "max_combo": 4, "multi_hit_combos": 12, "max_hurt_seconds": 1.0,
        "hurt_over_cap": 0, "kit_win_share": 0.5, "side_win_share": 0.5,
        "combo_histogram": {"1": 40, "2": 8, "3": 3, "4": 1, "5": 0, "6": 0, "7+": 0},
        "combo_damage_by_kit": {"rafael": 11.0, "matilde": 10.0},
        "combo_damage_sum_by_kit": {"rafael": 110.0, "matilde": 100.0},
        "combo_count_by_kit": {"rafael": 10, "matilde": 10},
    }
    base.update(over)
    return base


def passing_report() -> dict:
    return {
        "seed": 1,
        "kits": "rm",
        "regulation": {
            "mvm": metrics(matches=40),
            "cpu_hard_vs_cpu_hard": metrics(matches=40, pickups_per_fighter_minute=0.0, blocked_share=0.99, shield_raises_per_fighter_minute=11.0),
            "m_vs_cpu_easy": metrics(matches=24, ko_win_rate=0.8, multi_hit_combos=0),
            "m_vs_cpu_hard": metrics(matches=24),
            "cpu_normal_vs_cpu_normal": metrics(matches=24, pickups_per_fighter_minute=0.0, blocked_share=0.99),
        },
        "forced_sd": {"mvm": metrics(matches=20)},
    }


def verdicts(report: dict, acceptance: dict = GATED, **kwargs) -> dict[str, bool]:
    return {gate.name: gate.passed for gate in harness.evaluate_gates(report, acceptance, **kwargs)}


ALL_GATES = {
    "sudden_death_length", "pickups", "blocked_share", "ko_win_rate_easy", "shield_raises", "max_combo", "max_hurt_seconds",
    "multi_hit_combos", "kit_win_share", "combo_damage_gap", "min_matches",
}


def test_a_report_that_meets_every_gate_passes() -> None:
    results = verdicts(passing_report())
    assert set(results) == ALL_GATES
    assert all(results.values()), results


def test_the_cpu_only_reference_is_not_gated_on_food_blocking_or_shields() -> None:
    report = passing_report()
    assert report["regulation"]["cpu_hard_vs_cpu_hard"]["pickups_per_fighter_minute"] == 0.0
    assert report["regulation"]["cpu_hard_vs_cpu_hard"]["shield_raises_per_fighter_minute"] > THRESHOLD
    results = verdicts(report)
    assert results["pickups"] and results["shield_raises"]


def test_a_long_sudden_death_fails_only_that_gate() -> None:
    report = passing_report()
    report["forced_sd"]["mvm"] = metrics(mean_sd_seconds=45.5)
    results = verdicts(report)
    assert results.pop("sudden_death_length") is False
    assert all(results.values())


def test_a_sudden_death_of_exactly_the_limit_passes() -> None:
    report = passing_report()
    report["forced_sd"]["mvm"] = metrics(mean_sd_seconds=45.0)
    assert verdicts(report)["sudden_death_length"]


def test_no_match_reaching_sudden_death_fails_the_gate() -> None:
    report = passing_report()
    report["forced_sd"]["mvm"] = metrics(sd_matches=0, mean_sd_seconds=0.0)
    assert verdicts(report)["sudden_death_length"] is False


def test_too_few_pickups_in_any_model_matchup_fail_that_gate_only() -> None:
    report = passing_report()
    report["regulation"]["m_vs_cpu_hard"] = metrics(matches=24, pickups_per_fighter_minute=0.9)
    results = verdicts(report)
    assert results.pop("pickups") is False
    assert all(results.values())


def test_exactly_one_pickup_per_minute_is_not_above_the_floor() -> None:
    report = passing_report()
    report["regulation"]["mvm"] = metrics(matches=40, pickups_per_fighter_minute=1.0)
    assert verdicts(report)["pickups"] is False


def test_a_blocked_share_above_the_cap_fails_that_gate_only() -> None:
    report = passing_report()
    report["regulation"]["m_vs_cpu_easy"] = metrics(matches=24, blocked_share=0.71, ko_win_rate=0.8, multi_hit_combos=0)
    results = verdicts(report)
    assert results.pop("blocked_share") is False
    assert all(results.values())


def test_a_blocked_share_at_the_cap_passes() -> None:
    report = passing_report()
    report["regulation"]["mvm"] = metrics(matches=40, blocked_share=0.70)
    assert verdicts(report)["blocked_share"]


def test_a_low_ko_win_rate_against_easy_fails_that_gate_only() -> None:
    report = passing_report()
    report["regulation"]["m_vs_cpu_easy"] = metrics(matches=24, ko_win_rate=0.55, multi_hit_combos=0)
    results = verdicts(report)
    assert results.pop("ko_win_rate_easy") is False
    assert all(results.values())


def test_too_few_matches_fail_unless_smoke() -> None:
    report = passing_report()
    report["regulation"]["m_vs_cpu_hard"] = metrics(matches=23)
    assert verdicts(report)["min_matches"] is False
    assert "min_matches" not in verdicts(report, enforce_min_matches=False)


def test_the_share_matchups_need_forty_matches_and_forced_sudden_death_twenty() -> None:
    report = passing_report()
    report["regulation"]["mvm"] = metrics(matches=39)
    gates = {gate.name: gate for gate in harness.evaluate_gates(report, GATED)}
    assert not gates["min_matches"].passed and "regulation/mvm (39 of 40)" in gates["min_matches"].detail
    report = passing_report()
    report["forced_sd"]["mvm"] = metrics(matches=19)
    gates = {gate.name: gate for gate in harness.evaluate_gates(report, GATED)}
    assert not gates["min_matches"].passed and "forced_sd/mvm (19 of 20)" in gates["min_matches"].detail


def test_the_shield_gate_uses_the_recorded_threshold_in_the_model_matchups() -> None:
    report = passing_report()
    report["regulation"]["m_vs_cpu_hard"] = metrics(matches=24, shield_raises_per_fighter_minute=6.1)
    results = verdicts(report)
    assert results.pop("shield_raises") is False
    assert all(results.values())
    report["regulation"]["m_vs_cpu_hard"] = metrics(matches=24, shield_raises_per_fighter_minute=THRESHOLD)
    assert verdicts(report)["shield_raises"]


def test_without_a_recorded_threshold_the_shield_gate_fails_with_a_reason() -> None:
    gates = {gate.name: gate for gate in harness.evaluate_gates(passing_report(), ACCEPTANCE)}
    assert not gates["shield_raises"].passed
    assert gates["shield_raises"].threshold is None
    assert "--baseline" in gates["shield_raises"].detail


def test_a_combo_longer_than_six_hits_fails_that_gate_only() -> None:
    report = passing_report()
    report["forced_sd"]["mvm"] = metrics(matches=20, max_combo=7)
    results = verdicts(report)
    assert results.pop("max_combo") is False
    assert all(results.values())


def test_a_hurt_run_over_one_and_a_half_seconds_fails_that_gate_only() -> None:
    report = passing_report()
    report["regulation"]["cpu_normal_vs_cpu_normal"] = metrics(matches=24, max_hurt_seconds=1.52, pickups_per_fighter_minute=0.0)
    results = verdicts(report)
    assert results.pop("max_hurt_seconds") is False
    assert all(results.values())
    report["regulation"]["cpu_normal_vs_cpu_normal"] = metrics(matches=24, max_hurt_seconds=1.5)
    assert verdicts(report)["max_hurt_seconds"]


def test_too_few_multi_hit_combos_in_a_combo_matchup_fail_that_gate_only() -> None:
    report = passing_report()
    report["regulation"]["cpu_normal_vs_cpu_normal"] = metrics(matches=24, multi_hit_combos=4)
    results = verdicts(report)
    assert results.pop("multi_hit_combos") is False
    assert all(results.values())
    report["regulation"]["cpu_normal_vs_cpu_normal"] = metrics(matches=24, multi_hit_combos=5)
    assert verdicts(report)["multi_hit_combos"]


@pytest.mark.parametrize("share", [0.39, 0.61])
def test_a_kit_win_share_outside_the_band_fails_that_gate_only(share: float) -> None:
    report = passing_report()
    report["regulation"]["cpu_hard_vs_cpu_hard"] = metrics(matches=40, kit_win_share=share, pickups_per_fighter_minute=0.0, blocked_share=0.99)
    results = verdicts(report)
    assert results.pop("kit_win_share") is False
    assert all(results.values())


@pytest.mark.parametrize("share", [0.4, 0.6])
def test_a_kit_win_share_on_the_band_edge_passes(share: float) -> None:
    report = passing_report()
    report["regulation"]["mvm"] = metrics(matches=40, kit_win_share=share)
    assert verdicts(report)["kit_win_share"]


def test_a_kit_win_share_with_no_decided_match_fails_with_a_reason() -> None:
    report = passing_report()
    report["regulation"]["mvm"] = metrics(matches=40, kit_win_share=None)
    gates = {gate.name: gate for gate in harness.evaluate_gates(report, GATED)}
    assert not gates["kit_win_share"].passed and "no decided match" in gates["kit_win_share"].detail


def test_the_combo_damage_gap_is_pooled_over_the_regulation_matchups() -> None:
    report = passing_report()
    assert harness.combo_damage_gap(report["regulation"]) == pytest.approx(1 - 10.0 / 11.0)
    for name in report["regulation"]:
        report["regulation"][name] = dict(report["regulation"][name], combo_damage_sum_by_kit={"rafael": 100.0, "matilde": 70.0}, combo_count_by_kit={"rafael": 10, "matilde": 10})
    assert harness.combo_damage_gap(report["regulation"]) == pytest.approx(0.30)
    results = verdicts(report)
    assert results.pop("combo_damage_gap") is False
    assert all(results.values())


def test_the_combo_damage_gap_needs_combos_of_both_kits() -> None:
    report = passing_report()
    for name in report["regulation"]:
        report["regulation"][name] = dict(report["regulation"][name], combo_count_by_kit={"rafael": 4}, combo_damage_sum_by_kit={"rafael": 40.0})
    assert harness.combo_damage_gap(report["regulation"]) is None
    assert verdicts(report)["combo_damage_gap"] is False


def test_the_threshold_follows_the_design_formula() -> None:
    threshold, note = harness.compute_threshold(r_cpu=3.0, r_old=20.0)
    assert threshold == pytest.approx(5.0)  # min(10, max(4.5, 5.0))
    assert "min(0.5 * R_old" in note
    threshold, _ = harness.compute_threshold(r_cpu=10.0, r_old=40.0)
    assert threshold == pytest.approx(15.0)  # min(20, max(15, 12))
    threshold, note = harness.compute_threshold(r_cpu=8.0, r_old=12.0)  # 0.5 * R_old = 6 < R_cpu
    assert threshold == pytest.approx(12.0)
    assert "below R_cpu" in note
    threshold, _ = harness.compute_threshold(r_cpu=0.5, r_old=30.0)
    assert threshold == pytest.approx(2.5)  # min(15, max(0.75, 2.5))


def test_plan_matchups_groups_by_match_count() -> None:
    plan = harness.plan_matchups(harness.REGULATION_MATCHUPS, ACCEPTANCE, None)
    assert plan == {40: ("mvm", "cpu_hard_vs_cpu_hard"), 24: ("m_vs_cpu_easy", "m_vs_cpu_hard", "cpu_normal_vs_cpu_normal")}
    assert sum(count * len(names) for count, names in plan.items()) + 20 == 172
    assert harness.plan_matchups(("mvm", "m_vs_cpu_easy"), ACCEPTANCE, 3) == {3: ("mvm", "m_vs_cpu_easy")}


def test_a_missing_matchup_fails_its_gate_with_a_reason() -> None:
    report = passing_report()
    del report["regulation"]["m_vs_cpu_easy"]
    del report["forced_sd"]["mvm"]
    gates = {gate.name: gate for gate in harness.evaluate_gates(report, GATED)}
    assert not gates["ko_win_rate_easy"].passed and "not played" in gates["ko_win_rate_easy"].detail
    assert not gates["sudden_death_length"].passed and "not played" in gates["sudden_death_length"].detail
    assert gates["ko_win_rate_easy"].value is None


def test_no_model_matchup_at_all_fails_the_food_and_block_gates() -> None:
    report = passing_report()
    report["regulation"] = {"cpu_hard_vs_cpu_hard": metrics(matches=40)}
    results = verdicts(report)
    assert results["pickups"] is False and results["blocked_share"] is False and results["shield_raises"] is False


def test_the_default_config_holds_the_documented_gates() -> None:
    acceptance = harness.load_acceptance(harness.DEFAULT_CONFIG)
    recorded = acceptance.pop(harness.SHIELD_THRESHOLD_KEY)
    assert acceptance == ACCEPTANCE
    assert recorded > 0.0


def test_the_recorded_shield_threshold_is_the_one_the_committed_baseline_measured() -> None:
    baseline = json.loads((harness.REPORT_DIR / "shield-baseline.json").read_text())
    acceptance = harness.load_acceptance(harness.DEFAULT_CONFIG)
    threshold, _note = harness.compute_threshold(baseline["R_cpu"], baseline["R_old"])
    assert baseline["T"] == pytest.approx(threshold)
    assert acceptance[harness.SHIELD_THRESHOLD_KEY] == round(threshold, 2) == baseline["max_shield_raises_per_fighter_minute"]
    assert baseline["R_cpu_matchup"]["matches"] == 40 and {entry["matches"] for entry in baseline["R_old_matchups"].values()} == {24}


def test_a_config_without_acceptance_names_the_missing_keys(tmp_path: Path) -> None:
    config = tmp_path / "c.toml"
    config.write_text("[acceptance]\nmax_blocked_share = 0.7\n")
    with pytest.raises(SystemExit, match="max_mean_sd_seconds"):
        harness.load_acceptance(config)


def test_uses_model() -> None:
    assert harness.uses_model("mvm") and harness.uses_model("m_vs_cpu_hard")
    assert not harness.uses_model("cpu_easy_vs_cpu_easy")


def fake_godot(report: dict, calls: list | None = None):
    def run(model, matchups, matches, seed, force_sd, work_dir, kits="rm"):
        if calls is not None:
            calls.append({"model": model, "matchups": matchups, "matches": matches, "force_sd": force_sd, "kits": kits})
        table = report["forced_sd"] if force_sd else report["regulation"]
        return {"schema_version": 4, "matchups": {name: table[name] for name in matchups if name in table}}

    return run


def gated_config(tmp_path: Path) -> Path:
    config = tmp_path / "gated.toml"
    lines = ["[acceptance]"] + [f"{key} = {value}" for key, value in GATED.items()]
    config.write_text("\n".join(lines) + "\n")
    return config


def run_main(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, report: dict, extra: list[str], calls: list | None = None) -> int:
    monkeypatch.setattr(harness, "run_godot", fake_godot(report, calls))
    return harness.main(["--model", str(tmp_path / "model.onnx"), "--name", "demo", "--report-dir", str(tmp_path), "--config", str(gated_config(tmp_path)), *extra])


def test_main_writes_reports_and_exits_zero_when_every_gate_passes(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list = []
    assert run_main(tmp_path, monkeypatch, passing_report(), [], calls) == 0
    written = json.loads((tmp_path / "demo-harness.json").read_text())
    assert written["passed"] is True
    assert written["schema_version"] == 4
    assert [gate["passed"] for gate in written["gates"]] == [True] * len(ALL_GATES)
    markdown = (tmp_path / "demo-harness.md").read_text()
    assert "Overall: **PASS**" in markdown and "| mvm |" in markdown and "Combos, shields and kits" in markdown
    assert [(c["matches"], c["force_sd"], c["kits"]) for c in calls] == [(40, False, "rm"), (24, False, "rm"), (20, True, "rm")]
    assert calls[-1]["matchups"] == ("mvm",)


def test_the_baseline_writes_both_reports_with_the_measured_threshold(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    table = {
        "cpu_hard_vs_cpu_hard": metrics(matches=40, shield_raises=120, shield_raises_per_fighter_minute=4.0),
        "mvm": metrics(matches=24, shield_raises_per_fighter_minute=30.0),
        "m_vs_cpu_hard": metrics(matches=24, shield_raises_per_fighter_minute=22.0),
    }
    calls: list = []
    monkeypatch.setattr(harness, "run_godot", fake_godot({"regulation": table, "forced_sd": {}}, calls))
    bundled = tmp_path / "model.onnx"
    bundled.write_bytes(b"x")
    assert harness.main(["--baseline", "--model", str(bundled), "--report-dir", str(tmp_path), "--seed", "1"]) == 0
    written = json.loads((tmp_path / "shield-baseline.json").read_text())
    assert written["R_cpu"] == 4.0 and written["R_old"] == 30.0
    assert written["T"] == pytest.approx(6.0)  # min(15, max(6, 6))
    assert written["max_shield_raises_per_fighter_minute"] == 6.0
    assert written["R_old_matchups"]["mvm"]["rate"] == 30.0
    markdown = (tmp_path / "shield-baseline.md").read_text()
    assert "R_cpu" in markdown and "R_old" in markdown and "**6.00**" in markdown
    assert [(c["matchups"], c["matches"], c["kits"]) for c in calls] == [(("cpu_hard_vs_cpu_hard",), 40, "rm"), (("mvm", "m_vs_cpu_hard"), 24, "rm")]
    assert calls[0]["model"] is None and calls[1]["model"] == bundled


def test_a_model_is_required_without_baseline(tmp_path: Path) -> None:
    with pytest.raises(SystemExit) as raised:
        harness.main(["--report-dir", str(tmp_path)])
    assert raised.value.code == 2


def test_main_exits_non_zero_and_marks_the_report_fail_on_a_gate_failure(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    report = passing_report()
    report["regulation"]["m_vs_cpu_easy"] = metrics(matches=24, ko_win_rate=0.1, multi_hit_combos=0)
    assert run_main(tmp_path, monkeypatch, report, []) == 1
    written = json.loads((tmp_path / "demo-harness.json").read_text())
    assert written["passed"] is False
    assert "Overall: **FAIL**" in (tmp_path / "demo-harness.md").read_text()


def test_main_refuses_too_few_matches_without_smoke(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    with pytest.raises(SystemExit) as raised:
        run_main(tmp_path, monkeypatch, passing_report(), ["--matches", "2"])
    assert raised.value.code == 2


def test_main_smoke_allows_a_short_run(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    report = passing_report()
    for table in (report["regulation"], report["forced_sd"]):
        for name in table:
            table[name] = dict(table[name], matches=2)
    assert run_main(tmp_path, monkeypatch, report, ["--matches", "2", "--smoke"]) == 0
