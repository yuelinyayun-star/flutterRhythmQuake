#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract Scratch/TurboWarp HYP source-estimation blocks into readable docs.

The reference project is not authored as plain JavaScript. The deploy bundle
contains a compiled TurboWarp app plus `docs/assets/project.json`, where the
source-estimation logic is represented as Scratch blocks. This tool isolates
the HYP-related procedures and renders a compact, reviewable pseudo-code view.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


PROJECT_JSON = Path(
    ".dart_tool/external_refs/"
    "scratch-realtime-earthquake-viewer-page/docs/assets/project.json"
)
OUTPUT_MD = Path("docs/reference/scratch_hyp_algorithm_extracted.md")
OUTPUT_JSON = Path("docs/reference/scratch_hyp_algorithm_blocks.json")

TARGET_NAME = "受信と検出"
INCLUDED_PROCEDURE_NAMES = [
    "HYP:震源検出 %s %s",
    "HYP:誤差レベル計算 %s %s %s %s %s %s",
    "HYP:誤差レベル比較 %s %s %s %b %b %s",
    "HYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s",
    "JMA2001距離近似: %s %s %b %b",
    "epi最大距離(多目的1)or仮震央(カウント3id) %b %s",
    "検出id1_全点へ適用",
    "検出id2_各点の許可idと推定用をセット %s %s %s %s",
    "検出id3_点にIDを登録 %s %b",
    "検出id4_点に適用するべきIDを検索 %s %b",
    "検出id4-1_適用id最短7から候補選択 %s %s %s",
    "検出id4-2_適用id震源から候補選択 %s %s %s %s %s %s",
    "検出id適用数カウント追加 %s %b %s",
    "推定用tenPS時間計算(多目的0,2使用) %s %s",
    "検出id_推定PS時間id別再計算 %s",
    "検出id_グリッド別idと存在idをセット %s %s %s",
    "検出id_周囲gridの最新ID検索 %s %s %s %s",
    "検出id_消えたidに対応する検出無効化",
    "検出id_点の推定用をリセット %s",
    "検出id_同一震源統合 %s %s %b",
    "検出id_新規id追加 %s %b",
    "検出id距離計算 %s %s",
    "点-震源 距離計算 %s %s %s",
    "緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s",
    "距離の震度 %s %s %s %s",
]


Block = dict[str, Any]


def main() -> None:
    data = json.loads(PROJECT_JSON.read_text(encoding="utf-8"))
    target = next(t for t in data["targets"] if t.get("name") == TARGET_NAME)
    blocks: dict[str, Block] = {
        block_id: block
        for block_id, block in target.get("blocks", {}).items()
        if isinstance(block, dict)
    }

    procedures = find_procedures(blocks)
    selected = [
        procedures[name]
        for name in INCLUDED_PROCEDURE_NAMES
        if name in procedures
    ]
    selected_codes = {procedure["proccode"] for procedure in selected}

    for procedure in selected:
        procedure["calledProcedures"] = sorted(
            call
            for call in collect_called_procedures(
                blocks,
                procedure["definitionId"],
            )
            if call in selected_codes
        )
        reachable = collect_reachable_blocks(blocks, procedure["definitionId"])
        procedure["reachableBlockIds"] = sorted(reachable)

    extracted_blocks = {
        block_id: blocks[block_id]
        for procedure in selected
        for block_id in procedure["reachableBlockIds"]
        if block_id in blocks
    }
    payload = {
        "schemaVersion": "scratch_hyp_algorithm_blocks_v1",
        "sourceProject": PROJECT_JSON.as_posix(),
        "sourceTarget": TARGET_NAME,
        "procedures": selected,
        "blocks": extracted_blocks,
    }

    OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_JSON.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    OUTPUT_MD.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_MD.write_text(render_markdown(blocks, selected), encoding="utf-8")
    print(f"wrote {OUTPUT_MD}")
    print(f"wrote {OUTPUT_JSON}")


def find_procedures(blocks: dict[str, Block]) -> dict[str, dict[str, Any]]:
    prototypes: dict[str, tuple[str, Block]] = {}
    for block_id, block in blocks.items():
        if block.get("opcode") != "procedures_prototype":
            continue
        proccode = block.get("mutation", {}).get("proccode", "")
        prototypes[block_id] = (proccode, block)

    procedures: dict[str, dict[str, Any]] = {}
    for block_id, block in blocks.items():
        if block.get("opcode") != "procedures_definition":
            continue
        prototype_id = input_block_id(block.get("inputs", {}).get("custom_block"))
        if prototype_id not in prototypes:
            continue
        proccode, prototype = prototypes[prototype_id]
        mutation = prototype.get("mutation", {})
        procedures[proccode] = {
            "proccode": proccode,
            "definitionId": block_id,
            "prototypeId": prototype_id,
            "argumentNames": parse_json_list(mutation.get("argumentnames")),
            "argumentIds": parse_json_list(mutation.get("argumentids")),
            "warp": mutation.get("warp") == "true",
        }
    return procedures


def collect_called_procedures(
    blocks: dict[str, Block],
    root_id: str,
) -> set[str]:
    calls: set[str] = set()
    for block_id in collect_reachable_blocks(blocks, root_id):
        block = blocks.get(block_id)
        if not block:
            continue
        if block.get("opcode") == "procedures_call":
            proccode = block.get("mutation", {}).get("proccode")
            if proccode:
                calls.add(proccode)
    return calls


def collect_reachable_blocks(blocks: dict[str, Block], root_id: str) -> set[str]:
    seen: set[str] = set()

    def visit(block_id: str | None) -> None:
        if not block_id or block_id in seen or block_id not in blocks:
            return
        seen.add(block_id)
        block = blocks[block_id]
        visit(block.get("next"))
        for value in block.get("inputs", {}).values():
            for nested in input_block_ids(value):
                visit(nested)

    visit(root_id)
    return seen


def render_markdown(
    blocks: dict[str, Block],
    procedures: list[dict[str, Any]],
) -> str:
    out: list[str] = []
    out.append("# Scratch/TurboWarp HYP algorithm extraction")
    out.append("")
    out.append(
        "This is a generated, review-oriented extraction of the reference "
        "Scratch/TurboWarp source-estimation blocks. It is not production code."
    )
    out.append("")
    out.append(f"- Source project: `{PROJECT_JSON.as_posix()}`")
    out.append(f"- Source target/sprite: `{TARGET_NAME}`")
    out.append("- Encoding: UTF-8")
    out.append("")
    out.append("## Procedure map")
    out.append("")
    out.append("| Procedure | Arguments | Calls |")
    out.append("|---|---|---|")
    for procedure in procedures:
        args = ", ".join(procedure["argumentNames"])
        calls = "<br>".join(f"`{name}`" for name in procedure["calledProcedures"])
        out.append(f"| `{procedure['proccode']}` | {args} | {calls} |")
    out.append("")
    out.append("## Pseudo-code blocks")
    out.append("")
    for procedure in procedures:
        definition = blocks[procedure["definitionId"]]
        out.append(f"### `{procedure['proccode']}`")
        out.append("")
        out.append(f"- Definition block: `{procedure['definitionId']}`")
        out.append(f"- Prototype block: `{procedure['prototypeId']}`")
        if procedure["argumentNames"]:
            out.append(f"- Arguments: `{', '.join(procedure['argumentNames'])}`")
        out.append("")
        out.append("```text")
        render_stack(
            blocks,
            definition.get("next"),
            out,
            indent=0,
            visited=set(),
        )
        out.append("```")
        out.append("")
    return "\n".join(out) + "\n"


def render_stack(
    blocks: dict[str, Block],
    block_id: str | None,
    out: list[str],
    *,
    indent: int,
    visited: set[str],
) -> None:
    current = block_id
    while current:
        if current in visited:
            out.append("  " * indent + f"↩ {current} [already rendered]")
            return
        block = blocks.get(current)
        if not block:
            out.append("  " * indent + f"? {current} [missing]")
            return
        visited.add(current)
        out.append("  " * indent + render_block_line(current, block, blocks))
        for name, nested_id in substack_inputs(block):
            out.append("  " * indent + f"  {name}:")
            render_stack(
                blocks,
                nested_id,
                out,
                indent=indent + 2,
                visited=visited,
            )
        current = block.get("next")


def render_block_line(block_id: str, block: Block, blocks: dict[str, Block]) -> str:
    opcode = block.get("opcode", "?")
    if opcode == "procedures_call":
        label = block.get("mutation", {}).get("proccode", opcode)
    else:
        label = opcode
    parts = [f"{block_id}: {label}"]
    fields = field_summary(block)
    if fields:
        parts.append(f"fields[{fields}]")
    inputs = input_summary(block, blocks)
    if inputs:
        parts.append(f"inputs[{inputs}]")
    return " | ".join(parts)


def field_summary(block: Block) -> str:
    pairs: list[str] = []
    for name, value in block.get("fields", {}).items():
        pairs.append(f"{name}={field_value(value)}")
    return ", ".join(pairs)


def input_summary(block: Block, blocks: dict[str, Block]) -> str:
    pairs: list[str] = []
    for name, value in block.get("inputs", {}).items():
        if name.startswith("SUBSTACK"):
            continue
        pairs.append(f"{name}={describe_input(value, blocks)}")
    return ", ".join(pairs)


def substack_inputs(block: Block) -> list[tuple[str, str]]:
    result: list[tuple[str, str]] = []
    for name, value in block.get("inputs", {}).items():
        if not name.startswith("SUBSTACK"):
            continue
        nested = input_block_id(value)
        if nested:
            result.append((name, nested))
    return result


def describe_input(value: Any, blocks: dict[str, Block]) -> str:
    nested = input_block_id(value)
    if nested and nested in blocks:
        block = blocks[nested]
        opcode = block.get("opcode")
        if opcode in {
            "argument_reporter_string_number",
            "argument_reporter_boolean",
        }:
            return f"${field_value(block.get('fields', {}).get('VALUE'))}"
        if opcode == "math_number":
            return field_value(block.get("fields", {}).get("NUM"))
        if opcode == "text":
            return repr(field_value(block.get("fields", {}).get("TEXT")))
        if opcode == "data_variable":
            return f"var({field_value(block.get('fields', {}).get('VARIABLE'))})"
        if opcode == "data_listcontents":
            return f"list({field_value(block.get('fields', {}).get('LIST'))})"
        if opcode == "procedures_call":
            return f"call({block.get('mutation', {}).get('proccode')})"
        return f"{nested}:{opcode}"
    literal = literal_input(value)
    return repr(literal) if isinstance(literal, str) else str(literal)


def input_block_id(value: Any) -> str | None:
    ids = input_block_ids(value)
    return ids[0] if ids else None


def input_block_ids(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    ids: list[str] = []
    for item in value[1:]:
        if isinstance(item, str):
            ids.append(item)
        elif isinstance(item, list) and len(item) >= 2 and isinstance(item[1], str):
            ids.append(item[1])
    return ids


def literal_input(value: Any) -> Any:
    if isinstance(value, list):
        for item in value[1:]:
            if isinstance(item, list) and len(item) >= 2:
                return item[1]
    return value


def field_value(value: Any) -> str:
    if isinstance(value, list) and value:
        return str(value[0])
    return "" if value is None else str(value)


def parse_json_list(value: Any) -> list[str]:
    if not isinstance(value, str):
        return []
    parsed = json.loads(value)
    return [str(item) for item in parsed]


if __name__ == "__main__":
    main()
