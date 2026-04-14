# AGENTS.md

## 1) Project Scope

- Project: `chainora-contracts`
- Primary goal: implement and validate Chainora ROSCA v1 smart contracts using Foundry.
- Non-goals:
- No frontend/backend app development in this repository.
- No production key management or custody logic in this repository.

## 2) Stack Snapshot

- Languages: Solidity (`^0.8.24`) and JavaScript (Node.js 24+ ESM for the wizard CLI).
- Frameworks/Tooling: Foundry (`forge`, `anvil`, `cast`), `forge-std`, OpenZeppelin Contracts for standardized primitives/utilities, and a Node.js wizard CLI under `tooling/chainora-cli/`.
- Dependency management: git submodule (`lib/forge-std`).
- CI: GitHub Actions workflow at `.github/workflows/test.yml`.

## 3) Working Rules For Agents

- Plan first for multi-step changes, then implement and verify.
- Keep edits minimal and localized; avoid broad rewrites without explicit request.
- Do not change unrelated files.
- Do not run destructive git commands (`reset --hard`, force checkout, force push) unless explicitly requested.
- Deploy/admin tooling path is the JavaScript wizard CLI only; do not add new Solidity deploy/admin scripts.
- Any new admin action, deployable contract, deploy flow, or persistent env key must update all of:
- `tooling/chainora-cli/` wizard menu
- CLI action/service validation
- `.env.example`
- `README.md`
- CLI tests under `tooling/chainora-cli/test`
- Prefer battle-tested OpenZeppelin implementations for standardized concerns (for example ERC20 helpers, access control primitives, clone helpers, guards, and utility libraries) instead of introducing bespoke versions.
- If protocol-specific behavior requires custom logic around a standardized primitive, wrap or extend the OpenZeppelin building block narrowly and document why direct reuse is insufficient.
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
- `test/`: unit, integration, invariant-style tests and mocks.
- `tooling/chainora-cli/`: cross-platform wizard CLI for deploy/admin/timelock operations.
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
- `npm install`
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
- Wizard CLI:
- `npm run chainora`
- `npm run chainora -- --rpc-url <RPC_URL>`
- `npm run chainora -- --dry-run`
- CLI lint:
- `npm run lint`
- CLI typecheck:
- `npm run typecheck`
- CLI tests:
- `npm test`

## 7) Persistent CLI Env Inputs

The JavaScript wizard CLI reads persistent values from `.env`.

- Common:
- `RPC_URL`
- `ETH_RPC_URL`
- `PRIVATE_KEY`
- Timelock bootstrap defaults:
- `CHAINORA_MULTISIG`
- `CHAINORA_TIMELOCK_DELAY`
- `CHAINORA_PROPOSERS`
- `CHAINORA_EXECUTORS`
- `CHAINORA_CANCELLERS`
- Persistent deployed addresses:
- `CHAINORA_TIMELOCK`
- `CHAINORA_REGISTRY`
- `CHAINORA_DEVICE_ADAPTER`
- `CHAINORA_POOL_IMPLEMENTATION`
- `CHAINORA_FACTORY`
- Local-only stablecoin defaults:
- `CHAINORA_TEST_STABLECOIN`
- `CHAINORA_TEST_STABLECOIN_OWNER`
- `CHAINORA_TEST_STABLECOIN_INITIAL_SUPPLY`
- Note:
- The wizard auto-syncs successful deploys into the persistent address keys above.
- The CLI can prompt for `PRIVATE_KEY` at runtime if it is omitted from `.env`.

## 8) Code Style And Patterns

- Prefer custom errors from `src/libraries/Errors.sol` over string reverts.
- Emit protocol events via shared `Events` definitions when state changes matter.
- Keep state-machine checks explicit (`InvalidState`, deadline checks, role/member checks).
- Prefer OpenZeppelin's audited implementations when the required behavior is already standardized; do not reimplement common helpers such as safe ERC20 transfers, clone factories, access control mixins, reentrancy guards, pausability, signature verification, or math/address utilities without a clear protocol-specific reason.
- When replacing or extending an in-repo helper that overlaps with OpenZeppelin, keep the custom layer thin and focused on Chainora-specific rules rather than duplicating the underlying standardized logic.
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
- Use environment variables for CLI execution; do not hardcode secrets in contracts, tests, or CLI sources.
- Treat timelock operation tuples (`target`, `value`, `data`, `predecessor`, `salt`) as immutable identifiers once scheduled.
- Do not bypass timelock-only setters in registry/factory when changing protocol config semantics.
- Escalate before making changes that alter fund movement, access control, or pause/default recovery behavior.
- `CreatePool` tooling has been intentionally removed; if it returns later, implement it in the wizard CLI instead of restoring Solidity scripts.

## 11) Delivery Format

- Summarize what changed and why.
- List validation commands actually run and outcomes.
- Call out assumptions, residual risks, and follow-up checks.
