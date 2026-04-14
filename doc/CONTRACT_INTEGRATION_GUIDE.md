# Contract Integration Guide - Chainora

## Introduction

This document describes the main contract calls required to integrate with the Chainora ROSCA protocol.

It is intended for application developers who need to:
- discover deployed contract addresses
- create pools
- manage member onboarding
- run pool periods and auctions
- react to events and common revert conditions

The guide follows a command-reference style similar to the APDU documentation, but for smart contract integration.

---

## Contract Structure

The protocol is split into four main contract roles.

- `ChainoraProtocolTimelock`: governance control plane for privileged protocol changes
- `ChainoraProtocolRegistry`: shared protocol configuration such as stablecoin and adapter addresses
- `ChainoraRoscaFactory`: pool creation entrypoint
- `ChainoraRoscaPool`: member-facing runtime contract for pool formation and period execution

For most application integrations, the primary contracts are:
- `ChainoraProtocolRegistry`
- `ChainoraRoscaFactory`
- `ChainoraRoscaPool`
- the configured ERC-20 stablecoin

---

## Deployment Address Template

Fill in the actual deployed addresses for each environment.

| Network | Timelock | Registry | Factory | Pool Implementation | Stablecoin | Device Adapter | Reputation Adapter | Staking Adapter |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Local | `TBD` | `TBD` | `TBD` | `TBD` | `TBD` | `TBD` | `TBD` | `TBD` |
| Testnet (Chainora Rollup tCNR) | `0xCbd8415bA47fb8b26695eD61B68e3A94E46eB7E2` | `0xE51b472cA5528759EE72F3bA95e9A94fb0636AA6` | `0x83B2c694799c825b2DB78e75C6ad9BBf7B171e41` | `0x62f2fDaAc333c44D260658e89fe8A39A48C10755` | `TBD` | `TBD` | `TBD` | `TBD` |
| Mainnet | `TBD` | `TBD` | `TBD` | `TBD` | `TBD` | `TBD` | `TBD` | `TBD` |

---

## Protocol Rules and Constraints

Before sending transactions, keep these rules in mind.

- `targetMembers` must be in the range `2..255`
- `contributionAmount` must be greater than `0`
- `periodDuration`, `contributionWindow`, and `auctionWindow` must all be greater than `0`
- `contributionWindow + auctionWindow` must be strictly less than `periodDuration`
- `maxCycles` is derived on-chain from `targetMembers`
- if a device adapter is configured, pool creators must be device-verified
- members must approve the pool contract to spend stablecoins before deposit and contribution flows
- runtime transitions are member-driven; there is no public keeper fallback in this repository

---

## 1. Registry Discovery

### 1.1. `stablecoin()`

**Description**: Returns the ERC-20 token used by pools for deposits, contributions, payouts, and yield distribution.

**Call**:

```solidity
function stablecoin() external view returns (address)
```

**Parameters**: None

**Response**:
- `address`: stablecoin token address

**Example**:

```ts
const stablecoin = await publicClient.readContract({
  address: REGISTRY_ADDRESS,
  abi: registryAbi,
  functionName: 'stablecoin',
})
```

---

### 1.2. `deviceAdapter()`

**Description**: Returns the optional device verification adapter address.

**Call**:

```solidity
function deviceAdapter() external view returns (address)
```

**Parameters**: None

**Response**:
- `address`: device adapter address, or `0x0` if disabled

**Example**:

```ts
const deviceAdapter = await publicClient.readContract({
  address: REGISTRY_ADDRESS,
  abi: registryAbi,
  functionName: 'deviceAdapter',
})
```

---

### 1.3. `reputationAdapter()`

**Description**: Returns the optional reputation adapter used during no-bid recipient fallback.

**Call**:

```solidity
function reputationAdapter() external view returns (address)
```

**Parameters**: None

**Response**:
- `address`: reputation adapter address, or `0x0` if disabled

**Example**:

```ts
const reputationAdapter = await publicClient.readContract({
  address: REGISTRY_ADDRESS,
  abi: registryAbi,
  functionName: 'reputationAdapter',
})
```

---

### 1.4. `stakingAdapter()`

**Description**: Returns the optional staking adapter configured in the registry.

**Call**:

```solidity
function stakingAdapter() external view returns (address)
```

**Parameters**: None

**Response**:
- `address`: staking adapter address, or `0x0` if disabled

**Example**:

```ts
const stakingAdapter = await publicClient.readContract({
  address: REGISTRY_ADDRESS,
  abi: registryAbi,
  functionName: 'stakingAdapter',
})
```

---

## 2. Factory Integration

### 2.1. `poolCount()`

**Description**: Returns the number of pools created by the factory.

**Call**:

```solidity
function poolCount() external view returns (uint256)
```

**Parameters**: None

**Response**:
- `uint256`: current pool count

**Example**:

```ts
const poolCount = await publicClient.readContract({
  address: FACTORY_ADDRESS,
  abi: factoryAbi,
  functionName: 'poolCount',
})
```

---

### 2.2. `poolById(uint256 poolId)`

**Description**: Returns the pool address for a known pool id.

**Call**:

```solidity
function poolById(uint256 poolId) external view returns (address)
```

**Parameters**:
- `poolId`: sequential id assigned by the factory

**Response**:
- `address`: pool address

**Example**:

```ts
const poolAddress = await publicClient.readContract({
  address: FACTORY_ADDRESS,
  abi: factoryAbi,
  functionName: 'poolById',
  args: [1n],
})
```

---

### 2.3. `createPool(Types.PoolConfig config)`

**Description**: Creates a new pool clone and initializes it.

**Call**:

```solidity
function createPool(
    (uint256 contributionAmount, uint16 targetMembers, uint32 periodDuration, uint32 contributionWindow, uint32 auctionWindow) config
) external returns (address pool, uint256 poolId)
```

**Parameters**:
- `contributionAmount`: token amount each member contributes per period
- `targetMembers`: target number of members and derived maximum cycle count
- `periodDuration`: total period length in seconds
- `contributionWindow`: contribution phase duration in seconds
- `auctionWindow`: auction phase duration in seconds

**Response**:
- `pool`: deployed pool clone address
- `poolId`: sequential pool id

**Requirements**:
- registry stablecoin must be set
- config must satisfy all invariant checks
- if `deviceAdapter` is configured, `msg.sender` must pass `isDeviceVerified`

**Common revert cases**:
- `Errors.InvalidConfig()`
- `Errors.Unauthorized()`

**Event**:
- `ChainoraPoolCreated(uint256 poolId, address pool, address creator)`

**Example**:

```ts
const poolConfig = {
  contributionAmount: parseUnits('100', 6),
  targetMembers: 5,
  periodDuration: 7 * 24 * 60 * 60,
  contributionWindow: 2 * 24 * 60 * 60,
  auctionWindow: 1 * 24 * 60 * 60,
}

const txHash = await walletClient.writeContract({
  address: FACTORY_ADDRESS,
  abi: factoryAbi,
  functionName: 'createPool',
  args: [poolConfig],
})
```

**How to get the new pool address**:
- wait for transaction receipt
- decode `ChainoraPoolCreated`
- or read `poolCount()` then `poolById(poolId)`

---

## 3. Stablecoin Approval

### 3.1. `approve(pool, amount)`

**Description**: Allows the pool contract to transfer stablecoins from a member account.

**Why it is required**:
- `contribute()` uses `transferFrom`

**Call**:

```solidity
function approve(address spender, uint256 amount) external returns (bool)
```

**Parameters**:
- `spender`: pool address
- `amount`: allowance amount

**Response**:
- `bool`: ERC-20 approval result

**Example**:

```ts
await walletClient.writeContract({
  address: STABLECOIN_ADDRESS,
  abi: erc20Abi,
  functionName: 'approve',
  args: [POOL_ADDRESS, 2n ** 256n - 1n],
})
```

---

## 4. Pool Formation Commands

### 4.1. `proposeInvite(address candidate)`

**Description**: Opens an invite proposal while the pool is still forming.

**Call**:

```solidity
function proposeInvite(address candidate) external returns (uint256 proposalId)
```

**Parameters**:
- `candidate`: account proposed for admission

**Response**:
- `proposalId`: invite proposal id

**Requirements**:
- pool status must be `Forming`
- caller must already be a member
- candidate must be non-zero and not already a member

**Common revert cases**:
- `Errors.InvalidState()`
- `Errors.NotMember()`
- `Errors.InvalidConfig()`

**Event**:
- `ChainoraInviteProposed(uint256 proposalId, address candidate, address proposer)`

**Example**:

```ts
const proposeTx = await walletClient.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'proposeInvite',
  args: [candidateAddress],
})
```

---

### 4.2. `voteInvite(uint256 proposalId, bool support)`

**Description**: Records a vote for an open invite proposal.

**Call**:

```solidity
function voteInvite(uint256 proposalId, bool support) external
```

**Parameters**:
- `proposalId`: invite proposal id
- `support`: `true` for yes, `false` for no

**Response**: None

**Requirements**:
- pool status must be `Forming`
- caller must be a member
- proposal must still be open
- caller must not have voted already in this proposal

**Common revert cases**:
- `Errors.InvalidState()`
- `Errors.NotMember()`
- `Errors.ProposalClosed()`
- `Errors.AlreadyVoted()`

**Event**:
- `ChainoraInviteVoted(uint256 proposalId, address voter, bool support)`

**Example**:

```ts
await walletClient.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'voteInvite',
  args: [proposalId, true],
})
```

---

### 4.3. `acceptInvite(uint256 proposalId)`

**Description**: Allows the invited account to accept membership after invite quorum is reached.

**Call**:

```solidity
function acceptInvite(uint256 proposalId) external
```

**Parameters**:
- `proposalId`: invite proposal id

**Response**: None

**Requirements**:
- pool status must be `Forming`
- proposal must still be open
- caller must be the invited candidate
- yes votes must be at least two-thirds of the current active member count

**Common revert cases**:
- `Errors.InvalidState()`
- `Errors.ProposalClosed()`
- `Errors.NotInvitee()`
- `Errors.ProposalNotPassed()`

**Events**:
- `ChainoraInviteAccepted(uint256 proposalId, address member)`
- `ChainoraPoolActivated(uint256 cycleId, uint64 periodStartAt)` when the target member count is reached

**Example**:

```ts
await inviteeWallet.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'acceptInvite',
  args: [proposalId],
})
```

---

## 5. Pool Runtime Commands

### 5.1. `contribute()`

**Description**: Transfers the caller's contribution into the pool for the current period.

**Call**:

```solidity
function contribute() external
```

**Parameters**: None

**Response**: None

**Requirements**:
- caller must be an active member
- pool status must be `Active`
- cycle must not already be complete
- period status must be `Collecting`
- current time must be on or before `contributionDeadline`
- caller must not have contributed already
- caller must approve the pool to spend `contributionAmount`

**Common revert cases**:
- `Errors.NotActiveMember()`
- `Errors.InvalidState()`
- `Errors.DeadlinePassed()`
- `Errors.AlreadyContributed()`

**Event**:
- `ChainoraContributionPaid(uint256 cycleId, uint256 periodId, address member, uint256 amount)`

**Example**:

```ts
await walletClient.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'contribute',
})
```

---

### 5.2. `submitDiscountBid(uint256 discount)`

**Description**: Submits an auction discount bid for the current period.

**Call**:

```solidity
function submitDiscountBid(uint256 discount) external
```

**Parameters**:
- `discount`: discount requested by the bidder

**Response**: None

**Requirements**:
- caller must be an active member
- caller must not have received payout already in the current cycle
- pool status must be `Active`
- cycle must not be complete
- all active members must already be accounted for as contributed
- current time must be before `auctionDeadline`
- `discount` must be greater than the current best discount

**Common revert cases**:
- `Errors.NotActiveMember()`
- `Errors.InvalidState()`
- `Errors.DeadlineNotReached()`
- `Errors.ContributionMissing()`
- `Errors.DeadlinePassed()`
- `Errors.InvalidConfig()`

**Event**:
- `ChainoraBidSubmitted(uint256 cycleId, uint256 periodId, address bidder, uint256 discount)`

**Example**:

```ts
await walletClient.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'submitDiscountBid',
  args: [parseUnits('10', 6)],
})
```

---

### 5.3. `closeAuctionAndSelectRecipient()`

**Description**: Closes the auction and determines the payout recipient.

**Call**:

```solidity
function closeAuctionAndSelectRecipient() external
```

**Parameters**: None

**Response**: None

**Requirements**:
- caller must be an active member
- pool status must be `Active`
- cycle must not be complete
- current time must be at or after `auctionDeadline`
- if still in `Collecting`, all active members must already be accounted for as contributed

**Selection rules**:
- if there is a best bidder, that bidder becomes the recipient
- otherwise the contract selects from eligible active members who have not yet received in the cycle
- if a reputation adapter exists, the contract may snapshot and compare reputation scores
- if no reputation adapter exists, the first eligible member found is selected

**Common revert cases**:
- `Errors.NotActiveMember()`
- `Errors.InvalidState()`
- `Errors.DeadlineNotReached()`
- `Errors.ContributionMissing()`
- `Errors.AuctionNotOpen()`
- `Errors.AuctionAlreadyClosed()`
- `Errors.NoEligibleRecipient()`
- `Errors.InvalidConfig()`

**Event**:
- `ChainoraRecipientSelected(uint256 cycleId, uint256 periodId, address recipient, uint256 payoutAmount, uint256 discount)`

**Example**:

```ts
await walletClient.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'closeAuctionAndSelectRecipient',
})
```

---

### 5.4. `claimPayout()`

**Description**: Lets the selected recipient claim the payout for the current period.

**Call**:

```solidity
function claimPayout() external
```

**Parameters**: None

**Response**: None

**Requirements**:
- period status must be `PayoutOpen`
- caller must be the selected recipient
- payout must not be claimed already

**Common revert cases**:
- `Errors.PayoutUnavailable()`
- `Errors.NotRecipient()`
- `Errors.AlreadyClaimed()`

**Event**:
- `ChainoraPayoutClaimed(uint256 cycleId, uint256 periodId, address recipient, uint256 amount)`

**Example**:

```ts
await recipientWallet.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'claimPayout',
})
```

---

### 5.5. `claimYield()`

**Description**: Lets a member claim accumulated yield from discount sharing.

**Call**:

```solidity
function claimYield() external
```

**Parameters**: None

**Response**: None

**Requirements**:
- caller must be a member
- `claimableYield(caller)` must be greater than `0`

**Common revert cases**:
- `Errors.NotMember()`
- `Errors.PayoutUnavailable()`

**Event**:
- `ChainoraYieldClaimed(uint256 cycleId, uint256 periodId, address member, uint256 amount)`

**Example**:

```ts
await walletClient.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'claimYield',
})
```

---

### 5.6. `finalizePeriod()`

**Description**: Finalizes the current period after payout and full period expiry.

**Call**:

```solidity
function finalizePeriod() external
```

**Parameters**: None

**Response**: None

**Requirements**:
- caller must be an active member
- pool status must be `Active`
- cycle must not be complete
- period status must be `PayoutOpen`
- payout must already be claimed
- current time must be at or after `startAt + periodDuration`

**Result**:
- current period becomes `Finalized`
- if all active members have already received in the current cycle, extend voting opens
- otherwise the next period opens immediately

**Common revert cases**:
- `Errors.NotActiveMember()`
- `Errors.InvalidState()`
- `Errors.PayoutUnavailable()`
- `Errors.DeadlineNotReached()`

**Event**:
- `ChainoraPeriodFinalized(uint256 cycleId, uint256 periodId)`

**Example**:

```ts
await walletClient.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'finalizePeriod',
})
```

---

## 6. Default and Archive Refund Commands

### 6.1. `markDefaultAndArchive(address defaultedMember)`

**Description**: Marks a missed contribution as default, archives the pool immediately, and credits archive refunds to members who already contributed in the interrupted period.

**Call**:

```solidity
function markDefaultAndArchive(address defaultedMember) external
```

**Parameters**:
- `defaultedMember`: active member who missed the contribution deadline

**Response**: None

**Requirements**:
- caller must be an active member
- pool status must be `Active`
- cycle must not be complete
- period status must be `Collecting`
- current time must be at or after `contributionDeadline`
- defaulted member must still be active
- defaulted member must not have contributed in the period

**Common revert cases**:
- `Errors.NotActiveMember()`
- `Errors.InvalidState()`
- `Errors.InvalidConfig()`
- `Errors.DeadlineNotReached()`

**Events**:
- `ChainoraPoolArchivedOnDefault(address defaultedMember, uint256 cycleId, uint256 periodId)`
- `ChainoraPoolArchived()`

**Example**:

```ts
await walletClient.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'markDefaultAndArchive',
  args: [defaultedMember],
})
```

---

### 6.2. `claimArchiveRefund()`

**Description**: Lets a member withdraw their contribution back after the pool was archived mid-period due to a default.

**Call**:

```solidity
function claimArchiveRefund() external
```

**Response**: None

**Requirements**:
- caller must be a member
- pool status must be `Archived`
- caller must have a non-zero archive refund balance

**Common revert cases**:
- `Errors.NotMember()`
- `Errors.PoolNotArchived()`
- `Errors.PayoutUnavailable()`

**Event**:
- `ChainoraArchiveRefundClaimed(address member, uint256 amount)`

**Example**:

```ts
await walletClient.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'claimArchiveRefund',
})
```

---

## 7. Extension and Archive Commands

### 7.1. `voteExtendCycle(bool support)`

**Description**: Votes on whether the pool should continue into the next cycle.

**Call**:

```solidity
function voteExtendCycle(bool support) external
```

**Parameters**:
- `support`: `true` to continue, `false` to archive immediately

**Response**: None

**Requirements**:
- caller must be an active member
- pool status must be `Active`
- current cycle must already be complete
- extend vote must be open
- caller must not have voted already in the current extend round

**Outcome**:
- any `false` vote archives the pool immediately
- unanimous `true` votes start the next cycle
- if `currentCycle >= maxCycles`, the next-cycle path archives instead

**Common revert cases**:
- `Errors.NotActiveMember()`
- `Errors.InvalidState()`
- `Errors.AlreadyVoted()`

**Events**:
- `ChainoraExtendVoted(address voter, bool support, uint256 yesVotes, uint256 requiredVotes)`
- `ChainoraPoolArchived()`
- `ChainoraPoolActivated(uint256 cycleId, uint64 periodStartAt)`

**Example**:

```ts
await walletClient.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'voteExtendCycle',
  args: [true],
})
```

---

### 7.2. `archive()`

**Description**: Archives the pool when the contract is in an archive-eligible state.

**Call**:

```solidity
function archive() external
```

**Parameters**: None

**Response**: None

**Requirements**:
- caller must be a member
- pool must be one of these:
  - `Active` with completed cycle and open extend vote
  - already `Archived`

**Common revert cases**:
- `Errors.NotMember()`
- `Errors.InvalidState()`

**Event**:
- `ChainoraPoolArchived()`

**Example**:

```ts
await walletClient.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'archive',
})
```

---

### 7.3. `leaveAfterArchive()`

**Description**: Marks a member as having left an archived pool.

**Call**:

```solidity
function leaveAfterArchive() external
```

**Parameters**: None

**Response**: None

**Requirements**:
- caller must be a member
- pool status must be `Archived`
- caller must not have left before
- caller must have no claimable yield remaining
- caller must have no claimable archive refund remaining

**Common revert cases**:
- `Errors.NotMember()`
- `Errors.PoolNotArchived()`
- `Errors.AlreadyLeft()`
- `Errors.InvalidState()`

**Event**:
- `ChainoraLeftPool(address member)`

**Example**:

```ts
await walletClient.writeContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'leaveAfterArchive',
})
```

---

## 8. Read Methods for UI and Backend

### 8.1. `poolStatus()`

**Description**: Returns the current pool status.

**Response values**:
- `0`: `Forming`
- `1`: `Active`
- `2`: `Archived`

**Example**:

```ts
const poolStatus = await publicClient.readContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'poolStatus',
})
```

---

### 8.2. `periodInfo(uint256 cycleId, uint256 periodId)`

**Description**: Returns detailed runtime data for a specific cycle and period.

**Call**:

```solidity
function periodInfo(uint256 cycleId, uint256 periodId)
    external
    view
    returns (
        uint8 status,
        uint64 startAt,
        uint64 contributionDeadline,
        uint64 auctionDeadline,
        address recipient,
        address bestBidder,
        uint256 bestDiscount,
        uint256 totalContributed,
        uint256 payoutAmount,
        bool payoutClaimed,
        bytes32 reputationSnapshotId
    )
```

**Parameters**:
- `cycleId`: cycle number
- `periodId`: period number inside the cycle

**Response**:
- `status`: `0 = Collecting`, `1 = Auction`, `2 = PayoutOpen`, `3 = Finalized`
- `startAt`: period start timestamp
- `contributionDeadline`: contribution deadline timestamp
- `auctionDeadline`: auction deadline timestamp
- `recipient`: selected recipient address
- `bestBidder`: current best bidder
- `bestDiscount`: current best discount
- `totalContributed`: total amount collected for the period
- `payoutAmount`: payout amount after discount
- `payoutClaimed`: whether payout was claimed
- `reputationSnapshotId`: snapshot id used for fallback reputation selection

**Example**:

```ts
const period = await publicClient.readContract({
  address: POOL_ADDRESS,
  abi: poolAbi,
  functionName: 'periodInfo',
  args: [cycleId, periodId],
})
```

---

### 8.3. Other recommended reads

Use these reads frequently in UI or backend state sync:
- `currentCycle()`
- `currentPeriod()`
- `activeMemberCount()`
- `members()`
- `isMember(address)`
- `isActiveMember(address)`
- `inviteProposal(uint256)`
- `hasContributed(uint256,uint256,address)`
- `hasReceivedInCycle(uint256,address)`
- `claimableYield(address)`
- `claimableArchiveRefund(address)`
- `cycleCompleted()`
- `extendVoteState()`
- `hasLeftArchive(address)`

**Example**:

```ts
const [currentCycle, currentPeriod, activeMemberCount, cycleCompleted] = await Promise.all([
  publicClient.readContract({ address: POOL_ADDRESS, abi: poolAbi, functionName: 'currentCycle' }),
  publicClient.readContract({ address: POOL_ADDRESS, abi: poolAbi, functionName: 'currentPeriod' }),
  publicClient.readContract({ address: POOL_ADDRESS, abi: poolAbi, functionName: 'activeMemberCount' }),
  publicClient.readContract({ address: POOL_ADDRESS, abi: poolAbi, functionName: 'cycleCompleted' }),
])
```

---

## 9. Events Reference

| Event | Meaning |
| --- | --- |
| `ChainoraPoolCreated` | New pool was created |
| `ChainoraInviteProposed` | New member proposal was created |
| `ChainoraInviteVoted` | Invite vote state changed |
| `ChainoraInviteAccepted` | Candidate accepted invite and became a member |
| `ChainoraPoolActivated` | Pool became active or started a new cycle |
| `ChainoraContributionPaid` | A member contributed for the current period |
| `ChainoraBidSubmitted` | Auction bid state changed |
| `ChainoraRecipientSelected` | Recipient and payout amount were determined |
| `ChainoraPayoutClaimed` | Recipient claimed payout |
| `ChainoraYieldClaimed` | Member claimed yield |
| `ChainoraPeriodFinalized` | Period closed and next period or cycle logic advanced |
| `ChainoraPoolArchivedOnDefault` | Pool was archived immediately because a member defaulted |
| `ChainoraArchiveRefundClaimed` | Member reclaimed a contribution from an interrupted period |
| `ChainoraExtendVoted` | End-of-cycle vote state changed |
| `ChainoraPoolArchived` | Pool entered archived state |
| `ChainoraLeftPool` | Member left an archived pool |

---

## 10. Common Revert Errors

| Error | Meaning |
| --- | --- |
| `ZeroAddress()` | Zero address used in a configuration path |
| `InvalidConfig()` | Input values or current assumptions are invalid |
| `Unauthorized()` | Caller lacks the required permission or verification |
| `InvalidState()` | Function is not valid in the current state |
| `AlreadyInitialized()` | Pool clone initialize was called twice |
| `AlreadyVoted()` | Caller already voted in the relevant round |
| `ProposalClosed()` | Invite proposal is closed |
| `ProposalNotPassed()` | Invite acceptance attempted before enough yes votes |
| `NotInvitee()` | Caller is not the invited candidate |
| `NotMember()` | Caller is not a member |
| `NotActiveMember()` | Caller is not an active member |
| `DeadlineNotReached()` | Function requires a later timestamp |
| `DeadlinePassed()` | Function missed its valid time window |
| `AlreadyContributed()` | Caller already contributed in this period |
| `ContributionMissing()` | Required current-period contributions are still missing |
| `AuctionNotOpen()` | Auction path is not open |
| `AuctionAlreadyClosed()` | Recipient is already selected |
| `NoEligibleRecipient()` | No eligible active member remains |
| `NotRecipient()` | Caller is not the payout recipient |
| `PayoutUnavailable()` | Payout or yield is not claimable now |
| `AlreadyClaimed()` | Payout already claimed |
| `PoolNotArchived()` | Function requires archived state |
| `AlreadyLeft()` | Caller already left the archived pool |

---

## 11. Typical Integration Workflows

### 11.1. Create a pool

```text
1. Read Registry.stablecoin()
2. Optionally verify creator eligibility if device adapter is enabled
3. Call Factory.createPool(config)
4. Decode ChainoraPoolCreated to get pool address
5. Store poolId -> pool address mapping
```

### 11.2. Form a pool

```text
1. Member proposes candidate with proposeInvite(candidate)
2. Existing members vote with voteInvite(proposalId, support)
3. Candidate calls acceptInvite(proposalId)
4. When targetMembers is reached, pool emits ChainoraPoolActivated and opens period 1 in `Collecting`
```

### 11.3. Run one period

```text
1. Active members approve pool spending if needed
2. Active members call contribute() before contributionDeadline
3. Eligible member optionally calls submitDiscountBid(discount)
4. After auctionDeadline, active member calls closeAuctionAndSelectRecipient()
5. Selected recipient calls claimPayout()
6. Members with yield call claimYield()
7. After period end, active member calls finalizePeriod()
```

### 11.4. Handle default and archive

```text
1. Wait until contributionDeadline passes
2. Active member calls markDefaultAndArchive(defaultedMember)
3. Pool emits ChainoraPoolArchivedOnDefault and ChainoraPoolArchived
4. Members who already contributed call claimArchiveRefund()
```

### 11.5. End-of-cycle decision

```text
1. Finish all periods until cycleCompleted() == true
2. Active members call voteExtendCycle(true/false)
3. Any false vote archives immediately
4. Unanimous true vote starts next cycle or archives if maxCycles is reached
```

---

## 12. Integration Notes

1. **Approval Management**:
   - members must approve the pool before contribution flows
   - missing allowance causes token transfer failure

2. **State Management**:
   - timestamps alone do not advance state
   - a valid member transaction is required to move the pool forward

3. **Fallback Recipient Selection**:
   - if no bid is submitted, the protocol falls back to eligible members
   - if a reputation adapter exists, it may determine the selected recipient

4. **Default and Archive Semantics**:
   - a default during `Collecting` archives the pool immediately
   - members who already contributed in the interrupted period can reclaim that contribution with `claimArchiveRefund()`
   - archive is terminal for runtime activity
   - `leaveAfterArchive()` is bookkeeping only and does not withdraw funds automatically

5. **Client Design Guidance**:
   - use events for indexing
   - use view reads for current state confirmation
   - use `periodInfo()` timestamps as the single source of truth for countdowns and button states

---

## 13. Support

If you need to extend this guide, keep the same structure for each contract function:
- Description
- Call
- Parameters
- Response
- Requirements
- Common revert cases
- Events
- Example

This keeps the contract documentation consistent with the APDU command documentation style.
