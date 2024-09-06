---
title: Mercury Layer Vulnerability Disclosures Report
date: 2024-09-06
mathjax: true
category: code
description: An examination of validation vulnerabilities in the Mercury Layer client libraries.
---

# Preamble

This report applies to the [Mercury Layer Statechains](https://mercurylayer.com) protocol as of August 2024. My investigations were conducted at commit `78a9d2ce13d27cab7d73136720cbe68b8d7dab25` on the `dev` branch of [the `mercurylayer` repository](https://github.com/commerceblock/mercurylayer). The original insecure protocol implemented by this software is described [here](https://web.archive.org/web/20240824191217/https://docs.mercurylayer.com/docs/mercury-protocol/main-protocol/) (archived link). Hopefully by the time you're reading this report, these vulnerabilities have already been fixed and aren't deployed in any production systems handling real money.

## Mercury

Statechain is a protocol intended to allow Bitcoin users to securely transfer bitcoins between each other off-chain, while maintaining full ownership of the coins. Similar to ECash, Statechains rely on a semi-trusted blind server which acts as an authenticator for the off-chain transactions. Unlike ECash though, Statechains claim to be _non-custodial_ as well as blind.

> The blind key-update server never has control or custody, and is never aware of the identity of any specific UTXO.

<sup><a href="https://mercurylayer.com/">Source</a></sup>

It's unclear to me what the distinction is between "Mercury" and "Statechains", so for the remainder of this report I'm going to simply refer to this protocol as "Mercury" to avoid ambiguity.

The expected flow of a Mercury transaction is as follows:

- A user Alice creates a _statecoin_ by depositing bitcoins into a 2-of-2 address, sharing control of her coins with the Mercury server. Call her deposit transaction `tx0`.
- The mercury server gives Alice a blind signature on a timelocked transaction `tx1`, referred to as a "backup" transaction in the Mercury docs. This transaction pays all the coins from `tx0` back to Alice.
- The mercury server increments a counter for the blind signature it just created.
- Alice can give her coins to a peer Bob off-chain by having the server blind-sign a new backup transaction `tx2` with a lower timelock which pays to Bob's address instead of Alice's.
- The mercury server increments its blind-signature counter.
- Alice gives Bob `[tx1, tx2]`, and a special key called `t1` which lets Bob assume Alice's role in the 2-of-2 escrow.
- Bob can query the server for its current signature counter value, and thus confirm the server has issued exactly two signatures on transactions which spend `tx0`. He verifies the two signatures in `tx1` and `tx2` to confirm those are the two existing signatures.
- **CRUCIALLY:** Bob must validate the two transactions match the format he expects: If `tx1` has locktime $l$ then `tx2` must have locktime $l - \Delta$, where $\Delta$ is some reasonable block-interval. He must check that `tx2` pays to him, and that it is a valid usable transaction, and that no other transactions before it (like `tx1`) could supercede his transaction if he publishes `tx2` first.
- If Bob accepts the transfer as valid, the server updates its key share to match Bob's newly computed key share. The server can securely delete its old share of the 2-of-2 escrow key with Alice. By claiming to do this, the server is promising not to collude with Alice later, and promises that Bob now has sole signing power over this statecoin.
- Bob now 'owns' the statecoin UTXO created by `tx0`, in the sense that he can use `tx2` to sweep `tx0` to his control before Alice can use `tx1`, and _if the server is honest_ then he knows no other signatures were created for this particular statecoin UTXO. Or he could follow Alice's example, and transfer the statecoin to someone else off-chain in the same manner Alice did for Bob, thus saving time and mining fees.

There are additional fancy maths needed to make the server truly blind. There are also time-anchoring commitments, additional authentication signatures and other subtleties at play, but this is the core of the Mercury Statechains protocol, and it's all you really need to know for the purposes of this report.

## Custody

If you read the above high-level protocol description carefully, you'll notice that the actual money is still unspent in the original UTXO created by `tx0`. Neither `tx1` nor `tx2` have been published. If the server was malicious, it could easily defraud statecoin receivers by colluding with Alice for a double-spend attack, even after Bob has long since passed the statecoin on to a new party.

Mercury tries to mitigate risks of server compromise with [Intel SGX](https://en.wikipedia.org/wiki/Software_Guard_Extensions), but there is no way for a user's machine to verify the HTTPS server they're interacting with is actually _using_ SGX, let alone using it correctly, with a securely written SGX program. SGX doesn't protect the receiver of a Mercury statecoin from a key server which has been _designed_ to rug-pull them.

## Security Model

Given these known exceptions to the non-custodial claims made by Mercury, I will be assuming the key server is honest for the remainder of this report, as otherwise the security of Mercury would already be forfeit.

If we hold the honest-server assumption, then the mercury protocol asserts that after completion of [the transfer and keyshare-update protocol phase](https://docs.mercurylayer.com/docs/mercury-protocol/main-protocol#key-reassignment), an honest statecoin receiver Bob should be overwhelmingly confident that his ownership of the bitcoins in `tx0` _cannot_ be contested. Once the timelock expires, Bob should always be the first agent with sole capacity to claim the funding output of `tx0`.

# The Vulnerabilities

And yet, it turns out that even if the server is completely honest, an honest statecoin receiver Bob may still be defrauded by a malicious statecoin sender Alice. This is possible due to a set of implementation bugs which allow the sender too much leniency when constructing and signing Bob's backup transaction, `tx2`.

Some of these oversights allow the sender Alice to perform _griefing attacks_ which let her destroy Bob's money without probable benefit to herself. Others are easily exploitable for immediate profit by Alice.

| ID | Cause | Severity | Consequences |
|-|-|-|-|
| VULN_1 | Arbitrary sighash flags are allowed | Medium | Enables griefing of receivers |
| VULN_2 | Arbitrary TX version numbers are allowed | Medium | Permits deferred double-spending by senders |
| VULN_3 | Arbitrary TX input/output array lengths are allowed | Medium | Permits deferred double-spending by senders |
| VULN_4 | Arbitrary `tx1` locktimes are allowed | High | Permits **immediate** double-spending by senders |
| VULN_5 | Arbitrary input sequence sequence numbers are allowed | High | Permits **immediate** double-spending by senders |

Vulnerabilities are numbered in ascending order of severity. I'll now examine each in more detail.

## VULN_1: Arbitrary Sighash Flags

**Severity:** Medium
**Consequence:** Griefing of receivers
[Code reference](https://github.com/commerceblock/mercurylayer/blob/78a9d2ce13d27cab7d73136720cbe68b8d7dab25/lib/src/transfer/receiver.rs#L340)

**Summary**: When validating the signatures of statecoin backup transactions, the implementation blindly accepts the [input's taproot sighash flag](https://developer.bitcoin.org/devguide/transactions.html?highlight=sighash#signature-hash-types) from the transaction it is verifying. This means the sender has full control of which sighash flags are used by the backup transactions she creates, including the most recent one (which the receiver cares about most).

There are a number of techniques which can be applied by a malicious sender with this power.

The most obvious is that the sender could poison the latest signature using `SIGHASH_NONE`, which makes the transaction outputs malleable. Anyone who learns the signature can then spend the input however they like as long as they don't change the transaction inputs, version, or locktime.

If the receiver publishes a backup transaction poisoned in this way, they will be throwing away their coins, as any blockchain network observers could spend that input with an alternate transaction of the same inputs/version/locktime. This creates a _race-to-the-bottom_ fee-rate bidding war, as each spender outbids the last with an escalating mining fee in their attempts to claim the money. The end result is that the receiver's coins are almost all donated to the miners.

This attack is limited in severity because it doesn't present the attacker Alice with any incentive to participate in the attack, beyond causing Bob misery.

## VULN_2: Arbitrary Transaction Version Numbers

**Severity:** Medium
**Consequence:** Deferred double-spending

**Summary:** The mercury statecoin receiver code does not validate the version number of the backup transactions it is given when receiving a statecoin. The code assumes that each backup transaction has a valid standard version number (1 or 2). This can be abused to trick the receiver into accepting a non-standard backup transaction.

Bitcoin transactions are considered consensus-valid but non-standard by bitcoin network nodes if their version number is neither `1` nor `2` (little-endian encoded). Non-standard transactions are treated as spam, and are not propagated by default by Bitcoin network nodes.

To exploit this fact, Alice gives Bob a backup transaction `tx2` with a non-standard version number - `0xDEADBEEF` for instance. If Bob ever tries to broadcast `tx2`, he will have difficulty finding any nodes who will relay his transaction. Once he realizes the problem, Bob has a short window of time - probably just a few blocks - to contact a miner directly and pay to have his non-standard transaction prioritized. If Bob cannot do this within the short block interval defined by the Mercury key server, then Alice's backup transaction `tx1` will eventually unlock, and she can use it to sweep Bob's statecoin UTXO back to her control.

This vulnerability on its own is not as severe as it sounds, because Bob still has plenty of time to detect this fault and rectify the situation by cooperating with the honest key server. He might even do so unintentionally.

If Bob were to transfer the statecoin to a third party Carol in an honest fashion, then Carol's ownership of the statecoin is secure even though Bob's ownership was questionable. This is because Bob constructs Carol's backup TX, and if he does so honestly, then Carol's backup TX locktime matures before Alice's will. Carol's backup TX will be usable even though Bob's backup TX was not.

It is only while Bob _believes_ he holds the statecoin that the statecoin is vulnerable to theft by Alice. If Bob disposes of the statecoin by cooperating with the key server, then the risk of Alice effecting her deferred sweep is thwarted. But in the event the key server is taken offline before Bob can transfer the statecoin, then there is a good chance Alice will sweep the statecoin UTXO before Bob can.

*Note:* There are numerous ways for a transaction to be considered 'non-standard', so I am inclined to expect that other bugs in the same class as VULN_2 may exist in the Mercury codebase receiver validation logic.

## VULN_3: Arbitrary Outputs Array Length

**Severity:** Medium
**Consequence:** Deferred double-spending
[Code reference](https://github.com/commerceblock/mercurylayer/blob/78a9d2ce13d27cab7d73136720cbe68b8d7dab25/lib/src/transfer/receiver.rs#L353-L362)

**Summary:** The mercury statecoin receiver code lacks any validation for the length of the `TxOut` vector of the backup transactions it validates when receiving a statecoin. The code assumes that each backup transaction has only a single output, without any confirmation thereof. This offers additional flexibility to the sender when creating backup transactions.

For instance, see [the way Mercury has implemented fee rate validation](https://github.com/commerceblock/mercurylayer/blob/78a9d2ce13d27cab7d73136720cbe68b8d7dab25/lib/src/transfer/receiver.rs#L353-L362).

```rust
let fee = tx0_output.value - tx_n.output[0].value;
let fee_rate = fee as f64 / tx_n.vsize() as f64;

if (fee_rate + fee_rate_tolerance) < current_fee_rate_sats_per_byte {
    return Err(MercuryError::FeeTooLow);
}

if (fee_rate - fee_rate_tolerance) > current_fee_rate_sats_per_byte {
    return Err(MercuryError::FeeTooHigh);
}
```

- `tx0_output` is the funding output created by the depositor - Alice in our earlier example - i.e. the initial deposit UTXO which is confirmed and unspent on-chain.
- `tx_n` is the most recently signed backup transaction given by Alice, which Bob must scrutinize. If he accepts the statecoin transfer, `tx_n` will be the only option for him to recover these coins if the key server becomes unavailable.
- `current_fee_rate_sats_per_byte` is a reasonable fee rate as reported by Bob's trusted Electrum server.
- `fee_rate_tolerance` is some reasonable tolerance for fee rate ambiguity, configured by Bob.

Bob validates the `fee_rate` falls within some reasonable range (+/- `fee_rate_tolerance`) around `current_fee_rate_sats_per_byte`. If this check passes, then the `fee_rate` is considered reasonable, and _so is the output value_ - The code does not validate `tx_n.output` anywhere else.

By using `tx_n.output[0].value` as the backup transaction's output value sum and `tx0_output.value` as the input value sum for fee purposes, the mercury implementation assumes that `tx_n` has only a single input and a single output, but actually this is not always the case.

When communicating `tx_n` to the receiver, [the sender communicates the entire serialized transaction](https://github.com/commerceblock/mercurylayer/blob/78a9d2ce13d27cab7d73136720cbe68b8d7dab25/lib/src/wallet/mod.rs#L183), and the receiver [deserializes it using consensus encoding](https://github.com/commerceblock/mercurylayer/blob/78a9d2ce13d27cab7d73136720cbe68b8d7dab25/lib/src/transfer/receiver.rs#L321). No validation of the backup TX's input/output length occurs until well after the backup TX is accepted as valid, and so the sender Alice could add outputs to the transaction without Bob noticing.

Alice cannot add inputs to `tx_n`, thanks to [Bob's use of `Prevouts::All` when checking Alice's signature on the first `TxIn`](https://github.com/commerceblock/mercurylayer/blob/78a9d2ce13d27cab7d73136720cbe68b8d7dab25/lib/src/transfer/receiver.rs#L344-L346). But Alice _can_ add an additional `TxOut` without Bob noticing, and she can abuse this option to make the Bob's backup transaction `tx_n` unusable. Alice simply adds a second output with a large value, such that the sum value of all `tx_n.outputs` exceeds `tx0_output.value` (the value of all inputs). Such a transaction would not pass basic consensus validation rules. Even though it is a properly signed transaction, it is not consensus-valid, and so Bob would be unable to ever include it in a block.

In reality, Alice still controls the coins, as her timelocked backup transaction is presumably still valid. She could simply wait until her timelock expires and broadcast her backup TX to sweep the statecoin UTXO back to an address she fully controls.

Similar to VULN_2, if Bob transfers the statecoin to a third party or withdraws it on-chain via the key server, Alice loses her ability to double-spend it.

The key difference between VULN_2 and VULN_3 in terms of severity is that TX version number standardization is not consensus-critical. A backup TX with a non-standard version number can still be mined, although with greater difficulty. A backup TX crippled with invalid input/output values can _never_ be mined.

## VULN_4: Arbitrary Initial Locktime

**Severity:** High
**Consequence:** Instant double-spend
[Code reference](https://github.com/commerceblock/mercurylayer/blob/78a9d2ce13d27cab7d73136720cbe68b8d7dab25/lib/src/transfer/receiver.rs#L272-L305)

**Summary:** The mercury statecoin receiver code permits any arbitrary locktime for the initial backup transaction `tx1`. Although the decrementing locktime interval between each backup TX is validated, the overall min/max range of the backup transaction locktimes is not checked.

This permits two opposite attack approaches with distinct consequences:

1. The sender can provide a statecoin whose backup TX locktimes are in the dim and distant future, making them worthless to a non-immortal receiver. This results in a loss of money for the receiver, although only if the key-server refuses to help with recovery of the funds.
2. The sender can provide a statecoin whose backup TX locktimes are in the past, rendering all backup transactions equally valid in the present day. After the receiver accepts this statecoin, the sender can then broadcast their backup transaction, engaging the receiver in a fee-rate bidding war at any time, each party using CPFP to bump the fee on their preferred backup transaction.

Attack 2 is clearly the more threatening of the two possibilities, as it offers an immediate incentive for the sender to engage in the attack. The sender has nothing to lose, so they are likely to outbid the receiver, or at worst donate the receiver's money to the miners.

Note that this attack depends on the ability to control the initial backup TX locktime, and so the attacker must _create_ the statecoin with which they perpetrate the attack.

## VULN_5: Arbitrary Input Sequence Numbers

**Severity:** High
**Consequence:** Instant double-spend
[Code reference](https://github.com/commerceblock/mercurylayer/blob/78a9d2ce13d27cab7d73136720cbe68b8d7dab25/lib/src/transfer/receiver.rs#L272-L313)

**Summary:** The mercury statecoin receiver code does not validate the sequence numbers of backup transaction inputs when receiving a statecoin. This allows a statecoin sender to disable the locktime enforcement of her own backup transaction without the receiver noticing.

Every bitcoin transaction input has a 32-bit sequence number which handles a number of duties. Among the jobs of the sequence number is enforcing relative locktimes, and disabling a transaction's absolute locktime.

> Sequence numbers were meant to allow multiple signers to agree to update a transaction; when they finished updating the transaction, they could agree to set every input’s sequence number to the four-byte unsigned maximum (0xffffffff), allowing the transaction to be added to a block even if its time lock had not expired.
> \
> Even today, setting all sequence numbers to 0xffffffff (the default in Bitcoin Core) **can still disable the time lock,** so if you want to use locktime, at least one input must have a sequence number below the maximum. Since sequence numbers are not used by the network for any other purpose, setting any sequence number to zero is sufficient to enable locktime.

[Source](https://developer.bitcoin.org/devguide/transactions.html#locktime-and-sequence-number)

The fundamental security of the Mercury protocol relies on the consensus-level enforcement of backup transaction locktimes. Mercury's code assumes, given a set of transactions with distinct and descending locktimes, the transaction with the lowest locktime will always be the first to become usable. This is not the case, and sequence numbers are the reason why. **Statecoin senders can abuse this faulty assumption to break the fundamental security of Mercury, and immediately double spend a statecoin they transferred to an honest receiver.**

Alice constructs her backup transaction `tx1` such that all of its inputs have a sequence of `0xFFFFFFFF`. This disables locktime _and_ RBF on her backup transaction, meaning she can publish it at any time, and Bob will not be able to easily replace it. Alice then transfers the statecoin to Bob according to the normal Mercury protocol. Due to this gap in the receiver validation logic, Bob's machine fails to notice the locktime on `tx1` is not enforced, and he mistakenly accepts the statecoin transfer as valid.

Assuming Alice is buying something from Bob (e.g. a product, service, or [Lightning Latch transfer](https://docs.mercurylayer.com/docs/mercury-protocol/lightning-latch)), Alice can pay Bob this fraudulent statecoin, wait until Bob fulfills his half of the exchange, and then broadcast `tx1` to sweep the statecoin UTXO at any time of her choosing thereafter. Bob has at best a few minutes to react by trying to outbid `tx1` with a new transaction, which will be difficult given Alice has nothing to lose and can easily outbid Bob by burning more of his own money.

Unlike the other double-spending vulnerabilities VULN_2, VULN_3, and VULN_4, this attack is much more severe, for three major reasons.

First, this attack gives Bob almost no time at all to detect the fault and attempt recovery with the key server.

Second, while the other double-spend attacks are ephemeral, VULN_5 is a permanent trap laid under the statecoin Alice created: Even if Bob transfers the statecoin to a third party Carol, the original depositor Alice maintains full timelock-free spending power over the statecoin. Thus Alice can defraud Carol by way of Bob, without ever interacting with Carol.

Third, and quite significantly, the current implementation of Mercury [uses the max sequence number `0xFFFFFFFF`](https://github.com/commerceblock/mercurylayer/blob/78a9d2ce13d27cab7d73136720cbe68b8d7dab25/lib/src/transaction.rs#L218), disabling locktime on _all Mercury backup transactions_ by default. This means that all existing statecoins created or transferred using the old unsafe Mercury code are vulnerable to double-spending by _any_ previous statecoin holder with a signed backup TX, even if the previous holders were using the vanilla mercury code without any malicious intent at the time.

<sup>Side-note: Sequence numbers could also be used to create relative timelocks which make a backup TX unspendable until some distant future date. So in a way this is another instantiation of the "invalidate Bob's backup TX" class of attacks (see VULN_2, VULN_3). The locktime-nullification trick is strictly better in every way for the attacker than that approach though.</sup>

# Recommendations

First and most urgently, all statecoins should be withdrawn on-chain _immediately_ to avoid double-spending theft due to the max-sequence bug (VULN_5).

Second, the vulnerabilities should be fixed, but rather than patching each vulnerability individually, a higher-level approach should be taken.

All of the vulnerabilities discussed in this report are symptoms of a more fundamental problem: They are failures of the implementation to properly _validate the backup transactions_ given to the receiver by the sender. There are good reasons to suspect that additional bugs of the same genre exist, lurking elsewhere in the Mercury implementation. After all: it takes a _lot_ of validation to check a bitcoin transaction is consensus-valid, let alone standardized, relayable, and economical. Replicating _all_ of those checks is simply impractical, and a single validation failure could make a backup transaction unusable (or impractical to use).

My suggested solution to fix all these vulnerabilities at once is to enact a minor paradigm shift in the way Mercury backup transactions are checked.

**The sender should give the receiver a bare-minimum of data points needed to _reconstruct_ all the fully-signed backup transactions, omitting the full details of the transactions.**

The receiver should then validate the statecoin's history of signatures by independently _reconstructing_ each backup transaction according to a set of declarative rules prescribed by the protocol, e.g. always set `nSequence` to 0 for TX inputs; always use only a single input and a single output; locktime must always decrement by `n` blocks for each consecutive TX; always use `SIGHASH_ALL` for TX witnesses; etc. The sender must follow these rules when signing the backup transactions. This ensures the transactions fit all the requirements of the protocol.

Alternately, for backwards compatibility, the receiver could carefully extract the bare minimum data needed from all the backup transactions given by the sender, and thereafter reconstruct all the backup transactions from those aforementioned rules. The extraction logic would need to be very cautious about handling the untrusted input transactions.

More concretely, you might think of the sender transmitting only four data points:
- A UTXO outpoint (describing `tx0`)
- The initial locktime of the first backup transaction, `tx1`
- A vector of transaction outputs (describing each `tx_n.output[0]`)
- A vector of BIP340 signatures (proving each `tx_n` was signed by the key server)

The receiver reconstructs the remainder of the backup transactions, filling in the blanks with the sender's data once they have validated critical properties, such as "the most recent TX must pay a reasonable amount to Bob's address" or "the locktimes must be a reasonable time in the future". The transaction construction logic may also be _versioned,_ to encourage compatibility as the protocol changes over time.

If all signatures pass verification, then Bob knows his statecoin is spendable because _he_ built the backup transactions using a procedure he knows to be safe. If the sender's backup transactions deviate from the prescribed structure in any way, the receiver's transactions won't match and TX signature verification will fail.

This approach hardens the receiver's implementation against malicious transaction design by taking away the sender's ability to _give_ badly designed transactions in the first place, thus eliminating large classes of attacks (including all of the attacks in this report) which are dependent on the flexibility of input currently available to the statecoin sender.

No new risk is introduced to the sender, as long as they follow the same strict TX-construction procedure when signing the backup transaction.

## Conclusion

This set of vulnerabilities is a lesson in how difficult it is to manually validate signed Bitcoin transactions from untrusted sources. There are simply too many variables at play for most implementations to keep up with.

A safe rule-of-thumb for multi-party Bitcoin transaction protocols, especially L2 protocols which operate off-chain, is to _reduce as much as possible the quantity of information transmitted between parties._ Not only does this improve efficiency of the protocol, but more importantly, we can reduce the amount of data each party needs to validate, limiting attack surface.

Ideally, the parties of a Bitcoin protocol should be imbued with shared knowledge of how to conduct themselves (e.g. how to construct backup transactions) without the need to communicate that information (e.g. without sending fully serialized TXs back and forth). Even the slightest deviation from the agreed protocol (e.g. a maliciously built TX) should be caught with a bare minimum of validation, such as a Schnorr signature verification check.
