# AGENTS.md

## 1) Project Scope

- Project: `chainora-contracts`
- Primary goal: implement and validate Chainora ROSCA v1 smart contracts using Foundry.
- Non-goals:
- No frontend/backend app development in this repository.
- No production key management or custody logic in this repository.

## 2) Stack Snapshot

- Languages: Solidity (`^0.8.24`) and Foundry script/test Solidity.
- Frameworks/Tooling: Foundry (`forge`, `anvil`, `cast`), `forge-std`.
- Dependency management: git submodule (`lib/forge-std`).
- CI: GitHub Actions workflow at `.github/workflows/test.yml`.

## 3) Working Rules For Agents

- Plan first for multi-step changes, then implement and verify.
- Keep edits minimal and localized; avoid broad rewrites without explicit request.
- Do not change unrelated files.
- Do not run destructive git commands (`reset --hard`, force checkout, force push) unless explicitly requested.
- Preserve naming convention:
- Public/core protocol contracts use `Chainora*` prefix.
- Internal modules/libraries keep short names (`MembershipModule`, `Types`, `Errors`, etc.).
- Keep runtime behavior member-driven:
- Do not add public keeper fallback logic unless explicitly requested.
- Only active members should trigger pool runtime transitions.

## 4) MCP Servers (Required)

- Use `serena` MCP server to inspect codebase structure, symbol usage, and impact analysis before substantial edits.
- Use `context7` MCP server to validate external technical references (Foundry, Solidity patterns, standards, and library guidance).
- Treat these as default required tools for design/refactor/security-sensitive changes.
- If one MCP server is unavailable, state that clearly in your response and proceed with best local evidence.

## 5) Repository Layout And Boundaries

- Root folders:
- `src/`: production contracts.
- `script/`: deployment/configuration/create-pool scripts.
- `test/`: unit, integration, invariant-style tests and mocks.
- `lib/forge-std/`: Foundry test/script utility dependency.

- Contract boundaries:
- `src/governance/ChainoraProtocolTimelock.sol`: delayed governance execution and role-gated scheduling/execution/cancel.
- `src/core/ChainoraProtocolRegistry.sol`: protocol config registry (stablecoin + adapters), timelock-gated setters.
- `src/core/ChainoraRoscaFactory.sol`: pool creation via clone and pool implementation pointer management.
- `src/pool/ChainoraRoscaPool.sol` + `src/pool/modules/*`: pool state machine and member-facing runtime actions.
- `src/adapters/interfaces/*`: protocol-facing adapter interfaces only.
- `src/adapters/mocks/*`: test/local mocks; do not couple production flows to mock-only behavior.
- `src/libraries/*`: shared errors, events, types, clone utility, math, safe-transfer helpers.

- Import boundaries:
- Do not import `test/**` into `src/**`.
- Do not import adapter mocks from production contracts unless explicitly building test-only scaffolding.
- Keep governance/control-plane checks in timelock/registry/factory; avoid scattering admin logic across pool modules.

## 6) Commands

Run from repository root.

- Install dependencies:
- `git submodule update --init --recursive`
- Build:
- `forge build --sizes`
- Format check:
- `forge fmt --check`
- Format write:
- `forge fmt`
- Full tests:
- `forge test -vvv`
- Gas snapshot:
- `forge snapshot`
- Coverage summary:
- `forge coverage --report summary`
- Local chain for manual deploy testing:
- `anvil`

## 7) Deployment Script Inputs

Scripts are in `script/deploy/*.s.sol` and rely on environment variables.

- Common:
- `PRIVATE_KEY`
- Deploy core:
- `CHAINORA_MULTISIG`
- `CHAINORA_TIMELOCK_DELAY`
- Configure registry:
- `CHAINORA_REGISTRY`
- `CHAINORA_TIMELOCK`
- `CHAINORA_STABLECOIN`
- `CHAINORA_DEVICE_ADAPTER`
- `CHAINORA_REPUTATION_ADAPTER`
- `CHAINORA_STAKING_ADAPTER`
- Create pool:
- `CHAINORA_FACTORY`
- `CHAINORA_CONTRIBUTION_AMOUNT`
- `CHAINORA_TARGET_MEMBERS`
- `CHAINORA_PERIOD_DURATION`
- `CHAINORA_CONTRIBUTION_WINDOW`
- `CHAINORA_AUCTION_WINDOW`
- `CHAINORA_MAX_CYCLES`

## 8) Code Style And Patterns

- Prefer custom errors from `src/libraries/Errors.sol` over string reverts.
- Emit protocol events via shared `Events` definitions when state changes matter.
- Keep state-machine checks explicit (`InvalidState`, deadline checks, role/member checks).
- Use existing storage/module pattern in pool contracts; add new pool logic inside modules unless change is explicitly cross-cutting.
- Keep adapter integration behind interfaces from `src/adapters/interfaces`.
- Prefer small, testable functions and avoid introducing hidden side effects in core state transitions.

## 9) Testing Expectations

- Add or update tests for any behavior change.
- Place tests by scope:
- Unit: `test/unit/**`
- Integration flow: `test/integration/**`
- Invariant-style properties: `test/invariant/**`
- Before finalizing non-trivial changes, run:
- `forge fmt --check`
- `forge build --sizes`
- `forge test -vvv`
- `forge snapshot`

## 10) Data, Secrets, And Safety

- Never commit real private keys or secret RPC credentials.
- Use environment variables for script execution; do not hardcode secrets in scripts/tests.
- Treat timelock operation tuples (`target`, `value`, `data`, `predecessor`, `salt`) as immutable identifiers once scheduled.
- Do not bypass timelock-only setters in registry/factory when changing protocol config semantics.
- Escalate before making changes that alter fund movement, access control, or pause/default recovery behavior.

## 11) Delivery Format

- Summarize what changed and why.
- List validation commands actually run and outcomes.
- Call out assumptions, residual risks, and follow-up checks.
