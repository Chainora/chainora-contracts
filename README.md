## Chainora ROSCA Contracts

This repository contains the Chainora ROSCA v1 smart contracts plus a cross-platform JavaScript wizard CLI for deploy and timelock admin operations.

### Key design choices

- Control-plane contracts use an upgrade-ready pattern (`ChainoraProtocolRegistry`, `ChainoraRoscaFactory`, timelock-governed upgrades).
- Pool instances are deployed via minimal proxies (clones) from `ChainoraRoscaFactory`.
- Runtime is member-driven: only active pool members can call period transition functions.
- Pool formation does not escrow upfront contributions; members start paying when period 1 opens.
- A missed contribution archives the pool immediately, and contributors from the interrupted period can claim refunds.
- External integrations (device verification, reputation snapshots, staking) are adapter-based.
- Deploy and admin tooling now lives in `tooling/chainora-cli/`; Solidity deploy/admin scripts are no longer part of the repo workflow.

### Main contracts

- `src/core/ChainoraProtocolRegistry.sol`
- `src/core/ChainoraRoscaFactory.sol`
- `src/pool/ChainoraRoscaPool.sol`
- `src/governance/ChainoraProtocolTimelock.sol`

### Tooling

- Contract build and tests: Foundry (`forge`)
- Deploy/admin wizard: Node.js CLI at `tooling/chainora-cli/`
- CLI entrypoint: `npm run chainora`

### Setup

1. Install Foundry dependencies:
   - `git submodule update --init --recursive`
2. Use Node.js `24+`, then install Node dependencies:
   - `npm install`
3. Build artifacts before using the wizard:
   - `forge build --sizes`
4. Copy `.env.example` to `.env` and set at least:
   - `RPC_URL`
   - `ETH_RPC_URL`
   - optionally `PRIVATE_KEY`

### Wizard CLI

Run the wizard:

```bash
npm run chainora
```

Override RPC or use dry-run:

```bash
npm run chainora -- --rpc-url http://23.94.63.207:8545
npm run chainora -- --dry-run
```

The CLI contains three branches:

- `Deploy`
  - `Bootstrap Core`
- `Deploy Timelock`
- `Deploy Registry`
- `Deploy Device Adapter`
- `Deploy Reputation Adapter`
- `Deploy Pool Implementation`
- `Deploy Factory`
- `Deploy ChainoraTestUSD`
- `Admin`
  - `Registry > setStablecoin | setDeviceAdapter | setReputationAdapter | setStakingAdapter`
  - `Factory > setRegistry | setPoolImplementation`
  - `Device Adapter > setTrustVerifier | revokeUser`
  - `Reputation Adapter > setTrustVerifier`
- `Timelock Utilities`
  - `Inspect Operation`
  - `Cancel Operation`

The wizard is keyboard-first and defaults are sourced from `.env`, so operators can usually keep pressing `Enter`.

### Persistent Environment Values

Keep only long-lived values in `.env`:

- `RPC_URL`
- `ETH_RPC_URL`
- `PRIVATE_KEY` if you do not want the CLI to prompt at runtime
- `CHAINORA_MULTISIG`
- `CHAINORA_TIMELOCK_DELAY`
- `CHAINORA_PROPOSERS`
- `CHAINORA_EXECUTORS`
- `CHAINORA_CANCELLERS`
- `CHAINORA_TIMELOCK`
- `CHAINORA_REGISTRY`
- `CHAINORA_DEVICE_ADAPTER`
- `CHAINORA_REPUTATION_ADAPTER`
- `CHAINORA_POOL_IMPLEMENTATION`
- `CHAINORA_FACTORY`
- `CHAINORA_TEST_STABLECOIN`
- `CHAINORA_TEST_STABLECOIN_OWNER`
- `CHAINORA_TEST_STABLECOIN_INITIAL_SUPPLY`

Successful deploys auto-sync the relevant persistent addresses into `.env`. Some admin execute flows can optionally sync updated addresses as well.

### Production Flow

1. Run `forge build --sizes`.
2. Run `npm run chainora`.
3. Choose `Deploy` and either:
   - run `Bootstrap Core` for a fresh environment, or
   - deploy individual contracts one by one.
4. Use `Admin` to schedule and execute timelock-managed updates such as:
   - setting the stablecoin
   - switching `deviceAdapter`
   - switching `reputationAdapter`
   - switching `poolImplementation`
5. Use `Timelock Utilities` to inspect or cancel pending operations when needed.

### Reputation scoring flow

- Contracts only store and verify reputation scores; they do not calculate score deltas onchain.
- Backend services can discover completed pools from `ChainoraPoolArchived()` and backfill that pool's event history to compute final score changes.
- After computing final scores offchain, a trusted verifier signs a batch update and a relayer submits it to `ChainoraReputationAdapter`.

### Current Tooling Gap

- `CreatePool` has been intentionally removed from repo tooling in this round.
- Smart contracts still expose `createPool(Types.PoolConfig)`, but there is currently no wizard or script wrapper for pool creation in this repository.
- If pool creation tooling returns later, it must be added to the JavaScript wizard CLI instead of reintroducing Solidity scripts.

### Tests

- Foundry contract tests:
  - `forge test -vvv`
- Wizard CLI tests:
  - `npm test`

### Local commands

```bash
forge fmt --check
forge build --sizes
forge test -vvv
forge snapshot
npm run lint
npm run typecheck
npm test
```
