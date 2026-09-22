#!/usr/bin/env python3
"""Validate, build, install and restore Corsairs Gold mission MSG resources."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


TOOLS_ROOT = Path(__file__).resolve().parent
PATCH_ROOT = TOOLS_ROOT.parent
GAME_ROOT = PATCH_ROOT.parent
DEFAULT_ORIGINAL = (
    PATCH_ROOT / "backup/missions/MIS01/BLU/MSG/MIS01BLU.ENG"
)
DEFAULT_TRANSLATION = (
    PATCH_ROOT / "translations/MIS01_BLU_MSG_MIS01BLU.utf8.txt"
)
DEFAULT_TARGET = GAME_ROOT / "data/missions/MIS01/BLU/MSG/MIS01BLU.ENG"
DEFAULT_SELECTED_LINES = [
    4, 5, 6, 8, 9, 13, 14, 15, 18, 19, 23, 24, 25, 29, 33, 34, 35, 36,
    39, 40, 41, 44, 48, 49, 50, 55, 56, 60, 61, 62, 66, 67, 68, 69, 73, 74,
    76, 77, 78, 80, 85, 86, 87, 89, 94, 95, 96, 100, 101, 104,
]

SECTION_RE = re.compile(r"^\[[^\]]+\]$")
EVENT_RE = re.compile(r"^(ACTIVATION|REALIZATION|FAILURE)\s*=$")


class MsgToolError(RuntimeError):
    """An expected validation or usage failure."""


@dataclass(frozen=True)
class Document:
    path: Path
    lines: tuple[str, ...]
    encoding: str
    raw: bytes

    @property
    def sha256(self) -> str:
        return hashlib.sha256(self.raw).hexdigest()


def _check_crlf(data: bytes, path: Path) -> None:
    without_crlf = data.replace(b"\r\n", b"")
    if b"\r" in without_crlf or b"\n" in without_crlf:
        raise MsgToolError(f"{path}: file contains a non-CRLF line ending")
    if not data.endswith(b"\r\n"):
        raise MsgToolError(f"{path}: file must end with CRLF")


def read_original(path: Path) -> Document:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise MsgToolError(f"Cannot read {path}: {exc}") from exc
    _check_crlf(data, path)
    try:
        text = data.decode("cp1251")
    except UnicodeDecodeError as exc:
        raise MsgToolError(f"{path}: invalid Windows-1251 data: {exc}") from exc
    return Document(path, tuple(text[:-2].split("\r\n")), "cp1251", data)


def read_translation(path: Path) -> Document:
    try:
        data = path.read_bytes()
        text = data.decode("utf-8-sig")
    except (OSError, UnicodeDecodeError) as exc:
        raise MsgToolError(f"Cannot read UTF-8 translation {path}: {exc}") from exc

    normalized = text.replace("\r\n", "\n")
    if "\r" in normalized:
        raise MsgToolError(f"{path}: unsupported standalone CR line ending")
    if not normalized.endswith("\n"):
        raise MsgToolError(f"{path}: translation must end with a newline")
    lines = tuple(normalized[:-1].split("\n"))
    return Document(path, lines, "utf-8", data)


def is_structure_line(line: str) -> bool:
    return bool(SECTION_RE.fullmatch(line) or EVENT_RE.fullmatch(line))


def validate_pair(original: Document, translation: Document) -> None:
    if len(original.lines) != len(translation.lines):
        raise MsgToolError(
            "Line count differs: "
            f"{len(translation.lines)} translated != {len(original.lines)} original"
        )

    for number, (old, new) in enumerate(
        zip(original.lines, translation.lines), start=1
    ):
        if (is_structure_line(old) or is_structure_line(new)) and old != new:
            raise MsgToolError(
                f"Structural line {number} was changed: {old!r} -> {new!r}"
            )
        try:
            new.encode("cp1251")
        except UnicodeEncodeError as exc:
            raise MsgToolError(
                f"Translated line {number} cannot be encoded as Windows-1251: {exc}"
            ) from exc


def context_by_line(lines: Iterable[str]) -> list[tuple[str, str]]:
    section = "-"
    event = "-"
    result: list[tuple[str, str]] = []
    for line in lines:
        if SECTION_RE.fullmatch(line):
            section = line[1:-1]
            event = "-"
        else:
            match = EVENT_RE.fullmatch(line)
            if match:
                event = match.group(1)
        result.append((section, event))
    return result


def changed_line_numbers(original: Document, translation: Document) -> list[int]:
    return [
        number
        for number, (old, new) in enumerate(
            zip(original.lines, translation.lines), start=1
        )
        if old != new
    ]


def validate_selected_lines(
    original: Document,
    translation: Document,
    selected_lines: Iterable[int],
) -> list[int]:
    validate_pair(original, translation)
    selected = sorted(set(selected_lines))
    if not selected:
        raise MsgToolError("No translated lines were selected")

    last_line = len(original.lines)
    invalid = [number for number in selected if number < 1 or number > last_line]
    if invalid:
        raise MsgToolError(f"Line numbers outside 1..{last_line}: {invalid}")

    for number in selected:
        index = number - 1
        old = original.lines[index]
        new = translation.lines[index]
        if is_structure_line(old):
            raise MsgToolError(f"Refusing to replace structural line {number}: {old}")
        if old == new:
            raise MsgToolError(f"Line {number} has no translation change")
    return selected


def build_selected_lines(
    original: Document,
    translation: Document,
    selected_lines: Iterable[int],
) -> bytes:
    """Replace complete text lines without layout-visible padding."""
    selected = validate_selected_lines(original, translation, selected_lines)
    output: list[str] = list(original.lines)
    for number in selected:
        output[number - 1] = translation.lines[number - 1]
    return ("\r\n".join(output) + "\r\n").encode("cp1251")


def write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            prefix=path.name + ".",
            suffix=".tmp",
            dir=path.parent,
            delete=False,
        ) as temporary:
            temporary.write(data)
            temporary.flush()
            os.fsync(temporary.fileno())
            temporary_name = temporary.name
        os.replace(temporary_name, path)
    except OSError as exc:
        if temporary_name:
            try:
                Path(temporary_name).unlink(missing_ok=True)
            except OSError:
                pass
        raise MsgToolError(f"Cannot atomically write {path}: {exc}") from exc


def load_pair(args: argparse.Namespace) -> tuple[Document, Document]:
    original = read_original(args.original)
    translation = read_translation(args.translation)
    validate_pair(original, translation)
    return original, translation


def print_build_report(
    original: Document,
    translation: Document,
    selected: list[int],
    result: bytes,
) -> None:
    contexts = context_by_line(original.lines)
    print(f"Original:    {original.path}")
    print(f"Translation: {translation.path}")
    print(f"Bytes:       {len(result)} (original {len(original.raw)})")
    print("Selected translated lines:")
    for number in selected:
        section, event = contexts[number - 1]
        old_size = len(original.lines[number - 1].encode("cp1251"))
        new_size = len(translation.lines[number - 1].encode("cp1251"))
        print(f"  {number:3}  {section:7} {event:11} {new_size:3}/{old_size:3} bytes")


def command_inspect(args: argparse.Namespace) -> int:
    original, translation = load_pair(args)
    changed = changed_line_numbers(original, translation)
    longer = [
        number
        for number in changed
        if len(translation.lines[number - 1].encode("cp1251"))
        > len(original.lines[number - 1].encode("cp1251"))
    ]
    sections = sum(1 for line in original.lines if SECTION_RE.fullmatch(line))
    events = sum(1 for line in original.lines if EVENT_RE.fullmatch(line))

    print(f"Original:    {original.path}")
    print(f"SHA-256:     {original.sha256}")
    print(f"Translation: {translation.path}")
    print(f"Layout:      {len(original.lines)} lines, {sections} sections, {events} events")
    print(f"Changed:     {len(changed)} lines")
    print(f"Longer:      {len(longer)} lines")
    print("Validation:  OK")

    if args.verbose:
        contexts = context_by_line(original.lines)
        for number in changed:
            section, event = contexts[number - 1]
            old_size = len(original.lines[number - 1].encode("cp1251"))
            new_size = len(translation.lines[number - 1].encode("cp1251"))
            marker = "longer" if new_size > old_size else "ok"
            print(
                f"{number:3}  {section:7} {event:11} "
                f"{new_size:3}/{old_size:3} bytes  {marker}"
            )
    return 0


def command_install(args: argparse.Namespace) -> int:
    original, translation = load_pair(args)
    selected = validate_selected_lines(
        original, translation, args.line or DEFAULT_SELECTED_LINES
    )
    result = build_selected_lines(original, translation, selected)
    print_build_report(original, translation, selected, result)
    if args.apply:
        write_atomic(args.target, result)
        print(f"Installed atomically: {args.target}")
    else:
        print("Dry run only; use --apply to install it.")
    return 0


def command_full(args: argparse.Namespace) -> int:
    original, translation = load_pair(args)
    selected = changed_line_numbers(original, translation)
    result = build_selected_lines(original, translation, selected)
    print_build_report(original, translation, selected, result)
    if args.apply:
        if not args.acknowledge_experimental:
            raise MsgToolError(
                "Full MSG installation is not fully tested in game; add "
                "--acknowledge-experimental for an intentional test"
            )
        write_atomic(args.target, result)
        print(f"Installed experimental full translation: {args.target}")
    else:
        print("Dry run only. Full MSG installation remains experimental.")
    return 0


def command_restore(args: argparse.Namespace) -> int:
    original = read_original(args.original)
    if args.apply:
        write_atomic(args.target, original.raw)
        print(f"Restored atomically: {args.target}")
    else:
        print(f"Restore dry run: {args.original} -> {args.target}")
    return 0


def command_self_test(args: argparse.Namespace) -> int:
    original, translation = load_pair(args)
    selected = build_selected_lines(original, translation, DEFAULT_SELECTED_LINES)
    full = build_selected_lines(
        original, translation, changed_line_numbers(original, translation)
    )

    assert selected != original.raw
    assert full != original.raw
    assert selected.count(b"\r\n") == original.raw.count(b"\r\n")
    assert full.count(b"\r\n") == original.raw.count(b"\r\n")

    selected_lines = selected.decode("cp1251")[:-2].split("\r\n")
    full_lines = full.decode("cp1251")[:-2].split("\r\n")
    for number in DEFAULT_SELECTED_LINES:
        assert selected_lines[number - 1] == translation.lines[number - 1]
    for number in changed_line_numbers(original, translation):
        assert full_lines[number - 1] == translation.lines[number - 1]

    print("Self-test: OK")
    print(f"Original bytes: {len(original.raw)}")
    print(f"Selected bytes: {len(selected)}")
    print(f"Full bytes:     {len(full)}")
    print(f"CRLF records:   {original.raw.count(b'\r\n')}")
    return 0


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", type=Path, default=DEFAULT_ORIGINAL)
    parser.add_argument("--translation", type=Path, default=DEFAULT_TRANSLATION)
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    commands = parser.add_subparsers(dest="command", required=True)

    inspect_parser = commands.add_parser("inspect", help="validate and report layout")
    inspect_parser.add_argument("--verbose", action="store_true")
    inspect_parser.set_defaults(handler=command_inspect)

    install_parser = commands.add_parser(
        "install", help="build selected translated lines without padding"
    )
    install_parser.add_argument(
        "--line",
        type=int,
        action="append",
        help="1-based physical line to install; repeat as needed (default: 4, 5 and 6)",
    )
    install_parser.add_argument("--apply", action="store_true")
    install_parser.set_defaults(handler=command_install)

    full_parser = commands.add_parser(
        "full", help="build the complete, currently experimental translation"
    )
    full_parser.add_argument("--apply", action="store_true")
    full_parser.add_argument("--acknowledge-experimental", action="store_true")
    full_parser.set_defaults(handler=command_full)

    restore_parser = commands.add_parser("restore", help="restore the pristine MSG")
    restore_parser.add_argument("--apply", action="store_true")
    restore_parser.set_defaults(handler=command_restore)

    test_parser = commands.add_parser("self-test", help="run non-writing checks")
    test_parser.set_defaults(handler=command_self_test)
    return parser


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()
    try:
        return args.handler(args)
    except MsgToolError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
