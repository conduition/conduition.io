---
title: Vulnerabilities in the Cashu ECash Protocol
date: 2026-01-10
mathjax: true
category: code
description: I found some vulnerabilities in Cashu's protocol for deterministic wallet recovery.
---

In July 2025 I discovered vulnerabilities in the [Cashu protocol](https://cashu.space/) and some Cashu wallets, and reported them to select Cashu developers. I sent an early draft of this article to them, and we worked together to discuss and address the vulnerability. We agreed on a long term and a short term fix, both of which I believe successfully mitigate any exploits. I was paid a $500 bug bounty for finding it and reporting it responsibly.

This article describes what I originally found, and why it needed to be patched. I also discuss the patches implemented by Cashu wallet development teams.

## Prerequisite Knowledge

- [Elliptic curve math basics](/cryptography/ecc-resources)
- [Ecash](https://en.wikipedia.org/wiki/Ecash) (optional but handy)

Already familiar with Ecash? [Click here to skip to the fun parts](#The-Vulnerability).

## Notation

Just so we're all on the same page:

| Notation | Meaning |
|:--------:|---------|
| $G$ | The [base-point of the secp256k1 curve.](https://bitcoin.stackexchange.com/questions/58784/how-were-the-secp256k1-base-point-coordinates-decided) |
|$n$ | The [_order_ of the secp256k1 curve](https://crypto.stackexchange.com/questions/53597/how-did-someone-discover-n-order-of-g-for-secp256k1). There are $n - 1$ possible valid non-zero points on the curve, plus the 'infinity' point (AKA zero). |
|$x \leftarrow \mathbb{Z}\_{n}$ | Sampling $x$ randomly from the set of integers modulo $n$. Note that we exclude zero when sampling. |
| $a\ \|\|\ b$ | Concatenation of the byte arrays $a$ and $b$. |

## Ecash

[Chaumian Ecash](https://en.wikipedia.org/wiki/Ecash) implementations backed by Bitcoin are a growing privacy-focused subsection of the Bitcoin usage landscape, and with good reason: Reviving a well-studied technology and repurposing it for Bitcoin offers a new set of of usability improvements and trade-offs, making Bitcoin-powered payment systems fit into new use cases.

An Ecash mint issues _Ecash notes_ in various denominations, which can be redeemed later at the mint for some fungible commodity or service (such as Bitcoin). This is conceptually very similar to the physical banks of ye olden days, which accepted deposits of some fungible asset like silver or gold, and issued _physical cash_ (paper notes or metal coins) of various denominations in return, which could be used to reclaim the equivalent amount of the physical asset.

In the case of a Bitcoin-backed Ecash mint, the mint accepts Bitcoin deposits, and issues Ecash notes which can be redeemed for Bitcoin at a future time, for as long as the mint remains solvent and operating.

The basic principles of an Ecash mint are:

- **Authenticity** - The Ecash mint can be certain the Ecash notes it creates cannot be forged by others, so that when a depositor redeems a note, the mint is safe against fraudulent withdrawals.
- **Fungibility** - Depositors can be certain the Ecash notes they receive are anonymous and fungible. Instead of the mint giving a depositor a bearer token (which would have to be recognizable by the mint later when redeemed), the depositor cooperates with the mint to _blind_ the Ecash notes they receive through a clever cryptographic protocol called _blind signatures._

### How it works

To fully understand the vulnerability, we must first understand the inner mechanics of Ecash blind signatures.

Imagine a mint, with a secret key $m$ and public key $M = mG$.

Alice trusts the mint operators and knows $M$. She decides to make a \\$1 deposit into the Ecash mint. She expects an equivalent amount of Ecash in return.

Let $H'(x) \rightarrow P$ be a hash function which maps some arbitrary input data $x$ to a point $P$ on the secp256k1 curve, in such a way that the discrete log of $P$ is unknowable. [Here is an example of one such a hash function](https://github.com/cashubtc/nuts/blob/6024402ff8bcbe511e3e689f6d85f5464ecc3982/00.md#hash_to_curvex-bytes---curve-point-y).

1. Alice samples some random scalar $r \leftarrow \mathbb{Z}\_{n}$

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

- The cryptography alone doesn't protect against replay attacks or double-spending. Alice could resubmit $(x, Z)$, and so the mint must remember which values of $Z$ or $x$ have already been redeemed.
- Only the mint can verify its own Ecash notes. For Alice to pay someone with an Ecash note, the recipient must be able to swap out the note for a fresh one by contacting the mint directly. The recipient hasn't been paid until they successfully swap Alice's Ecash note for a fresh one which only they know.
- So far we've assumed the mint only has a single key pair $m$ and $M = mG$. In reality the mint needs a way to issue and distinguish notes of different denominations (\\$1, \\$5, \\$50, etc) and Ecash mint implementations usually do this by having _multiple keys:_ one per denomination. In the Cashu protocol, a mint groups these keys into a "Key Set" with a unique hash identifier. Imagine this like having a different printing template for \\$1 paper cash notes compared to \\$5 notes.

# The Vulnerability

The vulnerability, which all exploits described in this article depend upon, lies in [the Cashu specification document NUT-13: Deterministic Secrets](https://github.com/cashubtc/nuts/blob/a246a91ceb39ffd33ea1f768b7a7e946d422f91a/13.md). This document describes a deterministic backup standard for Cashu wallets. Let's briefly summarize how NUT-13 works.

## NUT-13

The idea behind NUT-13 is to give Cashu wallets a standardized way to generate any secret preimage $x$ and blinding factor $r$ deterministically, so they can be recovered later from a static backup key. The wallet can then use [NUT-09](https://github.com/cashubtc/nuts/blob/main/09.md) to recover the blinded signature $Q = mA$ from the mint, and repeat the unblinding again to get a valid ecash proof $Z = Q - rM = mY$.

To achieve this, NUT-13 uses [BIP39 seed phrases](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki) and [BIP32 key derivation](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki), inspired by classic hierarchical deterministic (HD) Bitcoin wallet standards. A NUT-13 compliant wallet is supposed to generate a 12-word BIP39 seed phrase when first launched. The user is typically encouraged to save this seed phrase somewhere secure.

The wallet software hashes the mnemonic into a seed, [in the manner described in BIP39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki#user-content-From_mnemonic_to_seed). The seed is then hashed into a BIP32 master key, [as described in BIP32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki#user-content-Master_key_generation). When receiving or minting ecash from a mint, the wallet derives any secret preimage $x$ and blinding factor $r$ deterministically from the master key.

To prevent reuse of preimages or blinding factors, the wallet is expected to manage a stateful counter for each unique keyset. The wallet must increment the counter for each new ecash proof minted from that keyset ID. ***Remember this. It will be important later.***

Concretely, NUT-13 specifies that wallets must derive $x$ and $r$ from the master key with a specific key path derived from two parameters, `keyset_id_int` and `counter_k`:

```
secret_derivation_path = m/129372'/0'/{keyset_id_int}'/{counter_k}'/0
r_derivation_path      = m/129372'/0'/{keyset_id_int}'/{counter_k}'/1
```

- `counter_k` is just an integer, statefully managed by the wallet on a per-keyset basis.
- `keyset_id_int` is a reduced integer representation of the relevant keyset ID, which itself is 16 hexadecimal characters. This is computed as:

```py
keyset_id_int = parse_int(keyset_id_hex, base=16) % (2 ** 31 - 1)
```

<div style="background-color: rgba(255, 255, 90, 0.05); border-radius: 8px; padding: 15px 15px 15px 30px;">

> why not just use the keyset ID directly as a 64-bit integer?

Because BIP32 derivation path elements must be 32-bit integers, and their most significant bit indicates whether hardened derivation is required. NUT-13 reduces the keyset ID modulo $2^{31}-1$ to ensure the result does not overflow a `uint32` when $2^{31}$ is added for hardening.
</div>

The wallet then derives two BIP32 child keys at these paths, and uses the child private keys as the secret $x$ and blinding factor $r$.

## The Flaw

The problem is thus:

**Wallets track counters by keyset ID, but secrets are derived only from the _reduced_ 31-bit keyset ID integer representation.**

The Cashu spec does not require clients to validate keyset IDs are derived correctly, so a malicious mint can easily choose a keyset ID whose 31 bit integer representation collides with that of another mint's keyset.

If a NUT-13 wallet receives ecash proofs from two such colliding keysets, _the wallet will reuse the same set of preimages and blinding factors for outputs on both keysets._

### Example

At the time of writing, [the Minibits](https://www.minibits.cash/) mint's current active keyset has an 8-byte hex ID `00500550f0494146`, which in base-10 integer form is $e = 22523843323707718$.

To pick a keyset ID in the same 31-bit residue class as Minibits' keyset ID $e$, I simply generate a random positive integer $v < 2^{25}$, and then compute my new keyset ID $e'$ as

$$
e' = v \cdot (2^{31} - 1) + (e \mod 2^{31} - 1)
$$

This satisfies $e' \equiv e \mod 2^{31} - 1$. Thus, any NUT-13 wallets will derive the same preimages and blinding factors when minting ecash proofs from keyset $e'$ as they do for keyset $e$.

### Keyset ID Verification

[According to NUT-02](https://github.com/cashubtc/nuts/blob/main/02.md#deriving-the-keyset-id), Keyset IDs are supposed to be derived from a hash of the public keys constituting the keyset. However, in my research I found no Cashu clients which actually verify the keyset ID is derived correctly, so mints are pretty much free to choose whatever keyset ID they want.

Yet, even if clients _did_ verify the keyset ID is correct, this still doesn't fix the problem.

There are only $2^{31} - 1$ (about 2 billion) possible keyset ID integer representations. That's a puny search space for modern computers. With a simple 100-line rust program I brute-force searched using my below-average CPU, and within a few hours I found 4 completely valid keysets whose keyset ID integer residues collided with those of popular Cashu mints.

# The Exploit

Reusing a secret preimage and blinding factor across two different mints does not inherently compromise any ecash. An attacker running a malicious mint must conduct a carefully targeted attack to compromise proofs from a target mint, one key at a time.

To fall victim to this attack, the user (or his wallet) must first attempt to swap and then spend ecash proofs from the malicious mint. Unfortunately, some Cashu wallets have automated background tasks which do exactly this, sometimes without any user interaction at all.

## Method

To execute an attack, I first select a target mint and a target pubkey $K = kG$ from one of that mint's keysets, whose corresponding secret key is $k$, unknown to me. My attack is intended to steal ecash proofs issued by $K$, probably with the end goal of melting (withdrawing) them over the Lightning Network.

I construct a keyset $\kappa$ consisting of a single public key $K'$ of denomination 1 sat. I construct the keyset such that $K' = qK$ for some secret scalar $q$ known only to me. The keyset ID of $\kappa$ is manipulated (either analytically or by brute-force) so that its 31-bit residue collides with that of my target mint's keyset ID.

I spin up a custom mint server which I control, with a domain name, TLS certificates, etc. Make it look authentic, but don't advertise it. My mint publishes the keyset $\kappa$ as the only active keyset on its `/v1/keys` and `/v1/keysets` endpoints.

### Airdropping

I select some target users, possibly using Nostr metadata events to determine which wallet my victims are using, and which mints they use. The Nostr integrations baked into most Cashu wallets makes mining this data surprisingly easy.

I send them each a "poisonous airdrop" Cashu token, consisting of Cashu proofs sourced from my mint, possibly issued under a different keyset than $\kappa$. The data in these proofs themselves don't matter - what matters is whether the victim users will attempt to claim the proofs.

### Swapping

If a victim user swaps the airdropped proofs for fresh proofs, the user's wallet will derive secrets and blinding factors from the BIP32 path `m/129372'/0'/{keyset_id_int}'/{counter_k}'/{0,1}`. The `keyset_id_int` will match that of the target mint's keyset, but because my malicious keyset $\kappa$ has a distinct ID, _the user's wallet will initialize a brand new state counter._

For every new blinded output index $i$ the victim requests from my mint, they will derive secret $x_i$, challenge $Y_i = H'(x_i)$, and blinding factor $r_i$. When they send the swap request, the user's wallet reveals a blinded message $B_i' = Y_i + r_i G$. These values will all be identical to those which the user would've (and may have already) used when transacting with my target mint for the same counter value $i$.

**Example**: I send a victim 1024 sats in a single proof from my mint, using a normal but inactive keyset. The user swaps the proof with my mint. Because my mint's only active keyset is $\kappa$ which only contains a single 1-sat denomination key, the user's wallet will request 1024 output proofs from that 1-sat key. The user's wallet reveals $\\{B_1', B_2', ... B_{1024}'\\}$, where $B_i' = Y_i + r_i G$.

### Restoring

Before responding to the victim's swap request, my mint contacts the `POST /v1/restore` endpoint of my target mint, as defined in [NUT-09](https://github.com/cashubtc/nuts/blob/main/09.md). This endpoint essentially acts as an input/output record for every previous blind signature the target mint has authored.

My mint now possesses a set of blinded messages $\\{B_1', B_2', ...\\}$ received from the victim which _may_ have been used on the target mint as well. I use the target mint's NUT-09 `/v1/restore` endpoint to test all these blinded messages. If the mint has previously signed one of the blinded messages $B_i'$, the target mint returns:

$$
\begin{align}
C_i^\* &= k B_i' \\\\
       &= k ( Y_i + r_i G ) \\\\
\end{align}
$$

Note that the `/v1/restore` endpoint returns _any_ signatures made across the entire keyset. A blinded signature is only relevant to our attack if the signing key $k$ used matches the target pubkey $K$, and not some other key in the target mint's keyset. We can filter out irrelevant signatures by checking the `amount` denomination in the response data matches the denomination of $K$.

I have now "recovered" (stolen) any available blinded signatures $\\{C_i^\*\\}$ from the target mint, and I can use them to build a response for the victim's still-in-progress swap request.

### Swap Response

For each blinded signature $C_i^\*$ we found, the malicious mint multiplies it by my secret $q$, and returns it to the user for output $i$:

$$
\begin{align}
C_i' &= q C_i^\* \\\\
     &= q k B_i' \\\\
     &= q k ( Y_i + r_i G ) \\\\
\end{align}
$$

For each blinded message $B_i'$ for which we _did not_ find a blinded signature on the target mint, we return $C_i' = G$ and store $B_i'$ in a database. It will be useful later, I promise.

### Unblinding

Upon receiving all $\\{C_i'\\}$ from our malicious mint, the victim wallet will perform the usual ecash unblinding algorithm using the reused blinding factors $\\{r_i\\}$ and our mint's malicious pubkey $K'$.

$$
C_i = C_i' - r_i K'
$$

These will be stored in the user's wallet as if they were valid proofs. Usually at this point, the user receives UI confirmation that the Cashu token they received was valid, and their wallet balance visibly increases.

### Spending

The user may attempt to spend some of these newly acquired proofs, such as by melting and sending over the lightning network. The user may also send proofs directly to someone else as a Cashu token, and the receiver will then swap the proofs to confirm their validity just as the user first did.

In either case, the proof secret $x_i$ and unblinded signature $C_i$ will be sent to my malicious mint.

### Stealing

When we receive a proof $(x_i, C_i)$ issued by our malicious swap protocol, we first check the target mint if the proof for challenge $Y_i = H'(x_i)$ has been spent. If so, we ignore this proof - there is nothing to steal.

If the proof is unspent, then we take one of two paths to try to steal it:

1. **$C_i$ may have been constructed from a blind signature recovered from the target mint.**

In this case, my mint receives:

$$
\begin{align}
C_i &= C_i' - r_i K' \\\\
    &= q C_i^\* - r_i K' \\\\
    &= q k ( Y_i + r_i G ) - r_i K' \\\\
    &= q k Y_i + q k r_i G - r_i K' \\\\
    &= q k Y_i +  r_i K' - r_i K' \\\\
    &= q k Y_i \\\\
\end{align}
$$

We can compute the target mint's signature on $Y_i$ valid under $K$:

$$
\begin{align}
W_i &= q^{-1} \cdot C_i \\\\
     &= q^{-1} \cdot q k Y_i \\\\
     &= k Y_i \\\\
\end{align}
$$

Note that due to the blinding done by the victim, we cannot verify mathematically if $C_i = q k Y_i$. The only way we can check is by attempting to swap the ecash proof $(x_i, W_i)$ at the target mint. We do exactly this, and only proceed to path 2 if swapping fails.

2. **Alternatively, $C_i$ was constructed without a blind signature from the target mint.**

Then in this case, our mint has been given:

$$
C_i = G - r_i K'
$$

This lets us isolate the term which contains the secret blinding factor, which we still don't know.

$$
\begin{align}
   C_i &= G - r_i K' \\\\
r_i K' &= G - C_i \\\\
\end{align}
$$

By itself this is not enough to steal any ecash, but we can combine this with the archive of blinded messages received by our malicious mint.

Before doing that though, we should hit the target mint's `/v1/restore` endpoint again, passing any blinded messages ${B_j'}$ for which we didn't already find a blind signature back in the [Restoring](#Restoring) phase of the attack. We maintain an up-to-date mapping of $B_j' \rightarrow C_j^\*$, mapping blind messages to their corresponding blind signatures "recovered" from the target mint.

Now we can iterate through each archived blind message/signature tuple $(B_j', C_j^\*)$ and compute a _potentially valid_ unblinded signature $V_j$:

$$
\begin{align}
V_j &= C_j^\* - q^{-1} (G - C_i) \\\\
    &= C_j^\* - q^{-1} (r_i K') \\\\
    &= C_j^\* - q^{-1} (r_i q K) \\\\
    &= C_j^\* - r_i K \\\\
\end{align}
$$

If the blinding term $r_i K$ we extracted matches the archived blind signature $C_j^\*$, then $C_j^\* = k B_i'$, and:

$$
\begin{align}
V_j &= C_j^\* - r_i K \\\\
    &= k B_i' - r_i K \\\\
    &= k (Y_i + r_i G) - r_i K \\\\
    &= k Y_i + r_i k G - r_i K \\\\
    &= k Y_i + r_i K - r_i K \\\\
    &= k Y_i \\\\
\end{align}
$$

Again we cannot verify this mathematically from the victim's input alone due to blinding, so we must check each candidate proof $(x_i, V_j)$ by attempting to swap it on the target mint. If we find a valid signature $V_j$, we can stop iterating and erase $(B_j, C_j^\*)$.

If we find no match, then we know $x_i$ must be a secret which the target mint has not signed yet. We put the victim's proof $(x_i, C_i)$ into a background queue which occasionally re-checks it against any new blind signatures $C_j^\*$ recovered from the target mint.

### Final Response

Our final response to the victim's swap/melt request is not very consequential. While we've already gotten everything we need to steal some proofs from the victim, we are limited to stealing at most $n$ proofs if the user only ever spends $n$ of the proofs from our malicious key set $\kappa$.

This attack makes it impossible to verify whether the victim's proofs are "authentic" or not, so the reasonable approach would be to simply hard-code the `/v1/swap` endpoint to auto-succeed, and hardcode the `/v1/melt/*` endpoints to return a success status with change outputs, without actually allowing users to pull money out of the malicious mint. The hope is that the victim retries or otherwise keeps interacting with our mint, and in so doing exposes more and more of their proofs from the target mint.

# Analysis

A discussion of the properties of this attack: drawbacks, practicality, mitigations, etc.

## Affected Software

Though some were more vulnerable than others, any Cashu wallet which uses NUT-13 seeds was at risk of attack. Unfortunately, this means most Cashu wallets were vulnerable. I certainly identified that Minibits, Cashu.me, and Nutstash were vulnerable.

For the attack to work, a victim wallet must do two things:

1. Swap my airdropped proofs out for new proofs.
2. Spend the new proofs in melt or swap operation.

Upon receiving a token from an unfamiliar mint, some Cashu wallets may show a prompt asking if the user would like to add the mint and accept the token. If the user clicks yes, they will have completed step 1. If the user then tries to spend those tokens in any way, they will fall victim to step 2.

In other cases like Minibits, Cashu wallets receiving a new token will automatically add my mint to the user's trusted mint list, and swap the airdropped proofs out for new ones. This ticks off step 1, but not step 2. For that, the user must take manual action.

In the worst cases, some wallets may have a "transfer to trusted mint by default" option which does both step 1 and step 2 without user interaction. These wallets are the most vulnerable as they can be attacked without requiring any action from the user, aside from unlocking the wallet.

## Practicality

This attack is complex, but surprisingly practical. The only major hitch which hampers a large-scale attack is that the malicious mint can only really attack one target key $K$ at a time. This could be improved - or worsened, depending on your perspective - for the special case of victims whose wallets auto-swap our airdropped proofs.

We can wait until the victim is online, and then break our airdrop up into discrete steps. The first airdrop might target the upstream mint key $K_1$. Our malicious mint advertises a keyset containing the key $K_1' = q K_1$. We send a 1000 sat token to the victim, and the victim wallet auto-swaps it with 1000 outputs issued from $K_1'$. We then rotate our keyset to target $K_2$, setting $K_2' = q K_2$. Then we send a second 1000-sat token which the victim auto-swaps into proofs from $K_2'$. This may only take a few seconds to execute.

After all airdrops are complete, the user has a wallet filled with 2000 proofs from our two malicious keysets. If the victim were to try to spend all 2000 sats at once, they would reveal to us the first 1000 proofs they were issued from _both_ $K_1$ _and_ $K_2$.

We could scale this attack up to cover more target keys if desired.

## Visibility

From the user's perspective, this is what an attack would look like:

1. (optional) I receive an ecash token, possibly with some social engineering message like _"We're starting a new mint, and we're giving out free sats! Withdraw if you like, it's your money now!"_. I paste or scan the token into my wallet.
    - I may need to manually approve adding a new trusted mint.
    - This step may be skipped in cases where wallets have auto-receive enabled.
2. I see UI confirmation of a newly received ecash transaction under the new mint.
3. I try to withdraw my newly airdropped ecash over lightning.
4. The lightning withdrawal says it succeeded, but the invoice wasn't actually paid. Weird. Maybe try again?
5. Well this mint definitely doesn't work. Block it and go on with my day.
6. Some time later, I try to pay a lightning invoice from my balance on another mint, but the transaction fails with a "proof already spent" error. Where did my money go?


## Mitigations

After speaking with the Cashu developer community and debating different options, we arrived at two fixes: A short-term backwards-compatible fix, and a long-term protocol-level fix.

### Long Term Fix

The long term fix is the easier one to understand. In a perfect world all Cashu users would migrate to it immediately.

It's very simple. Just ditch BIP32 completely - BIP32 was meant for a very different purpose - and instead compute secrets $x$ and $r$ using a single hash or HMAC, invoked on the full keyset ID and counter.

```py
hash = hmac_sha512(seed, keyset_id + counter.to_bytes())
x = hash[:32]
r = hash[32:]
```

This approach cryptographically compartmentalizes deterministic secrets scoped for different keysets, provided that the wallet manages the stateful counter correctly and verifies keyset IDs. It fixes the core flaw, which is that secrets derived via NUT-13 for distinct keyset IDs may collide.

When I initially contacted the Cashu developer community about this, they mentioned that improving security of keyset IDs at the specification level was already ongoing work, and they were actively working to transition to longer 256-bit keyset IDs, dubbed ["keyset ID v2"](https://github.com/cashubtc/nuts/pull/182). We agreed this could be a good opportunity to insert this long-term protocol-level fix into the Cashu specification itself.

### Short Term Fix

The short term fix is more complicated, because it must be backwards-compatible with the existing protocol so as not to break interaction between existing mints and wallets. This fix should only be used until wallets and mints have updated to support v2 keyset IDs and the more long-term secure deterministic secret derivation scheme.

Cashu wallet developers have been advised to add code to their applications which guards against the attack scenario where two keyset IDs have colliding 31-bit residues. This more or less means a wallet must constantly check every keyset ID it encounters to see if any have colliding residues. If a wallet finds a new keyset ID with a residue which collides with one in its cache, the wallet should prompt the user to confirm which mint they trust more. Proofs issued by the less-trusted mint should be marked as hazardous, possibly unspendable.

- Note that it's not enough to only compare against active keyset IDs, because an attacker could target the inactive keysets of legitimate mints.
- We also cannot just focus on keysets for which the user _currently_ holds valid proofs, because the attacker could proactively trick a victim into revealing secrets they haven't used on the target mint yet (but may use in the future). As soon as those secrets are used on the target mint to create blinded proofs, the attacker could then steal those proofs and unblind them.
- Trust-on-first-use (TOFU) is not a good policy here, because it's feasible than an attacker could swoop in early with some kind of timing attack to fool wallets into becoming their more-trusted mint. The user needs to be informed that something is wrong so they can recognize and rectify the situation.
- Note that some wallets (Minibits) track counters not just by keyset ID but also _by mint,_ which creates another opportunity for this attack to re-emerge. All cashu wallets should ensure they are compliant with the updated version of the NUT-13 spec.

## Conclusion

As of publishing time, I have not personally gone through every Cashu wallet to verify these bugs have been patched - I had a very busy Autumn working on [optimizing post-quantum cryptography](/code/fast-slh-dsa/) - But the Cashu developers have assured me the short term fix has been effectuated in every major Cashu wallet, and the long term keyset ID v2 protocol update is well on its way with implementations forthcoming.

Along the way I hope readers take home a few lessons about security engineering in general:

- Look closely at apps which perform automated tasks using sensitive bearer secrets. Avoid auto-trusting anything outside direct user input (and even then).
- Deterministic secrets are fickle. Pay attention to how the derivation mechanism works, but also how it is used. There could be mistaken assumptions.
- Be careful when using "SHOULD" in a cryptographic specification. Figure out when "SHOULD" needs to be "MUST".
- Watch out for injections - Anytime a large domain is pigeonholed into a smaller space.

Big thanks to the Cashu devs for bearing the bulk of the work of actually fixing this thing. While the initial research was challenging, there is little I find more prosaically daunting than corralling teams of open source devs to fix an obscure vulnerability, and they saved me from attempting that myself.
