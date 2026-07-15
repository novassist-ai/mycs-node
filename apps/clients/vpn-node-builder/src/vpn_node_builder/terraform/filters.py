"""Composable console filters for streamed Terraform (and other) command output."""

from __future__ import annotations

from collections.abc import Callable, Sequence
from typing import Protocol


class ConsoleFilter(Protocol):
    """Filter console lines while a full copy is still teed to a log file."""

    def feed(self, line: str) -> Sequence[str]:
        """Consume one input line; return zero or more lines to print."""

    def flush(self) -> Sequence[str]:
        """Emit any buffered lines at end of stream."""


class PredicateFilter:
    """Adapt ``line -> str | None`` predicates (``None`` means drop)."""

    def __init__(self, predicate: Callable[[str], str | None]) -> None:
        self._predicate = predicate

    def feed(self, line: str) -> Sequence[str]:
        kept = self._predicate(line)
        return () if kept is None else (kept,)

    def flush(self) -> Sequence[str]:
        return ()


class ComposeFilter:
    """Pipe lines through multiple :class:`ConsoleFilter` instances in order."""

    def __init__(self, *filters: ConsoleFilter) -> None:
        self._filters = filters

    def feed(self, line: str) -> Sequence[str]:
        current: Sequence[str] = (line,)
        for filt in self._filters:
            nxt: list[str] = []
            for item in current:
                nxt.extend(filt.feed(item))
            current = nxt
        return current

    def flush(self) -> Sequence[str]:
        out: list[str] = []
        for index, filt in enumerate(self._filters):
            for item in filt.flush():
                current: Sequence[str] = (item,)
                for later in self._filters[index + 1 :]:
                    nxt: list[str] = []
                    for value in current:
                        nxt.extend(later.feed(value))
                    current = nxt
                out.extend(current)
        return out


def compose_filters(*filters: ConsoleFilter) -> ConsoleFilter | None:
    """Return a composed filter, or ``None`` when no filters are given."""
    if not filters:
        return None
    if len(filters) == 1:
        return filters[0]
    return ComposeFilter(*filters)


def drop_prefix(*prefixes: str) -> ConsoleFilter:
    """Drop lines that start with any of the given prefixes."""

    def _pred(line: str) -> str | None:
        for prefix in prefixes:
            if line.startswith(prefix):
                return None
        return line

    return PredicateFilter(_pred)


class DropPlanOutNoteFilter:
    """Drop Terraform's speculative-plan reminder and its preceding rule/blank.

    Suppresses the trailing::

        ──────────────── ...
        <blank>
        Note: You didn't use the -out option to save this plan...
    """

    _NOTE_PREFIX = "Note: You didn't use the -out option"

    def __init__(self) -> None:
        self._pending: list[str] = []

    def feed(self, line: str) -> Sequence[str]:
        if line.startswith(self._NOTE_PREFIX):
            self._pending.clear()
            return ()

        if self._is_horizontal_rule(line):
            emitted = tuple(self._pending)
            self._pending = [line]
            return emitted

        if self._pending and self._is_horizontal_rule(self._pending[0]):
            # After a held rule: blank likely belongs to the note prelude.
            if line == "":
                self._pending.append(line)
                return ()
            emitted = tuple(self._pending)
            self._pending.clear()
            return (*emitted, line)

        return (line,)

    def flush(self) -> Sequence[str]:
        emitted = tuple(self._pending)
        self._pending.clear()
        return emitted

    @staticmethod
    def _is_horizontal_rule(line: str) -> bool:
        stripped = line.strip()
        if len(stripped) < 20:
            return False
        return all(ch in {"─", "-", "━", "═"} for ch in stripped)
