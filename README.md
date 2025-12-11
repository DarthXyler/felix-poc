# Felix – Oracle Failure Shutdown PoC

This PoC runs entirely in Foundry's local test environment.  
It does not interact with mainnet, or any external oracle.

This repository contains a Foundry test that reproduces an oracle-failure bug
in Felix’s `HLPriceFeed` and shows that:

- `BorrowerOperations` enters temporary shutdown after an oracle failure, but  
- other modules (e.g. `TroveManager`) keep operating on a frozen `lastGoodPrice`.

The issue is **protocol-side logic**, not “incorrect data supplied by a third-party oracle”.
We simulate an oracle failure locally by overwriting the Hyperliquid `SYSTEM_CONTRACT`
address with a reverting mock.

## Files

- `poc/ShutdownOracleFailureBypass.t.sol`

## How to run

From the repo root:

```bash
forge test -vv --match-contract ShutdownOracleFailureBypassTest
