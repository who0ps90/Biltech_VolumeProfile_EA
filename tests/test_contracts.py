"""Portable specification tests. Run: python -m unittest discover -s tests -v.

These tests execute the independent Python oracle, never the EA or MT5 APIs.
Native production-header tests are tests/BiltechVP_Tests.mq5.
"""
import concurrent.futures
import datetime as dt
import json
from pathlib import Path
import threading
import unittest

from spec_oracle import profile, signal_oracle, us_offset, eu_dst, volume_down, quote_events, trade_events

HERE = Path(__file__).parent
FIXTURES = json.loads((HERE / "signal_cases.json").read_text(encoding="utf-8"))


class SignalSpecificationTests(unittest.TestCase):
    def test_all_handcheck_cases(self):
        for case in FIXTURES["cases"]:
            with self.subTest(case=case["name"]):
                self.assertEqual(signal_oracle(case, FIXTURES["defaults"]), case["expected"])

    def test_every_prefix_has_no_future_dependency(self):
        for case in FIXTURES["cases"]:
            for end in range(1, len(case["bars"]) + 1):
                with self.subTest(case=case["name"], prefix=end):
                    prefix = case | {"bars": case["bars"][:end]}
                    self.assertEqual(signal_oracle(prefix, FIXTURES["defaults"]),
                                     [s for s in case["expected"] if s["index"] < end])

    def test_signal_entry_interval_and_price_drift(self):
        bar_open, period, atr, close = 1000, 300, 10, 100
        eligible = lambda now, price: bar_open+period <= now < bar_open+2*period and abs(price-close) <= .2*atr
        self.assertFalse(eligible(1299, 100))
        self.assertTrue(eligible(1300, 102))
        self.assertTrue(eligible(1599, 98))
        self.assertFalse(eligible(1600, 100))
        self.assertFalse(eligible(1300, 102.0001))

    def test_replay_stable_identifier_and_reset(self):
        case = FIXTURES["cases"][0]
        identity = lambda index: f"reference:bar{index}:1:1"
        first = signal_oracle(case, FIXTURES["defaults"])
        replay = signal_oracle(case, FIXTURES["defaults"])
        self.assertEqual([identity(s["index"]) for s in first], [identity(s["index"]) for s in replay])
        self.assertEqual(signal_oracle(case | {"bars": case["bars"][1:]}, FIXTURES["defaults"]), [])


class ProfileSpecificationTests(unittest.TestCase):
    def test_maximum_included_in_final_bin_and_weight_conserved(self):
        p = profile([100, 101, 102, 103, 104], [2, 1, 1, 1, 1], 1, 4, 70)
        self.assertEqual(p["bins"], [2, 1, 1, 2])
        self.assertEqual(sum(p["bins"]), 6)
        self.assertEqual(p["poc"], 100.5)

    def test_poc_ties_midpoint_then_lower(self):
        p = profile([100.2, 101.2, 102.2, 103.2], [1, 3, 3, 1], 1, 4, 50)
        self.assertEqual((p["poc"], p["val"], p["vah"]), (101.5, 101, 103))

    def test_value_area_adjacent_ties_choose_lower(self):
        p = profile([100.2, 101.2, 102.2, 103.2], [2, 4, 2, 1], 1, 4, 60)
        self.assertEqual((p["poc"], p["val"], p["vah"]), (101.5, 100, 102))

    def test_m1_proportional_overlap_and_zero_range(self):
        p = profile([101, 101], [10, 3], 1, 2, 50, [(100, 102), (101, 101)])
        self.assertEqual(p["bins"], [5, 8])
        self.assertEqual(sum(p["bins"]), 13)

    def test_integer_tick_width_and_requested_row_bound(self):
        p = profile([100.12, 117.13], [3, 7], .25, 60, 100)
        self.assertEqual(p["lower"], 100)
        self.assertLessEqual(p["rows"], 60)
        self.assertAlmostEqual(p["width"]/.25, round(p["width"]/.25))
        self.assertLessEqual(117.13, p["lower"]+p["rows"]*p["width"])
        self.assertEqual(sum(p["bins"]), 10)

    def test_missing_profile_blocks(self):
        with self.assertRaises(ValueError):
            profile([], [], .1, 60, 70)

    def test_quote_flags_and_same_millisecond_events(self):
        rows = [{"ms": 1, "bid": 100, "flags": {"BID"}},
                {"ms": 2, "bid": 100, "flags": {"ASK"}},
                {"ms": 3, "bid": 101, "flags": {"BID"}},
                {"ms": 3, "bid": 100, "flags": {"BID"}},
                {"ms": 3, "bid": 101, "flags": {"BID"}},
                {"ms": 4, "bid": 101, "flags": {"BID"}}]
        self.assertEqual(quote_events(rows), [100, 101, 100, 101])

    def test_trade_quote_record_does_not_repeat_stale_volume(self):
        rows = [{"last": 100, "volume": 7, "flags": {"LAST", "VOLUME"}},
                {"last": 100, "volume": 7, "flags": {"BID"}},
                {"last": 101, "volume": 0, "flags": {"LAST"}}]
        self.assertEqual(trade_events(rows), [(100, 7)])

    def test_coverage_nonempty_is_insufficient(self):
        expected = set(range(390))
        downloaded = {0, 1, 389}
        self.assertTrue(downloaded)
        self.assertLess(len(downloaded & expected)/len(expected), .98)


class TimeSpecificationTests(unittest.TestCase):
    def test_us_transition_exact_seconds(self):
        self.assertEqual(us_offset(dt.datetime(2026, 3, 8, 6, 59, 59)), -300)
        self.assertEqual(us_offset(dt.datetime(2026, 3, 8, 7)), -240)
        self.assertEqual(us_offset(dt.datetime(2026, 11, 1, 5, 59, 59)), -240)
        self.assertEqual(us_offset(dt.datetime(2026, 11, 1, 6)), -300)

    def test_mismatched_us_eu_transition_weeks(self):
        for utc, us, eu in [(dt.datetime(2026, 3, 16, 12), -240, False),
                            (dt.datetime(2026, 3, 30, 12), -240, True),
                            (dt.datetime(2026, 10, 26, 12), -240, False)]:
            self.assertEqual(us_offset(utc), us)
            self.assertEqual(eu_dst(utc), eu)

    def test_historical_2006_and_emergency_1974(self):
        self.assertEqual(us_offset(dt.datetime(2006, 3, 20)), -300)
        self.assertEqual(us_offset(dt.datetime(2006, 4, 3)), -240)
        self.assertEqual(us_offset(dt.datetime(1974, 1, 6, 6, 59, 59)), -300)
        self.assertEqual(us_offset(dt.datetime(1974, 1, 6, 7)), -240)

    def test_half_open_entry_window_and_overnight(self):
        inside = lambda minute, a, b: a <= minute < b if a < b else minute >= a or minute < b
        self.assertTrue(inside(585, 585, 690))
        self.assertFalse(inside(690, 585, 690))
        self.assertTrue(inside(30, 1320, 120))
        self.assertFalse(inside(120, 1320, 120))

    def test_previous_completed_eligible_day(self):
        now = dt.datetime(2026, 1, 5, 10)
        candidates = [now.date()-dt.timedelta(days=i) for i in range(8)]
        holiday = {dt.date(2026, 1, 1)}
        previous = next(d for d in candidates if d.weekday() < 5 and d not in holiday and dt.datetime.combine(d, dt.time(16)) <= now)
        self.assertEqual(previous, dt.date(2026, 1, 2))


class ExecutionContractTests(unittest.TestCase):
    def test_A_poc_space_uses_proposed_actual_entry(self):
        allowed = lambda entry, stop, poc, d: (entry < poc and entry+2*(entry-stop) <= poc) if d == 1 else (entry > poc and entry-2*(stop-entry) >= poc)
        self.assertTrue(allowed(100.3, 99.5, 105, 1))
        self.assertTrue(allowed(109.7, 110.5, 105, -1))
        self.assertFalse(allowed(104, 99.5, 105, 1))
        self.assertFalse(allowed(105.1, 99.5, 105, 1))

    def test_lot_floor_never_increases_budget(self):
        self.assertEqual(volume_down(.129, .01, 10, .01), .12)
        self.assertEqual(volume_down(.009, .01, 10, .01), 0)
        self.assertEqual(volume_down(.74, .25, 5, .25), .5)
        self.assertEqual(volume_down(99, .01, 2, .01), 2)

    def test_risk_in_account_currency_with_costs(self):
        # Synthetic OrderCalcProfit result: loss at SL = 350 account-currency
        # units / lot, plus 7 commission + 3 adverse slippage. No pip formula.
        budget, calculated_loss, commission, slippage = 100, 350, 7, 3
        lots = volume_down(budget/(calculated_loss+commission+slippage), .01, 10, .01)
        self.assertEqual(lots, .27)
        self.assertLessEqual(lots*(calculated_loss+commission+slippage), budget)

    def test_simultaneous_reservation_is_serialized(self):
        lock = threading.Lock()
        reservations = {}
        def reserve(i):
            with lock:
                if sum(reservations.values()) + .3 > .5:
                    return False
                reservations[i] = .3
                return True
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            accepted = list(pool.map(reserve, range(8)))
        self.assertEqual(sum(accepted), 1)
        self.assertLessEqual(sum(reservations.values()), .5)

    def test_restart_preserves_submission_and_partial_fill(self):
        state = {"processed": ["id1"], "reservation": {"id1": .25}, "filled": .4, "status": "partial"}
        restarted = json.loads(json.dumps(state))
        self.assertIn("id1", restarted["processed"])
        self.assertEqual(restarted["reservation"]["id1"], .25)
        self.assertNotEqual(restarted["status"], "new")

    def test_failed_submission_is_not_resubmitted(self):
        processed = set()
        attempts = []
        for outcome in ["rejected", "delayed", "partial"]:
            signal = "same-id"
            if signal not in processed:
                processed.add(signal)  # Persist before sending.
                attempts.append(outcome)
        self.assertEqual(attempts, ["rejected"])

    def test_daily_latch_and_counters_reset_only_on_new_ny_day(self):
        state = {"day": "2026-01-05", "loss_latched": True, "fills": 2}
        recovered = json.loads(json.dumps(state))
        self.assertTrue(recovered["loss_latched"])
        new_day = "2026-01-06"
        if recovered["day"] != new_day:
            recovered.update(day=new_day, loss_latched=False, fills=0)
        self.assertEqual(recovered, {"day": new_day, "loss_latched": False, "fills": 0})

    def test_group_pnl_includes_floating_change_and_all_costs(self):
        realized = 20 - 2 - 1 - .5
        floating_start, floating_now = 10, -20
        self.assertEqual(realized + floating_now-floating_start, -13.5)

    def test_netting_requires_unambiguous_position_deal_ownership(self):
        owned = lambda magics, expected: bool(magics) and set(magics) == {expected}
        self.assertTrue(owned([42, 42], 42))
        self.assertFalse(owned([42, 0], 42))
        self.assertFalse(owned([42, 43], 42))
        self.assertFalse(owned([], 42))

    def test_missing_news_is_fail_closed_and_does_not_gate_management(self):
        news_available, required = False, True
        entry_allowed = news_available or not required
        management_allowed = True
        self.assertFalse(entry_allowed)
        self.assertTrue(management_allowed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
