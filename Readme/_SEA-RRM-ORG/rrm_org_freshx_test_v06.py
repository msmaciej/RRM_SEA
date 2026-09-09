#!/usr/bin/env python3
# =============================================================================
# rrm_org_freshx_test.py
# -----------------------------------------------------------------------------
# Python replica of the three v05 RRM_ORG gates so they can be tested on MT5 CSV
# data without the terminal:
#
#   1. Fresh-cross gate   (engine: CheckFreshCrossGate)  — chart TF, per layer
#   2. UNO-Shark context  (engine: UnoSharkDirection)    — S allowed in UNO when
#                                                          34/89 ordered, 13 between
#   3. MTF FreshX         (engine: CheckMtfFreshCross)   — TF1 must be YOUNG:
#                                                          its own 34/89 cross found
#                                                          and <= N slope-pullbacks
#
# All three use the engine's slope definition of a pullback (fast-EMA pace over
# lookback/4 vs baseline pace over lookback; ratio < flat_ratio, or slope against
# bias). No price "touch" anywhere.
#
# The BASE TS=1 candidate detection is borrowed from rrm_org_discriminator.py and
# is an APPROXIMATION of the EA (the layer machine is simplified). The gate
# arithmetic itself is exact. SignalScan stays the authority for TS verdicts.
#
# Usage:
#   python3 rrm_org_freshx_test.py ../Files/EURUSD_M1_202608030000_202608312359.csv
#       [--tf M1] [--tf1 M5] [--tf2 M15] [--session] [--layers S|all]
#       [--at "2026.08.12 09:35"] [--ideal]
#
#   --ideal   list "ideal setup" windows independent of the approximate voters:
#             chart TF in EM/TM (or UNO-Shark) with its 34/89 cross <= 40 bars old,
#             TF1 young (34/89 cross, <= 2 pullbacks), TF2 direction aligned.
# =============================================================================
import argparse, importlib.util, os
import numpy as np, pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("disc", os.path.join(HERE, "rrm_org_discriminator.py"))
disc = importlib.util.module_from_spec(spec); spec.loader.exec_module(disc)

RULE = {"M1": "1min", "M5": "5min", "M15": "15min", "M30": "30min", "H1": "1h", "H4": "4h"}

# ---- engine constants (RRM_ORG preset defaults) ----------------------------
FLAT_RATIO   = 0.10          # Inp_RRM_ORG_LayerPBFlatRatio
ALLOW_REV    = True          # Inp_RRM_ORG_LayerPBAllowReversal
LOOKBACK     = {"W": 21, "M": 34, "S": 55}     # Inp_RRM_ORG_LayerPBLookback_W/M/S
REFPAIR      = {"W": (2, 3), "M": (2, 3), "S": (3, 4)}   # FreshX_RefPair_W/M/S (13/34, 13/34, 34/89)
FASTSLOT     = {"W": 1, "M": 2, "S": 3}
MAXPB        = {"W": 2, "M": 3, "S": 0}        # FreshX_MaxPullbacks_W/M/S (0 = unlimited)
FX_WINDOW    = 300                             # FreshX_Lookback
MTF_MAXPB    = 2                               # MTF_FreshX_MaxPullbacks
MTF_WINDOW   = 200                             # MTF_FreshX_Lookback (TF1 bars)
MTF_PBLOOK   = 55                              # MTF_FreshX_PBLookback
EPS          = 1e-8                            # SEA_LAYER_SLOPE_EPSILON
SESSION_OK   = [(7, 12), (8, 18), (14, 22)]    # Win1 07-12, London 09-17 ±1h, NY 14-22 (server hours)

# ---- shared slope-episode counter (mirror of the MQL loop) -----------------
def slope_episodes(fast, i_new, i_old, bias, lookback):
    """fast: numpy array oldest->newest. Count pullback episodes over bar indices
    [i_old .. i_new] (inclusive, i_old is the cross bar). Same arithmetic as
    UpdateSingleLayerPullback / CheckFreshCrossGate at each bar."""
    k = max(2, lookback // 4)
    episodes, in_pb = 0, False
    for j in range(i_old, i_new + 1):
        if j - lookback - 1 < 0:
            continue
        baseline = (fast[j - 1] - fast[j - lookback - 1]) / lookback
        current  = (fast[j] - fast[j - k]) / k
        ratio = abs(current) / abs(baseline) if abs(baseline) >= EPS else 0.0
        pb = ratio < FLAT_RATIO
        if not pb and ALLOW_REV and current != 0.0 and ((bias > 0) != (current > 0)):
            pb = True
        if pb and not in_pb:
            episodes += 1
        in_pb = pb
    return episodes

def last_cross(a, b, i, bias, window):
    """Index of the most recent bar <= i where a-b turned into the bias direction.
    Returns -1 if none inside `window` bars or if a/b are not aligned now."""
    d0 = a[i] - b[i]
    if (bias > 0 and d0 <= 0) or (bias < 0 and d0 >= 0):
        return -2                        # not aligned: gate not applicable
    lo = max(1, i - window)
    for j in range(i, lo - 1, -1):
        d, dp = a[j] - b[j], a[j - 1] - b[j - 1]
        now  = d > 0 if bias > 0 else d < 0
        prev = dp > 0 if bias > 0 else dp < 0
        if now and not prev:
            return j
    return -1

def fresh_cross_gate(E, layer, bias, i):
    """E: dict slot->numpy EMA arrays of the chart TF. Returns (ok, episodes, age)."""
    sa, sb = REFPAIR[layer]
    c = last_cross(E[sa], E[sb], i, bias, FX_WINDOW)
    if c == -2:
        return True, 0, -1                 # pair not aligned → layer's own align check rejects
    if c == -1:
        return False, 0, -1                # no cross in window = stale
    ep = slope_episodes(E[FASTSLOT[layer]], i, c, bias, LOOKBACK[layer])
    ok = (MAXPB[layer] == 0) or (ep <= MAXPB[layer])
    return ok, ep, i - c

def uno_shark_dir(e2, e3, e4, tol=2e-5):
    if e3 > e4 + tol and e4 < e2 < e3: return +1
    if e4 > e3 + tol and e3 < e2 < e4: return -1
    return 0

def htf_closed_index(htf_index, t):
    """Position of the last FULLY CLOSED HTF bar as of chart bar time t
    (engine: hb = bar containing t; base = hb+1 → one older)."""
    hb = htf_index.searchsorted(t, side="right") - 1
    return hb - 1

def mtf_fresh_cross(H, hi, bias):
    """H: dict slot->arrays of the HTF (34=3, 89=4). Returns (ok, episodes, age)."""
    if hi < MTF_PBLOOK + 12:
        return True, 0, -1
    c = last_cross(H[3], H[4], hi, bias, MTF_WINDOW)
    if c == -2:
        return True, 0, -1                 # MTF direction voter owns this case
    if c == -1:
        return False, 0, -1
    ep = slope_episodes(H[3], hi, c, bias, MTF_PBLOOK)
    return (ep <= MTF_MAXPB), ep, hi - c

def mtf_direction(H, hi):
    """Legacy MTF vote with 34/89: position + both sloping with it (RequirePhase)."""
    if hi < 1: return 0
    f0, f1, s0, s1 = H[3][hi], H[3][hi - 1], H[4][hi], H[4][hi - 1]
    above = f0 > s0
    if above and f0 <= f1 and s0 <= s1: return 0
    if (not above) and f0 > f1 and s0 > s1: return 0
    return +1 if above else (-1 if f0 < s0 else 0)

def in_session(t):
    h = t.hour + t.minute / 60.0
    return any(a <= h < b for a, b in SESSION_OK)

def emas(df):
    return {1: disc.ema(df.close, 5).values, 2: disc.ema(df.close, 13).values,
            3: disc.ema(df.close, 34).values, 4: disc.ema(df.close, 89).values}

# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--tf", default="M1"); ap.add_argument("--tf1", default="M5"); ap.add_argument("--tf2", default="M15")
    ap.add_argument("--session", action="store_true", help="apply the v05 session windows")
    ap.add_argument("--layers", default="S", help="MTF_FreshX_Layers: S | all")
    ap.add_argument("--allow-w", action="store_true", help="AllowLayerW (v05: off on M1/M5)")
    ap.add_argument("--at", default=None, help="comma list of 'YYYY.MM.DD HH:MM' chart bars to explain")
    ap.add_argument("--ideal", action="store_true")
    ap.add_argument("--max-print", type=int, default=60)
    a = ap.parse_args()

    raw = disc.load_csv(a.csv)
    def frame(tf):
        d = raw if tf == "M1" and a.csv.find("_M1_") >= 0 else \
            raw.resample(RULE[tf]).agg({"open": "first", "high": "max", "low": "min", "close": "last"}).dropna()
        return d
    d0, d1, d2 = frame(a.tf), frame(a.tf1), frame(a.tf2)
    D = disc.build(d0); E = emas(d0); H1 = emas(d1); H2 = emas(d2)
    print(f"# chart {a.tf}: {len(d0)} bars  TF1 {a.tf1}: {len(d1)}  TF2 {a.tf2}: {len(d2)}   {d0.index[0]} -> {d0.index[-1]}")

    # ---- --ideal: structural scan, independent of the approximate voters ----
    if a.ideal:
        print("\n# IDEAL-SETUP WINDOWS: chart TF phase EM/TM or UNO-Shark, chart 34/89 cross <= 40 bars old,"
              " TF1 young (34/89 cross, <= 2 pullbacks), TF2 direction aligned")
        rows = []
        for i in range(120, len(d0)):
            e2, e3, e4 = E[2][i], E[3][i], E[4][i]
            ph, bias = disc.phase_bias(e2, e3, e4)
            shark = 0
            if bias == 0:
                shark = uno_shark_dir(e2, e3, e4); bias = shark
                if bias == 0: continue
            if a.session and not in_session(d0.index[i]): continue
            c34 = last_cross(E[3], E[4], i, bias, FX_WINDOW)
            age = i - c34 if c34 >= 0 else -1
            if not (0 <= age <= 40) and not ph.startswith("EM"): continue
            h1i = htf_closed_index(d1.index, d0.index[i]); h2i = htf_closed_index(d2.index, d0.index[i])
            ok1, ep1, age1 = mtf_fresh_cross(H1, h1i, bias)
            dir2 = mtf_direction(H2, h2i)
            if ok1 and age1 >= 0 and dir2 == bias:
                rows.append((d0.index[i], ph if not shark else f"UNO-SHARK({'L' if shark>0 else 'S'})",
                             bias, age, ep1, age1, dir2))
        # collapse consecutive bars into windows
        wins = []
        for r in rows:
            if wins and (r[0] - wins[-1][1]) <= pd.Timedelta(RULE[a.tf]) * 3 and wins[-1][2] == r[2]:
                wins[-1][1] = r[0]
            else:
                wins.append([r[0], r[0], r[2], r])
        print(f"# {len(rows)} qualifying bars in {len(wins)} windows")
        for w in wins[:a.max_print]:
            r = w[3]
            print(f"{w[0]:%Y.%m.%d %H:%M} -> {w[1]:%H:%M}  {'LONG' if w[2]>0 else 'SHORT'}  at start → chart:{r[1]} 34/89 age={r[3]}"
                  f"   {a.tf1}: pb={r[4]} age={r[5]}   {a.tf2}: dir={r[6]:+d}")
        return

    # ---- candidate scan through the approximate BASE + the v05 gates ----
    at = None
    if a.at:
        at = set(pd.to_datetime([s.strip() for s in a.at.split(",")], format="%Y.%m.%d %H:%M"))
    stats = dict(base=0, session=0, layerW=0, freshx=0, mtf_dir=0, mtf_fresh=0, kept=0, shark=0)
    kept = []
    for i in range(120, len(D)):
        t = D.index[i]
        if at is not None and t not in at: continue
        e = disc.evaluate_bar(D, i, 1.5)
        r = D.iloc[i]
        # --- UNO-Shark extension of the approximate base: S may fire in UNO-Shark geometry
        shark = 0
        if e["bias"] == 0:
            shark = uno_shark_dir(r.e2, r.e3, r.e4)
            if shark != 0:
                lng = shark > 0
                pos = (r.e3 > r.e4) if lng else (r.e3 < r.e4)
                bc  = (r.close > r.e3) if lng else (r.close < r.e3)
                win = D["e3_sl"].iloc[i-3:i+1]
                dipped = (win.abs().min() < 0.1 * abs(win).mean()) or ((win < 0).any() if lng else (win > 0).any())
                recov = (r.e3_sl > 0 and r.e4_sl > 0) if lng else (r.e3_sl < 0 and r.e4_sl < 0)
                dpi_ok  = (r.dpi > 0) == lng and (np.sign(r.dpi) == np.sign(r.cci))
                psar_ok = (r.psar < r.close) if lng else (r.psar > r.close)
                cb = ((r.close > r.open) == lng) and (((r.close - r.low) if lng else (r.high - r.close)) / max(r.high - r.low, 1e-9) >= 0.75)
                if pos and bc and dipped and recov and dpi_ok and psar_ok and cb:
                    e.update(ts1=True, layer="S", bias=shark, phase="UNO-SHARK")
        if not e.get("ts1"):
            if at is not None: print(f"{t:%Y.%m.%d %H:%M}  BASE reject: {e.get('block')}")
            continue
        stats["base"] += 1
        bias, layer = e["bias"], e["layer"]
        if layer == "W" and not a.allow_w:
            stats["layerW"] += 1
            if at is not None: print(f"{t:%Y.%m.%d %H:%M}  reject: AllowLayerW=false")
            continue
        if a.session and not in_session(t):
            stats["session"] += 1
            if at is not None: print(f"{t:%Y.%m.%d %H:%M}  reject: SESSION")
            continue
        okx, ep, age = fresh_cross_gate(E, layer, bias, i)
        h1i = htf_closed_index(d1.index, t); h2i = htf_closed_index(d2.index, t)
        dir1, dir2 = mtf_direction(H1, h1i), mtf_direction(H2, h2i)
        okm, ep1, age1 = mtf_fresh_cross(H1, h1i, bias)
        mtf_scope = (a.layers == "all") or (layer == "S")
        line = (f"{t:%Y.%m.%d %H:%M} {'L' if bias>0 else 'S'} {e['phase']:<9} L{layer} "
                f"FreshX[pb={ep} age={age}] {a.tf1}[dir={dir1:+d} pb={ep1} age={age1}] {a.tf2}[dir={dir2:+d}]")
        if not okx:
            stats["freshx"] += 1; print(line + "  → L_FRESHX_STALE") if (at is not None or len(kept) < a.max_print) else None; continue
        if dir1 != bias or dir2 != bias:
            stats["mtf_dir"] += 1; print(line + "  → MTF direction") if at is not None else None; continue
        if mtf_scope and not okm:
            stats["mtf_fresh"] += 1; print(line + "  → L_MTF_FRESHX_STALE") if (at is not None or len(kept) < a.max_print) else None; continue
        stats["kept"] += 1; stats["shark"] += int(e["phase"] == "UNO-SHARK")
        kept.append(line)
        if at is not None or len(kept) <= a.max_print: print(line + "  → TS=1 (v05)")
    print("\n# SUMMARY  (approximate base; gates exact)")
    for k, v in stats.items(): print(f"  {k:<10}{v}")

if __name__ == "__main__":
    main()
