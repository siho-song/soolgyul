"""Temporary: refactor guard. Deleted with refactor_guard/ when the refactor ends.

Compares the guard output of the base and of the change:
every picture must be pixel-identical and every card case word-identical.

    python3 refactor_guard/compare.py <base out> <head out> <diff dir>
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops

base, head, diff_dir = (Path(p) for p in sys.argv[1:4])
diff_dir.mkdir(parents=True, exist_ok=True)
problems: list[str] = []
new: list[str] = []


def changed_pixels(a: Image.Image, b: Image.Image) -> Image.Image:
    """A grey image, non-zero wherever any channel of the two differs."""
    bands = ImageChops.difference(a, b).split()
    most = bands[0]
    for band in bands[1:]:
        most = ImageChops.lighter(most, band)
    return most


def pictures() -> None:
    base_files = {p.name for p in (base / "screens").glob("*.png")}
    head_files = {p.name for p in (head / "screens").glob("*.png")}
    for name in sorted(base_files - head_files):
        problems.append(f"picture gone: {name}")
    new.extend(sorted(head_files - base_files))
    for name in sorted(base_files & head_files):
        a_path, b_path = base / "screens" / name, head / "screens" / name
        if a_path.read_bytes() == b_path.read_bytes():
            continue
        a = Image.open(a_path).convert("RGBA")
        b = Image.open(b_path).convert("RGBA")
        changed = None
        if a.size != b.size:
            problems.append(f"picture size {a.size} -> {b.size}: {name}")
        else:
            if a.tobytes() == b.tobytes():
                continue
            changed = changed_pixels(a, b)
            problems.append(f"picture changed in {changed.getbbox()}: {name}")
        width, height = a.width + b.width, max(a.height, b.height)
        sheet = Image.new("RGBA", (width + a.width, height), "white")
        sheet.paste(a, (0, 0))
        sheet.paste(b, (a.width, 0))
        if changed is not None:
            marked = changed.point(lambda v: 255 if v else 0)
            sheet.paste(Image.new("RGBA", a.size, "red"), (width, 0), marked)
        sheet.save(diff_dir / name)


def cases(path: Path) -> dict[str, str]:
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    return {json.loads(line)["case"]: line for line in lines}


def corpus() -> None:
    for path in sorted((base / "cards").glob("*.jsonl")):
        a, b = cases(path), cases(head / "cards" / path.name)
        changed = [c for c in a if a[c] != b.get(c)]
        new.extend(f"{path.name}: {c}" for c in b if c not in a)
        for case in changed[:5]:
            before = json.dumps(json.loads(a[case])["value"], ensure_ascii=False, indent=1)
            after = (
                json.dumps(json.loads(b[case])["value"], ensure_ascii=False, indent=1)
                if case in b
                else "(gone)"
            )
            (diff_dir / f"{path.stem}.{len(problems)}.txt").write_text(
                f"{case}\n--- base\n{before}\n--- change\n{after}\n", encoding="utf-8"
            )
        if changed:
            problems.append(f"{path.name}: {len(changed)} cases changed, first: {changed[0]}")


def complete(out: Path) -> None:
    """A run that stopped early leaves pictures or card files out."""
    if not any((out / "screens").glob("*.png")):
        problems.append(f"no pictures in {out}")
    for name in ("cards.single", "cards.random", "cards.fixtures", "pipeline", "letters", "taste_fit"):
        if not (out / "cards" / f"{name}.jsonl").exists():
            problems.append(f"missing {name}.jsonl in {out}")


complete(base)
complete(head)
pictures()
corpus()
for line in new[:20]:
    print(f"new (not compared): {line}")
if problems:
    print(f"{len(problems)} differences (details in {diff_dir}):")
    for line in problems[:60]:
        print(f"  {line}")
    sys.exit(1)
print("no picture and no card case changed")
