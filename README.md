## Chainora ROSCA Contracts (Foundry)

This repository contains the Chainora ROSCA v1 smart-contract architecture.

### Key design choices

- Control-plane contracts use an upgrade-ready pattern (`ChainoraProtocolRegistry`, `ChainoraRoscaFactory`, timelock-governed upgrades).
- Pool instances are deployed via minimal proxies (clones) from `ChainoraRoscaFactory`.
- Runtime is member-driven: only active pool members can call period transition functions.
- External integrations (device verification, reputation snapshots, staking) are adapter-based.

### Main contracts

- `src/core/ChainoraProtocolRegistry.sol`
- `src/core/ChainoraRoscaFactory.sol`
- `src/pool/ChainoraRoscaPool.sol`
- `src/governance/ChainoraProtocolTimelock.sol`

### Adapters

- `src/adapters/interfaces/IChainoraDeviceAdapter.sol`
- `src/adapters/interfaces/IChainoraReputationAdapter.sol`
- `src/adapters/interfaces/IChainoraStakingAdapter.sol`

Mock adapters are available in `src/adapters/mocks` for tests and local simulation.

### Scripts

- `script/deploy/DeployCore.s.sol`
- `script/deploy/ConfigureRegistry.s.sol`
- `script/deploy/CreatePool.s.sol`

### Tests

- Unit tests: `test/unit`
- Integration tests: `test/integration`
- Invariant-oriented tests: `test/invariant`

### Local commands

```bash
forge fmt --check
forge build --sizes
forge test -vvv
forge test --match-path test/invariant/* -vvv
forge snapshot
forge coverage --report summary
```
