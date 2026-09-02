# Getting the XEMA harness into the real repo

The harness is committed locally as `f7b4627` on top of your current HEAD
`b0244b7956fe4c2851e71cb956462bd7f3591409`. This build environment has no push
credentials, so apply it on your side with EITHER of:

## Option A — git bundle (recommended; carries the exact commit)
```bash
cd RRM_SEA
git fetch /path/to/xema-harness_f7b4627.bundle main:xema-harness
git merge --ff-only xema-harness      # fast-forwards main to f7b4627
git push origin main
```

## Option B — patch (git am)
```bash
cd RRM_SEA
git am /path/to/0001-Add-consolidated-conformance-checked-XEMA-test-harne.patch
git push origin main
```

## Option C — just the files
Copy `xema-harness/` into `_SEA-Scripts/xema-harness/` and commit normally.

## Then, to reach a true conformance PASS
Produce an EA_LOG fixture per `_SEA-Scripts/xema-harness/fixtures/TEMPLATE_conformance_EA_LOG.csv`
(MT5 tester, EURUSD H1, ~1-2 months, DEFAULT XEMA config, collect/log mode), commit it as
`fixtures/conformance_EURUSD_H1_<dates>.csv`, then:
```bash
cd _SEA-Scripts/xema-harness
python3 xema_harness_260902-01.py <EURUSD_H1>.csv --htf M15=<EURUSD_M15>.csv \
    --verify fixtures/conformance_EURUSD_H1_<dates>.csv   # expect PASS, exit 0
```
Until that PASSes, conformance vs the EA is UNVERIFIED (the shipped REGRESSION
fixture only guards harness drift).
