# rheo-fm

<img src="./logo.PNG" width="300" alt="Logo"/>

Rheo fixed-maturity markets. SPECS.md is the single source of truth.

## Specs

- Fixed-maturity offers only: `maturities[]` + `aprs[]`, strictly increasing, exact-match APR lookup.
- Allowed maturities are governance-controlled via `riskConfig.maturities`.
- `minTenor`/`maxTenor` validation uses `tenor = maturity - block.timestamp`.
- Market orders accept `maturity`; existing positions price on `debtPosition.dueDate`.
- Collections copy configs are relative and require exact maturity matches.
- Yield-curve interpolation and variable pool borrow rate paths are removed.

See `SPECS.md` for details.

## Test

```bash
forge install
forge test
```
