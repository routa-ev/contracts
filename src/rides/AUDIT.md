# Routa EV-Ride Escrow System — Security Audit

**Scope:** `RoutaEvRideFactory.sol`, `RoutaEvRide.sol`, `RoutaEvRideEscrow.sol`, `BaseTransfer.sol`, and associated interfaces (`IRoutaEvRide`, `IRoutaEvRideEscrow`, `IRoutaEvRideFactory`, `IRoutaGeo`)

**Audit type:** Manual review (logic, access control, signature scheme, value flow)

**Disclaimer:** This is a manual, point-in-time review and is not a substitute for a professional third-party audit, formal verification, or fuzzing/invariant testing (Foundry, Echidna, Halmos) prior to mainnet deployment.

---

## Credits

**Auditor:** Claude (Anthropic), at the request of Kingsley
**Review type:** Manual code review of provided source files
**Date:** June 20, 2026

---

## Summary

| #   | Finding                                                                                                          | Severity    |
| --- | ---------------------------------------------------------------------------------------------------------------- | ----------- |
| 1   | `RoutaEvRideFactory.deploy()` — driver/payer consent unbound from ride terms (`_messageHash` is caller-supplied) | 🔴 Critical |
| 2   | `RoutaEvRide.fulfill()` / `cancel()` — static, non-domain-separated message enables cross-ride signature replay  | 🔴 Critical |
| 3   | `_actionHash` lock enables unilateral fund-lock / griefing between payer and driver                              | 🟠 High     |
| 4   | `emergencyCancel()` missing `status == IN_PROGRESS` guard                                                        | 🟠 High     |
| 5   | ERC-2612 `permit()` signature is front-runnable (signature griefing DoS)                                         | 🟡 Medium   |
| 6   | No check that `payer != driver` (self-dealing)                                                                   | 🟡 Medium   |
| 7   | `Escrow.deposit()` not enforced "callable once" despite NatSpec claim                                            | 🟡 Medium   |
| 8   | Escrow has no independent accounting / invariant checks                                                          | ⚪ Low      |
| 9   | Clone implementation contract has no disabled initializer                                                        | ⚪ Low      |
| 10  | `trustedForwarder` compromise spoofs `_msgSender()` across factory & ride                                        | ⚪ Low      |
| 11  | `feeBps` / `cancellationFeeBps` unbounded (no `<= 10000` check)                                                  | ⚪ Low      |
| 12  | `GeoCoords` lat/lng has no range validation                                                                      | ⚪ Info     |

---

## 🔴 Critical Findings

### 1. `RoutaEvRideFactory.deploy()` — driver consent is unbound from ride terms

**Location:** `RoutaEvRideFactory.sol::deploy()`

```solidity
(bytes memory a, bytes memory b) = _splitConsolidatedSignature(_params._consolidatedSignature);
bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(_params._messageHash);
address _payer  = ECDSA.recover(ethSignedHash, a);
address _driver = ECDSA.recover(ethSignedHash, b);
```

`_messageHash` is a plain `bytes32` field on `DeploymentParams`, supplied directly by the caller. **No code path recomputes this hash from the actual deployment parameters** — `_token`, `_amountPayable`, `_feePercentageBps`, `_cancellationFeePercentageBps`, the coordinates, or `_offChainReference`. The contract simply trusts whatever hash value the caller passes and recovers two signers from it.

**Impact:**
The driver's (and, structurally, the payer's) signature proves only that the signer once signed _some_ hash equal to the value supplied in this call — it proves nothing about agreement to the specific ride terms being deployed. Because `_checkPayer` only requires `_payer == msg.sender`, an attacker acting as payer can:

1. Obtain (or reuse) a driver's signature `b` over some hash `H` that the driver signed for a legitimate, unrelated purpose.
2. Submit `_messageHash = H` together with **arbitrary** `_params` — different token, inflated `_amountPayable`, maximal `_cancellationFeePercentageBps`, fabricated route — and a fresh `_offChainReference`.
3. Deploy a ride binding that driver to terms they never reviewed or agreed to.

This breaks the core trust assumption of the dual-signature design: signatures must cryptographically commit to the data they authorize, not to an arbitrary hash chosen by the relayer/caller.

**Remediation:**
Stop accepting `_messageHash` as input entirely. Compute it on-chain via EIP-712, binding the digest to the actual struct fields and to the contract's domain (chain ID + `address(this)`):

```solidity
bytes32 constant RIDE_TYPEHASH = keccak256(
    "RideTerms(address token,uint256 amountPayable,uint24 feeBps,uint24 cancellationFeeBps,bytes32 startCoordsHash,bytes32 endCoordsHash,bytes32 offChainRefHash)"
);

bytes32 structHash = keccak256(abi.encode(
    RIDE_TYPEHASH,
    _params._token,
    _params._amountPayable,
    _params._feePercentageBps,
    _params._cancellationFeePercentageBps,
    keccak256(abi.encode(_params._startCoords)),
    keccak256(abi.encode(_params._endCoords)),
    keccak256(bytes(_params._offChainReference))
));

bytes32 digest = _hashTypedDataV4(structHash); // inherit OZ EIP712
address _payer  = ECDSA.recover(digest, a);
address _driver = ECDSA.recover(digest, b);
```

Inherit OpenZeppelin's `EIP712` in the factory; never recover against an externally supplied hash.

---

### 2. `RoutaEvRide.fulfill()` / `cancel()` — static message enables cross-ride signature replay

**Location:** `RoutaEvRide.sol::fulfill()`, `RoutaEvRide.sol::cancel()`

```solidity
bytes32 messageHash = keccak256(abi.encodePacked('RoutaEv:fulfill')); // identical in cancel(): 'RoutaEv:cancel'
bytes32 signedHash  = MessageHashUtils.toEthSignedMessageHash(messageHash);
address signer      = ECDSA.recover(signedHash, signature);
```

This hash is **identical across every ride clone ever deployed by the factory.** It contains:

- no `address(this)` / contract identity,
- no chain ID,
- no ride or escrow identifier,
- no nonce,
- no reference to the ride's actual terms (amount, fee, parties).

A payer's or driver's signature over `"RoutaEv:fulfill"` (or `"RoutaEv:cancel"`) is valid **forever, on every ride** where that address happens to be set as `payer` or `driver`. These signatures are not confidential:

- They are passed as a plaintext calldata argument (visible in the public mempool and permanently in tx history).
- They are also stored in `_fulfillmentSignatures` — declared `private`, but Solidity's `private` only restricts _Solidity-level_ access; the raw storage slot is trivially readable on-chain via `eth_getStorageAt`.

**Impact:**
Anyone who captures one `fulfill` or `cancel` signature from a user can replay it against **any other ride** that user is a party to — with completely different amounts, fee splits, and penalty calculations than the ride they actually signed for. This allows forced premature payout release or forced cancellation without the signer's consent for that specific ride.

**Remediation:**
Adopt the same EIP-712 pattern used in Finding #1. Because each ride is its own minimal-proxy clone with a distinct address, simply inheriting `EIP712` (whose domain separator includes `address(this)`) and signing a typed struct automatically scopes every signature to exactly one ride:

```solidity
bytes32 constant FULFILL_TYPEHASH = keccak256("Fulfill(address ride,uint8 action)");

bytes32 structHash = keccak256(abi.encode(FULFILL_TYPEHASH, address(this), uint8(0) /* fulfill */));
bytes32 digest = _hashTypedDataV4(structHash);
address signer = ECDSA.recover(digest, signature);
```

Consider also adding an explicit `deadline` parameter to bound signature validity in time.

---

## 🟠 High Findings

### 3. `_actionHash` lock enables unilateral fund-lock / griefing

**Location:** `RoutaEvRide.sol::fulfill()`, `cancel()`

```solidity
if (_actionHash != bytes32(0) && _actionHash != messageHash) revert InvalidAction();
```

Whichever action — `fulfill` or `cancel` — receives the **first** valid signature permanently locks the ride to that action type. If the payer signs `fulfill` first, the driver can no longer call `cancel()` even if the ride legitimately needs to be cancelled (vehicle breakdown, dispute, no-show), and vice versa. The only escape hatch is `emergencyCancel`, gated entirely behind the team owner.

**Impact:** Either counterparty can unilaterally force the ride into a state requiring manual team intervention to resolve, indefinitely locking the counterpart's funds in escrow in the interim.

**Remediation:** Document this as an intentional dispute-arbitration trigger, and/or add a self-serve timeout: if one party has signed `fulfill` and a configurable window elapses without the second signature, allow the other party to call `cancel()` instead of requiring team mediation.

---

### 4. `emergencyCancel()` missing status guard

**Location:** `RoutaEvRide.sol::emergencyCancel()`

```solidity
function emergencyCancel(uint256 _payerAmount, uint256 _driverAmount) external {
    address sender = _msgSender();
    address team = Ownable(factory).owner();
    if (sender != team) revert OnlyTeam();
    require(_payerAmount + _driverAmount == amountPayable, 'Invalid amounts');
    // ⚠️ no status check, unlike fulfill()/cancel()
    ...
}
```

Unlike `fulfill()` and `cancel()`, this function does not check `status == Status.IN_PROGRESS`. The team can invoke it on a ride that is already `COMPLETED` or `CANCELLED`, overwriting `status` and emitting a misleading `StatusChanged` event. Actual fund transfers would likely revert (escrow already drained), but the missing invariant removes a safety net and can corrupt on-chain/off-chain state consistency in edge cases (e.g., dust remaining in escrow).

**Remediation:**

```solidity
if (status != Status.IN_PROGRESS) revert NotAllowed();
```

---

## 🟡 Medium Findings

### 5. ERC-2612 `permit()` signature is front-runnable

**Location:** `RoutaEvRideFactory.sol::deploy()`

```solidity
(uint8 v, bytes32 r, bytes32 s) = _getVRSFromSignature(permitSignature);
IERC20Permit(_params._token).permit(_payer, address(this), _params._amountPayable, deadline, v, r, s);
```

The `(v, r, s)` permit signature is visible in calldata before the transaction is mined. Anyone observing the pending transaction can extract it and call `permit()` on the token directly, consuming the payer's nonce. The factory's subsequent internal `permit()` call then reverts, causing the entire `deploy()` transaction to fail — a cheap, repeatable denial-of-service against ride creation.

**Remediation:** Check existing allowance first and treat `permit()` as best-effort:

```solidity
if (IERC20(token).allowance(_payer, address(this)) < amount) {
    try IERC20Permit(token).permit(_payer, address(this), amount, deadline, v, r, s) {} catch {}
}
if (IERC20(token).allowance(_payer, address(this)) < amount) revert InsufficientAllowance();
```

---

### 6. No check that `payer != driver`

**Location:** `RoutaEvRideFactory.sol::deploy()`

Nothing prevents `_payer == _driver`. Combined with any future incentive, rebate, or points program, this is a self-dealing / wash-trading vector.

**Remediation:**

```solidity
if (_payer == _driver) revert SelfRideNotAllowed();
```

---

### 7. `Escrow.deposit()` not enforced "callable once"

**Location:** `RoutaEvRideEscrow.sol::deposit()`

The interface NatSpec states deposit _"Can be called by anyone, and just once"_ — but this is not enforced on-chain. It is currently safe only because the factory's `approve()` + `deposit()` sequence happens to execute exactly once per ride. There is no state flag preventing a second call.

**Remediation:**

```solidity
bool private _deposited;

function deposit() external {
    if (_deposited) revert AlreadyDeposited();
    _deposited = true;
    ...
}
```

---

## ⚪ Low / Informational Findings

### 8. Escrow has no independent accounting

`payout()` and `emergencyPayout()` trust whatever the ride contract (`factory` in escrow's terminology) reports, with no independent tracking of total deposited vs. total disbursed. Any bug in the ride contract's logic propagates directly to fund loss with no backstop at the escrow layer.

**Remediation:** Track `totalDeposited` at `deposit()` time and assert cumulative payouts never exceed it.

### 9. Clone implementation contract has no disabled initializer

`rideImplementation` (the EIP-1167 template) can have `initialize()` called directly on it. This is harmless today because clones use `DELEGATECALL` with separate storage, so calling `initialize()` on the implementation only affects the implementation's own unused storage. Still, this relies on an architectural invariant holding forever.

**Remediation:** Explicitly disable initialization on the implementation contract in its constructor as defense-in-depth.

### 10. `trustedForwarder` compromise spoofs `_msgSender()`

A malicious or compromised `trustedForwarder` can spoof `_msgSender()` in `_checkPayer` (factory) and the team check in `emergencyCancel` (ride). This is the standard ERC-2771 trust assumption, but given it gates both deployment authorization and emergency fund movement, the forwarder contract should be under timelock/multisig control rather than a single key, and should itself be audited.

### 11. `feeBps` / `cancellationFeeBps` unbounded

`initialize()` does not check that `_feeBps` or `_cancellationFeeBps` are `<= 10000` (100%). Out-of-range values cause checked-arithmetic underflow reverts downstream in `cancel()` (denial of service on that ride), but no fund loss.

**Remediation:**

```solidity
if (_feeBps > BASE_BPS || _cancellationFeeBps > BASE_BPS) revert InvalidFeeBps();
```

### 12. `GeoCoords` has no range validation

`startLat`/`startLng`/`endLat`/`endLng` are stored as raw `int256` with no validation against valid latitude (±90°) / longitude (±180°) ranges. Data-hygiene issue, not a security vulnerability.

---

## Priority Recommendations

1. **Before any further testing or deployment:** fix Findings #1 and #2 (EIP-712 domain separation for both the factory's deployment signatures and the ride's fulfill/cancel signatures). These are the load-bearing fixes — everything else is secondary while consent and authorization can be forged or replayed.
2. Add the `emergencyCancel` status guard (#4) and the escrow deposit lock (#7) — both are one-line, low-risk fixes that close real gaps.
3. Address the permit front-running DoS (#5) before relying on this flow in production, since it's a free, repeatable way to grief ride creation.
4. Treat the `_actionHash` griefing vector (#3) as a product/design decision — decide explicitly whether team-mediated resolution is acceptable or whether a timeout-based fallback is needed.
5. Re-run Foundry fuzz/invariant tests (and ideally Echidna or Halmos) against the corrected EIP-712 signing scheme, since the digest construction changes are the kind of thing that's easy to get subtly wrong (struct encoding, dynamic-type hashing for `string`/`bytes` fields, domain separator caching across clones).
