"""Stage a model for the Hub and PRINT the upload commands. It never uploads.

    uv run python -m bvs_training.prepare_upload --repo <owner>/<name> --license <spdx> \
        --confirm <owner>/<name> --replay ../training/reports/bvs_default-replay.mp4
    uv run python -m bvs_training.prepare_upload --space --confirm-space RafaelJaime/BroVSister

Publishing is a remote operation that needs the user's explicit confirmation of the
destination, the operation and the credential. This script therefore has no network
code: it does not import any Hub client, never reads authentication state, and only
prints the `hf` commands for a human (or the orchestrator, after the user confirmed) to run.
Without `--confirm <repo id>` equal to `--repo` it exits non-zero before doing anything; the
Space deploy steps need their own `--confirm-space <space id>` (confirming the model repo does
not confirm the Space, or the reverse). `--replay <path>` stages that file as `replay.mp4` next
to the model (the model page shows it); without it, a `replay.mp4` already sitting next to
`model.onnx`/`bvs.json` in `--source` is still staged automatically.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shlex
import shutil
import sys
from pathlib import Path
from string import Template

from bvs_training import schema, sidecar

BUNDLED_DIR = schema.REPO_ROOT / "game" / "ai" / "models" / "bvs_default"
TEMPLATE = Path(__file__).resolve().parents[1] / "templates" / "model_card.md"
DEFAULT_HARNESS_REPORT = Path(__file__).resolve().parents[1] / "reports" / "bvs_default-harness.json"
STAGE_ROOT = Path(__file__).resolve().parents[1] / "out" / "upload"
FILES = ("model.onnx", "bvs.json")
# Staged next to the model when present in the source folder (a gameplay replay for the model page).
OPTIONAL_FILES = ("replay.mp4",)
# `hf` alone can resolve to an unrelated CLI (for example the Higgsfield one), so the printed
# commands run the Hugging Face CLI through uvx. `hf upload` also creates a missing repo.
HF = "uvx --from huggingface_hub hf"
TAGS = ("BVS", schema.SCHEMA_TAG, "reinforcement-learning")
# The web build's Space (design D19); confirming the model repo never confirms this, or the reverse.
SPACE_ID = "RafaelJaime/BroVSister"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render_results(eval_block: dict) -> tuple[str, str]:
    """(model-index results YAML, markdown table) from the sidecar `eval` block."""
    yaml_lines, rows = [], ["| Opponent | Matches | Win rate |", "|----------|---------|----------|"]
    for key, result in sorted(eval_block.items()):
        opponent = key.replace("vs_", "").replace("_", " ")
        matches, rate = result.get("matches", 0), float(result.get("win_rate", 0.0))
        rows.append(f"| {opponent} | {matches} | {rate:.2f} |")
        yaml_lines += [
            "      - task:",
            "          type: reinforcement-learning",
            "        dataset:",
            f"          name: {opponent}",
            "          type: bvs-matches",
            "        metrics:",
            "          - type: win_rate",
            f"            value: {rate:.4f}",
            f"            name: win rate versus {opponent} over {matches} matches",
        ]
    if not eval_block:
        yaml_lines = ["      []"]
        rows.append("| (not evaluated) | 0 | n/a |")
    return "\n".join(yaml_lines), "\n".join(rows)


def render_harness(harness: dict | None) -> str:
    """The acceptance-gate table (`reports/bvs_default-harness.json`'s `gates`) as markdown.

    Missing or unreadable is reported, not hidden, so a model card never silently omits it.
    """
    if not harness or not harness.get("gates"):
        return "(no harness report found; run `bvs_training.harness` and pass `--harness-report`)"
    rows = ["| Gate | Verdict | Measured | Threshold |", "|------|---------|----------|-----------|"]
    for gate in harness["gates"]:
        verdict = "PASS" if gate.get("passed") else "FAIL"
        rows.append(f"| {gate['name']} | {verdict} | {float(gate.get('value', 0.0)):.2f} | {float(gate.get('threshold', 0.0)):.2f} |")
    overall = "PASS" if harness.get("passed") else "FAIL"
    rows.append(f"\nOverall (seed {harness.get('seed', '?')}, kits `{harness.get('kits', '?')}`): **{overall}**")
    return "\n".join(rows)


def render_card(repo: str, license_id: str, side: dict, harness: dict | None = None) -> str:
    results_yaml, table = render_results(side.get("eval", {}))
    return Template(TEMPLATE.read_text()).substitute(
        license=license_id,
        repo_name=repo.split("/")[-1],
        label=side.get("label", repo.split("/")[-1]),
        results_yaml=results_yaml,
        results_table=table,
        harness_table=render_harness(harness),
        commit=side.get("trained_on_commit", "unknown"),
    )


def load_harness(path: Path) -> dict | None:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return None


def stage(repo: str, license_id: str, source: Path, allow_unbundled: bool, replay: Path | None = None, harness_report: Path = DEFAULT_HARNESS_REPORT) -> Path:
    name = repo.split("/")[-1]
    for file in FILES:
        if not (source / file).exists():
            raise SystemExit(f"missing {source / file}")
    side = json.loads((source / "bvs.json").read_text())
    problem = sidecar.validate(side)
    if problem:
        raise SystemExit(f"bvs.json rejected: {problem}")
    if not allow_unbundled:
        for file in FILES:
            bundled = BUNDLED_DIR / file
            if not bundled.exists():
                raise SystemExit(f"no bundled copy of {file} at {bundled}; pass --allow-unbundled to stage anyway")
            if sha256(bundled) != sha256(source / file):
                raise SystemExit(f"{file} differs from the bundled copy {bundled}")
    target = STAGE_ROOT / name
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)
    for file in FILES:
        shutil.copyfile(source / file, target / file)
        assert sha256(target / file) == sha256(source / file), f"staged {file} differs from its source"
    for file in OPTIONAL_FILES:
        if (source / file).is_file():
            shutil.copyfile(source / file, target / file)
            assert sha256(target / file) == sha256(source / file), f"staged {file} differs from its source"
    if replay is not None:
        if not replay.is_file():
            raise SystemExit(f"--replay {replay} does not exist")
        shutil.copyfile(replay, target / "replay.mp4")
        assert sha256(target / "replay.mp4") == sha256(replay), "staged replay.mp4 differs from its source"
    (target / "README.md").write_text(render_card(repo, license_id, side, load_harness(harness_report)))
    return target


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", help="destination repo id, <owner>/<name>")
    parser.add_argument("--license", help="SPDX license id confirmed by the user")
    parser.add_argument("--confirm", help="the repo id again: explicit confirmation of the destination")
    parser.add_argument("--source", type=Path, default=BUNDLED_DIR, help="folder with model.onnx and bvs.json")
    parser.add_argument("--allow-unbundled", action="store_true", help="do not require a matching bundled copy")
    parser.add_argument("--replay", type=Path, help="replay.mp4 to stage next to the model (e.g. ../training/reports/bvs_default-replay.mp4)")
    parser.add_argument("--harness-report", type=Path, default=DEFAULT_HARNESS_REPORT, help="harness.py JSON report to show on the model card")
    parser.add_argument("--space", action="store_true", help="print the Space deploy steps too (print-only, no deploy)")
    parser.add_argument("--confirm-space", help="the Space id again: explicit confirmation of the Space destination")
    args = parser.parse_args(argv)

    if args.repo is None and not args.space:
        parser.error("pass --repo (to stage a model for the Hub) or --space (to print the Space deploy steps)")

    if args.repo is not None:
        if not args.license:
            parser.error("--license is required with --repo")
        if args.confirm != args.repo:
            print(
                "refusing to prepare an upload: explicit confirmation is required. "
                f"Re-run with --confirm {args.repo} once the user confirmed the destination, "
                "the operation and the credential.",
                file=sys.stderr,
            )
            return 2
        if args.repo.count("/") != 1 or not all(args.repo.split("/")):
            print("--repo must look like <owner>/<name>", file=sys.stderr)
            return 2

        target = stage(args.repo, args.license, args.source, args.allow_unbundled, args.replay, args.harness_report)
        message = f"Add BVS policy ({schema.SCHEMA_TAG})"
        try:
            shown = target.relative_to(schema.REPO_ROOT)
        except ValueError:
            shown = target
        print(f"staged {target}")
        print("sha256 of the staged files matches their source.")
        print("\nNothing was uploaded. After the user confirms destination, operation and credential, run:\n")
        print(f"  {HF} repos create {shlex.quote(args.repo)} --repo-type model --exist-ok")
        print(f"  {HF} upload {shlex.quote(args.repo)} {shlex.quote(str(shown))} . --repo-type model --commit-message {shlex.quote(message)}")
        print(f"\nExpected tags on the Hub: {', '.join(TAGS)} (from the README front matter).")

    if args.space:
        if args.confirm_space != SPACE_ID:
            print(
                "refusing to print the Space deploy steps: explicit confirmation is required. "
                f"Re-run with --confirm-space {SPACE_ID} once the user confirmed the Space destination, "
                "the operation and the credential (confirming the model repo above does not confirm the Space).",
                file=sys.stderr,
            )
            return 2
        print(f"\nNothing was deployed. After the user confirms the Space destination, operation and credential, deploy the web export to {SPACE_ID}:\n")
        print(f"  {HF} repos create {shlex.quote(SPACE_ID)} --repo-type space --space-sdk static --exist-ok")
        print(f"  {HF} upload {shlex.quote(SPACE_ID)} <web-export-dir> . --repo-type space --commit-message \"Deploy BVS web build ({schema.SCHEMA_TAG})\"")
        print(f"\nThen check https://huggingface.co/spaces/{SPACE_ID} loads the new build.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
