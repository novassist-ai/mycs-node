from __future__ import annotations

from vpn_node_builder.terraform.filters import (
    DropPlanOutNoteFilter,
    compose_filters,
    drop_prefix,
)


def _drain(filt, lines: list[str]) -> list[str]:
    out: list[str] = []
    for line in lines:
        out.extend(filt.feed(line))
    out.extend(filt.flush())
    return out


def test_drop_plan_out_note_removes_rule_blank_and_note() -> None:
    filt = DropPlanOutNoteFilter()
    lines = [
        "Plan: 1 to add, 0 to change, 0 to destroy.",
        "",
        "─" * 80,
        "",
        "Note: You didn't use the -out option to save this plan, so Terraform "
        "can't guarantee to take exactly these actions if you run "
        '"terraform apply" now.',
    ]
    assert _drain(filt, lines) == [
        "Plan: 1 to add, 0 to change, 0 to destroy.",
        "",
    ]


def test_drop_plan_out_note_keeps_unrelated_rules() -> None:
    filt = DropPlanOutNoteFilter()
    lines = [
        "─" * 80,
        "Some other section",
    ]
    assert _drain(filt, lines) == lines


def test_compose_and_drop_prefix() -> None:
    filt = compose_filters(drop_prefix("SKIP:"), DropPlanOutNoteFilter())
    assert filt is not None
    lines = [
        "keep me",
        "SKIP: secret",
        "─" * 40,
        "",
        "Note: You didn't use the -out option to save this plan, so Terraform "
        "can't guarantee to take exactly these actions if you run "
        '"terraform apply" now.',
    ]
    assert _drain(filt, lines) == ["keep me"]


def test_compose_filters_empty_is_none() -> None:
    assert compose_filters() is None
