# Pool Runtime Sync Migration Guide

## Purpose

This document summarizes the runtime integration changes introduced by the phase-local deadline and runtime sync refactor in `ChainoraRoscaPool`.

It is intended for:
- frontend teams updating pool screens, countdowns, and CTAs
- backend teams updating indexers, automation, polling jobs, and event consumers

This guide focuses only on pool runtime behavior. It does not change the deploy/admin CLI flow.

---

## Executive Summary

The pool keeps the same stored on-chain states:
- `PoolStatus`: `Forming`, `Active`, `Archived`
- `PeriodStatus`: `Collecting`, `Auction`, `PayoutOpen`, `Finalized`

The key integration changes are:
- runtime transitions are now orchestrated by a shared internal sync path
- `closeAuctionAndSelectRecipient()` and `finalizePeriod()` were removed from the public pool API
- `syncRuntime()` was added as the explicit sync-only entrypoint for active members
- runtime actions such as `contribute()`, `submitDiscountBid()`, and `claimPayout()` now auto-sync first
- deadlines are now phase-local instead of all being anchored to `period.startAt`
- extend vote now has a fixed `1 days` deadline
- `runtimeStatus()` was added as the new source of truth for frontend/backend derived runtime state

---

## Breaking API Changes

### Removed public functions

These public functions are no longer exposed by `ChainoraRoscaPool`:
- `closeAuctionAndSelectRecipient()`
- `finalizePeriod()`

Any client, service, or automation still calling them must be updated.

### Added public functions

These public functions were added:
- `syncRuntime()`
- `runtimeStatus()`

### Unchanged enums

No new pool state enums were introduced.

Applications must not invent new stored states such as `ArchiveReady` or `ExtendVoteExpired`. Those are now derived off-chain via `runtimeStatus()`.

---

## Runtime Behavior Changes

### 1. Deadlines are now phase-local

Previously, the runtime effectively treated the whole period as anchored to one timestamp:
- `contributionDeadline`
- `auctionDeadline`
- finalization timing

That made dead time between phases reduce the usable time of later phases.

Now each phase starts its own timer when the phase actually opens:
- `Collecting` starts at period open
- `Auction` starts only when the pool actually transitions into `Auction`
- `PayoutOpen` starts only when the pool actually transitions into `PayoutOpen`

### Practical effect

- `periodInfo().auctionDeadline` is now `0` until `Auction` actually opens
- payout finalization is no longer derived from `startAt + periodDuration`
- a period's real-world wall-clock length can now be longer than `periodDuration`

`periodDuration` is still configured on-chain, but is now used as:

```text
payoutWindow = periodDuration - contributionWindow - auctionWindow
```

The intent is that dead time does not reduce the runtime budget of `Auction` or `PayoutOpen`.

### 2. Runtime transitions can happen inside normal user actions

The pool now pre-syncs on active-member runtime actions:
- `syncRuntime()`
- `contribute()`
- `submitDiscountBid()`
- `claimPayout()`
- `markDefaultAndArchive()`
- `voteExtendCycle()`
- `archive()`

That means a single transaction can now:
- advance one or more phases
- emit transition-related events
- still complete the original user action in the same transaction

Examples:
- `submitDiscountBid()` can first sync `Collecting -> Auction`, then place the bid
- `claimPayout()` can first sync `Auction -> PayoutOpen`, then claim
- `contribute()` can first finalize the previous period, open the next period, then record the new contribution

Backend event consumers must no longer assume that phase changes only happen in dedicated transition transactions.

### 3. Default handling stays explicit

If the contribution deadline has passed and not all active members contributed:
- the stored period state remains `Collecting`
- the pool does not auto-archive
- the pool does not auto-open `Auction`
- `runtimeStatus().archiveReady` becomes `true`

Resolution is still explicit through:
- `markDefaultAndArchive(defaultedMember)`

### 4. Extend vote now has a fixed 1 day deadline

When a cycle completes and extend voting opens:
- `extendVoteOpen = true`
- `extendVoteDeadline = block.timestamp + 1 days`

The vote rules are:
- a `false` vote archives immediately
- unanimous `true` votes before the deadline start the next cycle
- if the deadline expires without unanimous `true`, the pool does **not** auto-archive
- `archive()` remains the explicit path after expiry

---

## New Source Of Truth: `runtimeStatus()`

The new `runtimeStatus()` view should be the default integration surface for runtime UX and off-chain automation decisions.

### Return fields

`runtimeStatus()` returns `Types.RuntimeStatusView`:

- `poolStatus`
- `currentCycle`
- `currentPeriod`
- `storedPeriodStatus`
- `startAt`
- `contributionDeadline`
- `auctionDeadline`
- `payoutDeadline`
- `cycleCompleted`
- `extendVoteOpen`
- `extendVoteDeadline`
- `allActiveContributed`
- `archiveReady`
- `auctionReady`
- `payoutReady`
- `finalizeReady`
- `extendVoteExpired`
- `unpaidActiveMembers`

### Why this matters

The stored state alone is no longer enough for UX decisions.

Example:
- stored `PeriodStatus` can still be `Collecting`
- but `runtimeStatus()` may show:
  - `archiveReady = true`, meaning an eligible caller can explicitly archive on default via `markDefaultAndArchive(defaultedMember)`
  - `auctionReady = true`, meaning the next active-member tx can open `Auction`
  - `payoutReady = true`, meaning the next active-member tx can materialize recipient selection and open `PayoutOpen`

---

## Frontend Migration Checklist

### Required changes

- Stop calling or referencing `closeAuctionAndSelectRecipient()` and `finalizePeriod()`
- Use `runtimeStatus()` as the default read path for runtime pages
- Stop deriving auction and payout countdowns from `period.startAt`
- Stop assuming `auctionDeadline` is known at period open
- Add support for `payoutDeadline`
- Add support for `extendVoteDeadline` and `extendVoteExpired`
- Treat `archiveReady`, `auctionReady`, `payoutReady`, and `finalizeReady` as view-level flags, not stored states

### Recommended UI mapping

- `storedPeriodStatus = Collecting` and `archiveReady = false`
  - show collecting countdown from `contributionDeadline`
  - show contribution progress
- `storedPeriodStatus = Collecting` and `auctionReady = true`
  - show that the next eligible transaction can open `Auction`
- `storedPeriodStatus = Collecting` and `payoutReady = true`
  - show that the next eligible transaction will skip the expired auction window, select the recipient, and open payout
- `storedPeriodStatus = Collecting` and `archiveReady = true`
  - disable bid CTA
  - show `unpaidActiveMembers`
  - show `markDefaultAndArchive` CTA if the user is eligible
- `storedPeriodStatus = Auction`
  - use `auctionDeadline` for countdown
- `storedPeriodStatus = Auction` and `payoutReady = true`
  - show that the next eligible transaction can materialize recipient selection and open payout
- `storedPeriodStatus = PayoutOpen`
  - use `payoutDeadline` for countdown
- `storedPeriodStatus = PayoutOpen` and `finalizeReady = true`
  - show that the next eligible transaction can finalize the period
- `extendVoteOpen = true` and `extendVoteExpired = false`
  - show extend vote countdown from `extendVoteDeadline`
- `extendVoteOpen = true` and `extendVoteExpired = true`
  - disable vote CTA
  - keep `archive()` CTA available

### Important frontend note

`periodInfo()` is still useful for base period data, but it is no longer sufficient for runtime UX on its own.

In particular:
- `auctionDeadline` is `0` before auction starts
- `periodInfo()` does not expose `payoutDeadline`
- `periodInfo()` does not expose derived flags such as `archiveReady`

If you need runtime CTAs or countdowns, prefer `runtimeStatus()`.

---

## Backend Migration Checklist

### Indexers and read models

- Stop deriving phase readiness from `startAt + periodDuration`
- Stop assuming `auctionDeadline = startAt + contributionWindow + auctionWindow`
- Start indexing or polling `runtimeStatus()` if you need derived runtime flags
- If your read model stores deadlines, add `payoutDeadline`
- Treat `archiveReady` and `extendVoteExpired` as derived runtime conditions, not enum values

### Event consumers

Transition events can now appear inside other user actions.

Do not assume:
- recipient selection only happens in a dedicated `closeAuctionAndSelectRecipient()` transaction
- period finalization only happens in a dedicated `finalizePeriod()` transaction

Examples of valid event sequences in one transaction now include:
- sync into `Auction`, then bid
- sync into `PayoutOpen`, then claim payout
- finalize old period, open new period, then contribute to the new period

If your consumer groups logic by function selector or transaction label, it must be updated.

### Automation and bots

If any backend worker previously called:
- `closeAuctionAndSelectRecipient()`
- `finalizePeriod()`

it must switch to:
- `syncRuntime()` for explicit phase materialization

Keep these constraints in mind:
- only active members can trigger runtime sync
- `syncRuntime()` never auto-archives
- expired extend votes still need an explicit `archive()` call
- missed contributions still need an explicit `markDefaultAndArchive(defaultedMember)` call

---

## Example Read Flow

### Frontend polling

```ts
const status = await publicClient.readContract({
  address: poolAddress,
  abi: poolAbi,
  functionName: 'runtimeStatus',
})
```

Use `status` to decide:
- which countdown to render
- whether the pool is blocked by an unpaid member
- whether the next eligible transaction can open auction, open payout, or finalize payout
- whether extend voting is still open or already expired

### Explicit sync call

```ts
await walletClient.writeContract({
  address: poolAddress,
  abi: poolAbi,
  functionName: 'syncRuntime',
})
```

Use `syncRuntime()` when the app wants a dedicated "advance runtime" action.

Do not use it as a replacement for `archive()` or `markDefaultAndArchive()`.

---

## QA Scenarios To Re-Test

Frontend and backend teams should re-test at least these scenarios:

1. `Collecting` finishes, everyone has contributed, and the first bid opens `Auction` and places the bid in one transaction.
2. `Collecting` remains stored on-chain past the auction window, and `runtimeStatus().payoutReady` turns `true` before the first sync.
3. `Auction` expires, and the first payout claim both opens `PayoutOpen` and claims in one transaction.
4. `PayoutOpen` expires, and the next period's first contribution finalizes the previous period and contributes to the next one in one transaction.
5. A member misses contribution, `storedPeriodStatus` stays `Collecting`, and `runtimeStatus().archiveReady` turns `true`.
6. Extend voting opens, expires after 1 day, and the pool still requires explicit `archive()`.

---

## Contract Surface Reference

Primary files for this refactor:
- [src/pool/ChainoraRoscaPool.sol](../src/pool/ChainoraRoscaPool.sol)
- [src/pool/IChainoraRoscaPool.sol](../src/pool/IChainoraRoscaPool.sol)
- [src/pool/modules/RuntimeSyncModule.sol](../src/pool/modules/RuntimeSyncModule.sol)
- [src/pool/modules/PoolStorage.sol](../src/pool/modules/PoolStorage.sol)
- [src/libraries/Types.sol](../src/libraries/Types.sol)

Runtime regression tests:
- [test/unit/pool/ChainoraRoscaPool.RuntimeSync.t.sol](../test/unit/pool/ChainoraRoscaPool.RuntimeSync.t.sol)
