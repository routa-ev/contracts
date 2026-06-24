# Routa Payment Channel Suite — Security Audit

**Scope:**

- `RoutaPaymentChannel.sol`
- `RoutaPaymentFactory.sol`
- `IRoutaPaymentChannel.sol`
- `IRoutaPaymentFactory.sol`
- `BaseTransfer.sol`

**Audit date:** June 21, 2026

---

## Summary

| #   | Finding                                                                                            | Severity      |
| --- | -------------------------------------------------------------------------------------------------- | ------------- |
| C-1 | Reentrancy in `claim`/`refundPayment`/`revokePayment`/`emergencyRelease` (transfer-before-effects) | **Critical**  |
| H-1 | Implementation contract initializable by anyone                                                    | High          |
| H-2 | `close()` doesn't gate any state-mutating function                                                 | High          |
| M-1 | Permit signature front-run/griefing                                                                | Medium        |
| M-2 | Off-chain reference squatting                                                                      | Medium        |
| M-3 | Fee-on-transfer token accounting mismatch                                                          | Medium        |
| M-4 | Slug collision across different deployers                                                          | Medium        |
| L-1 | Zero-amount payments accepted                                                                      | Low           |
| L-2 | No zero-address validation on `receiver`/`owner` in `initialize()`                                 | Low           |
| L-3 | Centralized `emergencyRelease` with arbitrary receiver                                             | Low           |
| L-4 | `getPayment()` returns silent zero defaults for unknown IDs                                        | Low           |
| L-5 | No duplicate-token check in factory deploy params                                                  | Informational |

---

## Critical

### C-1: Reentrancy in `claim()`, `refundPayment()`, `revokePayment()`, and `emergencyRelease()` — funds transferred before state is updated

All four fund-moving functions follow this pattern:

```solidity
if (payment._token == ETHER) {
    _transferNative(receiver, _amount);   // external call happens FIRST
} else {
    _transferERC20(payment._token, receiver, _amount);
}
payment._amount -= _amount;               // state updated AFTER
```

`_transferNative` (in `BaseTransfer.sol`) uses a raw `.call{value: amount}('')`, which hands control to the recipient before any bookkeeping happens. There is no `ReentrancyGuard` anywhere in `RoutaPaymentChannel` or `BaseTransfer`.

**Impact:**

- In `claim()`, the recipient is the channel's configured `receiver`. If that address is ever a contract and becomes compromised or malicious, it can re-enter `claim()` repeatedly with the same `_paymentId` before `payment._amount` is decremented, draining the _entire pooled contract balance_ for that token — not just the allocation for the one payment being claimed.
- In `refundPayment()` and `revokePayment()`, the recipient is `payment._payer` — and **the payer is always attacker-controlled**, since anyone can be a payer. An attacker pays using a malicious contract as `_msgSender()`, then calls `revokePayment()` (no special permission required beyond being the payer of record). On receiving the native refund, the attacker's fallback function re-enters `revokePayment()` (or `refundPayment()`/`claim()`) on the _same_ `_paymentId` before `_revoked`/`_amount` are set, draining the channel's entire balance for that token — including funds belonging to other payers in the same channel.
- `emergencyRelease()` has the identical ordering bug. The blast radius is smaller since it's gated to a trusted "team" address, but the pattern is still unsafe.

**Recommendation:** Apply checks-effects-interactions consistently — mutate state (`payment._amount -= ...`, `_refunded = true`, `_revoked = true`, `_released = true`) **before** the external transfer in all four functions. Add `ReentrancyGuard`/`nonReentrant` as defense in depth, since both native transfers and `safeTransfer`/`safeTransferFrom` can hand control to recipient code (fallback functions, or `tokensReceived` hooks for ERC777-style tokens).

---

## High

### H-1: Uninitialized implementation contract — anyone can call `initialize()` on the master copy

`initialize()` has no access control beyond:

```solidity
if (factory != address(0)) revert AlreadyInitialized();
```

The constructor never sets `factory`, so the deployed _implementation_ contract (the one referenced by `RoutaPaymentFactory.channelImplementation`, as opposed to its clones) sits permanently uninitialized and callable by anyone. An attacker can call `initialize()` directly on the implementation and become its "owner."

This does not compromise existing or future clones — each clone has independent storage via `delegatecall` under the EIP-1167 pattern — but it is a well-known implementation-contract footgun. It enables impersonation/phishing (an attacker-"initialized" contract sitting at the known, documented implementation address) and is trivially avoidable.

**Recommendation:** In the constructor, set a sentinel value that blocks future initialization (e.g. `factory = address(this);`), or adopt OpenZeppelin's `Initializable` pattern and call `_disableInitializers()` in the constructor.

### H-2: `close()` doesn't actually gate anything

No function — `claim`, `payWithERC20`, `payWithNative`, `refundPayment`, `revokePayment` — checks `status == ChannelStatus.Active`. Calling `close()` only flips the `status` enum and emits `ChannelStatusChanged`; every payment, claim, and refund path continues to function identically before and after closure.

If `close()` is intended as a circuit breaker (e.g., ahead of a receiver migration, or in response to a detected issue), it currently provides no actual protection — it's effectively dead weight.

**Recommendation:** Add `if (status != ChannelStatus.Active) revert ChannelNotActive();` to whichever of the payment/claim/refund/revoke paths are meant to be frozen on closure. Decide explicitly which operations (if any, e.g. refunds) should remain available while closed, and encode that intent in the checks.

---

## Medium

### M-1: Permit signature front-run / griefing

In `payWithERC20`, the decoded `permitSignature` is necessarily visible in the mempool before it's mined. Anyone can extract `(v, r, s)` from the pending transaction and call `token.permit()` directly with the same parameters ahead of the real transaction, consuming the payer's nonce. The original `payWithERC20` call then reverts when it tries to call `permit()` itself.

**Impact:** Denial-of-service griefing — no funds are at risk, but a legitimate payer's transaction can be repeatedly front-run and cancelled, with no on-chain cost to the griefer beyond gas.

**Recommendation:** Wrap the `permit()` call in a try/catch and fall through to checking the resulting `allowance()` instead of reverting outright — a standard mitigation for this exact griefing pattern.

### M-2: Off-chain reference squatting

`_ensurePristineReference` makes `ref` strictly one-time-use on a first-come-first-served basis, with no binding to a specific intended payer or payment amount ahead of time. If `ref` values are predictable (e.g., sequential off-chain order IDs, which the naming strongly implies), an attacker can front-run a legitimate payer by submitting a trivial/dust payment using the same `ref`, permanently consuming it and blocking the real payment from ever completing under that reference.

**Recommendation:** Either bind `ref` usage to a specific expected payer/amount (e.g., a commitment scheme), or treat `ref` purely as an off-chain convenience label rather than an on-chain uniqueness guarantee.

### M-3: Fee-on-transfer / non-standard ERC20 accounting mismatch

`_transferFromERC20` records `payment._amount = _amount` — the nominal amount requested — without checking the contract's actual balance delta. If `_token` is a fee-on-transfer or rebasing token, the channel will record more value than it actually received. Later `claim()`/`refundPayment()` calls for that payment (or pooled funds for other payments in the same token) can then fail, or in adverse scenarios succeed by drawing down balance that belongs to other payments.

**Recommendation:** If only well-behaved, standard-compliant tokens are meant to be whitelisted, state this explicitly as an operational/deployment assumption documented for whoever curates `paymentTokens`. Otherwise, verify the actual balance delta around the transfer and use that as the recorded amount.

### M-4: Slug collision across different deployers

`Clones.cloneDeterministic`'s salt is `keccak256(_offChainSlug, sender, _tokens)`, so two _different_ `sender` addresses can each deploy a distinct channel claiming the same `_offChainSlug`. `offChainSlugToPaymentChannel[slug]` is simply overwritten by whichever `deploy()` call lands last on-chain — there is no uniqueness enforcement on the public slug registry itself, only on the exact `(slug, sender, tokens)` tuple.

**Impact:** Off-chain systems that resolve a channel purely by slug could be silently pointed at the wrong — or an attacker's — channel after a competing deploy.

**Recommendation:** Either scope slugs to be unique per-sender by design (and have integrators resolve by `(sender, slug)`), or enforce global slug uniqueness in `deploy()` by reverting if `offChainSlugToPaymentChannel[_offChainSlug] != address(0)`.

---

## Low / Informational

**L-1: Zero-amount payments accepted.** Neither `payWithERC20` nor `payWithNative` guards against `_amount == 0`. Zero-value payments still create a real `Payment` record, consume a `ref`, and emit events — mostly a spam/noise risk rather than a fund-safety issue.

**L-2: No zero-address validation in `initialize()`.** A zero `_receiver` doesn't block payments coming in, but it permanently blocks `claim()` once a payment is released, since `BaseTransfer` reverts on `to == address(0)`. This silently bricks fund release for any payment that reaches the `released` state under a misconfigured channel.

**L-3: Centralized `emergencyRelease` with arbitrary receiver.** `emergencyRelease` lets "team" (the factory's `owner()`) redirect a payment's full amount to an arbitrary `_receiver` parameter rather than the channel's configured `receiver`. This is presumably intentional design for emergency recovery flexibility, but it's worth stating explicitly: it's a fully centralized, single-key trust assumption spanning _every_ channel deployed by the factory. Compromise of the factory owner key allows draining all active channels' unreleased payments to addresses of the attacker's choosing.

**L-4: `getPayment()` returns silent zero defaults.** Querying a nonexistent `_paymentId` returns all-zero struct fields rather than reverting, which integrators could misread as "a real, zero-value payment" rather than "no such payment exists."

**L-5: No duplicate-token check in factory deploy params.** `_params._tokens` is not checked for duplicates before being stored as `paymentTokens`. Harmless beyond a slightly longer linear scan in `_checkTokenIsAllowed` and minor storage waste.

---

## Priority Recommendation

Fix **C-1** before any mainnet deployment — it is a direct, payer-triggerable drain of pooled channel funds (not merely a self-inflicted footgun), exploitable today by any payer using a malicious contract address and the native-token payment path. **H-1** and **H-2** should be resolved in the same pass, as both are cheap, mechanical fixes with outsized downside if skipped.
