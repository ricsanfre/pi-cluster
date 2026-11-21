#!/usr/bin/env python3
"""check-runner-versions.py

Fail when a tool pinned in `.mise.toml` disagrees with the version baked into
the `ansible-runner` image.

`.mise.toml` is the source of truth for the tools both layers use: the host
(mise) and the container that actually runs Ansible, Terraform and kubectl.
The two had drifted (kubectl 1.37.1 vs 1.37.2, helm 4.3.1 vs 4.3.2, opentofu
1.13.2 vs 1.13.9), which is only detectable by reading both files.

Only tools present on BOTH sides are compared:

  - host-only  (flux2, velero, istioctl, cilium-cli, longhorn/cli): never
    installed in the image, no comparison.
  - image-only (uv, python, alpine/helm's base): not pinned in `.mise.toml`,
    no comparison.

Image-only tools are deliberately ignored rather than reported, so Renovate
can keep bumping them independently.

Usage: python3 scripts/check-runner-versions.py [--repo-root DIR]
Exit:  0 when every shared tool matches, 1 otherwise.
"""

from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

# Image repository -> key in .mise.toml [tools]. Only images that exist on both
# sides are listed; everything else is intentionally ignored.
IMAGE_TO_TOOL = {
    "alpine/kubectl": "kubectl",
    "alpine/helm": "helm",
    "ghcr.io/opentofu/opentofu": "opentofu",
}

FROM_RE = re.compile(r"^\s*FROM\s+(?:--platform=\S+\s+)?(?P<image>\S+)", re.IGNORECASE)
COPY_FROM_RE = re.compile(r"--from=(?P<image>[^\s]+)", re.IGNORECASE)


def split_image_tag(ref: str) -> tuple[str, str | None]:
    """'ghcr.io/opentofu/opentofu:1.13.9' -> ('ghcr.io/opentofu/opentofu', '1.13.9').

    A ':' that belongs to a registry port is not a tag separator.
    """
    if ":" not in ref:
        return ref, None
    repo, _, tag = ref.rpartition(":")
    if "/" in tag:  # registry:port/image, no tag
        return ref, None
    return repo, tag


def normalize(version: str) -> str:
    """Drop a leading 'v' and any digest so 1.37.2, v1.37.2 and 1.37.2@sha match."""
    version = version.split(":", 1)[0].split("@", 1)[0].strip().strip('"')
    return version[1:] if version.startswith("v") and version[1:2].isdigit() else version


def read_mise(path: Path) -> dict[str, str]:
    data = tomllib.loads(path.read_text())
    return {str(k): normalize(str(v)) for k, v in data.get("tools", {}).items()}


def read_runner_images(path: Path) -> dict[str, set[str]]:
    """Return {tool: {versions}} for every mapped image reference in the Dockerfile."""
    found: dict[str, set[str]] = {}
    for line in path.read_text().splitlines():
        refs = []
        if match := FROM_RE.match(line):
            refs.append(match.group("image"))
        # `COPY --from=<image>` pulls a binary from another image; stage names
        # (`--from=uv`) have no registry path and are skipped.
        refs.extend(m.group("image") for m in COPY_FROM_RE.finditer(line) if "/" in m.group("image"))
        for ref in refs:
            repo, tag = split_image_tag(ref)
            tool = IMAGE_TO_TOOL.get(repo)
            if tool and tag:
                found.setdefault(tool, set()).add(normalize(tag))
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--repo-root",
        default=str(Path(__file__).resolve().parent.parent),
        help="repository root (default: parent of this script)",
    )
    args = parser.parse_args()

    root = Path(args.repo_root)
    mise_path = root / ".mise.toml"
    dockerfile_path = root / "ansible-runner" / "Dockerfile"
    for path in (mise_path, dockerfile_path):
        if not path.is_file():
            print(f"error: {path} not found", file=sys.stderr)
            return 2

    mise = read_mise(mise_path)
    runner = read_runner_images(dockerfile_path)

    shared = sorted(set(mise) & set(runner))
    failures: list[str] = []
    rows: list[tuple[str, str, str, bool]] = []

    for tool in shared:
        versions = runner[tool]
        if len(versions) > 1:
            failures.append(f"{tool}: runner image pins more than one version: {sorted(versions)}")
            continue
        image_version = next(iter(versions))
        ok = mise[tool] == image_version
        rows.append((tool, mise[tool], image_version, ok))
        if not ok:
            failures.append(f"{tool}: .mise.toml has {mise[tool]}, runner image has {image_version}")

    # A mapped image with no .mise.toml pin means the runner gained a tool
    # without a source of truth.
    for tool in sorted(set(runner) - set(mise)):
        failures.append(f"{tool}: pinned in the runner image but not in .mise.toml")

    if rows:
        width = max(len(r[0]) for r in rows)
        print(f"{'tool'.ljust(width)}  {'.mise.toml':<12}  {'runner image':<12}  status")
        for tool, host, image, ok in rows:
            print(f"{tool.ljust(width)}  {host:<12}  {image:<12}  {'ok' if ok else 'MISMATCH'}")

    if failures:
        print("\nRunner tool versions do not match .mise.toml:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        print(
            "\n.mise.toml is the source of truth. Bump it and the matching image tag in "
            "ansible-runner/Dockerfile in the same change.",
            file=sys.stderr,
        )
        return 1

    print(f"\n{len(shared)} shared tool(s) match .mise.toml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
