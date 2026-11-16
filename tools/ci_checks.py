#!/usr/bin/env python3
"""Pre-build verification checks for FullGram CI and local validation."""

from __future__ import annotations

import argparse
import configparser
import json
import re
import sys
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parent.parent

REQUIRED_FILES = [
    "versions.json",
    "build_number_offset",
    "README.md",
    "docs/PLUGIN_API.md",
    "docs/badges.example.json",
    "build-system/appstore-configuration.json",
    "build-system/Make/Make.py",
    "build-system/Make/BuildEnvironment.py",
    "build-system/Make/BuildConfiguration.py",
    "build-system/Make/ImportCertificates.py",
    "submodules/Camera/CameraNeo/Sources/FullGramRoundVideoMask.swift",
    "submodules/Display/Source/FullGramAIAssistant.swift",
    "submodules/Display/Source/FullGramAntiScam.swift",
    "submodules/Display/Source/FullGramAppearance.swift",
    "submodules/Display/Source/FullGramBackup.swift",
    "submodules/Display/Source/FullGramBadges.swift",
    "submodules/Display/Source/FullGramLuaEngine.swift",
    "submodules/Display/Source/FullGramMediaAudio.swift",
    "submodules/Display/Source/FullGramPluginManager.swift",
    "submodules/Display/Source/FullGramPluginValue.swift",
    "submodules/Display/Source/FullGramPythonEngine.swift",
    "submodules/Display/Source/FullGramSpeechBleep.swift",
    "submodules/Display/Source/FullGramVoiceDSP.swift",
    "submodules/TelegramCore/Sources/FullGram/FullGramGhostMode.swift",
    "submodules/TelegramCore/Sources/FullGram/FullGramMessageHistory.swift",
    "submodules/TelegramPresentationData/Sources/FullGramCustomizedTheme.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramAIAssistantScreen.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramAntiScamScreen.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramAppearanceScreens.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramMediaAudioScreens.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramPluginsScreen.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramSettingsController.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramSettingsSearchScreen.swift",
    "submodules/TelegramUI/Sources/FullGramAIOverlay.swift",
    "submodules/TelegramUI/Sources/FullGramChatLock.swift",
    "submodules/TelegramUI/Sources/FullGramLyrics.swift",
    "submodules/TelegramUI/Sources/FullGramPlayerOverlays.swift",
    "submodules/TelegramUI/Sources/FullGramPluginCommandBar.swift",
    "submodules/TelegramUI/Sources/FullGramProfanityBleep.swift",
    "submodules/TelegramUI/Sources/FullGramVoiceChanger.swift",
    "Telegram/Telegram-iOS/Resources/FullGramMascotPet.png",
    "Telegram/Telegram-iOS/Resources/FullGramMascotPortrait.png",
    "Telegram/Telegram-iOS/Resources/FullGramIcon_FullGramDefault.png",
    "Telegram/Telegram-iOS/Resources/FullGramIcon_FullGramMascot.png",
    "Telegram/Telegram-iOS/Resources/FullGramIcon_FullGramOrange.png",
    "Telegram/Telegram-iOS/Resources/FullGramIcon_FullGramRed.png",
]

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
CONFLICT_LINE_RE = re.compile(r"^(<<<<<<<\s|=======\s*$|>>>>>>>\s)")


def load_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise AssertionError(f"Invalid JSON in {path.relative_to(ROOT)}: {exc}") from exc


def check_required_files() -> None:
    missing = [rel for rel in REQUIRED_FILES if not (ROOT / rel).is_file()]
    if missing:
        raise AssertionError("Missing required files:\n  - " + "\n  - ".join(missing))

    for rel in REQUIRED_FILES:
        path = ROOT / rel
        if path.stat().st_size == 0:
            raise AssertionError(f"Required file is empty: {rel}")
        if path.suffix.lower() == ".png":
            header = path.read_bytes()[:8]
            if header != PNG_MAGIC:
                raise AssertionError(f"Invalid PNG signature in {rel}")


def check_configs() -> None:
    versions = load_json(ROOT / "versions.json")
    if not isinstance(versions, dict):
        raise AssertionError("versions.json must be a JSON object")
    for key in ("app", "xcode", "bazel", "macos"):
        if not versions.get(key):
            raise AssertionError(f"versions.json missing '{key}'")
    if ":" not in str(versions["bazel"]):
        raise AssertionError("versions.json 'bazel' must follow '<version>:<sha256>' format")

    build_offset_text = (ROOT / "build_number_offset").read_text(encoding="utf-8").strip()
    if not build_offset_text.isdigit():
        raise AssertionError(f"build_number_offset must be an integer, got: {build_offset_text!r}")

    appstore_cfg = load_json(ROOT / "build-system/appstore-configuration.json")
    if not isinstance(appstore_cfg, dict):
        raise AssertionError("build-system/appstore-configuration.json must be a JSON object")
    required_cfg_keys = (
        "bundle_id",
        "api_id",
        "api_hash",
        "team_id",
        "is_internal_build",
        "is_appstore_build",
        "appstore_id",
        "app_specific_url_scheme",
        "premium_iap_product_id",
        "enable_siri",
        "enable_icloud",
    )
    for key in required_cfg_keys:
        if key not in appstore_cfg:
            raise AssertionError(f"appstore-configuration.json missing '{key}'")

    badges = load_json(ROOT / "docs/badges.example.json")
    if not isinstance(badges, dict):
        raise AssertionError("docs/badges.example.json must be a JSON object")
    if "badges" not in badges and "users" not in badges:
        raise AssertionError("docs/badges.example.json must define 'badges' or 'users'")


def check_submodules(require_populated: bool) -> None:
    parser = configparser.ConfigParser()
    parser.read(ROOT / ".gitmodules", encoding="utf-8")
    sections = parser.sections()
    if not sections:
        raise AssertionError(".gitmodules contains no submodule definitions")

    for section in sections:
        sub_path = parser.get(section, "path", fallback="").strip()
        sub_url = parser.get(section, "url", fallback="").strip()
        if not sub_path or not sub_url:
            raise AssertionError(f"Incomplete submodule entry in .gitmodules: [{section}]")
        if sub_url.startswith("../") or sub_url.startswith("./"):
            raise AssertionError(
                f"Submodule [{section}] uses relative URL '{sub_url}', which breaks CI forks"
            )
        if require_populated:
            full_path = ROOT / sub_path
            if not full_path.is_dir() or not any(full_path.iterdir()):
                raise AssertionError(
                    f"Submodule directory is missing or empty: {sub_path} (did checkout fetch submodules?)"
                )


def iter_fullgram_swift_files() -> Iterable[Path]:
    for base in (ROOT / "submodules", ROOT / "Telegram"):
        if base.is_dir():
            for path in sorted(base.rglob("FullGram*.swift")):
                yield path


def check_swift_delimiters(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    for line_no, line in enumerate(text.splitlines(), start=1):
        if CONFLICT_LINE_RE.match(line):
            raise AssertionError(
                f"Git merge conflict marker found in {path.relative_to(ROOT)}:{line_no}"
            )

    pairs = {"(": ")", "[": "]", "{": "}"}
    closing = {v: k for k, v in pairs.items()}
    # Stack entries are either ("delim", open_ch, line) or ("interp", open_line, raw_hashes, multiline, quote_hashes)
    stack: list[tuple] = []

    i = 0
    n = len(text)
    line = 1
    block_comment_depth = 0
    in_line_comment = False
    # Current string mode: None or (raw_hashes, is_multiline)
    string_mode: tuple[int, bool] | None = None

    def count_hashes(pos: int) -> int:
        k = pos
        while k < n and text[k] == "#":
            k += 1
        return k - pos

    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if ch == "\n":
            line += 1
            in_line_comment = False
            i += 1
            continue

        if in_line_comment:
            i += 1
            continue

        if block_comment_depth > 0:
            if ch == "/" and nxt == "*":
                block_comment_depth += 1
                i += 2
                continue
            if ch == "*" and nxt == "/":
                block_comment_depth -= 1
                i += 2
                continue
            i += 1
            continue

        if string_mode is not None:
            raw_hashes, is_multiline = string_mode
            if ch == "\\":
                if text[i + 1 : i + 1 + raw_hashes] == "#" * raw_hashes and (
                    i + 1 + raw_hashes < n and text[i + 1 + raw_hashes] == "("
                ):
                    stack.append(("interp", line, string_mode))
                    string_mode = None
                    i += 2 + raw_hashes
                    continue
                # In single-line/multiline non-raw or raw string, skip escaped char on same line
                if raw_hashes == 0:
                    if i + 1 < n and text[i + 1] == "\n":
                        line += 1
                    i += 2
                    continue
            if is_multiline:
                if text[i : i + 3] == '"""' and text[i + 3 : i + 3 + raw_hashes] == "#" * raw_hashes:
                    string_mode = None
                    i += 3 + raw_hashes
                    continue
            else:
                if ch == '"' and text[i + 1 : i + 1 + raw_hashes] == "#" * raw_hashes:
                    string_mode = None
                    i += 1 + raw_hashes
                    continue
            i += 1
            continue

        # Code context
        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            block_comment_depth = 1
            i += 2
            continue

        if ch == "#":
            h = count_hashes(i)
            if text[i + h : i + h + 3] == '"""':
                string_mode = (h, True)
                i += h + 3
                continue
            if i + h < n and text[i + h] == '"':
                string_mode = (h, False)
                i += h + 1
                continue

        if text[i : i + 3] == '"""':
            string_mode = (0, True)
            i += 3
            continue
        if ch == '"':
            string_mode = (0, False)
            i += 1
            continue

        if ch in pairs:
            stack.append(("delim", ch, line))
        elif ch in closing:
            if ch == ")" and stack and stack[-1][0] == "interp":
                _, _, saved_mode = stack.pop()
                string_mode = saved_mode
                i += 1
                continue
            if not stack or stack[-1][0] != "delim" or stack[-1][1] != closing[ch]:
                raise AssertionError(
                    f"Unmatched '{ch}' in {path.relative_to(ROOT)}:{line}"
                )
            stack.pop()

        i += 1

    if block_comment_depth != 0:
        raise AssertionError(f"Unclosed block comment in {path.relative_to(ROOT)}")
    if string_mode is not None:
        raise AssertionError(f"Unclosed string literal in {path.relative_to(ROOT)}")
    if stack:
        top = stack[-1]
        if top[0] == "interp":
            raise AssertionError(
                f"Unclosed string interpolation in {path.relative_to(ROOT)}:{top[1]}"
            )
        raise AssertionError(
            f"Unclosed '{top[1]}' opened at {path.relative_to(ROOT)}:{top[2]}"
        )


def check_swift_sources() -> int:
    swift_files = list(iter_fullgram_swift_files())
    if not swift_files:
        raise AssertionError("No FullGram*.swift files found")

    for path in swift_files:
        check_swift_delimiters(path)
    return len(swift_files)


def check_conflict_markers_in_core_files() -> None:
    targets = [
        ROOT / "versions.json",
        ROOT / ".gitmodules",
        ROOT / ".github/workflows/build.yml",
        ROOT / "build-system/appstore-configuration.json",
    ]
    for path in targets:
        if not path.is_file():
            continue
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if CONFLICT_LINE_RE.match(line):
                raise AssertionError(
                    f"Git merge conflict marker found in {path.relative_to(ROOT)}:{line_no}"
                )


def check_python_scripts() -> int:
    py_files = [ROOT / "tools/ci_checks.py"] + sorted((ROOT / "build-system/Make").glob("*.py"))
    for path in py_files:
        compile(path.read_text(encoding="utf-8"), str(path), "exec")
    return len(py_files)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run FullGram pre-build CI checks.")
    parser.add_argument(
        "--require-submodules",
        action="store_true",
        help="Fail if any submodule directory listed in .gitmodules is empty.",
    )
    args = parser.parse_args()

    check_required_files()
    print(f"[OK] Required FullGram files and PNG assets ({len(REQUIRED_FILES)} files)")

    check_configs()
    print("[OK] versions.json, build_number_offset, appstore-configuration.json, badges.example.json")

    check_submodules(require_populated=args.require_submodules)
    mode = "populated + valid URLs" if args.require_submodules else "valid URLs"
    print(f"[OK] .gitmodules ({mode})")

    check_conflict_markers_in_core_files()
    swift_count = check_swift_sources()
    print(f"[OK] FullGram Swift source sanity checks ({swift_count} files)")

    py_count = check_python_scripts()
    print(f"[OK] Python build scripts syntax check ({py_count} files)")

    sys.path.insert(0, str(ROOT / "build-system" / "Make"))
    import PostboxImportCheck

    if PostboxImportCheck.run(str(ROOT)) != 0:
        raise AssertionError("PostboxImportCheck failed")
    print("[OK] PostboxImportCheck")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        raise SystemExit(1)
