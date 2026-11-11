"""Read-only package consistency checks. Not a native trading-engine test."""
from pathlib import Path
import csv
import json
import re

ROOT = Path(__file__).resolve().parents[1]

def main():
    source = (ROOT / "Biltech_VolumeProfile_EA.mq5").read_text(encoding="utf-8-sig")
    defaults = dict(re.findall(r'^input\s+\w+\s+(\w+)\s*=\s*([^;]+);', source, re.M))
    enums = {"ASSET_UNSELECTED":"0", "QUOTE_TICK_PROFILE":"0", "BROKER_TIME_UNKNOWN":"0", "NEWS_MT5_CALENDAR":"0", "PERIOD_M5":"5"}
    defaults = {k:enums.get(v.strip(),v.strip().strip('"')) for k,v in defaults.items()}
    for asset,index in (("GOLD",1),("NASDAQ100",2),("US30",3)):
        path = ROOT / "presets" / f"{asset}_research.set"
        values = dict(line.split("=",1) for line in path.read_text(encoding="utf-16").splitlines() if line and not line.startswith(";"))
        expected = dict(defaults, AssetPreset=str(index), InstanceMagic=str(2600100+index))
        assert values == expected, f"Preset defaults differ: {asset}"
        assert values["AllowLiveTrading"] == "false" and values["BrokerTimeMode"] == "0"
    print(f"PASS: 3 complete research presets match {len(defaults)} source inputs and intended identity overrides")
    for path in list(ROOT.rglob("*.mqh"))+list(ROOT.rglob("*.mq5")):
        for inc in re.findall(r'#include\s+"([^"]+)"',path.read_text(encoding="utf-8-sig")):
            assert (path.parent / inc.replace("\\","/")).exists(), f"Missing include {path}: {inc}"
        assert "#import" not in path.read_text(encoding="utf-8-sig"), f"Unexpected import: {path}"
    print("PASS: all local MQL includes resolve; no DLL imports")
    for path in [ROOT / "README.md", *ROOT.glob("docs/*.md")]:
        for target in re.findall(r'\]\(([^)]+)\)',path.read_text(encoding="utf-8-sig")):
            if "://" in target or target.startswith("#"): continue
            assert (path.parent / target.split("#")[0]).exists(), f"Broken local doc link: {path}: {target}"
    print("PASS: local documentation links resolve")
    with (ROOT/"data/news_SYNTHETIC.csv").open(newline="",encoding="utf-8-sig") as f:
        rows=list(csv.DictReader(f))
    assert rows and all(row["synthetic"]=="1" for row in rows)
    with (ROOT/"docs/results_template.csv").open(newline="",encoding="utf-8-sig") as f:
        rows=list(csv.DictReader(f))
    assert len(rows)==1 and rows[0]["status"]=="NOT_RUN" and None not in rows[0]
    print("PASS: sample news marked synthetic; market results remain NOT_RUN")
    for src,log in (("Biltech_VolumeProfile_EA.mq5","compile-main.log"),("tests/BiltechVP_Tests.mq5","compile-native-tests.log")):
        p=ROOT/src; binary=p.with_suffix(".ex5"); content=(ROOT/"logs"/log).read_text(encoding="utf-16")
        assert "Result: 0 errors, 0 warnings" in content
        dependencies=list(ROOT.glob("Include/BiltechVP/*.mqh")) + [p]
        if "tests/" in src: dependencies += list(ROOT.glob("tests/*.mqh"))
        assert binary.stat().st_mtime >= max(d.stat().st_mtime for d in dependencies), f"Binary predates source: {binary}"
    print("PASS: zero-error/warning compile logs and fresh EA/native-test EX5 files")

if __name__ == "__main__":
    main()
