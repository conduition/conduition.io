---
title: Discreet Log Contracts with Ecash Notes
date: 2024-05-19
mathjax: true
category: cryptography
---

Today I'd like to describe a way to use [Chaumian Ecash](https://en.wikipedia.org/wiki/Ecash) to commit to a conditional payment using an Ecash mint as a blind but trusted intermediary.

### Update 2024-05-29

I have since submitted [a proposal to the Cashu spec](https://github.com/cashubtc/nuts/pull/128) which enables DLCs on Cashu mints. The protocol therein is based on the contents of this article.

## Prerequisite Knowledge

- [Elliptic curve math basics](/cryptography/ecc-resources)
- [Discreet Log Contracts](https://bitcoinops.org/en/topics/discreet-log-contracts/) (optional but handy)
- [Ecash](https://en.wikipedia.org/wiki/Ecash) (optional but handy)

Already familiar with Ecash and DLCs? [Click here to skip to the fun parts](#DLCs-Ecash).

## Notation

Just so we're all on the same page:

| Notation | Meaning |
|:--------:|---------|
| $G$ | The [base-point of the secp256k1 curve.](https://bitcoin.stackexchange.com/questions/58784/how-were-the-secp256k1-base-point-coordinates-decided) |
|$q$ | The [_order_ of the secp256k1 curve](https://crypto.stackexchange.com/questions/53597/how-did-someone-discover-n-order-of-g-for-secp256k1). There are $q - 1$ possible valid non-zero points on the curve, plus the 'infinity' point (AKA zero). |
|$x \leftarrow \mathbb{Z}\_{q}$ | Sampling $x$ randomly from the set of integers modulo $q$. Note that we exclude zero when sampling. |
| $a\ \|\|\ b$ | Concatenation of the byte arrays $a$ and $b$. |

## Ecash

[Chaumian Ecash](https://en.wikipedia.org/wiki/Ecash) implementations backed by Bitcoin are kicking up a lot of developer activity today, and for good reason: By reviving a well-studied technology we can offer ordinary people a new wave of usability improvements, making Bitcoin-powered payment systems more approachable to businesses and customers alike.

An Ecash mint issues _Ecash notes_ in various denominations, which can be redeemed later at the mint for some fungible commodity or service (such as Bitcoin). This is conceptually very similar to the physical banks of ye olden days, which accepted deposits of some fungible asset like silver or gold, and issued _physical cash_ (paper notes or metal coins) of various denominations in return, which could be used to reclaim the equivalent amount of the physical asset.

In the case of a Bitcoin-backed Ecash mint, the mint accepts Bitcoin deposits, and issues Ecash notes which can be redeemed for Bitcoin at a future time, for as long as the mint remains solvent and operating.

The basic principles of an Ecash mint are:

- **Authenticity** - The Ecash mint can be certain the Ecash notes it creates cannot be forged by others, so that when a depositor redeems a note, the mint is safe against fraudulent withdrawals.
- **Fungibility** - Depositors can be certain the Ecash notes they receive are anonymous and fungible. Instead of the mint giving a depositor a bearer token (which would have to be recognizable by the mint later when redeemed), the depositor cooperates with the mint to _blind_ the Ecash notes they receive through a clever cryptographic protocol called _blind signatures._

### How it works

Imagine a mint, with a secret key $m$ and public key $M = mG$.

Imagine Alice, a user who makes a \\$1 deposit into the Ecash mint, and expects an equivalent amount of Ecash in return.

Let $H'(x) \rightarrow P$ be a hash function which maps some input $x$ to a point $P$ on the secp256k1 curve, in such a way that the discrete log of $P$ is unknowable. [Here is an example of one such a hash function](https://github.com/cashubtc/nuts/blob/6024402ff8bcbe511e3e689f6d85f5464ecc3982/00.md#hash_to_curvex-bytes---curve-point-y).

1. Alice samples some random scalar $r \leftarrow \mathbb{Z}\_{q}$

2. Alice picks a random secret $x$ and hashes it into a point $Y = H'(x)$

3. Alice gives the point $A = Y + rG$ to the mint.

4. The mint blindly signs Alice's blinded point $Q = mA$ and returns $Q$ to Alice. This point is called the _promise._

5. Alice unblinds the promise $Q$ into a _proof_ $Z$.

$$
\begin{align}
Z &= Q - rM \\\\
  &= mA - rM \\\\
  &= m(Y + rG) - rmG \\\\
  &= mY + rmG - rmG \\\\
  &= mY \\\\
\end{align}
$$

The pair of values $(x, Z)$ is a bearer token which Alice can give back to the mint at a time of her choosing. But because only Alice knows $r$ and $x$, only she knows the token $(x, Z)$, and so nobody can link that token to her deposit - at least, not mathematically.

To verify the authenticity of this token later at redemption time, the mint can check:

$$ Y = H'(x) $$
$$ mY = Z $$

The only other way for someone to have constructed $Z$ would have been to compute $yM = mY = myG = Z$ given the discrete log $y$ such that $yG = Y$. However, the hash-to-curve function $H'(x)$ Alice used ensures that no such $y$ can be knowable, and so the only way Alice could know $Z$ is if the mint itself created $Z$ using its secret key $m$.

The above is the essence of Ecash, but there are some gotchas to clean up:

- The cryptography alone doesn't protect against replay attacks or double-spending. Alice could resubmit $(x, Z)$, and so the mint must remember which values of $Z$ have already been redeemed.
- Only the mint can verify its own Ecash notes. For Alice to pay someone with an Ecash note, the recipient must be able to swap out the note for a fresh one by contacting the mint directly. The recipient hasn't been paid until they successfully swap Alice's Ecash note for a fresh one which only they know.
- So far I've assumed the mint only has a single key pair $m$ and $M = mG$. In reality the mint needs a way to distinguish between notes of different denominations (\\$1, \\$5, \\$50, etc) and Ecash mint implementations usually do this by having _multiple keys:_ one per denomination.


## Discreet Log Contracts

[Discreet Log Contracts (or DLCs for short)](https://bitcoinops.org/en/topics/discreet-log-contracts/) are a powerful cryptographic tool to enable conditional payments natively on Bitcoin.

A conditional payment is a payment which could be distributed to different recipients, in varying amounts, depending on some pre-agreed outcome or condition. The payment could be funded by a single party or by multiple participants who cooperatively commit their funds to the contract. Examples include sports betting, insurance contracts, futures contracts, poker, etc.

The subject of DLCs is deep, so I will not delve into that here. There are already numerous resources available online describing how DLCs work canonically on Bitcoin.

Today I want to describe how the same fundamental mechanics with which DLCs enable conditional payments on Bitcoin can _also_ be used to enable conditional payments with Ecash, while significantly improving privacy for the participants. Scalability is significantly better than on-chain or even Lightning.

Instead of a full description of DLCs, let me distill the concept down to the minimum we need for this article.

DLCs require that there exist one or more _oracles_ who can be trusted to attest to the true outcome of some event. These oracles operate publicly, broadcasting signed _announcements_ for future events, and later publishing a cryptographic _attestation_ when the outcome of that event is clear. Oracles should, by design, be unaware of who or how many people are subscribing to their attestations.

- Think of an _announcement_ as being a list of possible outcomes, each with a corresponding _locking point_ $K_i$ (for outcome index $i$).
- Think of an _attestation_ as revealing the discrete log of _only one_ of those locking points (the one corresponding to the true outcome), i.e. revealing $k_i$ such that $k_i G = K_i$.
- If the oracle reveals more than one of those locking secrets, their long-term credibility as an oracle is immediately gone, and any fraud can be proven succinctly.

_The above is a simplification, not how DLCs actually work._ In a real DLC, the oracle publishes a signature with a pre-announced nonce point. If you'd like to learn how DLCs actually work, I suggest reading [the original paper by Tadge Dryja](https://adiabat.github.io/dlc.pdf). But for our purposes today, this conceptual framework will do just fine.

# DLCs + Ecash

Let's say there exists some public oracle who promises to reveal a locking secret for one of the locking points $\\{K_1, K_2, K_3\\}$ for 3 possible outcomes of an event. If we let $i$ be the outcome which actually occurs, the oracle will reveal $k_i$ such that $k_i G = K_i$.

Alice and Bob want to place a wager on that event without trusting each other to pay up if they lose. Both parties will fund the DLC with \\$100 each.

- If $k_1$ is revealed, then Alice wins all $200.
- If $k_2$ is revealed, then Bob wins all $200.
- If $k_3$ is revealed, both Alice and Bob receive a refund, and get their $100 back.
- If no secret is revealed (timeout case) by the timestamp $t$, then both parties also receive a refund.

Alice and Bob _could_ conduct an on-chain DLC to execute this wager, which would be perfectly secure and trustless, but may not be economically practical for small amounts of bitcoin. On-chain DLCs also have privacy consequences: Alice and Bob's coins are associated on-chain forever.

If both Alice & Bob trust a common Ecash mint, they can conduct the same wager, still without trusting each other and without exposing the subject of their wager to the mint. Thus, the mint cannot censor their DLC based on the _kind_ of wager they are making (insurance contract or a poker game, both are indistinguishable to the mint). Although the mint does learn the final payout structure, and the total amount involved in the DLC, it doesn't learn anything about the other unused possible outcomes or their payout structures.


## Bird's Eye

At a high-level:

- Alice and Bob will cooperatively construct a pre-funded DLC package which Alice sends to the mint.
- The mint registers the DLC and waits for someone to claim winnings from one of the outcomes.
- Once an outcome has been claimed, the mint locks in the outcome and awaits any other possible payouts.
- After all payouts are claimed, the mint can purge the DLC from its memory.

## The Protocol

- Let $H(x)$ be a secure hash function, such as SHA256.
- Let $H'(x) \rightarrow P$ be a hash function which maps some input $x$ to a point $P$ on the secp256k1 curve, in such a way that the discrete log of $P$ is unknowable. [Here is an example of one such a hash function](https://github.com/cashubtc/nuts/blob/6024402ff8bcbe511e3e689f6d85f5464ecc3982/00.md#hash_to_curvex-bytes---curve-point-y).
- Let $d_a$ be Alice's payout secret, with corresponding public payout hash $D_a = H(d_a)$.
- Let $d_b$ be Bob's payout secret, with corresponding public payout hash $D_b = H(d_b)$.

1. Alice samples a random outcome blinding secret.

$$ b \leftarrow \mathbb{Z}\_q $$

She masks the outcome locking points with the blinding secret.

$$
\begin{align}
K_1' &= K_1 + b G \\\\
K_2' &= K_2 + b G \\\\
K_3' &= K_3 + b G \\\\
\end{align}
$$

This layer of blinding will obscure each $K_i$ from the mint, so that the mint cannot censor Alice and Bob based on the subject of their wager.

<details>
  <summary>Why can Alice do this without Bob's involvement?</summary>

It might seem odd that Alice can generate the blinding secret $b$ and perform the outcome blinding independently without input from Bob. Wouldn't this expose Bob to the possibility that Alice might maliciously choose these secrets in order to give her some advantage in resolving the DLC?

Thankfully this is not possible, because in order to resolve the DLC with the mint, Alice must eventually learn the discrete log of some $K_i' = K_i + b G$, which implies knowledge of the discrete log of $K_i$ as well. Bob would detect any attempt to cheat at step 6, when he verifies the correct locking points were used to register the DLC.

There is also no privacy risk here, because Alice already has the ability to doxx her and Bob's wager details to the mint if she wanted. The sole purpose of the outcome blinding secret is to obscure the subject of the DLC from the mint. This is also why we can use a single secret instead of unique random secrets for each outcome.

</details>


2. Alice encodes the payout structure $P_i$ for each DLC outcome $i$, with each participant in the payout identified by their public payout hash, and a corresponding weight for that participant. For instance, the payout for outcome $i = 3$ might be encoded as:

$$
P_3 := D_a\ \|\|\ 1\ \|\|\ D_b\ \|\|\ 1
$$

... where $\|\|$ denotes byte-wise concatenation. The weights (1) for each participant denote their relative shares of the winnings. 1:1 means a 50%/50% split, 3:1 means a 75%/25% split, etc.

The payout structure $P_2$, where Bob is the sole beneficiary, would look like this:

$$ P_2 := D_b\ \|\|\ 1 $$

There is also the payout structure for the timeout outcome, denoted $P_t$.

3. Alice pairs each blinded locking point $K_i'$, with the corresponding payout structure $P_i$ into a set of _branches,_ $\\{T_1, T_2, T_3\\}$.

$$
\begin{align}
T_1 &= (K_1', P_1) \\\\
T_2 &= (K_2', P_2) \\\\
T_3 &= (K_3', P_3) \\\\
\end{align}
$$

There is also the timeout branch, which is constructed slightly differently, using a hash-to-curve point generated from the timeout timestamp $t$, instead of a locking point from the oracle.

$$ T_t = (H'(t), P_t) $$

<sub>We hash $t$ into a point so that $T_t$ matches the type structure of $T_i$, as a developer convenience.</sub>

4. Alice sorts and arranges the branches $\\{T_1, T_2, T_3, T_t\\}$ into a [Merkle tree](https://en.wikipedia.org/wiki/Merkle_tree), and computes the payout merkle root hash $\hat{T}$.

This structure commits $\hat{T}$ to the set of locking points and payout structures in a way the mint can verify later, but without exposing any information until needed.

5. Alice gives Bob the outcome blinding secret $b$ and the merkle root hash $\hat{T}$.

6. Bob re-computes the payout merkle root $\hat{T}$ independently using the oracle locking points, blinding secret, and expected payout structures, just as Alice did.

Note that Bob _cannot_ simply verify the membership of the payout structures relevant only to Bob. Doing so would allow Alice to sneak in an extra branch for which she already knows the attestation secret. Bob must fully re-compute $\hat{T}$ to rule out that possibility.

7. Bob creates a set of _locked Ecash notes,_ worth \\$100 in total, which each commit to the specific DLC he is creating with Alice.

Let $(x, Z)$ be an Ecash note, as described in [the earlier section on Ecash](#Ecash). Bob computes a locked Ecash proof $Z'$ as:

$$ Z' = H'(Z\ \|\|\ \hat{T}\ \|\|\ 200) $$

Notice how $\hat{T}$ commits the locked proof to a specific set of DLC payout structures. The number 200 is included as a commitment to the total DLC funding amount. Otherwise Alice would be able to fund the same DLC using only Bob's locked Ecash without risking any money of her own.

The tuple $(x, Z')$ can be used as a locked Ecash note. It cannot be redeemed as valid Ecash under normal protocols, but it _can_ be proven to _have been derived_ from a valid Ecash note, if you also know $\hat{T}$.

For multiple notes, Bob would simply repeat this process multiple times per note.

8. Bob gives his \\$100 set of locked Ecash notes to Alice.

9. Alice constructs a similar set of locked Ecash notes worth \\$100. Technically she doesn't _need_ to lock her own Ecash as she isn't protecting it from anyone except herself, but this approach helps with code reuse and allows for untrusted proxies to submit DLCs to the mint.

10. Alice gives the mint:

    - The full $200 in locked Ecash notes (all should be issued by the mint)
    - The payout root hash $\hat{T}$
    - The total funding amount (\\$200)

11. The mint can verify each of the locked Ecash notes $(x, Z')$ using its secret key $m$ by re-computing:

$$ Y = H'(x) $$
$$ Z = mY $$
$$ Z' = H'(Z\ \|\|\ \hat{T}\ \|\|\ 200) $$

The mint checks all locked notes are valid and their proofs $Z$ haven't been used already. If some Ecash notes are invalid, the mint replies with an error, indicating to Alice which notes are invalid.

If the root hash $\hat{T}$ isn't already registered, the mint registers this DLC by storing $\hat{T}$ and the funding amount (\\$200). If $\hat{T}$ is already registered, the mint returns an error.

Bob can use $\hat{T}$ as an identifier to look up the DLC registration with the mint. Bob should be able to verify once the DLC is registered. If Alice takes too long to register the DLC, Bob can swap out his (non-locked) Ecash notes with the mint, to revoke Alice's ability to register the DLC later.

The mint could also create a publicly verifiable signature on $\hat{T}$ and give the signature to Alice, who can forward it to Bob to prove she did indeed register the DLC.

12. At this point both Alice and Bob are confident that the DLC is locked-in. Once the oracle attestation secret $k_i$ is revealed, either party can use the attestation secret to compute the blinded attestation secret, i.e. the discrete log of $K_i'$:

$$ k_i' = k_i + b $$

13. Bob can now claim winnings (if applicable) from the mint by submitting to the mint:
    - The merkle root hash $\hat{T}$ as an identifier
    - His payout secret $d_b$
    - The payout structure $P_i$
    - The blinded attestation secret $k_i'$
    - A merkle proof of inclusion that $T_i \in \hat{T}$
    - A set of challenge points (similar to the point $A = Y + rG$ in the earlier Ecash mint example, but we would use multiple challenge points because in a real-world scenario, the mint will likely need to issue multiple denominations of Ecash notes)

14. The mint verifies Bob's claim by first computing:

$$ D_b = H(d_b) $$
$$ K_i' = k_i' G $$
$$ T_i = (K_i', P_i) $$

The mint checks that the branch $T_i$ is indeed a valid member of the merkle root hash $\hat{T}$, and that $\hat{T}$ is registered in the mint's persistent memory.

By looking up Bob's public payout hash $D_b$ in the payout structure $P_i$, the mint can see how much Ecash Bob is owed for this particular outcome relative to the other participants. If $D_b \notin P_i$, then Bob's claim is fraudulent.

If these checks pass, then Bob's claim is deemed to be valid by the mint. The mint can use the set of challenge points given by Bob to mint new Ecash promises totalling the appropriate payout amount, to be returned to Bob. Say if $i = 2$, then Bob should be given \\$200 in Ecash at this juncture.

Alice can also execute the above steps for any winnings she is owed under outcome $i$.

### Timeout

If the oracle doesn't publish their attestation by the timeout timestamp $t$, then the timeout condition becomes enforceable. After the time $t$, any participant can submit:

- The merkle root hash $\hat{T}$ as an identifier
- Their payout secret
- The timeout payout structure $P_t$
- The timeout timestamp $t$
- A merkle proof of inclusion for the timeout branch $T_t \in \hat{T}$
- A set of challenge points for Ecash minting

...and the mint will be able to similarly verify against the merkle root hash $\hat{T}$. The mint must obviously check that $t$ is in the past, and if so the timeout outcome claim is valid.

15. Upon the first successful claim for a DLC on outcome $i$, the mint should atomically cache $P_i$ (or $P_t$) as the defacto outcome payout structure for this DLC, so that from now on the mint can only accept claim requests for outcome $i$. Why? Because otherwise Alice and Bob could collude to print infinite money from the mint by artificially selecting locking points for which they already know the attestation secrets.

16. The mint should remove Bob's payment hash $D_b$ from its cached copy of $P_i$ to denote that Bob has been paid out. Once the mint recognizes all Ecash payouts have been disbursed, the mint no longer needs to retain any information about that DLC. All participants have been paid out appropriately with Ecash and everyone is happy.

# Observations

Here I will evaluate Ecash DLCs' security, privacy, and scalability.

## Security

An Ecash DLC is not as secure as an on-chain Bitcoin DLC. The Ecash mint retains the ability to defraud or collude with the DLC participants. If the mint goes offline before the DLC matures, participants obviously cannot claim their Ecash winnings. However this is not a new risk for the participants, who are presumed to already be Ecash holders. Their money was already encumbered with this custodial liability, so it's worth emphasizing that the DLC introduces no new counterparty risk for anyone involved.

Users for whom counterparty risk is unacceptable should consider using on-chain DLCs, or perhaps [Ticketed DLCs using Lightning](/scriptless/ticketed-dlc).

## Privacy

The privacy result is phenomenal. Aside from network-level metadata like IP address, transport-layer info leaked by TLS and HTTP, etc, the mint only needs to learn:

- The total funding amount (individual funding amounts are obscured)
- The final payout structure (of the attested outcome only)
- The approximate settlement time (participants may intentionally delay settlement to better obfuscate which attestation they used)

Due to the blinding of outcome locking points, the mint cannot do a brute-force search of existing public oracles to determine what the participants are wagering on.

If the timeout case occurs, the participants _do_ need to reveal the timeout timestamp $t$, which might leak some information about the event in question, but timeout cases should be rare if oracles are doing their job as expected.

By revealing the merkle proof of inclusion of $T_i \in \hat{T}$, the participants may reveal a lower-bound on the number of possible outcomes, but this information can be obfuscated by structuring the merkle tree in a pseudorandom fashion to obscure the true number of leaf nodes.

Due to the fungible and blind nature of Ecash, the mint never learns exactly who claimed the winnings or how the winnings were used - only that the DLC's initial funders approved of the final payout structure.

## Scalability

Ecash DLCs are highly scalable from the mint's perspective, which is great considering a mint may need to manage thousands of DLCs or more.

An unresolved DLC of any volume or complexity is always represented as a constant-size data structure in the mint's memory. Regardless of how many possible outcomes there are, or how complex the payout structures become, a commitment to all of it is folded into the merkle root hash $\hat{T}$. The mint can process a DLC registration in a single round of communication, and DLC settlement can be done with at most $n$ rounds.

Claim verification at the settlement stage can be done in $O(\log n)$ time, again thanks to the merkle tree. If the mint caches the first valid claim's payout structure $P_i$, it can avoid repeating the verification process for each subsequent claim, at the cost of at most $O(n)$ memory.

For the DLC participants, the DLC setup process is more expensive, as computing $\hat{T}$ requires $O(n)$ curve addition/multiplication operations, plus an $O(n)$ number of hash operations. Each participant must compute $\hat{T}$ independently, and that work cannot be safely delegated.

Performance could be improved here in a transparent fashion, by sacrificing privacy and allowing the final attestation secret $k_i$ to be revealed in-the-clear, without the blinding secret $b$ to mask it. This makes constructing $\hat{T}$ purely a hashing process with no elliptic curve operations involved (beyond initially computing the lockings points from the oracle announcement), and so would be much faster. This comes at the cost of potentially revealing the nature of the event the DLC was subscribed to.

## Future Improvements/Extensions

- The mint could charge fees for processing a DLC.
- The DLC parameters could be updated if a predefined set of participants agree.
- The mint itself could act as an oracle. This consolidates trust more in a single party, but the mint notably _cannot distinguish_ whether the Ecash DLCs it resolves are subscribed to the mint's oracle, or to someone else's. Timing or other side channels would be the only possible link.
- Participants may be allowed to over-fund the DLC. The limit committed to by the locked Ecash notes might only be a threshold at which the DLC should be considered locked-in, and enforceable by the mint. Nothing prevents participants from over-funding if they wish to.
- Thanks to the locked Ecash concept, funding can be done out-of-band without input from the mint. This opens the door to crowdfunding services which use Ecash to fund DLCs. The mint would be unable to distinguish a crowdfunded DLC from a single-party funded one. Funders could back out at any time by swapping out the Ecash notes they promised to the crowdfunded DLC.
- The concept of locked Ecash could also be used to create crowd-funded multi-party payments in regular Ecash, not involving DLCs at all.
- Perhaps there is a way cross-mint transfers over Lightning could be useful to this protocol.
- Could the DLC oracles be incentivized using Ecash somehow?
- How best to integrate [digit-decomposition events](https://github.com/discreetlogcontracts/dlcspecs/blob/master/Oracle.md#digit-decomposition), where oracles provide more than one attestation secret per event?

## Conclusion

Although [Ticketed DLCs using Lightning](/scriptless/ticketed-dlc) would be much more secure against counterparty risk, Ecash DLCs seem much easier to implement, conceptually simpler, and thus less prone to bugs.

Like any DLC, the protocol is contingent on an honest and reliable Oracle, but _if_ one such oracle is present, the technique allows for a huge degree of flexibility, at an unprecedented scale. Small-scale micro-wagers could be conducted in seconds without touching the chain, and without the long lockup times needed in Lightning.

I see this as a highly promising avenue to transform Ecash into a programmable conditional payments layer, without additional trust in the mint, at near-zero cost to privacy. DLC-supported Ecash mints could be used by customers of gambling sites, insurance services, futures markets, and many more services in a completely private and egalitarian fashion. The mint, meanwhile, would have completely plausible deniability regarding the subject of the DLCs it services, and could charge fees for its trouble.
