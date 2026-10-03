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
    "min_matches": 20,
}


def metrics(**over) -> dict:
    base = {
        "matches": 20, "ko_results": 20, "ko_wins": 15, "ko_win_rate": 0.75, "draws": 0,
        "mean_match_seconds": 60.0, "mean_sd_seconds": 10.0, "max_sd_seconds": 20.0, "sd_matches": 20,
        "pickups_per_fighter_minute": 5.0, "throws_per_fighter_minute": 4.0, "blocked_share": 0.3,
        "damage_by_source": {"punch": 100.0, "ledge": 0.0, "food": 80.0, "bomb": 12.0}, "shield_breaks": 3,
    }
    base.update(over)
    return base


def passing_report() -> dict:
    return {
        "seed": 1,
        "matches": 20,
        "regulation": {
            "mvm": metrics(),
            "m_vs_cpu_easy": metrics(ko_win_rate=0.8),
            "m_vs_cpu_normal": metrics(),
            "cpu_hard_vs_cpu_hard": metrics(pickups_per_fighter_minute=0.0, blocked_share=0.99),
        },
        "forced_sd": {"mvm": metrics(), "cpu_hard_vs_cpu_hard": metrics()},
    }


def verdicts(report: dict, **kwargs) -> dict[str, bool]:
    return {gate.name: gate.passed for gate in harness.evaluate_gates(report, ACCEPTANCE, **kwargs)}


def test_a_report_that_meets_every_gate_passes() -> None:
    results = verdicts(passing_report())
    assert set(results) == {"sudden_death_length", "pickups", "blocked_share", "ko_win_rate_easy", "min_matches"}
    assert all(results.values()), results


def test_the_cpu_only_reference_is_not_gated() -> None:
    report = passing_report()
    assert report["regulation"]["cpu_hard_vs_cpu_hard"]["pickups_per_fighter_minute"] == 0.0
    assert verdicts(report)["pickups"]


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
    report["regulation"]["m_vs_cpu_normal"] = metrics(pickups_per_fighter_minute=0.9)
    results = verdicts(report)
    assert results.pop("pickups") is False
    assert all(results.values())


def test_exactly_one_pickup_per_minute_is_not_above_the_floor() -> None:
    report = passing_report()
    report["regulation"]["mvm"] = metrics(pickups_per_fighter_minute=1.0)
    assert verdicts(report)["pickups"] is False


def test_a_blocked_share_above_the_cap_fails_that_gate_only() -> None:
    report = passing_report()
    report["regulation"]["m_vs_cpu_easy"] = metrics(blocked_share=0.71, ko_win_rate=0.8)
    results = verdicts(report)
    assert results.pop("blocked_share") is False
    assert all(results.values())


def test_a_blocked_share_at_the_cap_passes() -> None:
    report = passing_report()
    report["regulation"]["mvm"] = metrics(blocked_share=0.70)
    assert verdicts(report)["blocked_share"]


def test_a_low_ko_win_rate_against_easy_fails_that_gate_only() -> None:
    report = passing_report()
    report["regulation"]["m_vs_cpu_easy"] = metrics(ko_win_rate=0.55)
    results = verdicts(report)
    assert results.pop("ko_win_rate_easy") is False
    assert all(results.values())


def test_too_few_matches_fail_unless_smoke() -> None:
    report = passing_report()
    report["regulation"]["mvm"] = metrics(matches=19)
    assert verdicts(report)["min_matches"] is False
    assert "min_matches" not in verdicts(report, enforce_min_matches=False)


def test_a_missing_matchup_fails_its_gate_with_a_reason() -> None:
    report = passing_report()
    del report["regulation"]["m_vs_cpu_easy"]
    del report["forced_sd"]["mvm"]
    gates = {gate.name: gate for gate in harness.evaluate_gates(report, ACCEPTANCE)}
    assert not gates["ko_win_rate_easy"].passed and "not played" in gates["ko_win_rate_easy"].detail
    assert not gates["sudden_death_length"].passed and "not played" in gates["sudden_death_length"].detail
    assert gates["ko_win_rate_easy"].value is None


def test_no_model_matchup_at_all_fails_the_food_and_block_gates() -> None:
    report = passing_report()
    report["regulation"] = {"cpu_hard_vs_cpu_hard": metrics()}
    results = verdicts(report)
    assert results["pickups"] is False and results["blocked_share"] is False


def test_the_default_config_holds_the_documented_gates() -> None:
    acceptance = harness.load_acceptance(harness.DEFAULT_CONFIG)
    assert acceptance == ACCEPTANCE


def test_a_config_without_acceptance_names_the_missing_keys(tmp_path: Path) -> None:
    config = tmp_path / "c.toml"
    config.write_text("[acceptance]\nmax_blocked_share = 0.7\n")
    with pytest.raises(SystemExit, match="max_mean_sd_seconds"):
        harness.load_acceptance(config)


def test_uses_model() -> None:
    assert harness.uses_model("mvm") and harness.uses_model("m_vs_cpu_hard")
    assert not harness.uses_model("cpu_easy_vs_cpu_easy")


def fake_godot(report: dict):
    def run(model, matchups, matches, seed, force_sd, work_dir):
        table = report["forced_sd"] if force_sd else report["regulation"]
        return {"schema_version": 3, "matchups": {name: table[name] for name in matchups if name in table}}

    return run


def run_main(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, report: dict, extra: list[str]) -> int:
    monkeypatch.setattr(harness, "run_godot", fake_godot(report))
    return harness.main(["--model", str(tmp_path / "model.onnx"), "--name", "demo", "--report-dir", str(tmp_path), *extra])


def test_main_writes_reports_and_exits_zero_when_every_gate_passes(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    assert run_main(tmp_path, monkeypatch, passing_report(), []) == 0
    written = json.loads((tmp_path / "demo-harness.json").read_text())
    assert written["passed"] is True
    assert written["schema_version"] == 3
    assert [gate["passed"] for gate in written["gates"]] == [True] * 5
    markdown = (tmp_path / "demo-harness.md").read_text()
    assert "Overall: **PASS**" in markdown and "| mvm |" in markdown


def test_main_exits_non_zero_and_marks_the_report_fail_on_a_gate_failure(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    report = passing_report()
    report["regulation"]["m_vs_cpu_easy"] = metrics(ko_win_rate=0.1)
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
