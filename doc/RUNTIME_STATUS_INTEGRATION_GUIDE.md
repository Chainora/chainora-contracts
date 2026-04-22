# Runtime Status Integration Guide

## Purpose

This document is the source of truth for integrating with `runtimeStatus()` after the canonical runtime timeline and realtime payout projection refactor in `ChainoraRoscaPool`.

It is intended for:
- frontend teams building pool screens, countdowns, badges, timelines, and call-to-action buttons
- backend teams building indexers, pollers, notification services, dashboards, and automations
- QA teams validating all meaningful runtime scenarios for the current period

If this document conflicts with older runtime-sync notes, prefer this guide for:
- `runtimeStatus()`
- `syncAction`
- canonical deadlines
- payout projection semantics

---

## Executive Summary

`runtimeStatus()` is now the primary read model for the current active period.

The key ideas are:
- the current period is evaluated against a canonical timeline anchored to `startAt`
- `storedPeriodStatus` still reflects the actual on-chain stored phase
- `syncAction` tells clients what phase transition is currently materializable by an active member transaction
- `projectedRecipient`, `projectedDiscount`, and `projectedPayoutAmount` provide a best-effort realtime payout preview

The most important distinction is:
- `storedPeriodStatus` is storage truth
- `syncAction` is transition truth
- payout projection is UI/backend preview data, not always a finalized on-chain outcome

---

## Core Concepts

### 1. What `startAt` means

`startAt` is the timestamp when the current period was opened by `_openPeriod()`.

It is the canonical anchor for all period timing:
- `contributionDeadline = startAt + contributionWindow`
- `auctionDeadline = startAt + contributionWindow + auctionWindow`
- `payoutDeadline = startAt + periodDuration`
- `payoutWindow = periodDuration - contributionWindow - auctionWindow`

Important notes:
- `payoutWindow` is a duration
- `payoutDeadline` is an absolute timestamp
- the invariant `periodDuration > contributionWindow + auctionWindow` still applies

### 2. Stored timeline vs canonical timeline

There are two related but different views of the current period.

Stored timeline:
- `storedPeriodStatus`
- `periodInfo().auctionDeadline`
- `periodInfo().recipient`
- `periodInfo().payoutAmount`

Canonical / derived timeline:
- `runtimeStatus().contributionDeadline`
- `runtimeStatus().auctionDeadline`
- `runtimeStatus().payoutDeadline`
- `runtimeStatus().syncAction`
- `runtimeStatus().projectedRecipient`

Meaning:
- stored values only change when a real transaction materializes a phase
- canonical values let clients understand what phase should be treated as effective right now, even before storage has been advanced

### 3. What `syncAction` means

`syncAction` tells you what the contract can materialize next if an active member sends a runtime-driving transaction now.

It is not a new stored phase.

At any given read, it has exactly one value:
- `None`
- `ArchiveReady`
- `AuctionReady`
- `PayoutReady`
- `FinalizeReady`

Frontend and backend code should use `syncAction` as the single readiness signal for the current period.

### 4. What payout projection means

`projectedRecipient` is a payout preview for the current period.

It is resolved as follows:
- if `period.recipient != address(0)`, return the actual selected on-chain recipient
- else if a `bestBidder` exists, project that bidder as the recipient
- else if all active members have contributed, choose the eligible member with the highest current live reputation
- else return `address(0)` so the projection can be hidden

Important implications:
- projection is best-effort preview data
- in no-bid fallback mode, it uses live reputation at read time
- when payout is actually opened, the contract may snapshot reputation and lock the final recipient using that snapshot
- therefore a projected fallback recipient may differ from the eventual finalized recipient if reputation changes before payout is materialized

---

## API Reference

`runtimeStatus()` returns `Types.RuntimeStatusView`:

```solidity
struct RuntimeStatusView {
    PoolStatus poolStatus;
    uint256 currentCycle;
    uint256 currentPeriod;
    PeriodStatus storedPeriodStatus;
    RuntimeSyncAction syncAction;
    uint64 startAt;
    uint64 contributionDeadline;
    uint64 auctionDeadline;
    uint64 payoutDeadline;
    bool cycleCompleted;
    bool extendVoteOpen;
    uint64 extendVoteDeadline;
    bool allActiveContributed;
    address projectedRecipient;
    uint256 projectedDiscount;
    uint256 projectedPayoutAmount;
    address[] unpaidActiveMembers;
}
```

### Enum values

#### `PoolStatus`

| Value | Meaning |
| --- | --- |
| `0` | `Forming` |
| `1` | `Active` |
| `2` | `Archived` |

#### `PeriodStatus`

| Value | Meaning |
| --- | --- |
| `0` | `Collecting` |
| `1` | `Auction` |
| `2` | `PayoutOpen` |
| `3` | `Finalized` |

#### `RuntimeSyncAction`

| Value | Meaning |
| --- | --- |
| `0` | `None` |
| `1` | `ArchiveReady` |
| `2` | `AuctionReady` |
| `3` | `PayoutReady` |
| `4` | `FinalizeReady` |

---

## Field-by-Field Semantics

| Field | Recommended use | Important note |
| --- | --- | --- |
| `poolStatus` | Top-level pool gating | Always evaluate this first |
| `currentCycle` | Detect whether the pool has become active | If `0`, there is no active runtime yet |
| `currentPeriod` | Identify the current active period | If `0`, do not render period runtime UI |
| `storedPeriodStatus` | Display storage truth, diagnostics, and historical context | Not sufficient by itself for current runtime UX |
| `syncAction` | Single readiness source for phase materialization | Use this before relying on `storedPeriodStatus` for display |
| `startAt` | Canonical anchor for current period timing | All current-period countdowns should be derived from this timeline |
| `contributionDeadline` | Collecting countdown | Canonical value for the current period |
| `auctionDeadline` | Auction countdown | May be meaningful before auction has been materialized in storage |
| `payoutDeadline` | End-of-period countdown | Always `startAt + periodDuration` |
| `cycleCompleted` | Detect transition from period flow to cycle-end flow | If `true`, switch to extend/archive UX |
| `extendVoteOpen` | Detect whether cycle extension voting is active | Only meaningful when `cycleCompleted = true` |
| `extendVoteDeadline` | Extend-vote countdown | Clients derive expiry by comparing to current time |
| `allActiveContributed` | Contribution-progress state and projection gating | If `false`, payout projection must be hidden |
| `projectedRecipient` | Recipient preview | `address(0)` means "projection hidden", not "no possible recipient exists" |
| `projectedDiscount` | Discount preview | `0` means no winning bid is currently projected or projection is hidden |
| `projectedPayoutAmount` | Payout amount preview | `0` when projection is hidden; may also be `0` for an invalid oversized bid preview |
| `unpaidActiveMembers` | Default handling UI and notifications | Most important while `storedPeriodStatus = Collecting` |

---

## Recommended Frontend Evaluation Order

Clients should derive display state in this order:

1. `poolStatus`
2. `currentCycle` and `currentPeriod`
3. `cycleCompleted` and `extendVoteOpen`
4. `syncAction`
5. `storedPeriodStatus`
6. payout projection fields

Why:
- if you start from `storedPeriodStatus`, the UI can lag behind the effective runtime phase
- if you use projection before checking `allActiveContributed`, you may show payout preview while the period is still contribution-incomplete
- if you ignore `cycleCompleted`, you may render normal period UI while the contract is already in cycle-end voting mode

### Recommended display-state pseudocode

```ts
function deriveDisplayState(status: RuntimeStatusView, nowSec: number) {
  if (status.poolStatus === PoolStatus.Forming || status.currentCycle === 0 || status.currentPeriod === 0) {
    return 'forming'
  }

  if (status.poolStatus === PoolStatus.Archived) {
    return 'archived'
  }

  if (status.cycleCompleted) {
    if (status.extendVoteOpen) {
      return nowSec <= Number(status.extendVoteDeadline)
        ? 'extend-vote-open'
        : 'extend-vote-expired'
    }
    return 'cycle-completed'
  }

  switch (status.syncAction) {
    case RuntimeSyncAction.ArchiveReady:
      return 'collecting-default-pending'
    case RuntimeSyncAction.AuctionReady:
      return 'auction-virtual'
    case RuntimeSyncAction.PayoutReady:
      return 'payout-virtual'
    case RuntimeSyncAction.FinalizeReady:
      return 'period-overdue-finalize'
  }

  switch (status.storedPeriodStatus) {
    case PeriodStatus.Collecting:
      return 'collecting-open'
    case PeriodStatus.Auction:
      return 'auction-open'
    case PeriodStatus.PayoutOpen:
      return 'payout-open'
    case PeriodStatus.Finalized:
      return 'finalized-materialized'
  }
}
```

---

## Countdown Rules

Use countdowns according to the table below.

| Display state | Countdown to show |
| --- | --- |
| `forming` | No runtime countdown |
| `collecting-open` | `contributionDeadline - now` |
| `collecting-default-pending` | No countdown; show default-pending state |
| `auction-virtual` | `auctionDeadline - now` |
| `auction-open` | `auctionDeadline - now` |
| `payout-virtual` | `payoutDeadline - now` |
| `payout-open` | `payoutDeadline - now` |
| `period-overdue-finalize` | No countdown; show finalize-ready state |
| `extend-vote-open` | `extendVoteDeadline - now` |
| `extend-vote-expired` | No countdown; show vote-expired state |
| `archived` | No runtime countdown |

Important rule:
- for the current active period, derive countdowns from `runtimeStatus()`, not from `periodInfo()`

In particular:
- `periodInfo().auctionDeadline` may still be `0` before auction is materialized
- `runtimeStatus().auctionDeadline` is the canonical deadline the UI should use

---

## CTA and Write-Action Mapping

`syncAction` exists so clients can decide which write path is appropriate without reverse-engineering readiness from multiple booleans.

| `syncAction` | Meaning | Recommended generic write action |
| --- | --- | --- |
| `None` | No immediate phase materialization is pending | Use normal action flow based on `storedPeriodStatus` |
| `ArchiveReady` | A missed contribution must be resolved explicitly | `markDefaultAndArchive(defaultedMember)` |
| `AuctionReady` | Collecting is complete and auction can be materialized | `syncRuntime()` or `submitDiscountBid()` |
| `PayoutReady` | Auction window is over and payout can be materialized | `syncRuntime()` |
| `FinalizeReady` | The period end has been reached and the period can be finalized | `syncRuntime()` |

### Special notes by action

#### `ArchiveReady`

`syncRuntime()` does not resolve default.

If `syncAction = ArchiveReady`:
- pick a member from `unpaidActiveMembers`
- call `markDefaultAndArchive(defaultedMember)`
- hide bid and payout CTAs

#### `AuctionReady`

If the user is about to place a bid:
- calling `submitDiscountBid(discount)` is valid
- the contract will auto-sync `Collecting -> Auction` first, then place the bid

If the app just wants to materialize the phase:
- call `syncRuntime()`

#### `PayoutReady`

This means the payout phase is already effective from the canonical timeline even if storage still says `Collecting` or `Auction`.

The generic safe option is:
- call `syncRuntime()`

An app may choose to show `claimPayout()` directly to the projected recipient, but only if it accepts that no-bid fallback projection is still preview data until payout is actually materialized.

#### `FinalizeReady`

The generic safe option is:
- call `syncRuntime()`

Also note:
- calling `contribute()` for the next period can auto-finalize the overdue prior period first

---

## Projection Rules in Detail

### When `projectedRecipient` is zero

This happens when:
- `allActiveContributed = false`

Interpretation:
- the payout preview is intentionally hidden
- this does not mean the period can never have a recipient

### When projection is effectively locked

Projection is effectively locked when:
- `period.recipient` has already been selected on-chain
- typically when the stored period has reached `PayoutOpen`

In that case:
- `projectedRecipient` reflects the actual selected recipient
- `projectedPayoutAmount` reflects the actual materialized payout amount

### When projection is only a preview

Projection is preview data when:
- all contributions are in
- but payout has not yet been materialized on-chain

Bid case:
- preview is driven by `bestBidder`
- this is usually more stable, unless a higher bid arrives later

No-bid fallback case:
- preview is driven by current live reputation
- it may change before payout is materialized if reputation changes first

### Tie-break behavior

If there is no bid and multiple eligible members share the same reputation score:
- the contract keeps the first eligible member in `_members` order

Clients should not invent a different tie-break rule.

### Oversized bid caveat

The contract rejects payout opening if `bestDiscount >= totalContributed`.

For safety, projection does not underflow:
- `projectedRecipient` may still point to `bestBidder`
- `projectedDiscount` may still show that oversized bid
- `projectedPayoutAmount` remains `0`

Frontend and backend code should treat that as invalid projected payout data and prevent such bids earlier at the application layer if desired.

---

## Relationship Between `runtimeStatus()` and `periodInfo()`

Use the two reads for different purposes.

### Use `runtimeStatus()` for

- current-period phase display
- current-period countdowns
- runtime CTA readiness
- realtime payout preview
- unpaid member lists
- bot and automation decisions

### Use `periodInfo()` for

- historical cycle/period details
- actual selected recipient once materialized
- actual best bid stored on-chain
- actual payout amount once materialized
- payout claimed state
- reputation snapshot id

### Practical rule

- current-period UX: prefer `runtimeStatus()`
- historical truth: prefer `periodInfo()` and events
- exact event-sourced accounting: prefer events plus `periodInfo()`

---

## Canonical Timeline Example

All examples below use this shared configuration:

- active members: `Alice`, `Bob`, `Carol`
- contribution amount: `100 USDC`
- total contributed when complete: `300 USDC`
- `periodDuration = 7 days`
- `contributionWindow = 2 days`
- `auctionWindow = 1 day`
- `payoutWindow = 4 days`
- `startAt = 2026-04-22 09:00:00 ICT`

Derived deadlines:
- `contributionDeadline = 2026-04-24 09:00:00 ICT`
- `auctionDeadline = 2026-04-25 09:00:00 ICT`
- `payoutDeadline = 2026-04-29 09:00:00 ICT`

Illustrative addresses:
- `Alice = 0xA11CE`
- `Bob = 0xB0B`
- `Carol = 0xCAFE`

---

## Detailed State Examples

The examples below focus on the fields that matter most for each situation.

### Case 1. Pool is still `Forming`

Situation:
- the pool has not reached the target member count
- there is no active cycle or current period

Example:

```json
{
  "poolStatus": "Forming",
  "currentCycle": 0,
  "currentPeriod": 0,
  "syncAction": "None",
  "cycleCompleted": false,
  "extendVoteOpen": false
}
```

Frontend:
- render formation UI
- do not render runtime countdowns
- ignore period-phase and payout projection fields

Backend:
- focus on formation and membership events
- no runtime bot action is needed

---

### Case 2. Pool is already `Archived`

Situation:
- the pool was archived due to default or end-of-cycle decision

Example:

```json
{
  "poolStatus": "Archived",
  "syncAction": "None",
  "cycleCompleted": true
}
```

Frontend:
- render terminal archived UI
- show `claimYield()`, `claimArchiveRefund()`, or `leaveAfterArchive()` where relevant
- ignore runtime sync behavior

Backend:
- no runtime bot action is needed
- only claimable balances and archive lifecycle remain relevant

---

### Case 3. Active, collecting, contributions still missing, before contribution deadline

Situation:
- `Alice` has contributed
- `Bob` and `Carol` have not
- current time is `2026-04-23 12:00:00 ICT`

Example:

```json
{
  "poolStatus": "Active",
  "storedPeriodStatus": "Collecting",
  "syncAction": "None",
  "allActiveContributed": false,
  "contributionDeadline": "2026-04-24 09:00:00 ICT",
  "projectedRecipient": "0x0000000000000000000000000000000000000000",
  "projectedDiscount": "0",
  "projectedPayoutAmount": "0",
  "unpaidActiveMembers": ["Bob", "Carol"]
}
```

Frontend:
- show collecting countdown to `contributionDeadline`
- show contribution progress
- hide payout projection
- primary CTA is `contribute()`

Backend:
- notifications to unpaid members make sense
- no runtime bot sync is needed yet

---

### Case 4. Active, collecting, all contributions are in, but contribution deadline has not been reached

Situation:
- all three members contributed early
- current time is `2026-04-23 12:00:00 ICT`

Example:

```json
{
  "poolStatus": "Active",
  "storedPeriodStatus": "Collecting",
  "syncAction": "None",
  "allActiveContributed": true,
  "contributionDeadline": "2026-04-24 09:00:00 ICT",
  "auctionDeadline": "2026-04-25 09:00:00 ICT",
  "payoutDeadline": "2026-04-29 09:00:00 ICT",
  "projectedRecipient": "Alice",
  "projectedDiscount": "0",
  "projectedPayoutAmount": "300 USDC"
}
```

Frontend:
- still render collecting state
- countdown is still `contributionDeadline`
- payout preview may be shown
- do not show auction-sync CTA yet

Explanation:
- contribution completeness does not mean auction is already open
- auction materialization is only ready after `contributionDeadline`

---

### Case 5. Active, collecting, contribution deadline passed, contributions still missing

Situation:
- `Alice` and `Bob` contributed
- `Carol` missed the deadline
- current time is `2026-04-24 10:00:00 ICT`

Example:

```json
{
  "poolStatus": "Active",
  "storedPeriodStatus": "Collecting",
  "syncAction": "ArchiveReady",
  "allActiveContributed": false,
  "unpaidActiveMembers": ["Carol"],
  "projectedRecipient": "0x0000000000000000000000000000000000000000",
  "projectedDiscount": "0",
  "projectedPayoutAmount": "0"
}
```

Frontend:
- this is the default-pending state
- hide bid and payout CTAs
- show `unpaidActiveMembers`
- primary CTA is `markDefaultAndArchive(Carol)`

Backend:
- if an active-member signer is available, call `markDefaultAndArchive`
- `syncRuntime()` is not the right action here

---

### Case 6. Active, collecting, contribution deadline passed, all contributions are in, auction deadline not reached

Situation:
- all three members contributed
- current time is `2026-04-24 12:00:00 ICT`
- storage still says `Collecting`

Example:

```json
{
  "poolStatus": "Active",
  "storedPeriodStatus": "Collecting",
  "syncAction": "AuctionReady",
  "allActiveContributed": true,
  "auctionDeadline": "2026-04-25 09:00:00 ICT",
  "projectedRecipient": "Alice",
  "projectedDiscount": "0",
  "projectedPayoutAmount": "300 USDC"
}
```

Frontend:
- treat auction as effectively active
- show auction countdown using `auctionDeadline`
- generic CTA is `syncRuntime()`
- if the user is about to bid, `submitDiscountBid()` can be used directly

Backend:
- `syncRuntime()` may be used to materialize auction explicitly
- if not, the period can still be treated as auction-effective off-chain

---

### Case 7. Active, collecting, auction deadline passed, payout deadline not reached

Situation:
- all three members contributed
- no one ever materialized auction
- current time is `2026-04-25 12:00:00 ICT`

Example:

```json
{
  "poolStatus": "Active",
  "storedPeriodStatus": "Collecting",
  "syncAction": "PayoutReady",
  "auctionDeadline": "2026-04-25 09:00:00 ICT",
  "payoutDeadline": "2026-04-29 09:00:00 ICT",
  "projectedRecipient": "Bob",
  "projectedDiscount": "0",
  "projectedPayoutAmount": "300 USDC"
}
```

Frontend:
- treat payout as effectively active
- show payout countdown using `payoutDeadline`
- generic CTA is `syncRuntime()`
- only show `claimPayout()` directly if the app accepts projection risk in no-bid fallback mode

Backend:
- current period can be treated as virtual payout
- a real transaction is still required to lock the actual on-chain recipient

---

### Case 8. Active, collecting, payout deadline already passed

Situation:
- all three members contributed
- no one materialized auction or payout
- current time is `2026-04-29 10:00:00 ICT`

Example:

```json
{
  "poolStatus": "Active",
  "storedPeriodStatus": "Collecting",
  "syncAction": "FinalizeReady",
  "payoutDeadline": "2026-04-29 09:00:00 ICT",
  "projectedRecipient": "Bob",
  "projectedPayoutAmount": "300 USDC"
}
```

Frontend:
- render a finalize-ready overdue-period state
- generic CTA is `syncRuntime()`
- `contribute()` for the next period may also auto-finalize first if the caller is eligible

Backend:
- this is a high-priority catch-up case for active-member automation
- one `syncRuntime()` call may advance the period through multiple virtual phases in one transaction

---

### Case 9. Active, stored `Auction`, auction deadline not reached

Situation:
- someone already materialized auction using `syncRuntime()` or `submitDiscountBid()`
- current time is `2026-04-24 15:00:00 ICT`

Example:

```json
{
  "poolStatus": "Active",
  "storedPeriodStatus": "Auction",
  "syncAction": "None",
  "auctionDeadline": "2026-04-25 09:00:00 ICT",
  "projectedRecipient": "Bob",
  "projectedDiscount": "10 USDC",
  "projectedPayoutAmount": "290 USDC"
}
```

Frontend:
- render normal auction UI
- countdown is `auctionDeadline`
- primary CTA is `submitDiscountBid()`
- winner preview should reflect `bestBidder` when present

---

### Case 10. Active, stored `Auction`, auction deadline passed, payout deadline not reached

Situation:
- auction was materialized
- bidding time has ended
- current time is `2026-04-25 12:00:00 ICT`

Example:

```json
{
  "poolStatus": "Active",
  "storedPeriodStatus": "Auction",
  "syncAction": "PayoutReady",
  "payoutDeadline": "2026-04-29 09:00:00 ICT",
  "projectedRecipient": "Bob",
  "projectedDiscount": "10 USDC",
  "projectedPayoutAmount": "290 USDC"
}
```

Frontend:
- treat payout as effectively ready
- countdown is `payoutDeadline`
- generic CTA is `syncRuntime()`
- showing direct `claimPayout()` is only appropriate if the app accepts preview risk when fallback selection is involved

Backend:
- a transaction is still required to materialize payout on-chain

---

### Case 11. Active, stored `Auction`, payout deadline already passed

Situation:
- auction was materialized
- but payout was never opened before period end
- current time is `2026-04-29 10:00:00 ICT`

Example:

```json
{
  "poolStatus": "Active",
  "storedPeriodStatus": "Auction",
  "syncAction": "FinalizeReady",
  "projectedRecipient": "Bob",
  "projectedPayoutAmount": "290 USDC"
}
```

Frontend:
- render an overdue-period finalize-ready state
- generic CTA is `syncRuntime()`

Backend:
- one `syncRuntime()` call can open payout and finalize immediately if needed

---

### Case 12. Active, stored `PayoutOpen`, payout deadline not reached

Situation:
- recipient has already been selected on-chain
- current time is `2026-04-26 12:00:00 ICT`

Example:

```json
{
  "poolStatus": "Active",
  "storedPeriodStatus": "PayoutOpen",
  "syncAction": "None",
  "payoutDeadline": "2026-04-29 09:00:00 ICT",
  "projectedRecipient": "Bob",
  "projectedDiscount": "10 USDC",
  "projectedPayoutAmount": "290 USDC"
}
```

Frontend:
- render normal payout UI
- countdown is `payoutDeadline`
- if the current user is the recipient and payout is unclaimed, show `claimPayout()`

Backend:
- projection is effectively stable here because recipient selection has already been materialized

---

### Case 13. Active, stored `PayoutOpen`, payout deadline already passed

Situation:
- payout was opened on-chain
- finalization has not happened yet
- current time is `2026-04-29 10:00:00 ICT`

Example:

```json
{
  "poolStatus": "Active",
  "storedPeriodStatus": "PayoutOpen",
  "syncAction": "FinalizeReady",
  "payoutDeadline": "2026-04-29 09:00:00 ICT",
  "projectedRecipient": "Bob",
  "projectedPayoutAmount": "290 USDC"
}
```

Frontend:
- render finalize-ready state
- generic CTA is `syncRuntime()`

Backend:
- the next active-member runtime transaction can finalize the period
- if payout is still unclaimed, finalization will auto-pay the recipient first

---

### Case 14. Current cycle is complete and extend voting is open

Situation:
- all active members have received payout in the current cycle
- the contract opened end-of-cycle extension voting

Example:

```json
{
  "poolStatus": "Active",
  "cycleCompleted": true,
  "extendVoteOpen": true,
  "extendVoteDeadline": "2026-04-30 09:00:00 ICT",
  "syncAction": "None"
}
```

Frontend:
- stop rendering normal period-phase UI
- render extend-vote UI
- CTAs are `voteExtendCycle(true)` and `voteExtendCycle(false)`
- countdown is `extendVoteDeadline`

Backend:
- reminder notifications are reasonable here

---

### Case 15. Extend vote has expired

Situation:
- `extendVoteOpen = true`
- current time is now past `extendVoteDeadline`
- the pool has not yet archived and has not yet started a new cycle

Example:

```json
{
  "poolStatus": "Active",
  "cycleCompleted": true,
  "extendVoteOpen": true,
  "extendVoteDeadline": "2026-04-30 09:00:00 ICT",
  "syncAction": "None"
}
```

Frontend:
- render "extend vote expired"
- disable `voteExtendCycle`
- keep `archive()` available

Backend:
- if an active-member signer is available, it may call `archive()`

Important:
- there is no `extendVoteExpired` field anymore
- clients must derive it as:

```ts
const extendVoteExpired =
  status.extendVoteOpen && nowSec > Number(status.extendVoteDeadline)
```

---

### Case 16. Previous period finalized and next period opened

Situation:
- `syncRuntime()` finalized the prior period
- the contract has already opened `currentPeriod + 1`

Example:

```json
{
  "poolStatus": "Active",
  "currentCycle": 1,
  "currentPeriod": 2,
  "storedPeriodStatus": "Collecting",
  "syncAction": "None",
  "allActiveContributed": false,
  "projectedRecipient": "0x0000000000000000000000000000000000000000",
  "projectedPayoutAmount": "0"
}
```

Frontend:
- reset to collecting UI for the new period
- countdowns now use the new `startAt`
- projection remains hidden until all active members have contributed again

---

## Frontend Implementation Guide

### Recommended read strategy

For the current period screen, read at least:
- `runtimeStatus()`
- `periodInfo(currentCycle, currentPeriod)` if you need exact stored best-bid, payout-claimed, or snapshot details
- `hasContributed(currentCycle, currentPeriod, currentUser)` for per-user button state
- `hasReceivedInCycle(currentCycle, currentUser)` for user eligibility checks

### Recommended frontend state model

Keep three layers distinct:

1. Pool shell state:
- `forming`
- `active`
- `archived`

2. Runtime display state:
- `collecting-open`
- `collecting-default-pending`
- `auction-virtual`
- `auction-open`
- `payout-virtual`
- `payout-open`
- `period-overdue-finalize`
- `extend-vote-open`
- `extend-vote-expired`

3. Current-user capabilities:
- can contribute
- can bid
- can claim payout
- can mark default
- can vote extend
- can archive

### Practical CTA mapping

| Display state | Primary CTA |
| --- | --- |
| `collecting-open` | `contribute()` |
| `collecting-default-pending` | `markDefaultAndArchive(defaultedMember)` |
| `auction-virtual` | `syncRuntime()` or `submitDiscountBid()` |
| `auction-open` | `submitDiscountBid()` |
| `payout-virtual` | `syncRuntime()` |
| `payout-open` | `claimPayout()` if current user is recipient |
| `period-overdue-finalize` | `syncRuntime()` |
| `extend-vote-open` | `voteExtendCycle(true/false)` |
| `extend-vote-expired` | `archive()` |
| `archived` | `claimYield()`, `claimArchiveRefund()`, `leaveAfterArchive()` as applicable |

### When to show projected payout info

Show projection when:
- `allActiveContributed = true`
- `poolStatus = Active`
- `cycleCompleted = false`

Hide projection when:
- `projectedRecipient == address(0)`
- `poolStatus != Active`
- `cycleCompleted = true`

### Suggested UI labels

| Condition | Suggested label |
| --- | --- |
| `syncAction = AuctionReady` | `Auction ready` or `Auction effective, awaiting sync` |
| `syncAction = PayoutReady` | `Payout ready` or `Payout effective, awaiting sync` |
| `syncAction = FinalizeReady` | `Finalize ready` or `Period end reached` |
| `syncAction = ArchiveReady` | `Default pending` |

Frontend should explicitly distinguish:
- stored period state
- display/runtime state
- next write action

Do not render `storedPeriodStatus` as the only runtime badge.

---

## Backend and Automation Guide

### How bots should use `runtimeStatus()`

If a backend service controls an active-member signer, the decision table should look like this:

| Condition | Recommended action |
| --- | --- |
| `poolStatus != Active` | No runtime sync needed |
| `cycleCompleted && extendVoteOpen && now > extendVoteDeadline` | `archive()` may be called |
| `syncAction = ArchiveReady` | Call `markDefaultAndArchive(defaultedMember)` |
| `syncAction = AuctionReady` | Call `syncRuntime()` if explicit auction materialization is desired |
| `syncAction = PayoutReady` | Call `syncRuntime()` if exact payout materialization is desired |
| `syncAction = FinalizeReady` | Call `syncRuntime()` |
| `syncAction = None` | No dedicated sync needed |

### What an indexer should persist

For the current period, it is useful to store:
- a `runtimeStatus()` snapshot
- the derived display state
- `projectedRecipient` and the time the snapshot was taken
- `syncAction`

For finalized historical truth, store:
- `ChainoraRecipientSelected`
- `ChainoraPayoutClaimed`
- `ChainoraPeriodFinalized`
- `periodInfo(cycleId, periodId)` when exact on-chain materialized fields matter

### Backend caveats

Do not:
- derive current countdowns only from `periodInfo().auctionDeadline`
- derive readiness only from `storedPeriodStatus`
- treat fallback projected recipient as finalized truth

Do:
- treat `runtimeStatus()` as the read model for the current period
- treat events plus `periodInfo()` as the source of truth for history and finalized data

---

## Common Integration Mistakes

### Mistake 1. Using `storedPeriodStatus` as the only runtime phase

Consequence:
- the UI can still show collecting while the period is effectively payout-ready

Correct approach:
- let `syncAction` override display state first

### Mistake 2. Using `periodInfo().auctionDeadline` for current-period countdowns

Consequence:
- before auction is materialized, that field may still be `0`

Correct approach:
- use `runtimeStatus().auctionDeadline`

### Mistake 3. Calling `syncRuntime()` when `syncAction = ArchiveReady`

Consequence:
- the transaction does not resolve default

Correct approach:
- call `markDefaultAndArchive(defaultedMember)`

### Mistake 4. Showing payout projection before all contributions are complete

Consequence:
- the UI implies payout selection while the period is still contribution-incomplete

Correct approach:
- if `projectedRecipient == address(0)`, hide the projection block

### Mistake 5. Treating fallback projection as final truth

Consequence:
- recipient notifications or UI can be wrong before payout is materialized

Correct approach:
- in no-bid fallback mode, treat projection as preview only
- use actual materialized recipient once payout is opened on-chain

---

## QA Checklist

At minimum, test all of the following:

1. Pool is `Forming`, `currentCycle = 0`, and runtime UI is not rendered.
2. `Collecting`, contributions are incomplete, and contribution countdown behaves correctly.
3. `Collecting`, contributions are incomplete, deadline passes, `syncAction = ArchiveReady`, and projection is hidden.
4. `Collecting`, all contributions are complete before the deadline, projection is visible, and `syncAction = None`.
5. `Collecting`, all contributions are complete after the contribution deadline, and `syncAction = AuctionReady`.
6. `Collecting`, all contributions are complete after the auction deadline, and `syncAction = PayoutReady`.
7. `Collecting`, all contributions are complete after the payout deadline, and `syncAction = FinalizeReady`.
8. `Auction`, before auction deadline, `syncAction = None`.
9. `Auction`, after auction deadline, `syncAction = PayoutReady`.
10. `PayoutOpen`, before payout deadline, `syncAction = None`.
11. `PayoutOpen`, after payout deadline, `syncAction = FinalizeReady`.
12. `cycleCompleted = true`, `extendVoteOpen = true`, and extend-vote UI is rendered.
13. Extend vote expires, voting is disabled, and `archive()` remains available.
14. `claimPayout()` from the projected recipient works correctly in a payout-virtual scenario when the contract auto-syncs first.
15. `contribute()` for the next period correctly auto-finalizes an overdue prior period first.

---

## Contract Surface References

Relevant files:
- [src/libraries/Types.sol](../src/libraries/Types.sol)
- [src/pool/modules/RuntimeSyncModule.sol](../src/pool/modules/RuntimeSyncModule.sol)
- [src/pool/ChainoraRoscaPool.sol](../src/pool/ChainoraRoscaPool.sol)
- [test/unit/pool/ChainoraRoscaPool.RuntimeSync.t.sol](../test/unit/pool/ChainoraRoscaPool.RuntimeSync.t.sol)

---

## Final Takeaways

If you only remember five things, remember these:

1. `runtimeStatus()` is the primary read model for the current period.
2. `storedPeriodStatus` alone is not enough for correct runtime UX.
3. `syncAction` is the single readiness signal clients should use.
4. Current-period deadlines should come from `runtimeStatus()`, not historical storage-only fields.
5. `projectedRecipient` is preview data; if it is zero, the projection should be hidden.
