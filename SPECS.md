# Rheo Fixed-Maturity Specs

## Overview

This document is the single source of truth for Rheo fixed-maturity markets.
It consolidates all current, meaningful requirements and implementation guidance.

High-level goals:
- Fixed-maturity offers only: limit orders are `{maturities[], aprs[]}` with strictly increasing
  maturities and exact-match APR lookup (no interpolation).
- Allowed maturities are governance-controlled and enforced via `riskConfig.maturities`.
- `minTenor`/`maxTenor` bounds remain and apply via `tenor = maturity - block.timestamp`.
- Market orders accept `maturity`; existing positions use their stored `dueDate`.
- Yield-curve interpolation and variable pool borrow-rate paths are removed.
- Collections copy configs remain relative and require exact maturity matching.

---

## Fixed-Maturity Offers Spec

### Core Feature
- Limit orders use fixed-maturity offers: `maturities[]` + `aprs[]`.
- Maturities are strictly increasing and have exact-match APR lookup (no interpolation).
- Allowed maturities are governance-controlled via `riskConfig.maturities`.
- The protocol enforces inversion/consistency checks per maturity only and does not enforce
  minimum maturity spacing or cross-maturity curve constraints. Governance should set the
  allowlist with appropriate spacing (or accept the tradeoffs) to avoid unintended
  cross-maturity spread/arbitrage opportunities.
- Limir orders and market orders must use maturities that are in the allowlist, which means exits revert if a maturity removed from allowlist
- An empty `riskConfig.maturities` allowlist is permitted and disables market orders via `INVALID_MATURITY`.

### Bounds and Validation
- Keep relative bounds: `minTenor`/`maxTenor` remain and are applied via
  `tenor = maturity - block.timestamp` for validation and fee math.
- `addMaturity` validates non-past and min/max tenor at update time.
- Because tenor is relative (remaining time-to-maturity), allowlisted maturities can drift
  out of range over time, and governance updates to `minTenor`/`maxTenor` can also make some
  allowlisted maturities immediately untradeable (reverting with `MATURITY_OUT_OF_RANGE`)
  without removing them from the allowlist. This is an intentional trade-off; governance
  should pre-check the allowlist before updating bounds and use explicit `removeMaturity`
  when deprecating maturities for transparency.
- Error semantics:
  - Use `INVALID_MATURITY` when a maturity is in-range but not on the governance allowlist.
  - Use `MATURITY_OUT_OF_RANGE` for bounds violations (min/max tenor checks).
- If a maturity is removed from the allowlist, market exits must revert, but repayment and
  standard liquidation must still work for existing positions.

### Market Orders
- Market orders (`BuyCreditMarket`, `SellCreditMarket`) accept `maturity`.
- `LiquidateWithReplacement` is deprecated and removed; only standard liquidation remains.
- For existing credit positions, ignore input maturity and use `debtPosition.dueDate` for
  pricing/validation. This is the same behavior as Rheo core.
- Exiting existing positions must still validate `debtPosition.dueDate` against the allowlist;
  if a maturity is removed, market exits must revert.
- Exiting existing positions also applies the current `minTenor`/`maxTenor` bounds to the
  remaining tenor (`debtPosition.dueDate - block.timestamp`). This means secondary market
  exits can become unavailable over time (as positions approach maturity) or after governance
  updates to `minTenor`/`maxTenor`, even if the position was valid at origination.
- Tenor is used only for pricing/fees (computed from maturity).
- Known limitation: `BuyCreditMarket`/`SellCreditMarket` events intentionally emit
  caller-supplied maturity/borrower inputs even when exits use the position's effective
  `dueDate`/borrower.

### Limit Orders
- Limit order actions store fixed-maturity offers and emit maturities + APRs.
- Exact-match maturity lookup only.
- When setting a limit order, the system allows only a subset of the maturities allowlist.

### Collections and Copies
- Collections copy configs use relative `minTenor`/`maxTenor` bounds.
- Collections require exact-match maturities (no fallback to intermediate tenors).
- Rate provider gating remains unchanged.

### Yield Curve and Variable Pool Borrow Rate
- Yield-curve interpolation is removed.
- Variable pool borrow rate paths are removed.

### Tests and Scripts
- Test helpers use tenors converted to absolute maturities and reference `riskConfig.maturities`.
- Limit/market order tests use risk-config maturities and precomputed maturities before
  `expectRevert` to avoid false positives.
- Collections tests avoid `expectRevert` ordering issues with maturity lookups.
- Scripts (limit/market/simulations) use maturities.

### Deployment Notes
- Clean-slate deployment only; no storage migration required.
- Off-chain indexer/matching must supply maturities and expect exact matches.

---
