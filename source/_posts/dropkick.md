---
title: DropKick - A Minimal Commit/Reveal Rescue Protocol
date: 2026-07-19
mathjax: true
category: bitcoin
description: Rescue quantum procrastinators by letting them prove their chronological superiority to a quantum attacker.
---

<sub>This work was [funded by a Brink grant](/bitcoin/my-first-grant/).</sub>

I've recently seen a number of posts on X and the mailing list regarding rescue protocols for Bitcoin's quantum procrastinators, and there seems to be a good deal of misunderstandings flying around. I attribute this to the unfortunate fragmentation in the literature on this subject.

In this post, I'd like to clear up confusion by showcasing past works on commit/reveal, their shortcomings and proposed mitigations, then finish by proposing a minimal commit/reveal protocol that I call _DropKick_ and discussing its costs & benefits. I believe DropKick serves as the most convenient, scalable, and suitable candidate for a post-quantum rescue protocol to deploy on Bitcoin.

If you're already familiar with rescue protocols and commit/reveal proofs, I suggest skipping straight to [the section on DropKick](#DropKick).

## Rescue Protocols

In case you're not familiar with the motivating problem of _quantum procrastinators_, basically the issue is that a large chunk of the Bitcoin supply is going to be exposed to quantum attackers when/if Q-day rolls around, no matter how many people proactively migrate to PQ-safe wallets. It would be really nice if we could soft-fork in a new rule to consensus to authenticate spenders of these vulnerable UTXOs, such that the authentic coin holders could pass this check, but that quantum attackers could not. This is called a "rescue protocol".

If designed correctly and deployed at the right time, a rescue protocol could minimize quantum theft, and maximize the number of authentic coin holders who can recover their coins after Q-day even if they don't take any proactive measures to secure their coins with PQC before Q-day.


## Knowledge Asymmetries

Rescue protocols are only possible because of _Knowledge Asymmetries_ between honest users and quantum attackers. A knowledge asymmetry ("KA" for short) is a piece of secret information that an honest key-holder would have, but which even an advanced quantum attacker does not have and cannot compute or guess.

Some examples of known Knowledge Asymmetries on Bitcoin include:

- Public keys for hashed address types like P2PKH which haven't been published before Q-day.
- Parent BIP32 xprivs used to derive account-level keys, e.g. an xpriv at key path `m/44'/0'`.
- Parent BIP32 xpubs used to derive address-level keys, e.g. an xpub at key path `m/44'/0'/0'`.
- Taproot internal keys.
- MuSig key aggregation contexts.

<sub>If you know of more asymmetries, please <a href="mailto:conduition@proton.me">message me!</a></sub>

These pieces of information typically stay secret after Q-day, because while a quantum computer may have the ability to break ECDLP and invert public keys, we assume they cannot efficiently find [2nd preimages](https://en.wikipedia.org/wiki/Preimage_attack) to the SHA256 hash function.

These KAs are quantum-secure because, in one form or another, they are all _preimages_ in a different computational pipelines which eventually spit out a Bitcoin address, like how a P2PKH address is derived from a pubkey, which is itself derived from a sequence of BIP32 keys, which are in turn derived from a seed phrase.

The point of a rescue protocol to add some (admittedly contrived) rules to Bitcoin's consensus, rules such as:

> This coin can only be spent by proving it was derived via hardened BIP32.

These rules would exploit the existence of KAs to shield inactive users (procrastinators) from quantum attackers, while still allowing the coins to be recovered in _the majority of cases._

I say "majority of cases" here, because it's not always possible to tell if a UTXO can be recovered using certain KAs.

For example, if you're given an arbitrary UTXO, it's not possible to tell at a glance whether that UTXO's address is a multisig, or a single-signer, or if it was derived using BIP32, etc. You can make some heuristic assumptions, like

> Old addresses are unlikely to use BIP32 and newer ones are more likely to use BIP32.

...but you can never be sure.

The only exceptions to this pickle that I'm aware of are hashed addresses and taproot internal keys.

- Hashed addresses (P2SH, P2PKH, P2WSH, P2WPKH) with hidden preimages can be enumerated via blockchain data. When Q-day comes, we can easily identify which addresses have hidden keys and which are exposed. Project Eleven does exactly this today, with their [Bitcoin Risq List](https://bitcoin-risq-list.projecteleven.com/).
- Taproot [BIP341](https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki#cite_note-23) specifies that every P2TR address should commit to a merkle root, even if no script spending paths are needed. This is codified for BIP32 wallets in [BIP86](https://github.com/bitcoin/bips/blob/master/bip-0086.mediawiki#address-derivation). So it seems safe to assume almost all P2TR addresses have an internal key.

In these cases, we can tell if a given UTXO supports either KA. In all others, we cannot.

New technical term needed here: If we can confidently enumerate the set of all Bitcoin UTXOs covered by a given KA at any given time, then we call that KA **decidable.** Otherwise we call it **undecidable.**


## Proof Systems

Great, so we've got a bunch of KAs, and in some cases we can identify which UTXOs a KA can cover, and in other cases we can't.

But how do we actually _use_ these KAs?

We need a _proving system,_ to allow an honest user to construct some kind of proof that she knows the _witness_ (secret data) for a specific KA. The signer attaches this proof to her transaction, presumably in some novel extension field. A Bitcoin node verifier can then check this proof against the UTXO's locking script, and if the proof is valid, and the rest of the legacy consensus rules are satisfied, then the spend is allowed.

**Note that the legacy Bitcoin consensus rules must also be satisfied, and so legacy witnesses (keys + signatures) are also needed because otherwise the upgrade to activate the rescue protocol would be a hard fork.**

We know of two such ways to do this:


### SNARKs

PQ-secure ZK-SNARKs, such as those recently [benchmarked by Laolu](https://groups.google.com/g/bitcoindev/c/Q06piCEJhkI) and [by Project Eleven](https://www.projecteleven.com/blog/proving-crypto-ownership-after-q-day), can turn a knowledge asymmetry into a binary or arithmetic circuit, and the honest signer can prove (in zero-knowledge) that she knows the witness as an input to that circuit.

This works for BIP32, taproot, and MuSig KA's, but not for hashed addresses. A hashed-address proof is just a proof the signer knows the preimage which computes her address, e.g. a pubkey for P(W)PKH, or a script for P2(W)SH. Such a proof would be trivial to forge by any classical attacker as soon as he sees the honest signer's spending transaction, given that (unless we assume a hard fork) the signer always needs to publish her address preimage in the spending TX.

SNARKs are nice for this because they are

- **Self-contained:** SNARKs are non-interactive. The verifier needs only the proof, and nothing else, to authenticate a rescue attempt.
- **Succinct:** One ZK-SNARK proof can, in theory, prove authorization over an effectively unbounded number of UTXOs, possibly across multiple transactions.

The main drawbacks of SNARK-based rescue protocols are:

- **Performance:** SNARK proving times typically run on the order of seconds for more complex statements. Recent developments like [Binius](https://www.binius.xyz/) and [Flock](https://blog.succinct.xyz/introducing-flock/) are promising improvements and the state-of-the-art is improving rapidly. Verification time runs often into the multiple milliseconds, several orders of magnitude slower than EC or hash-based signature verification.
- **Size:** PQ ZK-SNARKs are typically hundreds of kilobytes large, regardless of circuit complexity. To scale the SNARK approach, we'd either need massive witness discounts, or _recursive proofs_ that aggregate many individual proofs into one. The former is unpalatable in the wake of the BIP110 spam debate. The latter is difficult to fit into the architecture of Bitcoin - It seems like the responsibility for aggregating proofs would fall on miners, but it's not clear how to properly incentivize them to perform expensive proving computations.
- **Complexity:** SNARKs are mathematically complex beasts to implement, full of opportunities for small implementation mistakes. In theory the security assumptions of hash-based SNARKs are minimal, but in practice their implementation complexity leads to broad attack surface especially in circuit design, as [ZCash developers recently encountered](https://x.com/zooko/status/2062644925590900980). A break in soundness would mean that proofs could be forged. A break in zero-knowledge would expose users' secret witnesses to short-exposure attacks, rendering the ostensibly "protected" coins unsafe to rescue.


### Commit/Reveal

Commit/reveal protocols are a way to use a reliable timestamping service as the backbone of an authentication scheme. First proposed in [this 1998 paper](https://doi.org/10.1145/302350.302353), and later suggested as a means to design [FawkesCoin: a cryptocurrency without any public key cryptography][fawkescoin].

The idea behind FawkesCoin is thus:

- Find a secure hash function $H$.
- Pick a secret preimage $x$ and compute $y = H(x)$.
- Share $y$ as your public key (or receiving address).
- To sign a message $m$, run a three-step process:
  - Publish a _commitment_ $H(x, m)$ on-chain.
  - Wait a few blocks (until $H(x, m)$ cannot be reorged out).
  - Publish a _reveal_ containing $(x, m)$ on-chain.
- To verify a reveal on $m$, check that $H(x) = y$ and $H(x, m)$ is present on-chain.

The security is based on the fact that, assuming the blockchain is append-only, the authentic signer (the user who generated $x$) is the one who inserted $H(x, m)$ into the blockchain _first._

There are many additional subtleties to address, but this is the core idea of commit/reveal protocols, and they work not just to prove knowledge of hash preimages, but also to prove knowledge of solutions for any arbitrary [NP-complete problem](https://en.wikipedia.org/wiki/List_of_NP-complete_problems) in general (i.e. any problem for which solution-checking is fast).

For example, to prove knowledge of a Sudoku solution $x$, I can simply modify the public key $y$ to be a Sudoku puzzle with solution $x$. The verifier checks $x$ is a valid Sudoku solution once it is revealed.

Most PQ knowledge asymmetries are also NP-complete problems, so this generality means commit/reveal protocols can be applied as proof systems for proving _any KA_ in a Bitcoin PQ rescue protocol, without any heavy cryptography like SNARKs. Commit/reveal proofs are _much_ smaller than SNARKs, and are orders of magnitude faster to verify. They do have a few drawbacks which I'll discuss in the next sections, but most can be mitigated.

Commit/reveal protocols have been discussed numerous times on the mailing list and in the cryptographic literature (see [References](#References)).

For the rest of this article I will focus on commit/reveal proofs, and this will lead us towards a simple but effective design I call _DropKick_, which avoids most of the common footguns and complexities present in prior commit/reveal protocol proposals. DropKick focuses on implementation simplicity, and makes a small security concession in return (stay with me, it's not so far-fetched).

Before describing DropKick, let's define the knowledge asymmetry interface we need so our proof system generalizes over any knowledge asymmetry.


## Quantum-Hard Functions

Any knowledge asymmetry on Bitcoin can be abstracted as a _quantum-hard one-way function._ I'll now define what I mean by that.

Let $\mathbb W$ be the _space of possible witnesses._ (e.g. the space of all BIP32 xprivs)

Let $\mathbb S$ be the _space of all statements._ (e.g. the space of all Bitcoin addresses)

Let $f: \mathbb W \rightarrow \mathbb S$ be _quantum-hard one-way function,_ i.e. a polynomial-time algorithm such that anyone can compute $s = f(w)$ in reasonable time, but a randomized polynomial-time quantum adversary given only $s = f(w)$ can find a valid witness $w'$ such that $f(w') = s$ only with negligible (tiny) probability.

For example, in BIP32, $f$ might be an address-derivation pipeline, which includes the `BIP32-CKDPriv` function. In this case, the _witness_ $w \in \mathbb W$ would be a tuple consisting of the parent secret key, chaincode, derivation path, and address format instructions. The _statement_ $s \in \mathbb S$ would be a derived Bitcoin address. This function is _quantum-hard one-way_ because inverting it would involve finding 2nd-preimages in the HMAC-SHA256 function used by `BIP32-CKDPriv`.


## Proving a Witness with Commit/Reveal

To reframe FawkesCoin-style commit/reveal in the context of a quantum-hard function, we change the protocol slightly to use $f$ when generating keys and verifying reveals:

- Find a quantum-hard one-way function $f$.
- Pick a secret witness $w \in \mathbb W$ and compute $s = f(w) \in \mathbb S$.
- Share $s$ as your public key (or receiving address).
- To sign a message $m$, run a three-step process:
  - Publish a _commitment_ $H(w, m)$ on-chain.
  - Wait a few blocks (until $H(w, m)$ cannot be reorged out).
  - Publish a _reveal_ containing $(w, m)$ on-chain.
- To verify a reveal on $m$, check that $f(w) = s$ and $H(w, m)$ is present on-chain in a prior block.


# Problems

I'll now discuss the many problems with a naive FawkesCoin design as I described above, and the various mitigations available. This serves as background to justify the design choices of DropKick.


## Two-Step Signing

The signing procedure in [FawkesCoin][fawkescoin] is fundamentally a two-step process, with a mandatory delay between the _commit_ and _reveal_ steps. Once we know which message $m$ we wish to sign with our witness $w$, we must publish $H(w, m)$, and then wait for confirmations before publishing $(w, m)$ in-the-clear.

If we publish $(w, m)$ before $H(w, m)$ is mined, then an attacker who sees $w$ (e.g. in the mempool) can pick his own malicious message $m' \neq m$, and may try to publish $H(w, m')$ on-chain first. If he succeeds in getting $H(w, m')$ mined first before $H(w, m)$, then the attacker will be able to forge a reveal by publishing $(w, m')$ in the next block. We, the honest signer, have no recourse, because we cannot prove we knew $w$ before the attacker.

If we wait, but not for long enough, and publish $(w, m)$ after $H(w, m)$ has received only one or two confirmations, then the block containing $H(w, m)$ could be orphaned or reorged out of the chain, giving observers a race to mine $H(w, m')$ first, and so execute a forgery.

To be secure, we must wait until the block containing $H(w, m)$ has received enough confirmations that reorgs are not a concern.

<!-- Just as with receiving Bitcoin, confirmation depth thresholds may be chosen by user preference. Some users are fine to risk it with one confirmation. In other cases (e.g. high UTXOs) may want to wait 6 confirmations or more.

In a real-world implementation of commit/reveal on Bitcoin, this would manifest as a rather queer user-experience: To salvage your legacy coins after Q-day, you would need to open your wallet once, publish the commitment $H(w, m)$, and then later, after say 6 blocks (1 hour), come back online to publish $(w, m)$ and finish claiming your coins. -->

### Mitigations

Unfortunately this UX property cannot really be mitigated, as it is the core signing procedure in any commit/reveal protocol, and arguably the biggest drawback of commit/reveal compared to SNARKs.

We can delegate the initial commitment step to an untrusted third party, but we cannot delegate the reveal step, as the third party could elect to mine his own commitment and try to forge a signature. It seems the signer must be online for both commit and reveal steps.


## Commitment Bootstrapping

Bitcoin transactions must pay fees to miners, to prevent denial-of-service attacks and preserve the scarce resources of validator nodes.

How do we pay the fees needed to include our commitment $H(w, m)$ in a block if we only have legacy UTXOs available, which we now cannot spend without first publishing a confirmed commitment? We have a chicken-and-egg problem.

### Mitigations

Prior discussions have proposed several mitigations, the main theme being the use of pre-existing PQ UTXOs.

**PQ UTXO Bootstrapping.** Use existing post-quantum-secure UTXOs to bootstrap commitments for rescuing legacy UTXOs. A holder of a PQ-secure UTXO could publish commitments (e.g. in `OP_RETURN` outputs) and so rescue her own legacy coins very easily. Those who _do not_ already have PQ UTXOs would need to acquire help from users who do. Publishing a commitment $H(w, m)$ does not require knowledge of the secret witness $w$, and so unlike the reveal step it can be safely delegated.

The problem then becomes about incentives: The PQ rescuers would need to act charitably, or be incentivized through off-chain payment (credit cards, altcoins, etc).

**Salvage Fees.** A more interesting option is an on-chain "salvage fee" (a share of the UTXO being reclaimed). If we modify the commitment step slightly so that instead of posting $H(w, m)$, we post $H(H(w), m)$, then the salvager can open the inner hash and read the message $m$ to be signed without exposing the secret witness $w$. The salvager can thereby verify that the message $m$ enforces that some share of the rescued coins be paid to him as a salvage fee before publishing $H(H(w), m)$. The salvage fee option is intriguing as it provides a means to incentivize rescue by PQ UTXO holders. This idea seems unexplored in past discussions.

**Merkle Trees.** As pointed out in the [FawkesCoin paper][fawkescoin] (Section 5.5), we could also change how commitments appear on-chain. Instead of appearing in-the-clear (e.g one `OP_RETURN` per commitment), each commitment $H(w, m)$ in the mempool could be combined into a merkle tree by a single untrusted party, who we'll call the _aggregator_. The root of that merkle tree can be published on-chain by anyone who has PQ UTXOs at a constant cost, and we call this party the _publisher_.

- The aggregator accepts commitments, possibly with anti-DoS measures like captchas, zero-knowledge proofs, proof-of-work, or micropayments, and returns merkle proofs to clients in response. He sends completed merkle roots to the aggregator.
- The aggregator occasionally publishes a 32-byte merkle root somewhere clearly visible in a block.

The aggregator and publisher _could_ be the same entity.

By the way, this is very similar to [how OpenTimestamps already works today](https://petertodd.org/2016/opentimestamps-announcement#how-opentimestamps-works). OTS is a way of producing verifiable timestamps on arbitrary messages, by aggregating many different message hashes into a merkle tree which are intermittently published in Bitcoin blocks. It's feasible that we could reuse or modify OTS architecture for the purposes of posting commitments for commit/reveal.

### PQ UTXOs Requirement

Note that all known commitment bootstrapping techniques assume the existence of a cooperative user who holds at least one PQ-safe Bitcoin UTXO and is willing to publish a small `OP_RETURN` (e.g. to publish the root of a merkle tree of commitments), possibly for compensation. But what if there are no PQ UTXO holders available? Miners can also step up to assist, by publishing a commitment merkle root in a coinbase transaction. But ultimately we always need a second party to help here.

This is the other major drawback of commit/reveal which is evidently very difficult to do away with. This could potentially be fixed if Bitcoin nodes were to trust some external timestamping server, but that seems likely insecure.


## Indexing

When validating a reveal, nodes must have access to the set of commitments. This is a problem because validators cannot tell invalid commitments from valid ones, and if validators index all commitments naively, then the invalid commitments will consume scarce memory or disk space while growing potentially unbounded.

### Mitigations

**Expiry.** One way to fix this would be to institute expiry on commitments, so that nodes only need to index commitments into a temporary cache, whose unused entries are evicted after some number of blocks. However this would handicap commit/reveal users: Reveals are no longer valid in-perpetuity, and this enables censorship attacks (see the next section), griefing, and hapless misuse.

**SCV (Simple Commitment Verification).** To address this problem more elegantly, we must ensure commitments are indexed automatically by every node without consuming additional resources beyond what is already indexed today on Bitcoin.

Thankfully this is easily possible, provided that $H(w, m)$ is covered by a block hash. Every Bitcoin node has access to the set of all block headers, which are never pruned. Any commitment can then be opened by a proof of block inclusion, a la [SPV](https://learnmeabitcoin.com/technical/networking/node/#lightweight-node) and [OpenTimestamps](https://opentimestamps.org/): A vector of byte strings, and instructions for how to combine them with hashing such that anyone can verify the commitment's inclusion in a particular block hash. We call this an _opening proof._

Note this means we cannot put commitments into inscriptions or other envelopes which reside in the segregated block witness, because pruning Bitcoin nodes delete witness data after it is validated. Requiring nodes to index commitment inscriptions would create an arbitrary rule where nodes _must_ preserve only _certain_ TX witness data, but not others, and this data would grow unbounded.

If we were to put commitments in `OP_RETURN` outputs as many have suggested in the past, this would do the trick. However there is also a more efficient option: Hide the commitments inside of script pubkeys, e.g. in a P2MR leaf script. These script pubkeys are covered by the block hash, so they suffice for security, but posting commitments inside them doesn't add any additional data to the blockchain beyond what would already be published in a typical happy-path spend. This does add additional bytes to the commitment opening proof, but this data is safely prunable and so receives a witness discount.


## Censorship

In the context of Bitcoin, we cannot treat the blockchain as a completely permissionless append-only ledger. The miners collectively hold the ultimate say over which transactions are confirmed and when, and they typically act based on financial incentives.

We must consider the possibility of one or more miners actively censoring transactions, because in this case they have an incentive to do so.

If a miner sees a reveal of $(w, m)$ for some high-value address $s = f(w)$, then the miner can try to censor $(w, m)$ by refusing to mine it, and meanwhile sneak in a new commitment $H(w, m')$, in an attempt to forge a different reveal $(w, m')$ on a malicious message $m' \neq m$. If this attack succeeds against a rescue protocol on Bitcoin, the miner could steal all the coins held on the legacy address $s$.

### Mitigations


To prevent miner censorship, we have several options discussed in the literature and forums. Many are unfortunately not applicable to Bitcoin or rescue protocols, so I'll elide those and focus on viable options for our context.

<!-- **Earliest Transfer Wins.** The first idea proposed by FawkesCoin is to allow double-spending of coins by users who posted earlier commitments. If I posted $H(w, m)$ before $H(w, m')$, then I should be able to claw back my coins from such an attack. This presents a problem to Bitcoin, because the continuity of the transaction graph would be ruptured by such double spends, breaking the fundamental security of the system. -->

<!-- **Validator Refusal.** Validator nodes can refuse to accept blocks which contain a reveal $(w, m')$ for a commitment made at height $h'$ if the node knows of another valid reveal $(w, m)$ for a commitment at some lower height $h < h'$. If a node receives a block containing such an invalid reveal, the node replies with the correct reveal $(w, m)$. The hope is that this propagates through the network, rendering the malicious block invalid. However this breaks Bitcoin's mining systems: Why would miners spend energy mining blocks which can be trivially refuted by anyone? -->

<!-- **Challenge Period.** We have previously assumed the reveal transaction to be the final stage of the rescue protocol, presumably with outputs sending to an unencumbered single-signer PQ address. With this mitigation, validator nodes enforce a _challenge period_ of some large number of blocks after a reveal is mined. During the challenge period, the outputs of the reveal transaction are temporarily timelocked, so that commitments from earlier blocks can be revealed to supersede an initial malicious reveal, and reset the challenge period timelock. The problem with this approach is that miners can profit even from failed attacks: For every two blocks the miner can censor an authentic reveal, he can insert his own commitments in sequence and reveal them in reverse order to extract mining fees from the user. In the most extreme case, the miner could dump the entire UTXO's value into fees which the miner then receives in the coinbase transaction. If such a TX can be mined, then we would have to introduce discontinuities in Bitcoin's transaction graph to allow the honest user to claw it back. -->

**Ordering.** If verifiers can sort all commitments for a given witness $w$ chronologically by age, then when $w$ is revealed, they can reject reveals for all but the valid (first) commitment, and reject all others. The FawkesCoin authors suggest a naive version of this idea in Section 4.2 of [their paper][fawkescoin], proposing that $H(w)$ be appended to every commitment on-chain. When validating, the verifier asserts that a reveal must open the chronologically earliest commitment for $w$. The authors call this "tagging". As described, this is vulnerable to short-exposure griefing attacks: The _earliest_ commitment that includes $H(w)$ on-chain isn't necessarily posted by the honest user; $H(w)$ might have been duplicated while it was in the mempool, and republished by a malicious adversary with an invalid commitment $H(w', m')$ to prevent the honest user from recovering her coins. If this occurs and $H(w', m')$ is mined before $H(w, m)$, then there is no way for a validating node to know which is the earlier valid commitment, unless the earliest one is opened.

The observation made by Tim Ruffing, and improved by Tadge Dryja, is that once $w$ is published, verifiers must be able to distinguish authentic commitments from fraudulent ones. Concretely, if every commitment $H(w, m)$ also appends $H(w)$ and $m$, then it becomes possible for validators to filter out invalid commitments and find the authentic (first) commitments. The idea is that the validator, upon seeing a witness $w$, can sort the set of all commitments indexed under $H(w)$ by age, and enumerate the oldest ones until he finds the first valid commitment $(H(w), H(w, m), m)$. The node can then reject any reveal $(w, m')$, $m' \neq m$ for more a recent commitment. This was the approach suggested by [Tadge Dryja in this thread](https://groups.google.com/g/bitcoindev/c/LpWOcXMcvk8), who was inspired by [Tim Ruffing's idea of achieving similar commitment validation properties by posting authenticated ciphertexts](https://gnusha.org/pi/bitcoindev/1518710367.3550.111.camel@mmci.uni-saarland.de).

On one hand, ordering commitments is great because it guarantees authentic spending: If you are the first to post a valid commitment, then your reveal is guaranteed and immutable.

Unfortunately, ordering comes with big drawbacks. To have ordering, we must require _every_ commitment be posted on-chain **in-the-clear,** so that validator nodes can index them all in totality. We need not just timestamping, but also _proof of publication_ for _every_ commitment. Specifically, this rules out any off-chain aggregation of commitments (e.g. OpenTimestamps). If one were to allow commitments hidden in merkle trees, then it would be impossible for validators to find an ordering on all commitments for a given witness $w$: An earlier valid commitment might exist, hidden somewhere, deep in a merkle tree.

Ordering also requires validators to maintain a full index of all commitments, keyed by $H(w)$. This would introduce a new vector for denial-of-service attacks on Bitcoin as the set of indexed commitments could grow unbounded. It is impossible for nodes to distinguish authentic commitments from invalid commitments until the reveal stage, so unopened commitments can never be pruned. Commitments could be pruned if we introduce additional rules, like _"Commitments can only be opened up for up to $X$ blocks at most."_ Doing so may be feasible but also introduces additional complexity, user-experience issues, and opens back up the possibility of miner censorship attacks.

**Delayed Reveal.** Validator nodes enforce a long block delay between commitment and reveal transactions (e.g. 100+ blocks). A malicious miner attempting to steal the coins must also satisfy this delay requirement. This delay gives an honest user plenty of time to get her reveal transaction mined, **provided that miners are not all persistently colluding to censor it.** This worsens the user experience because users must wait a long time between the _commit_ and _reveal_ steps, but it is also very simple to implement, and very challenging for a single miner to defeat without near-total hashrate dominance. Reveal transactions can also hedge against miner attacks by paying more in fees to the miners, who would miss out on the income by censoring the reveal.


## Batching

In some cases, revealing the witness $w$ when rescuing certain UTXOs will also reveal a witness for other UTXOs owned by the same user. For example, revealing one's BIP32 xpriv at `m/44'/0'` will compromise the witnesses of every UTXO in any BIP32 account under that key path. Same for revealing the preimage for a hashed address, or a P2TR internal key, for addresses holding multiple UTXOs.

### Mitigations

To prevent commit/reveal spends from exposing other UTXOs to theft, the rescue protocol must be able to _batch rescue,_ i.e. spend multiple UTXOs covered by the same witness $w$ at once. For example if $f$ is a BIP32 hardened address derivation function, the rescue protocol would need to atomically move every P2PKH UTXO across every BIP32 account under `m/44'/0'/*` in a single pass of commit/reveal. This means the commit/reveal witness is not so much a "per UTXO" witness as a "per transaction" witness, because in most common cases, the witness will authenticate multiple UTXO spends. This is also more economical and block-space-efficient.


## One-Time Signing

Once a reveal $(w, m)$ is published, we can no longer use $w$ to authenticate again in the future unless we make a new commitment. This means if $m$ is a transaction sighash, then that transaction is _fixed,_ and the user cannot change it later. If the user made a mistake (e.g. signing an invalid transaction), or needs to bump the fee on her reveal transaction, or change the output destination address, etc, the user cannot do so without first inserting a new commitment. If the user has already published her reveal transaction, then this puts her on par with an attacker trying to forge a reveal.

### Mitigations

**Key Certification.** [FawkesCoin][fawkescoin] is designed explicitly as a system to opt-out of public key cryptography entirely. This is a like "doomsday prepper" level of paranoia: On Bitcoin we will always want to have some public key cryptography, because it makes the user-experience way better because you can sign multiple messages.

To rectify this, a commit/reveal user should not directly sign a message, but instead use her commit/reveal proof to _certify_ a given public key, and use that keypair to authenticate messages. In the context of a PQ rescue protocol, should be a public key for some post-quantum cryptosystem, such as [SHRINCS](https://delvingbitcoin.org/t/shrincs-324-byte-stateful-post-quantum-signatures-with-static-backups/2158). That PQ keypair can then be used to sign the actual transactions or other messages, which can be freely changed without modifying the commit/reveal proof. This enables RBF and other features of Bitcoin that require the ability to sign multiple messages.

**Multi-Key Certification.** If the PQ cryptosystem doesn't support MPC, threshold signing, or multi-signature signing protocols, then it would be wise to admit certification of _sets of PQ keys_, so that [salvage fees](#Commitment-Bootstrapping) can be enforceable through multi-signature setups.

**Script Certification.** One could generalize Multi-Key Certification to allow a commit/reveal user to endorse any arbitrary locking script, however this may lead to excess implementation complexity and bug surface.

# DropKick

After having explored the many subtleties of commit/reveal protocols, we will now explore a concrete instance of a commit/reveal rescue protocol which I believe achieves a high degree of security, and incentivizes cooperative rescue, while keeping consensus rule changes and engineering surface minimal. I call it _DropKick,_ because it is a straightforward two-step rescue protocol where one _drops_ a commitment on-chain, and later _kicks_ the coins elsewhere.

DropKick uses the original FawkesCoin commit/reveal scheme, but selects the most straightforward set of mitigations for various subproblems whenever such mitigations are available, and prioritizes _leanness_ of any changes to consensus, namely:

- **Salvage Fees,** to incentivize PQ UTXO holders to operate servers which aggregate and publish commitments.
- **Merkle-tree aggregated commitments,** to reduce the amount of information that validator nodes must index, and encourage benevolent users to offer scalable commitment aggregation services (possibly in exchange for salvage fees).
- **SCV (Simple Commitment Verification),** to free nodes from any indexing burdens, and allow light/pruned nodes to validate reveals.
- **Delayed Reveal,** to reduce incentive for miner censorship attacks without mandating any explicit indexing or ordering of commitments. We accept the slight risk of mass miner collusion here.
- **Key Certification,** to allow users to rectify errors, RBF transactions, and equivocate when an initial transaction is not sufficient. For PQ cryptosystems which do not natively support multi-signature or admit cooperative signing through generalized MPC, we may elect to use **Multi-Key Certification** so that rescuers can be more effectively incentivized.

## Proving

More concretely, DropKick proving works as follows:

- Let $H$ be a collision-resistant hash function.
- Let $f$ be a quantum-hard one-way function $f$.
- Let $d$ be a large block delay, e.g. 1440 blocks (10 days).

1. Find a set of witnesses $w = \\{w_1, w_2, ... w_n\\}$ such that the set of all $f(w_i) = s_i$ are the addresses (script pubkeys) of Bitcoin UTXOs $u = \\{u_1, u_2, ... u_n\\}$.
    - Practically, witnesses could be merged and reconstructed later, e.g. for BIP32 xprivs deriving many addresses.
2. Generate a post-quantum signing key $Q$.
    - We could also allow $Q$ to be a multisignature group key, which would enable aggregators to cosign and enforce salvage fees on reveal transactions.
3. Post a time-anchored commitment $H(H(w), Q)$ in a block, e.g. on an `OP_RETURN`, within a script pubkey, or in a merkle tree commingling with other such commitments published in the same way.
4. Compute an opening proof $\pi$ which can be used to verify the historical provenance of the commitment $H(H(w), Q)$.
5. Once the commitment $H(H(w), Q)$ has been mined for $d$ blocks, construct a transaction $T$ spending $u = \\{u_1, u_2, ... u_n\\}$ to arbitrary outputs.
6. Sign $T$ with $Q$ and the legacy EC keys, producing a post-quantum signature $\mathbf{sig}$.
7. Produce a set of legacy TX input witnesses $W$ to satisfy legacy consensus validation rules (e.g. EC signatures).
8. Attach the witness $w$, PQ-pubkey $Q$, signature $\mathsf{sig}$, legacy witnesses $W$, and opening proof $\pi$ producing a signed reveal transaction $T' = (T, w, Q, \mathsf{sig}, W, \pi)$.
9. Publish $T'$.

## Verifying

A verifier, presented with a reveal transaction $T' = (T, w, Q, \mathsf{sig}, W, \pi)$, must:

1. Validate all legacy consensus rules against $T$ and the legacy witnesses $W$ (soft-fork compatibility).
1. Authenticate the commitment opening $\pi$, asserting $H(H(w), Q)$ was committed _at least_ $d$ blocks earlier.
1. Verify $\mathsf{sig}$ is a valid signature on $T$ under $Q$.
1. Decompose $w = \\{w_1, w_2, ... w_n\\}$.
1. For each $i \in \\{1 ... n\\}$, verify that UTXO $u_i$ has script pubkey $s_i = f(w_i)$.

If all the above steps succeed, then the verifier knows that:

- The spender knew a quantum-hard witness $w_i$ for the script pubkey $s_i = f(w_i)$ that encumbered each UTXO $u_i$.
- The spender knew these witnesses for at least $d$ blocks.
- The spender authorized the use of a PQ signing key $Q$.
- The key $Q$ authorized the transaction $T$.

This completes authentication of the spending TX $T$, predicated on the assumption that upon $w$ being initially revealed, the spender would be the only agent in possession of a valid commitment to $H(H(w), Q)$ of age at least $d$.


## Benefits

DropKick:

- ✅ generalizes to any arbitrary knowledge asymmetry (hashed addresses, BIP32, etc).
- ✅ is unforgeable against quantum attackers, provided the PQ signature scheme is also unforgeable.
- ✅ has opening proofs of size logarithmic to the number of commitments in a block.
- ✅ allows equivocation (changing your mind) on the reveal transaction details, without needing to wait for confirmations on a second commitment transaction.
- ✅ allows users to incentivize commitment aggregators and publishers via enforceable salvage fees.
- ✅ is resistant to short-term miner collusion.
- ✅ supports batched rescue of multiple vulnerable UTXOs.
- ✅ has verification complexity linear in the size of the opening proof.

DropKick doesn't:

- ❌ require a hard fork.
- ❌ permit double-spending.
- ❌ force commitments to expire.
- ❌ allow griefing.
- ❌ enable any denial-of-service attacks on Bitcoin nodes.
- ❌ allow arbitrary rotation of scripts.
- ❌ require any explicit indexing of commitments - Bitcoin block headers themselves serve to aggregate many commitments.
- ❌ require heavy cryptographic machinery, with the exception of a PQ signature scheme: It's basically just OpenTimestamps re-engineered for a new purpose.

## Drawbacks

- ⚠️ Miners can theoretically steal coins if they can persistently censor a reveal transaction for $d$ blocks.
  - This should be hard to do in practice, as a significant majority of hashpower would need to collude for a period of at least $d$ blocks.
- ⚠️ The opening proof $\pi$ could be decently large, as it would need to embed the entire transaction that contains the commitment to $H(H(w), Q)$.
  - This could be mitigated by using a standard transaction format template, which is prefilled by the verifier. This restricts the shape of commitment transactions, but makes proofs much smaller because the prover need not provide the entire commitment transaction.
- ⚠️ The reveal transaction requires at least one PQ signature, which (depending on the scheme) may be quite large.
- ⚠️ Aggregators could be flooded with spam commitments, which would inflate the size of opening proofs $\pi$ for all users of that aggregator.
  - This can be mitigated through anti-DoS measures, like captchas, proof-of-work, salvage fees, or out-of-band payments.
- ⚠️ A single PQ signature suffices to sign for a large set of UTXOs $u = \\{u_1, u_2, ... u_n\\}$. This efficiency may introduce a weird incentive where some users _want_ to use commit/reveal to consolidate many inputs together, because DropKick would admit smaller witnesses and faster signing when spending large numbers of UTXOs, compared to using a single PQ signature per input. Is this a perverse incentive, or just a roundabout way of aggregating signatures from a single signer? More study is needed.
- ⚠️ If DropKick is deployed to authenticate _undecidable_ KAs (see the section on [Knowledge Asymmetries](#Knowledge-Asymmetries)), then as with any rescue protocol that acts on undecidable KAs, the resulting soft fork would be confiscatory: Some subset of restricted legacy UTXOs - of unknown size - would be confiscated because they lack the required KAs. As far as I know this is an unsolveable problem, and DropKick makes no impact there.


## Usage

**DropKick users** benefit from a very simple rescue UX: Come online once, generate a PQ key $Q$, and _drop_ a commitment $H(H(w), Q)$ on-chain, probably by querying an aggregator server off-chain. The user stores the opening proof $\pi$ on-disk, and the user can then go offline, free to return days/weeks/months later after, provided she waits at least $d$ blocks.

The user can, at any time after $d$ blocks, _kick_ the target coins away with a reveal transaction, paying to any arbitrary destination chosen at spending time, and authorized by a signature under $Q$. If the user loses the proof $\pi$, she can just make a new one - the old opening proof is hidden in some ancient merkle tree, lost to time, but not polluting the blockchain or the UTXO set at all.

Essentially, adding the commitment is a sort of "delayed import" of her legacy coins into a PQ wallet under $Q$, and wallets can design their UX and phrasing accordingly.

> - Import a legacy wallet? y/n
> - Enter your legacy seed phrase
> - Now wait 1000 blocks and your funds will be available 😇

**Aggregation server operators** can construct the PQ pubkey $Q$ jointly in tandem with the user, as a multisignature key (e.g. through concatenation, MPC, or interactive multisignature protocols). This allows the aggregation server to enforce constraints on the reveal transaction $T$, such as enforcing the payment of salvage fees. The given $H(w)$ (which is safe for the user to share), the aggregator can construct the commitment and opening proof of $H(H(w), Q)$, and either forward the commitment to a publisher or publish it himself, while the opening proof is given to the user who verifies its inclusion when mined.

**Legacy validator nodes** will ignore unknown transaction fields, and validate spends using legacy consensus rules, which are all satisfied by the legacy witnesses in $W$.

**New validator nodes** do not need to maintain any new indexes or download additional block data, nor do they need a new cryptographic primitive: A validator simply adds an additional validation rule based on checking the outputs of hash functions, and applies this rule when verifying spends of specific classes of UTXOs according to which KA applies in a given context - This is left purposefully unspecified.

## Conclusion

While SNARKs and ZKPs may be fun to study and to benchmark, I personally doubt very much that they will see any usage on Bitcoin's consensus layer. Bitcoin's cryptographic tooling is innately very conservative, and aims for leanness, simplicity, and performance. While SNARK assumptions are minimal, their real-world code footprint is anything but.

Interestingly, ZKPs still play a useful role in DropKick, as they allow users to prove they know an authentic witness $w$ for any statement $s = f(w)$ without revealing $w$, and this permits off-chain validation of witnesses. This is useful as an anti-DoS measure for aggregators, who would naturally want to filter out spam commitment submissions, and ZKPs would let them do exactly that, with minimal consequences if the proof system is unsound. (There _are_ severe consequences if the proof system is not _zero-knowledge,_ because then a proof might reveal the secret witness $w$!)

Contrastingly, I believe commit/reveal rescue protocols like _DropKick,_ introduced above, or [Tadge Dryja's _Lifeboat_](https://www.youtube.com/watch?v=4bzOwYPf1yo), are much more suitable candidates to build rescue protocols for live deployment to Bitcoin's consensus rule set. They require only a few hash function invocations; no complex arithmetization, circuit-building, constraint systems, polynomial commitment systems, or interactive oracle proofs. DropKick opening proofs, while larger than those of Lifeboat, are much smaller than a hash-based SNARK, and about the same size as an SPV proof which is typically less than 1 kilobyte - still [smaller than most PQ signature schemes!](https://pqshield.github.io/nist-sigs-zoo/)


## References

Much of what I discussed in this article was not my original idea - It has been discussed at-length on the mailing list for years. Outside Bitcoin, the cryptographic pedigree of commit/reveal protocols stretches back as far as 1998, and has even been proposed as a way to authenticate spending on a standalone cryptocurrency (FawkesCoin).

- https://doi.org/10.1145/302350.302353
- https://jbonneau.com/doc/BM14-SPW-fawkescoin.pdf
- https://gnusha.org/pi/bitcoindev/1518710367.3550.111.camel@mmci.uni-saarland.de/
- https://eprint.iacr.org/2023/362
- https://eprint.iacr.org/2025/1307
- https://groups.google.com/g/bitcoindev/c/LpWOcXMcvk8
- https://groups.google.com/g/bitcoindev/c/jr1QO95k6Uc
- https://groups.google.com/g/bitcoindev/c/uUK6py0Yjq0
- https://www.youtube.com/watch?v=4bzOwYPf1yo

However, many of the fundamental ideas are tied up in Bitcoin-specific terminology (e.g. signing a "TXID" instead of a "message", committing a "pubkey" instead of a "witness"). Many solutions are fractured, sprinkled throughout the mailing list and with trade-offs which were either unknown at the time, or at least not clearly spelled out.

I hope this article has helped consolidate some of this scattered knowledge into one place. If you know of more commit/reveal ideas/solutions which I haven't discussed here, please [message me](mailto:conduition@proton.me)! I may have known about some ideas and elided them, but if there are any neat tricks I've missed I would love to know.

Toodles :)

[fawkescoin]: https://jbonneau.com/doc/BM14-SPW-fawkescoin.pdf
