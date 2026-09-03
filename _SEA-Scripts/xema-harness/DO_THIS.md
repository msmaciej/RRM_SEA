# DO THIS (ignore everything from earlier chats)

You have 4 files. Here is exactly what to do with them.

## Step 1
Open a NEW chat.

## Step 2
Attach all 4 of these files:
- SEA_ENGINE_SPEC.md            ← the build instructions
- conformance_EURUSD_H1_260101-260831.csv   ← 21 real EA trades to match
- oracle_EURUSD_H1_260101-260831_rejects.csv ← debugging helper
- mt5_EURUSD_H1_20260902.log    ← the real MT5 test log (the proof)

## Step 3
Paste this one line as your message:

    Clone github.com/msmaciej/RRM_SEA. Build a Python engine for PRESET_XEMA
    exactly to the attached SEA_ENGINE_SPEC.md, then verify it reproduces the 21
    trades in the attached conformance CSV. Don't trust any result until it
    matches the log.

That's the whole thing. The new chat will build the tool correctly and check it
against the real EA before giving you any numbers.

---

## Why this replaces all the earlier "paste this" files
Earlier prompts assumed the Python's indicator math just needed tuning. The real
problem (found from your MT5 log): the EA uses MT5's BUILT-IN indicators
(iADX, iMA, iSAR, iBands), and the old Python used its own approximate versions —
so it blocked real trades. SEA_ENGINE_SPEC.md is the first handoff that states
this and gives the exact fix. Use only this set. Delete the older ones.

## One honest expectation
Even done perfectly, the tool RANKS settings well ("does this preset work on this
pair/TF/period, and how do settings change it") but won't match the EA's profit to
the exact cent — the tool uses hourly candles, the EA uses ticks. That's a data
limit, not a bug. The spec explains this.
