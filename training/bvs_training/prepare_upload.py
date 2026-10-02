"""Stage a model for the Hub and PRINT the upload commands. It never uploads.

    uv run python -m bvs_training.prepare_upload --repo <owner>/<name> --license <spdx> \
        --confirm <owner>/<name>

Publishing is a remote operation that needs the user's explicit confirmation of the
destination, the operation and the credential. This script therefore has no network
code: it does not import any Hub client, never reads authentication state, and only
prints the `hf` commands for a human (or the orchestrator, after the user confirmed) to run.
Without `--confirm <repo id>` equal to `--repo` it exits non-zero before doing anything.
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
STAGE_ROOT = Path(__file__).resolve().parents[1] / "out" / "upload"
FILES = ("model.onnx", "bvs.json")
TAGS = ("BVS", "bvs-schema-2", "reinforcement-learning")


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


def render_card(repo: str, license_id: str, side: dict) -> str:
    results_yaml, table = render_results(side.get("eval", {}))
    return Template(TEMPLATE.read_text()).substitute(
        license=license_id,
        repo_name=repo.split("/")[-1],
        label=side.get("label", repo.split("/")[-1]),
        results_yaml=results_yaml,
        results_table=table,
        commit=side.get("trained_on_commit", "unknown"),
    )


def stage(repo: str, license_id: str, source: Path, allow_unbundled: bool) -> Path:
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
    (target / "README.md").write_text(render_card(repo, license_id, side))
    return target


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", required=True, help="destination repo id, <owner>/<name>")
    parser.add_argument("--license", required=True, help="SPDX license id confirmed by the user")
    parser.add_argument("--confirm", help="the repo id again: explicit confirmation of the destination")
    parser.add_argument("--source", type=Path, default=BUNDLED_DIR, help="folder with model.onnx and bvs.json")
    parser.add_argument("--allow-unbundled", action="store_true", help="do not require a matching bundled copy")
    args = parser.parse_args(argv)

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

    target = stage(args.repo, args.license, args.source, args.allow_unbundled)
    message = "Add BVS policy (bvs-schema-2)"
    try:
        shown = target.relative_to(schema.REPO_ROOT)
    except ValueError:
        shown = target
    print(f"staged {target}")
    print("sha256 of the staged files matches their source.")
    print("\nNothing was uploaded. After the user confirms destination, operation and credential, run:\n")
    print(f"  hf repo create {shlex.quote(args.repo)} --repo-type model --exist-ok")
    print(f"  hf upload {shlex.quote(args.repo)} {shlex.quote(str(shown))} . --repo-type model --commit-message {shlex.quote(message)}")
    print(f"\nExpected tags on the Hub: {', '.join(TAGS)} (from the README front matter).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
