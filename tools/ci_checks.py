#!/usr/bin/env python3
"""Pre-build verification checks for FullGram CI and local validation."""

from __future__ import annotations

import argparse
import configparser
import json
import plistlib
import re
import struct
import subprocess
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
    "submodules/Display/Source/FullGramAdmin.swift",
    "submodules/Display/Source/FullGramAIAssistant.swift",
    "submodules/Display/Source/FullGramAntiScam.swift",
    "submodules/Display/Source/FullGramAppearance.swift",
    "submodules/Display/Source/FullGramAvatarFrames.swift",
    "submodules/Display/Source/FullGramBackup.swift",
    "submodules/Display/Source/FullGramBadges.swift",
    "submodules/Display/Source/FullGramCosmetics.swift",
    "submodules/Display/Source/FullGramLuaEngine.swift",
    "submodules/Display/Source/FullGramMediaAudio.swift",
    "submodules/Display/Source/FullGramPluginManager.swift",
    "submodules/Display/Source/FullGramPluginValue.swift",
    "submodules/Display/Source/FullGramPythonEngine.swift",
    "submodules/Display/Source/FullGramRustEngine.swift",
    "submodules/Display/Source/FullGramSpeechBleep.swift",
    "submodules/Display/Source/FullGramStudioTools.swift",
    "submodules/Display/Source/FullGramVoiceDSP.swift",
    "submodules/TelegramCore/Sources/FullGram/FullGramEconomy.swift",
    "submodules/TelegramCore/Sources/FullGram/FullGramGhostMode.swift",
    "submodules/TelegramCore/Sources/FullGram/FullGramGrantedNFTs.swift",
    "submodules/TelegramCore/Sources/FullGram/FullGramMessageHistory.swift",
    "submodules/TelegramPresentationData/Sources/FullGramCustomizedTheme.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramAIAssistantScreen.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramAntiScamScreen.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramAppearanceScreens.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramBadgeDeskController.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramCosmeticScreens.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramEconomyScreens.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramMediaAudioScreens.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramNFTDeskController.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramPluginsScreen.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramSettingsController.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramSettingsSearchScreen.swift",
    "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramWorkScreen.swift",
    "tools/cloudflare-worker/src/index.js",
    "submodules/TelegramUI/Sources/FullGramAIOverlay.swift",
    "submodules/TelegramUI/Sources/FullGramChatLock.swift",
    "assets/discord_cosmetics.json",
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

    display_syms: set[str] = set()
    for p in (ROOT / "submodules" / "Display").rglob("*.swift"):
        for m in re.finditer(
            r"\bpublic\s+(?:final\s+)?(?:class|struct|enum|protocol|func|let|var|typealias)\s+(FullGram\w+)",
            p.read_text(encoding="utf-8", errors="replace"),
        ):
            display_syms.add(m.group(1))

    extra_paths = {
        ROOT / "submodules" / "AvatarNode" / "Sources" / "AvatarNode.swift",
        ROOT / "submodules" / "TelegramUI" / "Sources" / "AppDelegate.swift",
        ROOT / "submodules" / "TelegramUI" / "Sources" / "SharedAccountContext.swift",
        ROOT / "submodules" / "TelegramUI" / "Sources" / "TelegramRootController.swift",
        ROOT / "submodules" / "TelegramUI" / "Sources" / "ManagedAudioRecorder.swift",
        ROOT / "submodules" / "TelegramUI" / "Sources" / "OverlayAudioPlayerControllerNode.swift",
        ROOT / "submodules" / "TelegramUI" / "Sources" / "Chat" / "ChatControllerLoadDisplayNode.swift",
        ROOT / "submodules" / "TelegramUI" / "Sources" / "OpenChatMessage.swift",
        ROOT / "submodules" / "TelegramUI" / "Sources" / "ChatController.swift",
        ROOT / "submodules" / "TelegramUI" / "Sources" / "ChatControllerNode.swift",
        ROOT / "submodules" / "TelegramUI" / "Sources" / "Chat" / "ChatMessageActionOptions.swift",
        ROOT / "submodules" / "TelegramUI" / "Components" / "Chat" / "ChatMessageInteractiveInstantVideoNode" / "Sources" / "ChatMessageInteractiveInstantVideoNode.swift",
        ROOT / "submodules" / "TelegramUI" / "Components" / "PeerInfo" / "PeerInfoScreen" / "Sources" / "PeerInfoProfileItems.swift",
        ROOT / "submodules" / "TelegramUI" / "Components" / "PeerInfo" / "PeerInfoScreen" / "Sources" / "PeerInfoScreenPerformButtonAction.swift",
        ROOT / "submodules" / "TelegramUI" / "Components" / "VideoMessageCameraScreen" / "Sources" / "VideoMessageCameraScreen.swift",
    }
    audit_files = list(dict.fromkeys([*swift_files, *(p for p in extra_paths if p.exists())]))

    for path in audit_files:
        check_swift_delimiters(path)
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        imports = set(re.findall(r"^import\s+(\S+)", text, re.M))

        if not rel.as_posix().startswith("submodules/Display/") and "Display" not in imports:
            used_display = [s for s in sorted(display_syms) if re.search(rf"\b{s}\b", text)]
            if used_display:
                raise AssertionError(f"{rel} uses {used_display[0]} without 'import Display'")
        if re.search(r"\bASDisplayNode\b", text) and "AsyncDisplayKit" not in imports:
            raise AssertionError(f"{rel} uses ASDisplayNode without 'import AsyncDisplayKit'")
        if "UndoOverlayController" in text and "UndoUI" not in imports:
            raise AssertionError(f"{rel} uses UndoOverlayController without 'import UndoUI'")
        if re.search(r"UIBarButtonItem\([^)]*style:\s*\.done\b", text):
            raise AssertionError(f"{rel} uses deprecated UIBarButtonItem.Style.done (use .plain)")
        if re.search(r"cell\.(?:textLabel|detailTextLabel)\b", text):
            raise AssertionError(f"{rel} uses deprecated UITableViewCell.textLabel/detailTextLabel (use UIListContentConfiguration)")
        if re.search(r"^\s*_\s*=\s*\w*[Oo]bserver\b", text, re.M):
            raise AssertionError(f"{rel} discards NotificationCenter observer without removing it in afterDisposed")
        if re.search(r"(?:\?\?\s*self\.rootController\b|rootController\s+as\??\s*ViewController\b)", text):
            raise AssertionError(f"{rel} treats TelegramRootController (NavigationController) as ViewController")
        if "Postbox" not in imports and re.search(r"(?<![.\w])(?:MessageId|PeerId|MediaId)\b", text):
            raise AssertionError(f"{rel} uses raw Postbox ID type (MessageId/PeerId/MediaId) without 'import Postbox' (use EngineMessage.Id / EnginePeer.Id / EngineMedia.Id)")
        if re.search(
            r"\blet\s+(\w+)\s*:\s*\[ViewController\][^\n]*(?:\n[^\n]*){0,4}?\bnavigationController\.viewControllers\b[^\n]*(?:\n[^\n]*){0,4}?\b\1\s*=",
            text,
        ):
            raise AssertionError(f"{rel} assigns navigationController.viewControllers ([UIViewController]) to [ViewController]")
        for disc_match in re.finditer(r"\bItemListDisclosureItem\s*\(", text):
            depth = 1
            pos = disc_match.end()
            in_str = False
            escaped = False
            while pos < len(text) and depth > 0:
                ch = text[pos]
                if in_str:
                    if escaped:
                        escaped = False
                    elif ch == "\\":
                        escaped = True
                    elif ch == '"':
                        in_str = False
                else:
                    if ch == '"':
                        in_str = True
                    elif ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                pos += 1
            call_text = text[disc_match.start() : pos]
            enabled_pos = call_text.find("enabled:")
            label_pos = call_text.find("label:")
            if enabled_pos != -1 and label_pos != -1 and enabled_pos > label_pos:
                line_no = text[: disc_match.start()].count("\n") + 1
                raise AssertionError(f"{rel}:{line_no} passes 'enabled:' after 'label:' in ItemListDisclosureItem(...)")
        if path.name == "AppDelegate.swift":
            obs_match = re.search(
                r"addObserver\(forName:\s*FullGramFonts\.didRequestAppRestartNotification.*?\n        \}",
                text,
                re.S,
            )
            if not obs_match or "MainActor.assumeIsolated" not in obs_match.group(0):
                raise AssertionError(f"{rel} FullGramFonts restart observer must wrap UIKit work in MainActor.assumeIsolated")

    frames_path = ROOT / "submodules" / "Display" / "Source" / "FullGramAvatarFrames.swift"
    frames_text = frames_path.read_text(encoding="utf-8")
    if frames_text.count("public func stop()") < 2:
        raise AssertionError("FullGramAvatarFrames.swift must define public func stop() on FullGramAvatarFrameView and FullGramProfileEffectOverlayView")

    # Guard against Swift 6 strict-concurrency pitfalls in FullGram*.swift files:
    # 1) Mutable `var x = 0` captured & mutated (`+=`) inside NotificationCenter.default.addObserver
    # 2) Non-isolated NSObjectProtocol observer properties inside UIKit classes that clean up in deinit
    mut_cap_re = re.compile(r"\bvar\s+(\w+)\s*=\s*0\b([\s\S]{0,1600}?)NotificationCenter\.default\.addObserver[\s\S]{0,400}?\{[\s\S]{0,300}?\b\1\s*\+=")
    uikit_class_re = re.compile(r"\bclass\s+\w+\s*:\s*(?:UIViewController|ViewController|UIView)\b")
    plain_obs_prop_re = re.compile(r"^\s*(?:private|fileprivate|internal|public)?\s*var\s+\w+\s*:\s*(?:\[NSObjectProtocol\]|NSObjectProtocol\?)", re.MULTILINE)
    for path in audit_files:
        if not path.name.startswith("FullGram"):
            continue
        rel = path.relative_to(ROOT)
        text = path.read_text(encoding="utf-8")
        m_cap = mut_cap_re.search(text)
        if m_cap:
            line_no = text[: m_cap.start()].count("\n") + 1
            raise AssertionError(
                f"{rel}:{line_no} captures mutable `var {m_cap.group(1)} = 0` across NotificationCenter.default.addObserver (use Atomic<Int> for Swift 6)"
            )
        if uikit_class_re.search(text) and "deinit {" in text:
            for obs_m in plain_obs_prop_re.finditer(text):
                line_text = text[obs_m.start() : obs_m.end()]
                if "nonisolated(unsafe)" not in line_text:
                    line_no = text[: obs_m.start()].count("\n") + 1
                    raise AssertionError(
                        f"{rel}:{line_no} observer property inside UIKit class with deinit should be marked `nonisolated(unsafe)` for Swift 6"
                    )

    return len(audit_files)


def check_fullgram_frames() -> int:
    """Validate generated FullGram avatar frames exist, are valid PNGs, and stay compact."""
    frames_dir = ROOT / "assets" / "frames"
    fg_frames = sorted(frames_dir.glob("fg_*.png"))
    if len(fg_frames) < 50:
        raise AssertionError(f"Expected at least 50 fg_*.png files in assets/frames, found {len(fg_frames)}")
    max_bytes = 250 * 1024
    for frame_path in fg_frames:
        w, h = read_png_dimensions(frame_path)
        if w <= 0 or h <= 0:
            raise AssertionError(f"Invalid dimensions {w}x{h} in {frame_path.relative_to(ROOT)}")
        size = frame_path.stat().st_size
        if size >= max_bytes:
            raise AssertionError(
                f"Frame {frame_path.relative_to(ROOT)} is too large ({size} bytes >= {max_bytes}); optimize APNG before release"
            )
    return len(fg_frames)


def read_png_dimensions(path: Path) -> tuple[int, int]:
    """Read and validate PNG header and return (width, height)."""
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != PNG_MAGIC or data[12:16] != b"IHDR":
        raise AssertionError(f"Invalid PNG header in {path.relative_to(ROOT)}")
    width, height = struct.unpack(">II", data[16:24])
    if width <= 0 or height <= 0:
        raise AssertionError(f"Invalid PNG dimensions {width}x{height} in {path.relative_to(ROOT)}")
    return width, height


def parse_minimum_os_version(build_text: str) -> tuple[int, ...]:
    match = re.search(r'minimum_os_version\s*=\s*"([0-9]+(?:\.[0-9]+)*)"', build_text)
    if not match:
        raise AssertionError("Telegram/BUILD missing minimum_os_version")
    return tuple(int(part) for part in match.group(1).split("."))


def check_xcassets_and_icons() -> tuple[int, int]:
    """Validate compiled xcassets, DefaultAppIcon appiconset rules, and alternate icons."""
    build_path = ROOT / "Telegram/BUILD"
    build_text = build_path.read_text(encoding="utf-8")
    min_os = parse_minimum_os_version(build_text)

    # 1. Validate all Contents.json files inside Telegram/ and submodules/ xcassets.
    xcasset_count = 0
    for base in (ROOT / "Telegram", ROOT / "submodules"):
        if not base.is_dir():
            continue
        for xcasset in sorted(base.rglob("*.xcassets")):
            xcasset_count += 1
            for contents_json in sorted(xcasset.rglob("Contents.json")):
                data = load_json(contents_json)
                if not isinstance(data, dict):
                    raise AssertionError(f"{contents_json.relative_to(ROOT)} must be a JSON object")
                for img in data.get("images", []):
                    filename = img.get("filename")
                    if filename and not (contents_json.parent / filename).is_file():
                        raise AssertionError(
                            f"Missing asset '{filename}' referenced by {contents_json.relative_to(ROOT)}"
                        )

    # 2. Strictly validate DefaultAppIcon.xcassets (compiled by //Telegram:Telegram actool).
    default_app_icon_dir = ROOT / "Telegram/Telegram-iOS/DefaultAppIcon.xcassets"
    appiconsets = sorted(default_app_icon_dir.glob("*.appiconset/Contents.json"))
    if not appiconsets:
        raise AssertionError("No .appiconset found under Telegram/Telegram-iOS/DefaultAppIcon.xcassets")

    for contents_json in appiconsets:
        data = load_json(contents_json)
        for idx, img in enumerate(data.get("images", [])):
            filename = img.get("filename")
            idiom = img.get("idiom", "")
            size_str = img.get("size", "")
            scale_str = img.get("scale", "1x")

            # actool rejects 76x76@1x iPad icons when minimum_os_version >= 10.0.
            if filename and min_os >= (10, 0) and idiom == "ipad" and size_str == "76x76" and scale_str == "1x":
                raise AssertionError(
                    f"{contents_json.relative_to(ROOT)} slot[{idx}] assigns '{filename}' to ipad 76x76@1x, "
                    f"which actool rejects for minimum_os_version >= 10.0"
                )
            if not filename:
                continue

            png_path = contents_json.parent / filename
            width, height = read_png_dimensions(png_path)
            if "x" in size_str and scale_str.endswith("x"):
                sw, sh = (float(part) for part in size_str.split("x"))
                scale = float(scale_str[:-1])
                expected = (int(round(sw * scale)), int(round(sh * scale)))
                if (width, height) != expected:
                    raise AssertionError(
                        f"{png_path.relative_to(ROOT)} is {width}x{height}, expected {expected[0]}x{expected[1]} "
                        f"for {size_str}@{scale_str}"
                    )

    # 3. Validate alternate_icon_folders, UTTypeIconFiles, and Swift icon registrations.
    alt_match = re.search(r"alternate_icon_folders\s*=\s*\[(.*?)\]", build_text, re.S)
    if not alt_match:
        raise AssertionError("Telegram/BUILD missing alternate_icon_folders")
    alt_folders = re.findall(r'"([^"]+)"', alt_match.group(1))
    if not alt_folders:
        raise AssertionError("Telegram/BUILD alternate_icon_folders is empty")

    for name in alt_folders:
        alt_dir = ROOT / "Telegram/Telegram-iOS" / f"{name}.alticon"
        if not alt_dir.is_dir():
            raise AssertionError(f"Missing alternate icon directory: {alt_dir.relative_to(ROOT)}")
        pngs = sorted(alt_dir.glob("*.png"))
        if not pngs:
            raise AssertionError(f"Alternate icon directory has no PNGs: {alt_dir.relative_to(ROOT)}")
        for png_path in pngs:
            read_png_dimensions(png_path)

    for icon_file in re.findall(r"<key>UTTypeIconFiles</key>\s*<array>\s*<string>([^<]+)</string>", build_text):
        matches = list((ROOT / "Telegram/Telegram-iOS").rglob(icon_file))
        if not matches:
            raise AssertionError(f"UTTypeIconFiles references missing icon '{icon_file}' in Telegram/BUILD")

    app_delegate_path = ROOT / "submodules/TelegramUI/Sources/AppDelegate.swift"
    if app_delegate_path.is_file():
        app_delegate_text = app_delegate_path.read_text(encoding="utf-8")
        for icon_name in re.findall(r'PresentationAppIcon\(name:\s*"([^"]+)"', app_delegate_text):
            if icon_name not in alt_folders:
                raise AssertionError(
                    f"AppDelegate.swift registers PresentationAppIcon '{icon_name}' missing from alternate_icon_folders"
                )

    appearance_path = ROOT / "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramAppearanceScreens.swift"
    if appearance_path.is_file():
        appearance_text = appearance_path.read_text(encoding="utf-8")
        for icon_expr, res_expr in re.findall(
            r"FullGramIconPreset\(iconName:\s*([^,]+),\s*title:[^,]+,\s*isMonochrome:[^,]+,\s*previewResource:\s*([^)]+)\)",
            appearance_text,
        ):
            icon_name = icon_expr.strip().strip('"')
            res_name = res_expr.strip().strip('"')
            if icon_name != "nil" and icon_name not in alt_folders:
                raise AssertionError(
                    f"FullGramAppearanceScreens.swift uses iconName '{icon_name}' missing from alternate_icon_folders"
                )
            if res_name != "nil":
                res_path = ROOT / "Telegram/Telegram-iOS/Resources" / f"{res_name}.png"
                if not res_path.is_file():
                    raise AssertionError(
                        f"FullGramAppearanceScreens.swift previewResource missing: {res_path.relative_to(ROOT)}"
                    )
                read_png_dimensions(res_path)

    return xcasset_count, len(alt_folders)


def check_plists_and_patches(require_submodules: bool) -> None:
    """Validate XML Info.plist files and unsigned CI patch readiness."""
    plist_targets = [
        ROOT / "Telegram/Telegram-iOS/Info.plist",
        ROOT / "Telegram/Telegram-iOS/InfoBazel.plist",
        ROOT / "Telegram/WatchApp/tgwatch Watch App/Info.plist",
    ]
    for path in plist_targets:
        if not path.is_file():
            raise AssertionError(f"Missing plist file: {path.relative_to(ROOT)}")
        try:
            plistlib.loads(path.read_bytes())
        except Exception as exc:
            raise AssertionError(f"Invalid plist XML in {path.relative_to(ROOT)}: {exc}") from exc

    for rel in ("Telegram/BUILD", "Telegram/Telegram-iOS/InfoBazel.plist", "Telegram/Telegram-iOS/Info.plist"):
        if "<string>fullgram</string>" not in (ROOT / rel).read_text(encoding="utf-8"):
            raise AssertionError(f"{rel} missing <string>fullgram</string> URL scheme")

    patch_path = ROOT / "tools/ci/unsigned-build-rules.patch"
    if not patch_path.is_file() or patch_path.stat().st_size == 0:
        raise AssertionError("Missing or empty tools/ci/unsigned-build-rules.patch")

    if require_submodules:
        rules_apple = ROOT / "build-system/bazel-rules/rules_apple"
        target_file = rules_apple / "apple/internal/ios_rules.bzl"
        if not target_file.is_file():
            raise AssertionError(
                f"Expected file missing in rules_apple submodule: {target_file.relative_to(ROOT)}"
            )
        rev = subprocess.run(
            ["git", "-C", str(rules_apple), "apply", "--reverse", "--check", str(patch_path)],
            capture_output=True,
            text=True,
        )
        if rev.returncode != 0:
            fwd = subprocess.run(
                ["git", "-C", str(rules_apple), "apply", "--check", str(patch_path)],
                capture_output=True,
                text=True,
            )
            if fwd.returncode != 0:
                raise AssertionError(
                    f"tools/ci/unsigned-build-rules.patch does not apply cleanly to rules_apple:\n{fwd.stderr.strip()}"
                )


def check_conflict_markers_in_core_files() -> None:
    targets = [
        ROOT / "versions.json",
        ROOT / ".gitmodules",
        ROOT / ".github/workflows/build.yml",
        ROOT / "build-system/appstore-configuration.json",
        ROOT / "Telegram/BUILD",
        ROOT / "Telegram/Telegram-iOS/Config-AppStoreLLC.xcconfig",
        ROOT / "Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/Contents.json",
        ROOT / "tools/ci/unsigned-build-rules.patch",
        ROOT / "tools/ci/prepare_macos.sh",
        ROOT / "submodules/TelegramUI/Sources/AppDelegate.swift",
        ROOT / "submodules/SettingsUI/Sources/Themes/ThemeSettingsAppIconItem.swift",
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


def check_no_hardcoded_secrets() -> None:
    patterns = [
        ("API key (sk-)", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b")),
        ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b")),
        ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
        ("Telegram Bot token", re.compile(r"\b\d{8,11}:[A-Za-z0-9_-]{30,}\b")),
        ("Hardcoded Bearer token", re.compile(r"Bearer\s+[A-Za-z0-9._-]{20,}")),
        ("Hardcoded admin secret", re.compile(r"(?:ADMIN_TOKEN|TG_BOT_TOKEN|SESSION_SECRET)\s*[:=]\s*[\"'][^\"']{8,}[\"']")),
    ]
    scan_paths = list(iter_fullgram_swift_files()) + [
        ROOT / "tools/cloudflare-worker/src/index.js",
        ROOT / "tools/cloudflare-worker/wrangler.jsonc",
    ]
    for path in scan_paths:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for label, rx in patterns:
            m = rx.search(text)
            if m:
                line_no = text[: m.start()].count("\n") + 1
                raise AssertionError(f"Potential hardcoded secret ({label}) in {path.relative_to(ROOT)}:{line_no}")


def check_fullgram_tabs_and_ui_safety() -> int:
    peer_info_dir = ROOT / "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources"
    checked_controllers = 0
    for path in sorted(peer_info_dir.glob("FullGram*.swift")):
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)

        # 1. Every ItemListController factory must deliver state on main queue.
        funcs = list(re.finditer(r"(?:public |private |internal )?func (fullGram\w+)\(", text))
        for i, match in enumerate(funcs):
            start = match.start()
            end = funcs[i + 1].start() if i + 1 < len(funcs) else len(text)
            body = text[start:end]
            if "ItemListController(" in body:
                checked_controllers += 1
                if "deliverOnMainQueue" not in body and "queue: .mainQueue()" not in body:
                    raise AssertionError(f"{rel} -> {match.group(1)}() creates ItemListController without main-queue delivery")

        # 2. Custom ListViewItemNode subclasses must not touch self.view inside init() (UIKit thread-safety / black screen).
        for node_match in re.finditer(r"class\s+(FullGram\w+Node)\s*:\s*ListViewItemNode\b", text):
            chunk = text[node_match.start() : node_match.start() + 3000]
            init_match = re.search(r"\binit\([^)]*\)\s*\{(.*?)\n    \}", chunk, re.S)
            if init_match and "self.view." in init_match.group(1):
                raise AssertionError(f"{rel} -> {node_match.group(1)}.init() touches self.view (move to didLoad())")

    # 3. Verify every FullGramCategory case is handled in fullGramSettingsController.
    settings_path = peer_info_dir / "FullGramSettingsController.swift"
    settings_text = settings_path.read_text(encoding="utf-8")
    cat_enum = re.search(r"public enum FullGramCategory:.*?\n\}", settings_text, re.S)
    if not cat_enum:
        raise AssertionError("FullGramCategory enum not found in FullGramSettingsController.swift")
    cases = re.findall(r"case\s+(\w+)\s*=", cat_enum.group(0))
    if not cases:
        raise AssertionError("No cases parsed from FullGramCategory")
    open_cat = re.search(r"openCategory:\s*\{(.*?)\n        \},", settings_text, re.S)
    if not open_cat:
        raise AssertionError("openCategory handler not found in FullGramSettingsController.swift")
    for case_name in cases:
        if f"case .{case_name}:" not in open_cat.group(1):
            raise AssertionError(f"FullGramCategory.{case_name} missing in openCategory router")

    return checked_controllers


def check_cloudflare_worker() -> None:
    worker = ROOT / "tools/cloudflare-worker/src/index.js"
    text = worker.read_text(encoding="utf-8")
    if "verifyTelegramInitData" not in text:
        raise AssertionError("Cloudflare worker missing Telegram initData cryptographic verification")
    cosmetics_post = re.search(r'path === "/cosmetics"\)\s*\{(.*?)\n    \}', text, re.S)
    if not cosmetics_post or "authenticateRequest" not in cosmetics_post.group(1):
        raise AssertionError("Cloudflare worker POST /cosmetics must enforce authenticateRequest()")
    admin_block = re.search(r'path\.startsWith\("/admin/"\)\)\s*\{(.*?)path === "/admin/badge"', text, re.S)
    if not admin_block or "authenticateRequest" not in admin_block.group(1) or "auth.isAdmin" not in admin_block.group(1):
        raise AssertionError("Cloudflare worker /admin/* must enforce authenticateRequest() and auth.isAdmin")

    import shutil
    if shutil.which("node"):
        res = subprocess.run(["node", "--check", str(worker)], capture_output=True, text=True)
        if res.returncode != 0:
            raise AssertionError(f"Cloudflare worker JS syntax error:\n{res.stderr.strip()}")


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

    xcasset_count, alt_count = check_xcassets_and_icons()
    print(f"[OK] Asset catalogs and app icons ({xcasset_count} xcassets, {alt_count} alternate icons)")

    frame_count = check_fullgram_frames()
    print(f"[OK] FullGram avatar frames ({frame_count} compact fg_*.png APNGs)")

    check_submodules(require_populated=args.require_submodules)
    mode = "populated + valid URLs" if args.require_submodules else "valid URLs"
    print(f"[OK] .gitmodules ({mode})")

    check_plists_and_patches(require_submodules=args.require_submodules)
    print("[OK] Info.plist XML and unsigned-build-rules.patch")

    check_conflict_markers_in_core_files()
    swift_count = check_swift_sources()
    print(f"[OK] FullGram Swift source sanity checks ({swift_count} files)")

    check_no_hardcoded_secrets()
    print("[OK] Hardcoded secrets scan (0 leaks)")

    tab_count = check_fullgram_tabs_and_ui_safety()
    print(f"[OK] FullGram tab & UI thread-safety checks ({tab_count} ItemListController routes)")

    check_cloudflare_worker()
    print("[OK] Cloudflare Worker security & JS syntax checks")

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
