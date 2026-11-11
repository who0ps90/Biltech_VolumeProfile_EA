"""Independent, offline specification oracle. This never executes MQL5.

Inputs are synthetic fixtures. The native harness separately executes production
headers. Execution contracts below do not simulate an MT5 broker or its API.
"""
import calendar
import datetime as dt
import math
from decimal import Decimal, ROUND_FLOOR


def profile(points, weights, tick, requested_rows, percent, ranges=None):
    if not points or len(points) != len(weights) or tick <= 0 or requested_rows < 1 or not 0 < percent <= 100:
        raise ValueError("invalid profile inputs")
    bounds = ranges or [(p, p) for p in points]
    if any(w <= 0 or a <= 0 or b < a for (a, b), w in zip(bounds, weights)):
        raise ValueError("invalid ranges/weights")
    bottom = math.floor(min(a for a, _ in bounds) / tick + 1e-9) * tick
    top = max(b for _, b in bounds)
    width = max(1, math.ceil((top - bottom) / (requested_rows * tick) - 1e-9)) * tick
    rows = max(1, math.ceil((top - bottom) / width - 1e-9))
    bins = [0.0] * rows
    for (a, b), w in zip(bounds, weights):
        if a == b:
            bins[min(rows - 1, max(0, int((a - bottom) / width + 1e-9)))] += w
        else:
            for j in range(rows):
                overlap = max(0, min(b, bottom + (j + 1) * width) - max(a, bottom + j * width))
                bins[j] += w * overlap / (b - a)
    mid = (rows - 1) / 2
    poc = min(range(rows), key=lambda j: (-bins[j], abs(j - mid), j))
    chosen = {poc}
    while sum(bins[j] for j in chosen) < sum(weights) * percent / 100:
        left, right = min(chosen) - 1, max(chosen) + 1
        candidates = [j for j in (left, right) if 0 <= j < rows]
        if not candidates:
            break
        chosen.add(min(candidates, key=lambda j: (-bins[j], j)))
    return dict(bins=bins, lower=bottom, width=width, rows=rows,
                poc=bottom + (poc + .5) * width,
                val=bottom + min(chosen) * width, vah=bottom + (max(chosen) + 1) * width)


def signal_oracle(case, defaults):
    """Replay completed prefixes; no bar reads an index greater than itself."""
    p = defaults | {k: v for k, v in case.items() if k != "bars"}
    val, vah, poc = p["val"], p["vah"], p["poc"]
    tick, prior = p["tick_size"], p["previous_bar_close"]
    enabled = case["enabled"]
    excursion = {d: None for d in (1, -1)}
    rearmed = {d: True for d in (1, -1)}
    breakouts = {d: None for d in (1, -1)}
    results = []
    for i, (op, hi, lo, cl, atr) in enumerate(case["bars"]):
        buf = max(2 * tick, .1 * atr)
        candidates = []
        if "A" in enabled and val <= p["previous_session_close"] <= vah:
            for d in (1, -1):
                start = excursion[d]
                if start is not None:
                    if val < cl < vah:
                        bars = case["bars"][start:i + 1]
                        extreme = min(b[2] for b in bars) if d == 1 else max(b[1] for b in bars)
                        candidates.append(dict(index=i, setup=1, direction=d, stop=extreme-d*buf, atr=atr, buffer=buf))
                        excursion[d] = None
                    elif i - start >= 3:
                        excursion[d] = None
                        rearmed[d] = False
                elif not rearmed[d]:
                    rearmed[d] = val <= cl <= vah
                elif (cl < val if d == 1 else cl > vah):
                    excursion[d] = i
        if "B" in enabled:
            for d in (1, -1):
                level = vah if d == 1 else val
                state = breakouts[d]
                if state is None:
                    threshold = level + d*buf
                    if (cl > threshold >= prior if d == 1 else cl < threshold <= prior):
                        breakouts[d] = dict(start=i, retest=None, atr=atr, buffer=buf)
                    continue
                fb = state["buffer"]
                if cl < level-fb if d == 1 else cl > level+fb:
                    breakouts[d] = None
                    continue
                start, retest = state["start"], state["retest"]
                if retest is None:
                    if lo <= level+fb and hi >= level-fb and (cl > level if d == 1 else cl < level):
                        state["retest"] = i
                    elif i - start >= 6:
                        breakouts[d] = None
                else:
                    extreme_index = 1 if d == 1 else 2
                    gate = (max if d == 1 else min)(case["bars"][j][extreme_index] for j in (start, retest))
                    if cl > gate if d == 1 else cl < gate:
                        bars = case["bars"][retest:i + 1]
                        extreme = min(b[2] for b in bars) if d == 1 else max(b[1] for b in bars)
                        candidates.append(dict(index=i, setup=2, direction=d, stop=extreme-d*fb, atr=state["atr"], buffer=fb))
                        breakouts[d] = None
                    elif i - retest >= 3:
                        breakouts[d] = None
        if "C" in enabled and lo <= poc+buf and hi >= poc-buf:
            if p["previous_session_close"] > vah and prior > poc+buf and cl > poc+buf and cl > op:
                candidates.append(dict(index=i, setup=3, direction=1, stop=lo-buf, atr=atr, buffer=buf))
            if p["previous_session_close"] < val and prior < poc-buf and cl < poc-buf and cl < op:
                candidates.append(dict(index=i, setup=3, direction=-1, stop=hi+buf, atr=atr, buffer=buf))
        if candidates:
            results.append(min(candidates, key=lambda s: (s["setup"], -s["direction"])))
        prior = cl
    return results


def nth_sunday(year, month, n):
    first = dt.date(year, month, 1)
    return 1 + (6 - first.weekday()) % 7 + (n - 1) * 7


def last_sunday(year, month):
    last = calendar.monthrange(year, month)[1]
    return last - (dt.date(year, month, last).weekday() - 6) % 7


def us_offset(utc):
    y = utc.year
    if y < 1970 or y > 2099:
        raise ValueError("unsupported date")
    start_month, start_day = 4, last_sunday(y, 4)
    end_month, end_day = 10, last_sunday(y, 10)
    if y == 1974:
        start_month, start_day = 1, 6
    elif y == 1975:
        start_month, start_day = 2, 23
    elif y >= 2007:
        start_month, start_day = 3, nth_sunday(y, 3, 2)
        end_month, end_day = 11, nth_sunday(y, 11, 1)
    elif y >= 1987:
        start_day = nth_sunday(y, 4, 1)
    return -240 if dt.datetime(y, start_month, start_day, 7) <= utc < dt.datetime(y, end_month, end_day, 6) else -300


def eu_dst(utc):
    y = utc.year
    return dt.datetime(y, 3, last_sunday(y, 3), 1) <= utc < dt.datetime(y, 10, last_sunday(y, 10), 1)


def volume_down(raw, minimum, maximum, step):
    result = (Decimal(str(min(raw, maximum))) / Decimal(str(step))).to_integral_value(rounding=ROUND_FLOOR) * Decimal(str(step))
    return float(result) if result >= Decimal(str(minimum)) else 0.0


def quote_events(records):
    # One input record is one event; same millisecond and same payload is not a
    # safe dedup key. Chunk ranges must be disjoint instead of record dedup.
    previous, counted = None, []
    for tick in records:
        if tick["bid"] <= 0:
            previous = None
            continue
        if "BID" in tick["flags"] and (previous is None or tick["bid"] != previous):
            counted.append(tick["bid"])
        previous = tick["bid"]
    return counted


def trade_events(records):
    return [(r["last"], r["volume"]) for r in records
            if r["flags"] & {"LAST", "VOLUME", "BUY", "SELL"} and r["last"] > 0 and r["volume"] > 0]
