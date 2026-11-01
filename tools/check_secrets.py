"""Fail CI if tracked source contains common credentials or private key files.

This is a lightweight guard, not a replacement for GitHub push protection.
The scanner never prints a matched value.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", ".godot", "build", "__pycache__"}
SECRET_FILES = {"id_rsa", "id_ed25519", "id_ecdsa"}
SECRET_SUFFIXES = {".pem", ".p12", ".pfx", ".key", ".kdbx"}
PATTERNS = {
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "JWT": re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{16,}\b"),
    "GitHub token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"),
    "OpenAI key": re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
    "AWS access key": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
}
ASSIGNMENT = re.compile(
    r"\b(?:api[_-]?key|api[_-]?token|secret|password)\b\s*[:=]\s*['\"]([^'\"\r\n]{20,})['\"]",
    re.IGNORECASE,
)
PLACEHOLDERS = ("YOUR_", "TEST_", "DUMMY", "EXAMPLE", "CHANGE_ME", "IM_SPIEL", "<", "${")


def source_files() -> list[Path]:
    top = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], cwd=ROOT, capture_output=True, text=True, check=False
    )
    result = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=False
    )
    if top.returncode == 0 and Path(top.stdout.strip()).resolve() == ROOT and result.returncode == 0:
        return [ROOT / p.decode("utf-8") for p in result.stdout.split(b"\0") if p]
    return [p for p in ROOT.rglob("*") if p.is_file() and not SKIP_DIRS.intersection(p.relative_to(ROOT).parts)]


def scan() -> list[str]:
    findings: list[str] = []
    for path in source_files():
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT).as_posix()
        name = path.name.lower()
        if name in SECRET_FILES or name == ".env" or (name.startswith(".env.") and name != ".env.example") or path.suffix.lower() in SECRET_SUFFIXES:
            findings.append(f"{relative}: credential file")
            continue
        raw = path.read_bytes()
        if b"\0" in raw:
            continue
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue
        for label, pattern in PATTERNS.items():
            for match in pattern.finditer(content):
                line = content.count("\n", 0, match.start()) + 1
                findings.append(f"{relative}:{line}: {label}")
        for match in ASSIGNMENT.finditer(content):
            value = match.group(1).strip().upper()
            if value.startswith(PLACEHOLDERS):
                continue
            line = content.count("\n", 0, match.start()) + 1
            findings.append(f"{relative}:{line}: hardcoded credential")
    return findings


if __name__ == "__main__":
    results = scan()
    if results:
        print("Possible credentials found (values hidden):")
        print("\n".join(results))
        sys.exit(1)
    print("Secret check passed.")
