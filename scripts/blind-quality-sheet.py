#!/usr/bin/env python3
"""두 모델의 benchmark-claude 결과를 모델명을 가린 A/B 평가지로 만들고, 채점 후 모델별로 집계한다.

  # 평가지 만들기: 표본·회차마다 두 출력을 무작위로 A/B에 배정한다.
  ./scripts/blind-quality-sheet.py build RUN_1.json RUN_2.json --samples SAMPLES.json --out .context/blind

  # 채점이 끝난 뒤 매핑을 적용해 집계한다.
  ./scripts/blind-quality-sheet.py unblind --out .context/blind scores-a.json scores-b.json

out 디렉터리에 sheet.md(사람용), sheet.json(채점 항목 ID), key.json(정답 매핑)을 쓴다.
채점자는 key.json을 읽지 않는다. 점수 파일 형식:
  {"judge": "이름", "items": [{"item": "en-short-1#1",
     "A": {"majorError": false, "checksMet": 1, "fluency": 5},
     "B": {"majorError": false, "checksMet": 1, "fluency": 4},
     "preference": "A" | "B" | "tie", "note": "선택"}]}
"""
import argparse
import json
import random
import statistics
import sys
from pathlib import Path


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def outputs_by_key(run):
    """(sampleID, repeatIndex) → 성공한 번역 출력."""
    result = {}
    for record in run["results"]:
        if record.get("status") == "success" and record.get("output") is not None:
            result[(record["sampleID"], record["repeatIndex"])] = record["output"]
    return result


def build(args):
    runs = [load(path) for path in args.runs]
    models = [run["model"] for run in runs]
    if models[0] == models[1]:
        # 같은 모델의 설정 비교(예: 프롬프트 변경 전후)는 결과 파일 이름으로 구분한다.
        models = [Path(path).stem for path in args.runs]
    samples = {sample["id"]: sample for sample in load(args.samples)["samples"]}
    outputs = [outputs_by_key(run) for run in runs]
    rng = random.Random(args.seed)

    keys = sorted(set(outputs[0]) & set(outputs[1]), key=lambda k: (list(samples).index(k[0]), k[1]))
    missing = sorted((set(outputs[0]) | set(outputs[1])) - set(keys))
    items, key_map = [], {}
    for sample_id, repeat in keys:
        order = [0, 1]
        rng.shuffle(order)
        item_id = f"{sample_id}#{repeat}"
        sample = samples[sample_id]
        items.append({
            "item": item_id,
            "direction": f"{sample['source']}->{sample['target']}",
            "size": sample["size"],
            "source": sample["text"],
            "checks": sample["checks"],
            "A": outputs[order[0]][(sample_id, repeat)],
            "B": outputs[order[1]][(sample_id, repeat)],
        })
        key_map[item_id] = {"A": models[order[0]], "B": models[order[1]]}

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "sheet.json").write_text(json.dumps({"items": items}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / "key.json").write_text(json.dumps({
        "seed": args.seed, "runs": [str(p) for p in args.runs], "missing": [f"{s}#{r}" for s, r in missing],
        "items": key_map,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = ["# 블라인드 번역 평가지", "",
             "각 항목의 A·B는 서로 다른 모델의 출력이며 배정은 항목마다 무작위다.",
             "출력마다 중대 오류(의미 반전·누락·숫자/코드 변경) 여부, 만족한 checks 수, 자연스러움(1~5)을 매기고 A/B/동률 선호를 고른다.", ""]
    for item in items:
        lines += [f"## {item['item']} ({item['direction']}, {item['size']})", "", "**원문**", "", fence(item["source"]),
                  "**checks**", ""] + [f"- {check}" for check in item["checks"]] + ["",
                  "**A**", "", fence(item["A"]), "**B**", "", fence(item["B"])]
    (out / "sheet.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"items: {len(items)}, missing pairs: {len(missing)}, sheet: {out / 'sheet.md'}")


def fence(text):
    return "```text\n" + text + "\n```\n"


def unblind(args):
    out = Path(args.out)
    key = load(out / "key.json")["items"]
    sheet = {item["item"]: item for item in load(out / "sheet.json")["items"]}
    judges = [load(path) for path in args.scores]
    models = sorted({model for entry in key.values() for model in entry.values()})

    def blank():
        return {"outputs": 0, "majorErrors": 0, "usable": 0, "checksMet": 0, "checksTotal": 0,
                "fluency": [], "wins": 0, "ties": 0, "byDirection": {}}

    per_judge = {}
    disagreements = []
    by_item = {}
    for judge in judges:
        stats = {model: blank() for model in models}
        seen = set()
        for score in judge["items"]:
            item_id = score["item"]
            if item_id not in key:
                sys.exit(f"{judge['judge']}: 알 수 없는 항목 {item_id}")
            seen.add(item_id)
            total = len(sheet[item_id]["checks"])
            direction = sheet[item_id]["direction"]
            for slot in ("A", "B"):
                model, value = key[item_id][slot], score[slot]
                s = stats[model]
                s["outputs"] += 1
                s["majorErrors"] += int(bool(value["majorError"]))
                s["usable"] += int(not value["majorError"] and value["fluency"] >= 3)
                s["checksMet"] += value["checksMet"]
                s["checksTotal"] += total
                s["fluency"].append(value["fluency"])
                d = s["byDirection"].setdefault(direction, {"outputs": 0, "majorErrors": 0, "fluency": []})
                d["outputs"] += 1
                d["majorErrors"] += int(bool(value["majorError"]))
                d["fluency"].append(value["fluency"])
            preference = score["preference"]
            if preference == "tie":
                for model in models:
                    stats[model]["ties"] += 1
                winner = "tie"
            else:
                winner = key[item_id][preference]
                stats[winner]["wins"] += 1
            by_item.setdefault(item_id, []).append({
                "judge": judge["judge"], "winner": winner,
                "majorError": {key[item_id][slot]: bool(score[slot]["majorError"]) for slot in ("A", "B")},
                "note": score.get("note"),
            })
        if seen != set(key):
            sys.exit(f"{judge['judge']}: 채점하지 않은 항목 {sorted(set(key) - seen)[:5]}…")
        for s in stats.values():
            s["fluencyMean"] = round(statistics.mean(s["fluency"]), 2)
            del s["fluency"]
            for d in s["byDirection"].values():
                d["fluencyMean"] = round(statistics.mean(d["fluency"]), 2)
                del d["fluency"]
        per_judge[judge["judge"]] = stats

    for item_id, entries in by_item.items():
        winners = {e["winner"] for e in entries}
        errors = {json.dumps(e["majorError"], sort_keys=True) for e in entries}
        opposite = {m for m in winners if m != "tie"}
        if len(opposite) > 1 or len(errors) > 1:
            disagreements.append({"item": item_id, "judges": entries})

    report = {"models": models, "perJudge": per_judge, "disagreements": disagreements, "key": key}
    (out / "unblinded.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for name, stats in per_judge.items():
        print(f"\n[{name}]")
        print("| 모델 | 출력 | 중대 오류 | 사용 가능 | checks | 자연스러움 | 선호 승 | 동률 |")
        print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
        for model in models:
            s = stats[model]
            print(f"| `{model}` | {s['outputs']} | {s['majorErrors']} | {s['usable']} | "
                  f"{s['checksMet']}/{s['checksTotal']} | {s['fluencyMean']} | {s['wins']} | {s['ties']} |")
    print(f"\n채점자 간 엇갈린 항목: {len(disagreements)}개 → {out / 'unblinded.json'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    b = sub.add_parser("build")
    b.add_argument("runs", nargs=2)
    b.add_argument("--samples", required=True)
    b.add_argument("--out", required=True)
    b.add_argument("--seed", type=int, default=20261008)
    u = sub.add_parser("unblind")
    u.add_argument("scores", nargs="+")
    u.add_argument("--out", required=True)
    args = parser.parse_args()
    build(args) if args.command == "build" else unblind(args)


if __name__ == "__main__":
    main()
