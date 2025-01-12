---
title: Discreet Log Contract Factories
date: 2025-01-11
mathjax: true
category: scriptless
description: Bitcoin smart contracts which can be extended infinitely and interrupted at any time.
---

This article describes a pattern of Bitcoin transactions to create [Discreet Log Contracts (DLCs)](https://www.dlc.wiki/) off-chain, and extend them without any on-chain transactions. I refer to them collectively as a "factory" because we can generate numerous DLCs from a single on-chain funding TX. You could also think of them as "endless DLCs" or "rolling DLCs".

- DLC Factories may be endlessly extended without any on-chain transaction. They can be interrupted and settled early by either party unilaterally, during pre-determined windows of time.
- DLC Factories are flexible and asymmetric, allowing us to create financial instruments similar to trad-fi options contracts, or stablecoin-like contracts which can be redeemed at any time for a fixed USD amount's worth of bitcoin.
- No new trusted third parties are involved. Only a passive oracle is needed, which is already a staple of traditional DLCs.
- Can be modified to fit specific use cases.

## Transaction Flow Chart

<img src="/images/dlc-factory/dlc-factory.svg">

## Setup Process

- Prepare to fund a 2-of-2 multisig UTXO shared by Alice & Bob. This encumbrance is denoted "A + B" in the diagram.
- Create two _commitment transactions_ spending the funding output, one for Alice and one for Bob.
  - A commitment TX may optionally have an absolute locktime set, to prevent the bearer from publishing it too early.
  - A commitment TX is a 1-input-1-output TX\*
  - Alice's commitment TX output can be spent if:
    - Alice and Bob both sign, OR
    - Bob signs AND
      - has _any_ valid attestation for the DLC, OR
      - has a valid liquidation attestation for some other related DLC (optional)
  - Bob's commitment TX output can be spent if:
    - Alice and Bob both sign, OR
    - Alice signs AND
      - has _any_ valid attestation for the DLC, OR
      - has a valid liquidation attestation for some other related DLC (optional)
- For each commitment TX, create a _settlement_ transaction, which spends its respective commitment transaction output.
  - A settlement TX is a 1-input-1-output TX\*
  - A settlement TX has some relative timelock, $\Delta$
  - A settlement TX output can be spent only if Alice and Bob both sign.
- Create two sets of DLC contract execution transactions (CETs) spending from Alice or Bob's respective settlement TX output.
  - One CET spends only one settlement TX - they are mutually exclusive.

<sub>\* Anchor outputs may be needed on these TXs, for cases where fee market fluctuations are a concern.</sub>

Once the contract TX structure is agreed upon, Alice and Bob adaptor-sign all the CETs with the appropriate oracle announcements.

Alice and Bob then cooperatively sign the commitment and settlement transactions, but critically each party only receives a counterparty signature on _their own respective version_ of the commitment/settlement transactions: Alice receives Bob's signature on Alice's commitment & settlement transactions, and Bob receives Alice's signature on Bob's commitment & settlement TXs. Both parties need CET adaptor signatures from each other on both branches, though, to prevent griefing. I'll explain this asymmetry in [the Analysis section](#Analysis).

After signatures are exchanged, both parties can sign and publish the funding TX. The DLC Factory is opened once the funding TX is published and mined. There is a free option here for whoever signs last, but this is also true of regular DLCs and is a known open problem.

## Settlement

To settle a DLC Factory unilaterally, we first choose which DLC we wish to settle, and publish our commitment transaction for that DLC. The commitment transaction's locktime (if set) must have matured, and the DLC attestation must not have been published yet, nor should it be published before the relative timelock $\Delta$ on the settlement spending path has expired.

Then we publish the settlement TX, which fully locks in the specific DLC. Once the settlement TX confirms, the contract is handled identically to a traditional DLC: Wait passively for an attestation, and once it is published, use the attestation to unlock and broadcast one of the adaptor-signed CETs.

This is why it is important that both parties receive a full set of CET adaptor signatures on both of their branches: If for example, Alice did not have Bob's CET adaptor signatures on Bob's CETs, then Bob could grief Alice by putting his set of transactions on-chain, and Alice would be unable to publish any of the CETs on Bob's side. If the oracle's attested outcome favors Alice, Bob can go offline and prevent Alice from claiming the money she's owed.

To settle a DLC Factory cooperatively, Alice and Bob can negotiate a new DLC they wish to fund. By default this would probably be one of the DLCs they have already agreed to enforce, but they could adjust it if desired. Once agreed, they create a _cooperative close_ transaction to spend the funding output, and then sign a single set of CETs spending it. These CETs divide the funds up according to whatever oracle announcement conditions Alice and Bob have agreed on, and they are the last CETs either of them will sign for this DLC Factory contract.

Alice and Bob then cooperatively sign and publish the cooperative close transaction, and carry on with executing a normal DLC from there. If either party stops cooperating at any point, the other can fall back on unilaterally publishing one of their commitment transactions.

## Punishment

Note that once the settlement TX is published, it is safe for either party to go offline, even after the DLC attestation is published. However, until then Alice and Bob must remain online and vigilant, watching to punish their counterparty in case they publish an old expired commitment transaction. If that happens, a participant will have until the relative locktime $\Delta$ expires to publish a punishment transaction and take the entire commitment TX output value.

Note that, like lightning, this punishment mechanism can be enforced in a way such that untrusted watchtowers can handle it independently on the participants' behalf. Simply modify the punishment path so that Alice and Bob both adaptor-sign a punishment transaction which can be unlocked by any one of the oracle's attestations. The parties then give the watchtower a copy of that transaction and a pointer to the oracle's announcement. The watchtower can unlock and publish the punishment TX if it detects the commitment transaction has been broadcast after the attestation has been published.

If the DLC is settled cooperatively, the watchtower doesn't directly learn which coins were involved with the contract, although the watchtower does learn the amount involved and which oracle event the transaction was derived from.

## Analysis

This structure allows Alice and Bob to engage with each other in multiple mutually exclusive DLCs, where either party is allowed to settle any DLC from the factory, as long as the attestation for that DLC *has not been published yet*, and won't be published for at least the relative timelock duration $\Delta$ after the commitment TX confirms. If the attestation were to be published before that time, the counterparty would be able to sweep all the money from the commitment transaction. This creates a deadline after which neither Alice nor Bob can safely publish their commitment transaction.

Why is this useful? It allows for an *indefinite rolling extension of a DLC without any on-chain transactions.* Extending a DLC Factory contract is straightforward: Simply sign a new set of CETs, settlement TXs, and commitment TXs using a new set of oracle announcements which are expected to be published further in the future. The old DLC will still be enforceable up until the aforementioned deadline. Afterward, the new DLC will take precedence, as neither party is safely able to publish the old commitment transactions. If the two parties cannot agree to extend the DLC Factory, then either party can simply publish a commitment transaction to lock in the execution of a particular DLC.

DLC Factories thereby allow us to create financial contracts which can be settled at many different times, instead of only maturing at one fixed time.

For example, Alice and Bob could create a contract for difference (CFD), a financial contract in which the participants agree to pay each other some variable amount of money based the price of a certain base asset such as gold, a stock, or even Bitcoin. This has [been done with DLCs before](https://github.com/p2pderivatives/cfd-dlc), but previous attempts at implementing CFDs with Bitcoin DLCs have always assumed a contract with a fixed maturity date, whereas most CFDs traded on traditional exchanges can be settled at any time and extended indefinitely. A DLC Factory would allow Bitcoin to mimic this highly flexible behavior of CFDs which is prized by short term traders.

You can also use this approach to create other more complex financial instruments on Bitcoin. Since the commitment transactions are asymmetrical, we can set up completely different DLCs on each side of the contract, depending on who publishes the commitment/settlement transactions. We can also prevent certain parties from settling by simply omitting their version of the commitment transaction. We could create:

- A CFD which pays out differently depending on which party initiates the settlement process.
- An option-like contract which allows only one of the contracting parties to "exercise" it.
- A stablecoin-like contract, where the bearer can redeem a fixed USD amount's worth of BTC at any time.
  - The counterparty would essentially be doing the opposite: leveraging their Bitcoin holdings to earn _even more BTC_ if the price of BTC increases. _I can imagine certain bitcoin plebs would really love this..._

## Modifications

There are several ways one could customize DLC Factories for specific use cases.

- Absolute timelocks on the commitment transactions can be used to enforce an order of precedence, so that at any one time, only some commitment transactions can be broadcast. For instance, a DLC Factory might have a DLC for each day, and each DLC might have a commitment transaction which matures at 8:00AM, for an announcement which will mature at 11:00AM. If $\Delta = 1\text{h}$, this gives the participants a window from 8:00-10:00 AM in which they can publish their commitment transactions safely. If they publish after 10:00AM, their counterparty could use the punishment path to rob them.
- Timelocks could be asymmetric between parties, so that one party can "lock-in" a DLC at certain times which the other can't. For instance, one party might be allowed to settle the DLC Factory at any time, while the other is only allowed to settle during weekday business hours.
- The commitment TX output's punishment path could use a locktime instead of an attestation encumbrance, to bequeath the money to the counterparty if the commitment transaction is published after a certain absolute time. This might be useful if the oracle's attestation timing is highly reliable, and watchtower privacy is important, as it would give a watchtower no information about the DLC Factory except for its total value.
- CETs could be asymmetric depending on who closes the factory. For instance, the closer's set of CETs might give them a slightly worse payout curve than the other party, to incentivize both parties to close the factory cooperatively rather than forcefully.
- You could add an HTLC condition to the funding output script, which would allow a trustless transfer of ownership via an on-chain transaction, potentially allowing people to purchase a position in a DLC Factory using lightning (more research needed).

## Down Sides

This ain't all chocolate and roses.

### Performance

Numeric-outcome DLCs are already incredibly slow to sign and verify, owing to the potentially large number of CET adaptor signatures involved. DLC Factories are doubly slow, because each DLC is asymmetric and requires two sets of CETs per DLC. And then of course we must do this signing procedure once for every set of commitment transactions (i.e. for every opportunity either party has to close the DLC Factory). Signing/verification performance would be best in a contract like an option, where only one party has the ability to publish a commitment transaction.

Though high, the performance cost of a DLC Factory can be amortized over time, as it is not strictly necessary for a commitment transaction to be signed until it is about to mature. So the participants might choose to sign only one DLC first, and then fund the contract, and work through the rest of the CET signatures over time.

### Liveness

The DLC participants now have a liveness requirement. In a traditional DLC, both parties can go offline even after the contract expiry time. If the oracle's attestation is not in your favor, you may simply stay offline and let the other party settle the DLC.

But DLC Factory participants, like Lightning Network channel peers, must actively monitor the blockchain to ensure their counterparty does not publish an old commitment transaction to steal money using outdated attestations. Each party must carefully ensure they are able to submit a punishment transaction in time, should this need arise.

This down side can be mitigated by watchtowers.

### Deadlocking

DLC Factory participants must also ensure they publish a commitment transaction in a timely fashion if the counterparty is not available to extend the factory's lifetime by signing a new set of commitment transactions and CETs. Otherwise the contract may enter a state where neither party has a safe way to unilaterally resolve the DLC Factory on-chain, unless both parties can come back together to conduct a cooperative close.

This is similar to how a lightning network channel peer would typically force-close a channel if their counterparty goes offline for too long, except in the case of DLC Factories there is a clear deadline at which point the Factory _must_ be settled on chain to ensure coins can be reclaimed fairly.

### Real-Life Events

DLC Factories are also not very conducive to attestations for real-world events which have flexible publishing dates.

First, the benefits are limited: Why extend a DLC Factory at all for an event which only occurs once?

Also, if an attestation could possibly be released early - such as for a sporting event which is canceled or forfeit - then the DLC Factory commitment transactions could be poisoned unexpectedly. In this case it would be useful to add an absolute timelock requirement to the punishment path of the commitment TX output, to allow parties to commit & settle a DLC if the attestation is published well ahead of the expected attestation time. Still, this format of contract works best for continuous, rolling, predictable sources of attestations, such as financial asset price data oracles.

## Summary

I've talked about DLCs a lot on this blog before, and I hope you see why I love them so much. DLCs are one of the most flexible ways to create Bitcoin smart contracts, and they can be used to simulate many classical financial instruments, as well as create novel ones we've never seen before.

If you have ideas for things to build using DLC Factories, or suggestions to improve this idea, please [let me know](mailto:conduition@proton.me)!
