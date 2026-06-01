# Adaptive Settings

## Purpose
Auto-detect maximum spread limits based on symbol type.

## How It Works
Different instruments have inherently different spreads:

```
Symbol = "EURUSD" → Detected as MAJOR → MaxSpread = 2.0 pips
Symbol = "XAUUSD" → Detected as GOLD  → MaxSpread = 5.0 pips
Symbol = "BTCUSD" → Detected as CRYPTO → MaxSpread = 50.0 pips
```

## Configuration
Set in **ZONE 3C** inputs:
- `Inp_Adaptive_PairType` — AUTO (auto-detect) or manual override
- `Inp_Adaptive_Spread_Major` — Major pairs (default: 2.0)
- `Inp_Adaptive_Spread_Minor` — Minor pairs (default: 4.0)
- `Inp_Adaptive_Spread_Exotic` — Exotic pairs (default: 10.0)
- `Inp_Adaptive_Spread_Gold` — Gold (default: 5.0)
- `Inp_Adaptive_Spread_Crypto` — Crypto (default: 50.0)

## What's NOT Adaptive
- **ATR gates** — User sets appropriate values in ZONE 2A
- **SL/TP distances** — Market-defined (PSAR/Swing/Fractal) or user-defined (Fixed/RR)
- **Cushions** — TF-based auto-calculation (see [TF-Based Cushions](README_EXIT_MANAGEMENT.md#tf-based-cushions))

## See Also
- [TF-Based Cushions](README_EXIT_MANAGEMENT.md#tf-based-cushions)
- [Exit Management](README_EXIT_MANAGEMENT.md)
- [Config Zones](README_CONFIG_ZONES.md#zone-3c-pair-specific-spread-limits)
