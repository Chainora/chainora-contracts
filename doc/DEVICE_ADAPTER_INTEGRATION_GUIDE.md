# Device Adapter Integration Guide - Chainora

## Introduction

This document describes the main contract calls required to integrate with the Chainora device verification adapter.

It is intended for application developers who need to:
- discover the configured device adapter address
- read device verification state for a wallet
- prepare backend-signed attestations
- submit device verification transactions from the dapp
- handle admin and governance flows related to verifier management
- react to events and common revert conditions

The guide follows the same command-reference style as the main contract integration guide, but focuses only on the device adapter flow.

---

## Contract Structure

The device verification flow involves three integration layers.

- `ChainoraProtocolRegistry`: exposes the configured `deviceAdapter` address
- `ChainoraDeviceAdapter`: verifies EIP-712 attestations and stores wallet verification state
- backend verifier service: validates card/device information off-chain and signs attestations with a trusted private key

For normal application integrations, the primary contracts are:
- `ChainoraProtocolRegistry`
- `ChainoraDeviceAdapter`

For operational and governance integrations, also consider:
- `ChainoraProtocolTimelock`

---

## Deployment Address Template

Fill in the actual deployed addresses for each environment.

| Network | Registry | Device Adapter | Timelock | Trusted Backend Verifier |
| --- | --- | --- | --- | --- |
| Local | `TBD` | `TBD` | `TBD` | `TBD` |
| Testnet | `TBD` | `TBD` | `TBD` | `TBD` |
| Mainnet | `TBD` | `TBD` | `TBD` | `TBD` |

---

## Protocol Rules and Constraints

Before sending transactions, keep these rules in mind.

- the adapter does not verify raw card or device data on-chain
- the backend verifier must validate the user off-chain, then sign an attestation for the wallet address
- the attestation payload is `DeviceVerificationAttestation(address user,uint256 nonce,uint64 deadline)`
- the transaction sender must be the same as `attestation.user`
- `attestation.nonce` must match `nextNonce(user)` at submission time
- `attestation.deadline` must not be expired when the transaction executes
- the recovered signer must be present in `trustVerifier`
- once a user is verified, repeated `submitVerification()` calls revert until governance revokes that user
- `revokeUser(user)` clears the verified flag and increments nonce so stale attestations cannot be reused
- if the protocol factory or pool module uses this adapter, unverified users cannot create pools or submit join requests

---

## 1. Registry Discovery

### 1.1. `deviceAdapter()`

**Description**: Returns the configured device adapter address from the protocol registry.

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

## 2. Device Adapter Read Methods

### 2.1. `isDeviceVerified(address user)`

**Description**: Returns whether the wallet is currently marked as device-verified.

**Call**:

```solidity
function isDeviceVerified(address user) external view returns (bool)
```

**Parameters**:
- `user`: wallet address to query

**Response**:
- `bool`: `true` if verified, `false` otherwise

**Example**:

```ts
const isVerified = await publicClient.readContract({
  address: DEVICE_ADAPTER_ADDRESS,
  abi: deviceAdapterAbi,
  functionName: 'isDeviceVerified',
  args: [userAddress],
})
```

---

### 2.2. `nextNonce(address user)`

**Description**: Returns the next required attestation nonce for a wallet.

**Call**:

```solidity
function nextNonce(address user) external view returns (uint256)
```

**Parameters**:
- `user`: wallet address to query

**Response**:
- `uint256`: nonce that the backend must sign into the next attestation

**Example**:

```ts
const nextNonce = await publicClient.readContract({
  address: DEVICE_ADAPTER_ADDRESS,
  abi: deviceAdapterAbi,
  functionName: 'nextNonce',
  args: [userAddress],
})
```

---

### 2.3. `trustVerifier(address verifier)`

**Description**: Returns whether an address is an approved backend verifier.

**Call**:

```solidity
function trustVerifier(address verifier) external view returns (bool)
```

**Parameters**:
- `verifier`: backend signer address

**Response**:
- `bool`: `true` if trusted, `false` otherwise

**Example**:

```ts
const isTrusted = await publicClient.readContract({
  address: DEVICE_ADAPTER_ADDRESS,
  abi: deviceAdapterAbi,
  functionName: 'trustVerifier',
  args: [backendVerifierAddress],
})
```

---

### 2.4. `timelock()`

**Description**: Returns the timelock address that governs verifier updates and user revocation.

**Call**:

```solidity
function timelock() external view returns (address)
```

**Parameters**: None

**Response**:
- `address`: timelock address

**Example**:

```ts
const timelock = await publicClient.readContract({
  address: DEVICE_ADAPTER_ADDRESS,
  abi: deviceAdapterAbi,
  functionName: 'timelock',
})
```

---

## 3. User Verification Command

### 3.1. `submitVerification(DeviceVerificationAttestation attestation, bytes signature)`

**Description**: Verifies a backend-signed EIP-712 attestation and stores the wallet as verified.

**Call**:

```solidity
function submitVerification(
    (address user, uint256 nonce, uint64 deadline) attestation,
    bytes signature
) external
```

**Parameters**:
- `attestation.user`: wallet being verified
- `attestation.nonce`: nonce that must equal `nextNonce(user)`
- `attestation.deadline`: last valid timestamp for the attestation
- `signature`: 65-byte ECDSA signature created by a trusted backend verifier

**Response**: None

**Requirements**:
- `attestation.user` must not be the zero address
- `msg.sender` must equal `attestation.user`
- `isDeviceVerified(attestation.user)` must currently be `false`
- current block timestamp must be less than or equal to `attestation.deadline`
- `attestation.nonce` must equal `nextNonce(attestation.user)`
- the recovered signer must exist in `trustVerifier`

**Result**:
- `isDeviceVerified(user)` becomes `true`
- `nextNonce(user)` increments by `1`

**Common revert cases**:
- `Errors.ZeroAddress()`
- `Errors.AttestationUserMismatch()`
- `Errors.AlreadyVerified()`
- `Errors.AttestationExpired()`
- `Errors.InvalidAttestationNonce()`
- `Errors.InvalidAttestationSignature()`
- `Errors.UntrustedVerifier()`

**Event**:
- `ChainoraDeviceVerified(address user, address verifier, uint256 nonce)`

**Example**:

```ts
const attestation = {
  user: walletClient.account.address,
  nonce: nextNonce,
  deadline: BigInt(Math.floor(Date.now() / 1000) + 300),
}

const txHash = await walletClient.writeContract({
  address: DEVICE_ADAPTER_ADDRESS,
  abi: deviceAdapterAbi,
  functionName: 'submitVerification',
  args: [attestation, signature],
})
```

---

## 4. EIP-712 Payload Construction

### 4.1. Domain Values

The adapter expects a fixed EIP-712 domain.

**Domain**:

```text
name: "ChainoraDeviceAdapter"
version: "1"
chainId: current network chain id
verifyingContract: deployed device adapter address
```

**Primary Type**:

```text
DeviceVerificationAttestation
```

**Type Definition**:

```text
DeviceVerificationAttestation(address user,uint256 nonce,uint64 deadline)
```

---

### 4.2. Backend Signing Example

**Description**: Example backend flow using `ethers` to sign a valid attestation.

**Example**:

```ts
import { Wallet } from 'ethers'

const signer = new Wallet(BACKEND_PRIVATE_KEY)

const domain = {
  name: 'ChainoraDeviceAdapter',
  version: '1',
  chainId,
  verifyingContract: DEVICE_ADAPTER_ADDRESS,
}

const types = {
  DeviceVerificationAttestation: [
    { name: 'user', type: 'address' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint64' },
  ],
}

const value = {
  user,
  nonce,
  deadline,
}

const signature = await signer.signTypedData(domain, types, value)
```

**Backend checklist**:
- read the correct `chainId`
- use the deployed adapter address as `verifyingContract`
- sign the latest `nextNonce(user)`
- keep `deadline` short enough to reduce replay risk
- return both `attestation` and `signature` to the dapp

---

## 5. Typical Dapp and Backend Workflow

### 5.1. Verify a wallet before pool actions

```text
1. Dapp reads Registry.deviceAdapter()
2. Dapp reads DeviceAdapter.isDeviceVerified(user)
3. If already verified, continue to pool creation or join flow
4. Otherwise dapp reads DeviceAdapter.nextNonce(user)
5. Dapp sends wallet address, nonce, and off-chain card/device data to backend
6. Backend validates the user and signs the EIP-712 attestation
7. Dapp calls DeviceAdapter.submitVerification(attestation, signature)
8. Dapp waits for confirmation
9. Dapp re-reads isDeviceVerified(user)
10. User proceeds to Factory.createPool(...) or Pool.submitJoinRequest()
```

---

### 5.2. Recommended preflight checks in the dapp

Before submitting the transaction, the dapp should validate:
- `attestation.user === connected wallet address`
- `attestation.nonce === nextNonce(user)` from a fresh read
- `attestation.deadline > now`
- `signature` is not empty
- `deviceAdapter` is not the zero address

---

## 6. Governance and Admin Commands

These calls are timelock-only and are typically executed through governance tooling, not regular dapp flows.

### 6.1. `setTrustVerifier(address verifier, bool allowed)`

**Description**: Adds or removes a trusted backend signer.

**Call**:

```solidity
function setTrustVerifier(address verifier, bool allowed) external
```

**Parameters**:
- `verifier`: backend signer address
- `allowed`: `true` to trust, `false` to remove trust

**Response**: None

**Requirements**:
- caller must be the configured timelock
- `verifier` must not be the zero address

**Common revert cases**:
- `Errors.Unauthorized()`
- `Errors.ZeroAddress()`

**Event**:
- `ChainoraDeviceTrustVerifierSet(address verifier, bool allowed)`

---

### 6.2. `revokeUser(address user)`

**Description**: Clears a wallet's verified state and invalidates pending attestations by incrementing nonce.

**Call**:

```solidity
function revokeUser(address user) external
```

**Parameters**:
- `user`: wallet to revoke

**Response**: None

**Requirements**:
- caller must be the configured timelock
- `user` must not be the zero address

**Result**:
- `isDeviceVerified(user)` becomes `false`
- `nextNonce(user)` increments by `1`

**Common revert cases**:
- `Errors.Unauthorized()`
- `Errors.ZeroAddress()`

**Event**:
- `ChainoraDeviceVerificationRevoked(address user, uint256 nextNonce)`

---

## 7. Events Reference

| Event | Meaning |
| --- | --- |
| `ChainoraDeviceTrustVerifierSet` | Trusted backend signer list changed |
| `ChainoraDeviceVerified` | A user attestation was accepted and stored |
| `ChainoraDeviceVerificationRevoked` | A user's verified status was revoked and nonce advanced |

---

## 8. Common Revert Errors

| Error | Meaning |
| --- | --- |
| `ZeroAddress()` | Zero address used in attestation or governance input |
| `Unauthorized()` | Caller is not the required timelock |
| `AlreadyVerified()` | User already has verified status |
| `AttestationExpired()` | Attestation deadline has passed |
| `AttestationUserMismatch()` | Transaction sender does not match attested user |
| `InvalidAttestationNonce()` | Attestation nonce does not match `nextNonce(user)` |
| `InvalidAttestationSignature()` | Signature format or ECDSA recovery is invalid |
| `UntrustedVerifier()` | Signature recovered to an address that is not trusted |

---

## 9. Typical Integration Workflows

### 9.1. Verify a new user

```text
1. Read Registry.deviceAdapter()
2. Read DeviceAdapter.isDeviceVerified(user)
3. Read DeviceAdapter.nextNonce(user)
4. Send off-chain verification request to backend
5. Backend signs EIP-712 attestation
6. Wallet calls submitVerification(attestation, signature)
7. Wait for ChainoraDeviceVerified event or receipt confirmation
```

### 9.2. Retry after revoke

```text
1. Governance calls revokeUser(user)
2. Dapp reads nextNonce(user) again
3. Backend signs a fresh attestation using the new nonce
4. Wallet calls submitVerification(attestation, signature) again
```

### 9.3. Rotate backend signer

```text
1. Governance calls setTrustVerifier(oldSigner, false)
2. Governance calls setTrustVerifier(newSigner, true)
3. Backend starts signing with the new private key
4. Dapp may optionally preflight trustVerifier(newSigner) for diagnostics
```

---

## 10. Integration Notes

1. **No On-Chain Raw Card Data**:
   - do not send raw card information or device secrets on-chain
   - only the attested wallet, nonce, deadline, and signature are required by the contract

2. **Nonce Handling**:
   - always read `nextNonce(user)` immediately before requesting a backend signature
   - any successful verification or governance revoke increments nonce

3. **Deadline Handling**:
   - short validity windows reduce replay exposure
   - if the deadline expires before mining, request a fresh attestation

4. **Signature Handling**:
   - the contract only trusts the recovered signer address
   - returning a public key to the dapp is optional and not used on-chain

5. **Dapp UX Guidance**:
   - read `isDeviceVerified(user)` before showing verification prompts
   - surface clear reasons for failed verification transactions
   - after a successful verification, continue directly to pool creation or join flow

---

## 11. Support

If you need to extend this guide, keep the same structure for each device adapter function:
- Description
- Call
- Parameters
- Response
- Requirements
- Common revert cases
- Events
- Example

This keeps the adapter documentation consistent with the rest of the Chainora contract integration documentation.
