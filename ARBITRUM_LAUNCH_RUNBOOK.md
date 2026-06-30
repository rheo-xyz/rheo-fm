# Arbitrum mainnet — WETH/USDC launch runbook

Step-by-step instructions for taking the live SizeFactory at
[`0x63CF5fc3dD8bc915056854053774FD28947Deb64`](https://arbiscan.io/address/0x63CF5fc3dD8bc915056854053774FD28947Deb64)
from "wired" to "first market live + Hypernative protection."

Every phase that touches on-chain state is split into either:
- **EOA broadcast** — the deployer signs and submits the tx directly via Foundry, or
- **Safe ceremony** — the script produces calldata for the team's Safe at `0x462B…c3a7`; signers approve in the web UI.

After each on-chain phase, **commit any address discoveries to `script/Networks.sol`** so the next phase has a single source of truth.

---

## 0. Status snapshot

| Phase | Item | State |
|---|---|---|
| 1.1 | `SizeFactory` proxy deployed | ✅ on-chain `0x63CF…Deb64` |
| 1.2 | Rheo impl + Vault impl + CollectionsManager wired | ✅ on-chain |
| 2a | `BorrowTokenVault` for USDC | ⏳ pending |
| 2b | `AaveAdapter` + `ERC4626Adapter` deployed | ⏳ pending |
| 2c | Adapters wired onto vault | ⏳ pending |
| 3 | `PriceFeed` (WETH/USDC) deployed | ⏳ pending |
| 3.1 | PriceFeed sub-contracts verified on Arbiscan | ⏳ pending |
| 5 | Market created via `createMarketRheo` | ⏳ pending |
| 6 | Market proxy verified on Arbiscan | ⏳ pending |
| **7** | **`HypernativePauser` contract deployed** | ⏳ **needs design + impl** |
| 8 | `PAUSER_ROLE` granted on factory to `HypernativePauser` | ⏳ pending |
| 9 | Hypernative monitoring configured (off-chain) | ⏳ pending |
| 10 | Smoke test: tiny WETH deposit | ⏳ pending |

26/26 fork-test assertions pass. v1.9 factory compatibility confirmed via `cast`.

---

## Pre-flight (do once before Phase 2a)

1. **Branch & build clean.** PR #13 is on `arbitrum-mainnet-deployment`. Make sure your working copy is on that branch and `forge build` is green.
2. **Environment.** Required env vars in `.env`:
   ```bash
   API_KEY_ALCHEMY=...
   API_KEY_ARBISCAN=...
   DEPLOYER_ADDRESS=0x...                         # funded EOA
   DEPLOYER_ACCOUNT=...                            # cast wallet keystore name
   SIGNER=0x...                                    # Ledger-backed Safe signer EOA
   LEDGER_PATH=m/44'/60'/0'/0/0
   OWNER=0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7
   TENDERLY_ACCOUNT_NAME=...
   TENDERLY_PROJECT_NAME=...
   TENDERLY_ACCESS_KEY=...
   ```
3. **Deployer ETH balance.** Send ~0.05 ETH to `$DEPLOYER_ADDRESS` on Arbitrum One — pad for Phase 2b (2 adapter deploys), Phase 3 (PriceFeed + 3 sub-contracts + Uniswap pool cardinality bump), Phase 6 (verify), Phase 7 (Hypernative pauser).
4. **Confirm v1.9 factory.** One-time sanity check:
   ```bash
   cast call 0x63CF5fc3dD8bc915056854053774FD28947Deb64 \
     "rheoImplementation()(address)" --rpc-url arbitrum-production
   ```
   Should return a non-zero address (currently `0x8adF4925556c99C0db977d7d32507394B28c858D`).
5. **Final dry run.** From the rheo-fm root:
   ```bash
   FOUNDRY_PROFILE=fork forge test --mc Arbitrum -vv
   ```
   Expect 26/26 passing. If anything regresses, stop and investigate before any on-chain step.

---

## Phase 2a — Safe creates the USDC `BorrowTokenVault`

**Who runs**: Safe ceremony.
**Why**: `createBorrowTokenVault` is admin-only on the factory; the Safe holds `DEFAULT_ADMIN_ROLE`.

1. Produce the calldata for the Safe UI:
   ```bash
   forge script script/ProposeSafeTxCreateBorrowVaultArbitrum.s.sol \
     --rpc-url arbitrum-production --sig "printCalldata()" -vvv
   ```
   The script first runs the F8 Aave reserve health checks (`getActive` / `!getPaused` / `!getFrozen` / `aTokenAddress != 0`) and the F9 duplicate-vault guard. If any of those fail, the script aborts loudly — **fix the cause before proceeding**.
2. Paste the printed `To` / `Value` / `Operation` / `Data` into the Safe UI's *New transaction → Contract interaction*. Signers approve.
3. After the Safe tx is mined, capture the vault address from the `CreateBorrowTokenVault(address)` event log on the SizeFactory tx. (Arbiscan → tx → Logs.)
4. **Update `script/Networks.sol`**:
   ```solidity
   // Was: address(0)
   contracts[ARBITRUM_MAINNET][Contract.RHEO_BORROW_VAULT_USDC] = 0x<new vault>;
   ```
   Commit, push to `arbitrum-mainnet-deployment`.
5. **Export for subsequent phases**:
   ```bash
   export BORROW_TOKEN_VAULT=0x<new vault>
   ```

---

## Phase 2b — Deploy `AaveAdapter` + `ERC4626Adapter`

**Who runs**: deployer EOA.
**Why**: Adapters take the vault address as a constructor arg. No admin role required.

```bash
forge script script/DeployBorrowVaultAdaptersArbitrum.s.sol \
  --rpc-url arbitrum-production \
  --sender $DEPLOYER_ADDRESS --account $DEPLOYER_ACCOUNT \
  --ffi --verify --broadcast -vvv
```

The script logs both addresses. Export them:
```bash
export AAVE_ADAPTER=0x<aaveAdapter>
export ERC4626_ADAPTER=0x<erc4626Adapter>
```

`--verify` should mark both contracts as Verified on Arbiscan automatically. If it doesn't (rare), re-verify manually:
```bash
forge verify-contract $AAVE_ADAPTER src/market/token/adapters/AaveAdapter.sol:AaveAdapter \
  --chain 42161 --etherscan-api-key $API_KEY_ARBISCAN \
  --constructor-args $(cast abi-encode "constructor(address)" $BORROW_TOKEN_VAULT) --watch
forge verify-contract $ERC4626_ADAPTER src/market/token/adapters/ERC4626Adapter.sol:ERC4626Adapter \
  --chain 42161 --etherscan-api-key $API_KEY_ARBISCAN \
  --constructor-args $(cast abi-encode "constructor(address)" $BORROW_TOKEN_VAULT) --watch
```

---

## Phase 2c — Safe wires the adapters onto the vault

**Who runs**: Safe ceremony (batched via `MultiSendCallOnly`).
**Why**: `setAdapter` and `setVaultAdapter` are owner-only on the vault.

```bash
forge script script/ProposeSafeTxWireBorrowVaultAdaptersArbitrum.s.sol \
  --rpc-url arbitrum-production --sig "printCalldata()" -vvv
```

The script prints two options:
- **Option A**: 3 separate `Call` transactions (paste into Safe UI's Contract interaction one at a time).
- **Option B** (recommended): 1 batched `DelegateCall` to `MultiSendCallOnly` (Safe UI's Transaction Builder → Custom data). Single signing ceremony for all 3 setters.

After execution, sanity-check the wiring:
```bash
# AAVE_ADAPTER_ID = bytes32("AaveAdapter")
cast call $BORROW_TOKEN_VAULT "getWhitelistedVaultAdapter(address)(address)" 0x0000000000000000000000000000000000000000 \
  --rpc-url arbitrum-production
```
Should return `$AAVE_ADAPTER`.

---

## Phase 3 — Deploy the WETH/USDC `PriceFeed`

**Who runs**: deployer EOA.
**Why**: pure contract deployment with constructor args from `Networks.sol`. The constructor internally deploys three sub-contracts (`ChainlinkSequencerUptimeFeed`, `ChainlinkPriceFeed`, `UniswapV3PriceFeed`) and may bump the Uniswap V3 pool's observation cardinality target.

```bash
forge script script/DeployPriceFeedArbitrum.s.sol \
  --rpc-url arbitrum-production \
  --sender $DEPLOYER_ADDRESS --account $DEPLOYER_ACCOUNT \
  --ffi --verify --broadcast -vvv
```

The script:
- Asserts the resulting `priceFeed.getPrice()` > 0 before exiting (catches a misconfigured oracle at deploy time).
- Logs all four addresses (PriceFeed proxy-less + 3 sub-contracts).

Export:
```bash
export PRICE_FEED=0x<priceFeed>
```

**Note on cardinality**: with `twapWindow = 15 min` and `averageBlockTime = 1 s`, the script requests `~1172` observation slots on the WETH/USDC 0.05% pool. The pool is one of the busiest on Arbitrum, so it likely already exceeds this; the constructor call is a no-op if so. Sanity:
```bash
cast call 0xC6962004f452bE9203591991D15f6b388e09E8D0 \
  "slot0()(uint160,int24,uint16,uint16,uint16,uint8,bool)" \
  --rpc-url arbitrum-production
```
Look at the 5th return value (`observationCardinality`). If < 1172, wait for swap activity to fill more slots before the fallback is queryable.

---

## Phase 3.1 — Verify PriceFeed sub-contracts on Arbiscan

**Who runs**: deployer EOA.
**Why**: `forge --verify` on Phase 3 only verifies the top-level `PriceFeed`. The three sub-contracts ship as unverified bytecode unless this follow-up runs.

```bash
forge script script/VerifyPriceFeedSubcontractsArbitrum.s.sol \
  --rpc-url arbitrum-production --sig "run()" --ffi -vvv
```

This reads `$PRICE_FEED`, derives each sub-contract address + its constructor args from the live PriceFeed's immutable getters, and invokes `forge verify-contract` for each via `vm.ffi`. After it exits, all three should be marked Verified on Arbiscan.

---

## Phase 5 — Safe creates the market

**Who runs**: Safe ceremony.
**Why**: `createMarketRheo` is admin-only on the factory.

```bash
forge script script/ProposeSafeTxDeployFirstMarketArbitrum.s.sol \
  --rpc-url arbitrum-production --sig "printCalldata()" -vvv
```

Script invariants enforced inside `printCalldata`:
- F4: factory at `RHEO_FACTORY` responds to `rheoImplementation()` (v1.9 ABI).
- F5: fee recipient is read from `contracts[block.chainid][Contract.RHEO_GOVERNANCE]` — no hardcoded duplicate.

Paste calldata into Safe UI → Contract interaction → sign. After execution, the market proxy address is in the `CreateMarket` event log on the SizeFactory tx.

```bash
export MARKET=0x<market proxy>
```

---

## Phase 6 — Verify the market proxy on Arbiscan

**Who runs**: deployer EOA.
**Why**: the market proxy is deployed *internally* by the factory, so Forge can't auto-verify it.

```bash
forge verify-contract $MARKET \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --chain 42161 --etherscan-api-key $API_KEY_ARBISCAN \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" \
    $(cast call 0x63CF5fc3dD8bc915056854053774FD28947Deb64 "rheoImplementation()(address)" --rpc-url arbitrum-production) \
    "0x") \
  --watch
```

(The `initData` arg encodes to `0x` because `createMarketRheo` initializes via a separate call after proxy deployment.)

---

## Phase 7 — Deploy `HypernativePauser` ⚠️ **needs impl**

**Who runs**: deployer EOA (after the contract is written + tested + reviewed).

### Status: NOT YET WRITTEN

No `HypernativePauser.sol` exists in `src/` yet. Before Phase 7 can run, the team needs to land:

1. `src/protection/HypernativePauser.sol` — minimal contract with shape:
   ```solidity
   contract HypernativePauser is Ownable2Step {
       ISizeFactory public immutable sizeFactory;
       mapping(address => bool) public pausers;

       event PauserSet(address indexed pauser, bool allowed);
       event PausedAll(address indexed caller, uint256 marketCount);

       error NotPauser();

       constructor(ISizeFactory _factory, address _initialOwner) Ownable(_initialOwner) {
           sizeFactory = _factory;
       }

       function setPauser(address pauser, bool allowed) external onlyOwner {
           pausers[pauser] = allowed;
           emit PauserSet(pauser, allowed);
       }

       function pauseAll() external {
           if (!pausers[msg.sender] && msg.sender != owner()) revert NotPauser();
           address[] memory markets = sizeFactory.getMarkets();
           for (uint256 i = 0; i < markets.length; i++) {
               IRheoAdmin(markets[i]).pause();
           }
           emit PausedAll(msg.sender, markets.length);
       }
   }
   ```
2. `script/DeployHypernativePauserArbitrum.s.sol` — EOA-broadcast deploy that:
   - Reads `RHEO_FACTORY` from `Networks.sol`.
   - Constructor args: `(sizeFactory, OWNER)` so the Safe owns it.
   - Logs the deployed address; user exports as `$HYPERNATIVE_PAUSER`.
3. `script/ProposeSafeTxConfigureHypernativePauserArbitrum.s.sol` — Safe ceremony that:
   - **First call**: `hypernativePauser.setPauser(hypernativeBotAddress, true)` (Hypernative provides their bot address).
   - **Second call**: `sizeFactory.grantRole(PAUSER_ROLE, hypernativePauser)` (PAUSER_ROLE is propagated to all markets via the factory-fallback in `Rheo.sol::onlyRoleOrRheoFactoryHasRole`).
   - Batched via MultiSendCallOnly. Same `run()` + `printCalldata()` pattern as other Safe-tx scripts.
4. `test/fork/ArbitrumHypernativePauser.t.sol` — fork test that:
   - Sets up the market (reuses `ArbitrumLiveMarketDeploymentForkTest`'s helpers).
   - Deploys `HypernativePauser`.
   - Grants `PAUSER_ROLE` to it on the factory via prank.
   - Calls `pauseAll()` as the Hypernative bot.
   - Asserts every market's `paused()` returns `true`.
5. `test/fork/ArbitrumHypernativePauser.t.sol` — adversarial tests:
   - Non-pauser caller reverts `NotPauser`.
   - Owner can `pauseAll` even without explicit `setPauser`.
   - Disabling a pauser via `setPauser(addr, false)` revokes their access.

Once those land in a follow-up PR, Phase 7 deploy is:
```bash
forge script script/DeployHypernativePauserArbitrum.s.sol \
  --rpc-url arbitrum-production \
  --sender $DEPLOYER_ADDRESS --account $DEPLOYER_ACCOUNT \
  --ffi --verify --broadcast -vvv

export HYPERNATIVE_PAUSER=0x<pauser>
```
And commit the address into `Networks.sol` as a new `Contract.RHEO_HYPERNATIVE_PAUSER` enum entry.

---

## Phase 8 — Safe grants `PAUSER_ROLE` to the pauser + registers the Hypernative bot

**Who runs**: Safe ceremony (batched, follows the Phase 1.2 / 2c pattern).

```bash
forge script script/ProposeSafeTxConfigureHypernativePauserArbitrum.s.sol \
  --rpc-url arbitrum-production --sig "printCalldata()" -vvv
```

This batches:
1. `hypernativePauser.setPauser(hypernativeBotAddress, true)` — whitelist Hypernative's automated trigger account.
2. `sizeFactory.grantRole(PAUSER_ROLE, hypernativePauser)` — propagates to every current and future market via the factory-fallback in `Rheo.onlyRoleOrRheoFactoryHasRole`.

After execution, sanity-check both:
```bash
# pauser registered
cast call $HYPERNATIVE_PAUSER "pausers(address)(bool)" <hypernative bot addr> --rpc-url arbitrum-production
# factory grants pauser role
cast call 0x63CF5fc3dD8bc915056854053774FD28947Deb64 \
  "hasRole(bytes32,address)(bool)" \
  $(cast keccak "PAUSER_ROLE") $HYPERNATIVE_PAUSER --rpc-url arbitrum-production
```

Both should return `true`.

---

## Phase 9 — Hypernative monitoring (off-chain)

**Who runs**: Hypernative + ops.

In the Hypernative dashboard:
1. Add Arbitrum One.
2. Register the new market proxy (`$MARKET`) and the `HypernativePauser` (`$HYPERNATIVE_PAUSER`) as monitored contracts.
3. Configure the **action** to be a transaction to `$HYPERNATIVE_PAUSER` invoking `pauseAll()` from the bot signer that was whitelisted in Phase 8.
4. Set the **detection rules** the team has agreed on (price manipulation, abnormal borrow patterns, etc.).
5. Run Hypernative's dry-run / simulation against a recent Arbitrum block to confirm the bot signer can successfully call `pauseAll()` end-to-end.

This is the only step in this runbook that's done outside Foundry.

---

## Phase 10 — Smoke test

**Who runs**: deployer EOA (or any volunteer EOA with a few WETH + USDC to spare).

1. Wrap a small amount of ETH to WETH on Arbitrum (e.g., 0.01 WETH).
2. Deposit it as collateral:
   ```bash
   cast send $MARKET "deposit((address,uint256,address))" \
     "($WETH_ADDR,10000000000000000,$DEPLOYER_ADDRESS)" \
     --rpc-url arbitrum-production --account $DEPLOYER_ACCOUNT
   ```
3. Confirm balance increased:
   ```bash
   cast call $MARKET "getUserView(address)" $DEPLOYER_ADDRESS --rpc-url arbitrum-production
   ```
4. Withdraw it back to confirm round-trip works.
5. (Optional) Repeat with USDC to confirm svUSDC mint/burn through Aave.

If both round-trips succeed, the market is live and functioning.

---

## Post-launch ops checklist

After Phase 10:

- [ ] Tag the commit on `arbitrum-mainnet-deployment` (e.g., `v1.9-arbitrum-launch`).
- [ ] Merge `arbitrum-mainnet-deployment` into `main`.
- [ ] File a public-facing announcement (Discord, Twitter) with the market proxy address.
- [ ] Update the rheo-fm and rheo-solidity READMEs to list Arbitrum in the supported chains table.
- [ ] Commit deployment artifacts (`broadcast/*Arbitrum*/42161/run-latest.json`) so the audit trail is reproducible.
- [ ] File a separate issue tracking the L2-sequencer-guard gap on v1.7/v1.8 oracle types before any non-WETH/USDC market is launched on Arbitrum (see the team-Slack thread).
- [ ] Confirm Hypernative is actively monitoring (test alert firing → see action proposed → manually decline so the market stays live).

---

## Emergency procedures

If something goes wrong mid-launch:

| Symptom | Action |
|---|---|
| Phase 2a / 2c / 5 / 8 Safe tx fails simulation in Tenderly | **Do not sign.** Re-run `--sig "printCalldata()"`, copy fresh calldata, paste into the same Safe tx, re-simulate. If still failing, post the Tenderly URL to the team channel. |
| Phase 3 PriceFeed returns 0 or a clearly wrong price | The deploy script will already have reverted. If somehow it lands, **do not run Phase 5**. Investigate `getPrice()` directly via `cast call $PRICE_FEED "getPrice()(uint256)"`. |
| Phase 7 pauser deployed but Phase 8 not yet executed | Markets are unprotected. Either expedite Phase 8 or grant `PAUSER_ROLE` to a manual key on the factory temporarily via a one-off Safe tx, then revoke after Phase 8 lands. |
| Hypernative bot needs to fire | Trigger `pauseAll()` directly via the Hypernative dashboard. To unpause individual markets afterward, Safe calls `Rheo.unpause()` on each. There is intentionally no `unpauseAll()` — recovery is manual per market to force a human review. |
| Live oracle goes haywire post-launch | The PriceFeed's `twapWindow` is immutable. To swap oracle: deploy new `PriceFeed` (EOA), Safe calls `market.updateConfig("priceFeed", newAddr)`. Lands atomically in one block. |

---

## Reference addresses

| Item | Address |
|---|---|
| Safe (governance + fee recipient) | `0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7` |
| SizeFactory proxy | `0x63CF5fc3dD8bc915056854053774FD28947Deb64` |
| Rheo implementation (Phase 1.2) | `0x8adF4925556c99C0db977d7d32507394B28c858D` |
| WETH | `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1` |
| USDC (native) | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` |
| Aave v3 Pool | `0x794a61358D6845594F94dc1DB02A252b5b4814aD` |
| Chainlink ETH/USD | `0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612` |
| Chainlink USDC/USD | `0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3` |
| Chainlink L2 sequencer uptime | `0xFdB631F5EE196F0ed6FAa767959853A9F217697D` |
| Uniswap V3 WETH/USDC 0.05% pool | `0xC6962004f452bE9203591991D15f6b388e09E8D0` |
