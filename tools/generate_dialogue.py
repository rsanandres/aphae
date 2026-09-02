#!/usr/bin/env python3
"""Batch-grow the dialogue pools with a local model (the voice pipeline's
write side). Run this on a machine with Ollama up; CI never calls it.

    python3 tools/generate_dialogue.py --lint
    python3 tools/generate_dialogue.py --domain confessional --per-bucket 10
    python3 tools/generate_dialogue.py --domain confessional --url http://127.0.0.1:11500 --model gemma3:latest

Reads resources/dialogue/<domain>.json, and for every kind/bucket asks the
model for new lines in the same register, using the existing lines as
few-shot examples. New lines are validated (known {tokens} only, sane
length), deduplicated case-insensitively, and appended in place — rerun
until the pools are as deep as you want. Nothing is ever deleted; prune by
hand, taste is the editor.

--lint checks coverage without a model: every kind/bucket present with at
least --min-lines lines, only known tokens used. Exit 1 on holes, so it can
gate CI later if wanted.
"""

import argparse
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIALOGUE_DIR = ROOT / "resources" / "dialogue"

KNOWN_TOKENS = {"name", "detail", "desc", "desc_cap", "partner", "lost", "enemy"}
TOKEN_RE = re.compile(r"\{([a-z_]+)\}")

BUCKET_VOICE = {
    "base": "any personality",
    "anxious": "an anxious, high-neuroticism worrier",
    "catty": "a blunt, low-agreeableness office cat",
    "bold": "a loud, high-extraversion showboat",
    "even": "a deadpan, mid-range personality",
    "partner": "someone naming their new flame {partner}",
    "lost": "someone mourning a colleague named {lost}",
    "enemy": "someone trash-talking rival group {enemy}",
}

KIND_CONTEXT = {
    "secret": "finally admitting a hidden truth to the camera; every line MUST contain {detail} mid-sentence (the secret, phrased like 'is quietly interviewing at a rival company')",
    "farewell": "a departing cast member's last word to the camera",
    "intro": "introducing themselves on day one; lines may use {name}, {desc} (their description, mid-sentence) or {desc_cap}",
    "romance": "reacting to their new office romance",
    "tragedy": "reacting to a colleague's death; subdued, human, no work-speak",
    "rivalry": "their crew is at war with another group",
    "drama": "reacting to general office chaos",
}


def load(domain: str) -> tuple[pathlib.Path, dict]:
    path = DIALOGUE_DIR / f"{domain}.json"
    return path, json.loads(path.read_text(encoding="utf-8"))


def lint(min_lines: int) -> int:
    problems = []
    for path in sorted(DIALOGUE_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        for kind, buckets in data.items():
            if kind.startswith("_"):
                continue
            if not isinstance(buckets, dict):
                problems.append(f"{path.name}/{kind}: not an object")
                continue
            for bucket, lines in buckets.items():
                if not isinstance(lines, list) or not all(isinstance(l, str) for l in lines):
                    problems.append(f"{path.name}/{kind}/{bucket}: not a string list")
                    continue
                if bucket == "base" and len(lines) < min_lines:
                    problems.append(f"{path.name}/{kind}/{bucket}: {len(lines)} lines, want >= {min_lines}")
                for line in lines:
                    bad = set(TOKEN_RE.findall(line)) - KNOWN_TOKENS
                    if bad:
                        problems.append(f"{path.name}/{kind}/{bucket}: unknown tokens {sorted(bad)} in: {line!r}")
    for p in problems:
        print("LINT:", p)
    print(f"lint: {'OK' if not problems else f'{len(problems)} problem(s)'}")
    return 1 if problems else 0


def ask_model(url: str, model: str, prompt: str) -> list[str]:
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "format": {
            "type": "object",
            "properties": {"lines": {"type": "array", "items": {"type": "string"}}},
            "required": ["lines"],
        },
        "options": {"temperature": 1.0},
    }).encode()
    req = urllib.request.Request(url.rstrip("/") + "/api/chat", body,
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.load(resp)
    content = json.loads(data["message"]["content"])
    return [str(l) for l in content.get("lines", [])]


def valid(line: str, existing_tokens: set[str]) -> bool:
    if not (12 <= len(line) <= 140):
        return False
    tokens = set(TOKEN_RE.findall(line))
    if tokens - KNOWN_TOKENS:
        return False
    # A generated line may only use tokens the bucket already demonstrates —
    # a {partner} in the drama pool would never fill and never be drawn.
    return tokens <= existing_tokens


def grow(domain: str, url: str, model: str, per_bucket: int) -> None:
    path, data = load(domain)
    total_added = 0
    for kind, buckets in data.items():
        if kind.startswith("_") or not isinstance(buckets, dict):
            continue
        for bucket, lines in buckets.items():
            if not isinstance(lines, list) or not lines:
                continue
            existing_tokens = set()
            for l in lines:
                existing_tokens |= set(TOKEN_RE.findall(l))
            examples = "\n".join(f'- "{l}"' for l in lines)
            prompt = (
                "You write one-line reality-TV confessional quips for an office show.\n"
                f"Situation: the speaker is {KIND_CONTEXT.get(kind, kind)}.\n"
                f"Voice: {BUCKET_VOICE.get(bucket, bucket)}.\n"
                f"Existing lines (match the register, NEVER duplicate or lightly rephrase them):\n{examples}\n\n"
                f"Tokens in {{braces}} are placeholders filled by the game — reuse only the tokens "
                f"the examples use, keep them mid-sentence.\n"
                f"Write {per_bucket} NEW lines. Punchy, under 120 characters, no emoji, no stage directions."
            )
            try:
                candidates = ask_model(url, model, prompt)
            except Exception as exc:  # noqa: BLE001 — report and move on
                print(f"{domain}/{kind}/{bucket}: model call failed ({exc}); skipping")
                continue
            seen = {l.strip().lower() for l in lines}
            added = 0
            for cand in candidates:
                cand = cand.strip().strip('"').strip()
                if not valid(cand, existing_tokens) or cand.lower() in seen:
                    continue
                lines.append(cand)
                seen.add(cand.lower())
                added += 1
            total_added += added
            print(f"{domain}/{kind}/{bucket}: +{added} (now {len(lines)})")
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {path} (+{total_added} lines total)")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lint", action="store_true", help="check coverage and tokens, no model needed")
    ap.add_argument("--min-lines", type=int, default=3, help="lint: minimum base-bucket depth")
    ap.add_argument("--domain", default="confessional")
    ap.add_argument("--url", default="http://127.0.0.1:11434", help="Ollama URL")
    ap.add_argument("--model", default="gemma3:4b")
    ap.add_argument("--per-bucket", type=int, default=8, help="new lines to request per bucket")
    args = ap.parse_args()
    if args.lint:
        return lint(args.min_lines)
    grow(args.domain, args.url, args.model, args.per_bucket)
    return lint(args.min_lines)


if __name__ == "__main__":
    sys.exit(main())
