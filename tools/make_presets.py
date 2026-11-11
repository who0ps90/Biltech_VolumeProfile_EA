"""Regenerate complete research presets from declared MQL input defaults."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ENUMS = {
    "ASSET_UNSELECTED": "0", "QUOTE_TICK_PROFILE": "0", "BROKER_TIME_UNKNOWN": "0",
    "NEWS_MT5_CALENDAR": "0", "PERIOD_M5": "5",
}

def main():
    source = (ROOT / "Biltech_VolumeProfile_EA.mq5").read_text(encoding="utf-8-sig")
    pairs = re.findall(r'^input\s+\w+\s+(\w+)\s*=\s*([^;]+);', source, re.M)
    base = {name: ENUMS.get(value.strip(), value.strip().strip('"')) for name, value in pairs}
    for asset, index in (("GOLD", 1), ("NASDAQ100", 2), ("US30", 3)):
        values = dict(base, AssetPreset=str(index), InstanceMagic=str(2600100+index))
        text = "; Research defaults; not optimized. Broker clock is intentionally UNKNOWN.\n"
        text += "; No broker symbol is set: attach only to the broker chart you have verified.\n"
        text += "\n".join(f"{k}={v}" for k, v in values.items()) + "\n"
        (ROOT / "presets" / f"{asset}_research.set").write_text(text, encoding="utf-16")
    print(f"Generated 3 presets, {len(base)} inputs each")

if __name__ == "__main__":
    main()
