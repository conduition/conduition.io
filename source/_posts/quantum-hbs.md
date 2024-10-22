---
title: Hash-Based Signature Schemes for Post-Quantum Bitcoin
date: 2024-10-21
mathjax: true
category: cryptography
description: All safe roads once were wild.
---

In my personal opinion, the most dangerous and unpredictable challenge facing Bitcoin is not political pressure, practical usability, scaling, or economic incentive... It is the threat of quantum computers.

Large and powerful organizations - both political and corporate - have been pouring _billions_ of dollars into developing quantum computers for decades. Ever since [Peter Shor published his (in)famous namesake algorithm in 1994](https://en.wikipedia.org/wiki/Shor%27s_algorithm), cryptographers have been preparing for "Q-Day" - the day a large, practically usable quantum computer becomes available.

If you're reading my blog, I can assume you are at least roughly familiar with elliptic curve public/private keys. I'll simply tell you that a quantum computer of sufficient power would be able to flip an EC public key backwards into its private key - a feat thought to be implausible with ordinary classical computers. You can see how this might be a problem. If you'd like to learn how this can be done in detail, check out [Shor's original paper](https://ieeexplore.ieee.org/document/365700).

This article won't dissect the mechanics of how quantum computers break Bitcoin public keys, nor is it intended as a doom-and-gloom FUD-piece about how we should all be digging graves, stocking bunkers, and prepping for day zero of the post-quantum meltdown. I won't bother to conjecture how long it will take for a powerful quantum computer to be invented - Estimates of when this will occur vary widely even between professional analysts. I will simply assume _it will happen,_ one day, eventually. When it does, we must deal with it.

My hope is that this article will show you the _landscape_ of the quantum threats facing the Bitcoin community. Then I'll explore various _hash-based signature schemes_ and analyze their potential to diffuse these threats, and the tradeoffs which inevitably come with them. Finally, I'll propose a novel upgrade path for Bitcoin clients which uses hash-based cryptography as a fallback option to insure bitcoin users against future quantum adversaries, without the need for any near-term consensus changes.

<img style="border-radius: 8px;" src="/images/quantum-hbs/pq-landscape.jpg">

<sub><i>All safe roads once were wild.</i></sub>

# The Quantum Threat

In this section I'll dive into the mechanics of how exactly a selfish quantum adversary could attack Bitcoin for financial gain. Understanding the fundamental threat of quantum computers in more detail will lead us to clues as to how we can improve our defenses.

Almost every Bitcoin transaction mined from the genesis block to today has authenticated itself using one or more asymmetric signatures. Sometimes public keys are hashed. Sometimes we use [Bitcoin script opcodes](https://en.bitcoin.it/wiki/Script) to encumber coins with additional validation steps (e.g. time delays). But eventually, to spend a Bitcoin UTXO safely, one _must be required_ to supply an asymmetric signature matching some public key committed to by the UTXO itself. The signature must commit to the spending transaction in some way so that it can't be applied to a different transaction.

If one were to encumber a transaction output with _only_ a hashlock, or _only_ a timelock, etc, with no asymmetric signature requirement, then that UTXO can be spent by anyone who observes it being spent (including the miners who _must_ see the transaction to validate it).

```python
OP_SHA256 <hash> OP_EQUAL
```

<sub>A simple hash-lock Bitcoin script pubkey. This script is unspendable until _someone_ reveals the preimage of `<hash>`. After that, the script could be easily unlocked by anyone.</sub>

Bitcoin transactions use signatures on the secp256k1 elliptic curve to achieve this asymmetric authentication dynamic. ECDSA is the older and more well-known signing algorithm, and [Schnorr is a cleaner, faster, more secure and more flexible signing algorithm](/cryptography/schnorr/) which was adopted several years ago as part of Bitcoin's Taproot upgrade. Bitcoin's Schnorr and ECDSA signing protocols both use the same secp256k1 elliptic curve.

ECDSA and Schnorr signing protocols are equally vulnerable to a quantum adversary (QA) who knows a victim's secp256k1 public key, because the QA can simply invert the public key into the private key, and sign any message they desire.

*However,* the same QA will have a much harder time computing the preimage (i.e. input) of a hash function given its output. The currently-known best-case-scenario for a QA brute-forcing a hash preimage is a quadratic speed boost, given by [Grover's algorithm](https://en.wikipedia.org/wiki/Grover%27s_algorithm). Quadratic in this context means that if a classical computer requires $n$ operations to do something, then the QA can do it in $\sqrt{n}$ operations. The smallest hash used in Bitcoin output scripts is RMD160 which has a security level of $2^{160}$, so a quantum computer could crack a preimage to RMD160 in at most $\sqrt{2^{160}} = 2^{80}$ operations. Not great, but still implausibly difficult according to current theory.

So not *all* one-way functions are dead in the water, and cryptographic hashes aren't the only ones still kicking.

Let's examine the different address (output script) types in more detail.

## Hashed Output Types

<sub>(AKA P2PKH/P2SH/P2WPKH/P2WSH)</sub>

The most commonly used type of Bitcoin address today is a pay-to-(witness)-public-key-hash address (P2PKH/P2WPKH), in which the public key is first hashed before being given to the payer. When spending this output, the owner signs the transaction and provides the raw public key so that verifiers (Bitcoin nodes) may re-hash it and compare the hash against the output script being spent.

```python
OP_DUP OP_HASH160 <hash> OP_EQUALVERIFY OP_CHECKSIG
```

<sub>The classic P2PKH locking-script.</sub>

In P2SH and P2WSH, the address instead is the hash of a [_Bitcoin locking script_](https://en.bitcoin.it/wiki/Script) which itself almost always contains at least one ECDSA pubkey, whose signature is required for spending. For the purposes of assessing post-quantum security, script-hash type outputs have effectively the same properties as key-hash type outputs, with the exception that P2WSH outputs are encoded as SHA256 hashes whereas all others are encoded as RMD160 hashes.

```python
OP_HASH160 <hash> OP_EQUAL
```

<sub>The classic P2SH locking-script.</sub>


These four types of addresses currently protect the bulk of the mined and circulating Bitcoin supply.

The threat of a quantum adversary (QA) is in its ability to invert public keys into private keys. If a key-hash or script-hash address has received _but not spent_ any of its coins, then the preimage of that hash (the key or the script) hasn't been revealed yet. Barring out-of-band exposure (e.g. via BIP32 xpubs leaked to servers or peers), the QA generally won't be able to attack such addresses practically.

This protection ends the moment the owner of the key/script-hash address tries to spend any of their coins. To validate a transaction spending a pay-to-\*-hash output, the Bitcoin network peers must be given the key/script preimage. A quantum adversary could easily monitor these transactions and see that preimage, which always contains a public key the QA can invert. After inverting, the QA can try to double-spend the coins with a new higher-fee transaction.

<img src="/images/quantum-hbs/quantum-adversary.svg">

Gracefully, the QA will have a limited time in which to mount this attack. A typical Bitcoin TX spends only 5 to 60 minutes of its public existence in the mempool before it is mined, at which point the coins will have moved permanently to a new address. If that new address is protected by a hash whose preimage the QA does not know, then the coins will be out of reach for the QA.

However, a significant fraction of key-hash and script-hash addresses are being reused on mainnet today. A reused address is one which receives one or more UTXOs, spends them, and having revealed their public key or spending-script, is still being used to custody additional Bitcoin UTXOs. [Some estimate the amount of bitcoin held on such reused addresses was at least 5 million BTC](https://x.com/pwuille/status/1108097835365339136) as recently as 2019. A quantum adversary has much more time to compute the public keys exposed by these addresses. Time is on the side of the QA here; The burden of action is squarely on the shoulders of the owner to move their coins to a fresh unused address.

There is also the possibility of a large mining pool becoming a quantum adversary. Such a pool could delay mining certain transactions intentionally, to give themselves more time to crack a newly discovered public key.

### Summary

P2PKH/P2SH/P2WPKH/P2WSH output script types _can_ be reasonably secure against a QA if used properly, provided the QA needs a decent amount of processing time (more than an hour) to invert a secp256k1 public key.

The problem is that proper usage is hard. [Ava Chow describes the numerous pitfalls which plague key-hashing as a countermeasure against a quantum adversary](https://bitcoin.stackexchange.com/questions/91049/why-does-hashing-public-keys-not-actually-provide-any-quantum-resistance).

## P2TR Outputs

In P2TR addresses, an _internal_ public key $P$ is _tweaked_ with a given hash $m$ to produce an _output public key_ $P' = P + H(P, m) \cdot G$ (where $G$ is the secp256k1 generator point). The output pubkey $P'$ is then encoded directly (unhashed) in the P2TR address which receivers distribute.

When spending, the bearer can either authenticate directly by signing as the output pubkey $P'$ ("key-path" spend), or they can provide the internal public key $P$, a Bitcoin locking script, unlocking witness stack, and a proof that the locking script was committed as a [merkle tree leaf](https://en.wikipedia.org/wiki/Merkle_tree) of $m$. If the script evaluation succeeds, the spender is deemed authentic ("script-path" spend). [See BIP341 for more information](https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki).

The critical distinction between P2TR and the legacy pay-to-\*-hash output script types is that taproot encodes a secp256k1 point directly in the output script. This means a quantum adversary (QA) can invert any P2TR output pubkey $P'$ to get its secret key, and claim the P2TR UTXO using a "key-path spend", even if the address has not been spent from before.

This is not a new observation, there has been much discourse and controversy surrounding this property of the taproot upgrade.

- https://freicoin.substack.com/p/why-im-against-taproot
- https://lists.linuxfoundation.org/pipermail/bitcoin-dev/2021-March/018641.html
- https://bitcoinops.org/en/newsletters/2021/03/24/#discussion-of-quantum-computer-attacks-on-taproot

### Summary

Against a quantum adversary, P2TR addresses are comparable in security to an already-reused key-hash address. The QA has unlimited time to invert the output pubkey and can start attacking any P2TR output from the moment they learn of its output public key $P'$. The burden of action is on the address owner to move funds to a quantum-safe address - or to avoid using the P2TR output script type - as soon as they realize the QA exists (or could exist soon).

## Note on Multisig

P2SH or P2WSH addresses which use `OP_CHECKMULTISIG` cause a linear increase in the processing time needed for a QA to fully compromise the address. For an $m$-of-$n$ multisig address composed of $n$ distinct pubkeys, the QA must invert at least $m$ of the constituent public keys to wield spending power over the address.

This slowdown will probably be offset by parallel-processing across multiple quantum processors, or with parallelized quantum algorithms which invert multiple public keys at once.

P2TR multisig addresses which use key aggregation do not have this property, because the taproot output pubkey $P' = P + H(P, m) \cdot G$ can always be inverted. Possessing the secret key of $P'$ is always sufficient to spend the P2TR output _under current consensus rules._

## Note on BIP32

Most consumer wallets derive their addresses using BIP32 hierarchical-deterministic (HD) wallet schemes. This allows a single seed to derive basically unlimited secret keys and corresponding public addresses for any script type. Wallets will sometimes share their extended public keys to avoid the need to communicate many individual child addresses.

To a quantum adversary, a BIP32 extended public key (xpub) is equivalent to its counterpart extended private key (xpriv) given enough time to invert the xpub. Once inverted, the QA can quickly derive all child addresses, and can thereafter monitor the blockchain to steal any funds paid to them.

[To comply with BIP44 standards](https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki), most wallets derive one xpub/xpriv pair at specific BIP32 paths for each Bitcoin address type.

- `m/44'/0'/n'` for P2PKH
- `m/49'/0'/n'` for P2SH-wrapped P2WPKH
- `m/84'/0'/n'` for native P2WPKH
- `m/86'/0'/n'` for P2TR

Each layer of derivation in these key paths after the master key (`m`) is _hardened,_ meaning that deriving that child key involves hashing the parent secret key.

Remember QAs cannot invert a hash function as efficiently as they invert elliptic curve public keys. This means that the BIP32 master key `m`, as well as the xprivs at any previously unused key path, are generally safe from the eyes of the QA provided the wallet has not exposed the BIP32 master public key. We will make use of this property in some of the options we discuss later.

# Quantum-Safe Signatures

The critical question is: _What cryptographic mechanism replaces elliptic curve digital signatures?_

Whatever mechanism replaces EC signatures must be _asymmetric,_ allowing a user to give payment instructions to a prospective sender, without surrendering control of their money to the sender. This way the receiver can claim that payment later without revealing their signing credentials to anybody (like one would with a password to a bank website). This rules out symmetric cryptographic schemes, such as HMAC, simple hashing, or symmetric encryption algorithms like AES or ChaCha.

We have numerous quantitative metrics by which to judge a replacement algorithm:

- Public key size
- Signature size
- Secret key size
- Key generation time
- Signature computation time
- Signature verification time

We also have qualitative statements we can make about a signing algorithm:

- *Statefulness:* Does a signer need to maintain state between each signature?
- *Reusability:* Can a signer reuse their secret key to sign multiple messages?

Today we're going to explore one genre of signing algorithms which is almost certainly the safest and most conservative candidate, but which comes with some big practical issues: *Hash-based signatures*, or *HBS* for short.

Hash-based signature schemes are constructed from a simple one-way cryptographic hash function like SHA256. Secret keys are usually vectors of preimages. Public keys are usually hashes, or vectors of hashes. Signatures are usually vectors of preimages, paired with auxiliary data needed to verify the preimages correspond to a specific static public key. Unlike other candidates for post-quantum cryptography, hash-based signatures do not rely on new (possibly flawed) cryptographic assumptions - This is what makes them the conservative option.

I'll now give a detailed description of several well-known hash-based signature algorithms, in increasing order of complexity. If I lose you in some of the math, don't worry - Understanding the internals of the HBS schemes is not critical to understanding how they can be applied to Bitcoin.

Skip through to the [final analysis section](#Analysis) if you don't care about the technical details of HBS schemes.

Before we begin, some notation:

| Notation | Meaning |
|:--------:|:---------:|
| $\\{0, 1\\}^n$ | The set of all possible bit strings of length $n$ |
| $x \leftarrow S$ | Uniform random sampling of an element $x$ from the set $S$ |

Let $H(x) \rightarrow \\{0, 1\\}^n$ be a secure cryptographic hash function which outputs pseudorandom bit strings of length $n$ (For SHA256, $n = 256$). All constructions below are typically based on this single cryptographic primitive.

<div style="background-color: rgba(255, 40, 90, 0.05); border-radius: 8px; padding: 15px 15px 15px 30px;"><b style="font-size: 130%;">Disclaimer</b>

<p>I began studying these hash-based signing protocols only a few weeks ago. Do not take my technical descriptions below as precise and safe for real-world use, because I have probably made typos or omitted stuff. The purpose of these descriptions is to illustrate and convey the essence of the algorithms, not to provide any concrete implementation instructions.</p>

<p>Roll your own crypto at your own peril.</p>

<p>If you are an expert in hash-based signatures and have noticed a typo, please <a href="mailto:conduition@proton.me">email me</a> or <a href="https://github.com/conduition/conduition.io">open a pull request to fix it.</a></p>
</div>

Let's start with the simplest and earliest-known example of an HBS scheme: [Lamport Signatures](https://en.wikipedia.org/wiki/Lamport_signature).

## Lamport Signatures

We want to sign a single bit of information - 0 or 1 - using our hash function $H(x)$.

We generate two random preimages of $n$ bits each:

$$ p_0 \leftarrow \\{0, 1\\}^n $$
$$ p_1 \leftarrow \\{0, 1\\}^n $$

The tuple $(p_0, p_1)$ is a *one-time* secret key.

Our public key is the tuple $(P_0, P_1) = (H(p_0), H(p_1))$. We can safely give the public key to anybody, and later reveal either $p_0$ to sign the bit zero, or $p_1$ to sign the bit one. Any observer with the public key $(P_0, P_1)$ can easily verify $H(p_b) = P_b$ for a given bit $b$.

We may generalize this approach to sign message strings of arbitrary bit length $m$ by generating more preimages - one per message bit. Then our secret key would be:

$$ (p_0, p_1) : p_i \leftarrow \\{\\{0, 1\\}^n\\}^m $$

Each $p_i$ is an array of $m$ random preimages $\\{p_{(i, 1)}, p_{(i, 2)}, ... p_{(i, m)}\\}$.

Our public key is made of hashes of every preimage.

$$
\begin{align}
(P_0, P_1) : P_i &= \\{P_{(i, 1)}, P_{(i, 2)}, ... P_{(i, m)}\\}  \\\\
                 &= \\{H(p_{(i, 1)}), H(p_{(i, 2)}), ... H(p_{(i, m)})\\}  \\\\
\end{align}
$$

To produce a signature $\sigma$ on the message bits $\\{b_1, b_2, ... b_m\\}$, we reveal the appropriate preimages per bit:

$$ \sigma = \\{p_{(b_1, 1)}, p_{(b_2, 2)}, ... p_{(b_m,\ m)}\\} $$

To verify, simply check that the hashed preimages match the public key for every bit $1 \le i \le m$ in the message.

$$ H(p_{(b_i,\ i)}) = P_{(b_i,\ i)} $$

### Properties

Lamport Signatures are a one-time signature (OTS) protocol - once the signer reveals a signature for a given public key, they can never use the same signing key again for a different message. If they do, the signer gives observers the ability to forge signatures on new messages they never consented to sign.

For instance, if $m = 2$ and a signer reveals two signatures for distinct messages $\\{0, 1\\}$ and $\\{1, 0\\}$, they will have now revealed all four preimages in their secret key $(p_0, p_1)$. Any observer can now sign the other messages $\\{1, 1\\}$ and $\\{0, 0\\}$ even though the key owner never approved those messages.

Signatures have bit length $n \cdot m$ and public keys have bit length $2 n m$.

Signing is simple, as it consists only of revealing secrets. Verification requires $m$ evaluations of $H(x)$.

### Modifications

We can modify lamport signatures to improve the amount of space consumed by keys and signatures at the cost of some computation time.

**Deterministic key-gen**: Instead of randomly sampling our secret key preimages, we can derive them from a root secret $r$ using $H$.

$$ p_{(b, i)} = H(r, b, i) $$

This way we only need to store a single 256-bit secret preimage for each Lamport OTS key, instead of $2m$ preimages, but we do need to compute $4m$ hashes to derive our public key, and we must compute $m$ hashes to sign a message of $m$ bits.

**Compact public keys:** We can reduce the size of public keys from $2 n m$ to simply $n$ bits, by representing the public key itself as a hash of the standard Lamport public key.

$$
\begin{align}
P &= H(P_0, P_1) \\\\
  &= H(P_{(0, 1)} ... P_{(0, m)},\ P_{(1, 1)} ... P_{(1, m)}) \\\\
\end{align}
$$

However, we must now adjust our signature algorithm to supply not only the $m$ preimages, but also the $m$ complementary hashes, which are needed to reconstruct the public key hash $P$.

$$
\sigma = \\{(p_{(b_1, 1)}, P_{(1-b_0, 1)}) ... (p_{(b_m, m)}, P_{(1 - b_m, m)})\\}
$$

Signatures double in size to $2nm$ bits, whereas public keys shrink from $2mn$ bits to only $n$ bits.

Verifiers can verify $\sigma$ against $P$ by hashing each of the $m$ preimages and then hashing those hashes to re-derive $P$.

### Comparisons

The following table shows some concrete examples of time/space tradeoffs for Lamport signatures. In these examples, I'll set $m = n = 256$, to emulate the results using the well-known hash function SHA256. All sizes are in bits.

| Algorithm | Signature size | Public key size | Secret key size |
|:---:|:---------------:|:-:|:-:|
| Vanilla Lamport | $m n = 65536$ | $2mn = 131072$ | $2mn = 131072$ |
| Compact Lamport | $2mn = 131072$ | $n = 256$ | $n = 256$ |

Below I note the time complexity of Lamport signatures in terms of the number of invocations of the hash function $H(x)$.

| Algorithm | Keygen time | Signing time | Verification time |
|:-:|:-:|:-:|:-:|
| Vanilla Lamport | $O(2m)$ | $O(1)$ | $O(m)$ |
| Compact Lamport | $O(4m + 1)$ | $O(m)$ | $O(m + 1)$ |

### Viability for Bitcoin

I expect the Compact Lamport signature approach would be the most practical flavor of Lamport Signatures, as public keys would be the same size or possibly smaller than a P2TR pubkey is today.

However, even the most space-efficient Lamport signatures with the lowest viable security levels ($m = n = 160$) would require at least 6400 bytes of witness space per signature before compression. That's 100x larger than a Schnorr signature.

There's also the matter of key reuse. Lamport signatures are a _one-time_ signature scheme. If a Bitcoin user spends from a hypothetical "pay-to-lamport-public-key" address, they'll never be able to spend from that address again without giving observers some power to forge signatures.

Power users would not be affected greatly, as the best-practice touted by most experienced Bitcoiners is to use addresses only once, for a single receive/spend cycle. Yet, as we've seen earlier, a huge fraction of bitcoiners by volume have either never heard this advice, or have disregarded it. It will be difficult to convey to these users that address reuse with Lamport signatures will be more than just a privacy no-no - It could seriously compromise their security. This would make life especially difficult for cold-storage hardware signing devices, which rely on a semi-trusted host machine to prompt them with transactions to sign.

Lamport signatures are stateful, in that a signer should know if he has used his private key to sign a message before to know whether signing again could be dangerous.

Lamport signatures are _not_ backwards compatible with Bitcoin's consensus protocol as it exists today, although [an outlandish scheme has been proposed by Ethan Heilman](https://mailing-list.bitcoindevs.xyz/bitcoindev/CAEM=y+XyW8wNOekw13C5jDMzQ-dOJpQrBC+qR8-uDot25tM=XA@mail.gmail.com/) which make use of `OP_SIZE` to Lamport-sign the size of an ECDSA signature. Whether this approach is secure is still up for debate. But even with such creative invention, the size of such a signature would prohibit its usage in P2WSH addresses. At least with current knowledge, a soft-fork would be needed to add Lamport signature support.

Even after such a soft fork, existing addresses with exposed public keys would still be vulnerable to a quantum adversary. Users would need to actively migrate coins to a hypothetical pay-to-lamport-public-key address format.

## Winternitz One-Time Signatures (WOTS)

Winternitz signatures rely on a chain of hashes starting from a set of secret preimages. By revealing certain intermediate hashes in that chain, the signer can sign a specific message.

In comparison to the Lamport scheme, WOTS shoulders a higher computational burden in exchange for much shorter signatures. Let's see how they work.

First, let's re-establish some parameters:

- Let $m$ be the bit-length of the message we want to sign.
- Let $w = 2^t$ be the "Winternitz parameter" (used for time/space tradeoffs).
- Let $t = \log_2 w$ be the bit-group width into which we parse the message.
- Let $\ell_1 = \left \lceil{\frac{m}{t}} \right \rceil$ be the length of the message in digits of base $w = 2^t$.
- Let $\ell_2 = \left \lfloor{\frac{\log_2(\ell_1(w-1))}{t}} \right \rfloor + 1$ be the checksum length in digits of base $w$.
- Let $\ell = \ell_1 + \ell_2$ be the overall length of the message plus the checksum in digits of base $w$.

As WOTS relies on hash-chains, we need a hash-chaining function $H^d(x)$ which uses our primitive hash function $H(x)$ internally.

$$ H^0(x) = x $$
$$ H^d(x) = H(H^{d-1}(x)) $$

So for instance, $H^2(x)$ would hash $x$ twice.

$$
\begin{align}
H^2(x) &= H(H^1(x))  \\\\
       &= H(H(H^0(x))) \\\\
       &= H(H(x)) \\\\
\end{align}
$$

Now we're ready to generate our keys. We start by sampling $\ell$ random preimages of $n$ bits each.

$$ p = \\{p_1 ... p_\ell\\} \leftarrow \\{\\{0, 1\\}^n\\}^\ell $$

To compute the Winternitz public key $P$, we iteratively hash each preimage $w-1 = 2^t - 1$ times.

$$ P_i = H^{w-1}(p_i) $$
$$ P = \\{P_1 ... P_\ell\\} $$

To sign a message $x$ of bit-length $m$, we break $x$ up into $\ell_1$ digits of base $w$ (I think of them as groups of $t$ bits).

$$ x = \\{x_1 ... x_{\ell_1}\\} : 0 \le x_i \lt w $$

We compute a _checksum_ $c$ of the message:

$$ c = \sum_{i=1}^{\ell_1} \left( w - 1 - x_i \right) $$

Because $c \le \ell_1(w-1)$, the binary representation of $c$ is at most $\log_2(\ell_1(w-1))$ bits long. This means we can always represent $c$ as an array of $\ell_2 = \left \lfloor{\frac{\log_2(\ell_1(w-1))}{t}} \right \rfloor + 1$ digits in base $w = 2^t$. In fact that's exactly what we'll do.


$$ \vec{c} = \\{c_1 ... c_{\ell_2}\\} : 0 \le c_i \lt w $$

We append this checksum array $\vec{c}$ to the message $x$, to get the final message to sign, which is just an array of $\ell = \ell_1 + \ell_2$ digits of base $w$ (I think of them as groups of $t$ bits).

$$
\begin{align}
b &= x \parallel \vec{c}  \\\\
  &= \\{x_1 ... x_{\ell_1},\ c_1 ... c_{\ell_2}\\} \\\\
\end{align}
$$

To sign the checksummed-message $b$, we go digit-by-digit through $b$, and for each digit $b_i \in b$, we recursively hash the preimage $p_i$, for $b_i$ iterations. This array of "intermediate hashes" in each hash-chain _is_ the Winternitz signature.

$$ \sigma_i = H^{b_i}(p_i) $$
$$ \sigma = \\{\sigma_1 ... \sigma_\ell\\} $$

A verifier given the plain message $x$ and public key $P = \\{P_1 ... P_\ell\\}$ must first reconstruct the checksummed message $b = x \parallel \vec{c}$ just like the signer should've. Then the verifier simply follows each hash chain in the signature to its expected terminal hash, and compares these terminal hashes against the public key $P$.

$$ P_i \stackrel{?}{=} H^{w-1-b_i}(\sigma_i) $$

If this holds for all $1 \le i \le \ell$, then the signature is valid.

### Properties

**Security.** Note the special role played by the checksum. Without it, revealing one set of intermediate hashes should allow an observer to forge signatures on any message in a "higher" position in the hash chain.

For instance, consider the following diagramed example.

<img src="/images/quantum-hbs/wots.svg">

If we don't add a checksum to the two-digit message $x$, the signature would simply be the two intermediate hashes $\\{H^3(p_1), H(p_2)\\}$. But then anybody who learns this signature could forge a signature on any message $x'$ "higher" in the chain, like $x' = \\{3, 2\\}$ or $x' = \\{3, 3\\}$.

Because of the checksum construction, increasing any message digit  $x_i \in x$ implies _decreasing_ at least one checksum digit $c_i \in \vec{c}$. To forge the signature on the checksum as well, the observer would need to invert the hash function (implausible). So an observer cannot forge any other valid signature for $P$ _as long as the signer uses their signing key $p$ only once._

**Size.** Signatures, public keys, and secret keys all have bit length

$$ n \cdot \ell = n \left( \left \lceil{\frac{m}{t}} \right \rceil + \left \lfloor{\frac{\log_2(\left \lceil{\frac{m}{t}} \right \rceil (w-1))}{t}} \right \rfloor + 1 \right) $$

In case that equation seems unintuitive to you, you're not alone. I plotted the relationship between the time/space tradeoff parameter $t$ on the X axis and the final WOTS signature size on the Y axis (in bits). I set $n = m = 256$ to generate this particular graph.

<img src="/images/quantum-hbs/wots-sig-size.png">

Higher values of $t$ result in much smaller signatures and keys at first, but we get diminishing returns. In the limit as $t \rightarrow \infty$, it seems the shortest we can make our signatures is $2n$.

Approaching anywhere near that limit would be wildly impractical though, because by increasing $t$ we also exponentially increase the amount of work we need to do to generate public keys, sign messages, and verify signatures.

**Runtime.** Given a secret key $p$ containing $\ell$ preimages, to derive its public key we must compute $O(\ell (2^t-1))$ hashes to derive our public key.

Public key generation uses the same hash-chaining procedure as signing/verifying. To sign or verify a signature, we must compute at worst $O(\ell \cdot (2^t-1))$ hashes (on average, only half that).

To avoid this exponential blowup in computation time, most real-world WOTS instantiations keep $t$ quite low, usually at most 16, which would mean computing on the order of $2^{16}$ hashes for a signature operation, per $t$ bits in the message. As you can see, beyond $t=16$ performance will become a big issue.

<img src="/images/quantum-hbs/wots-sig-performance.png">

<sub>X-axis is $t$, Y-axis is the number of iterations of $H$ needed to generate a public key.</sub>

For reference, my weedy little computer can generate a WOTS public key with $t=16$ in around 0.4 seconds. Verification and signing will each require about the same in sum, as the signer starts the hash-chain which the verifier finishes.

Curiously, due to the zero-sum nature of the hash-chain signature construction, signers and verifiers who are able to select the message they're signing can also influence the amount of work they and their counterparty must perform. By selecting a message digit $x_i$ significantly lower than the base $w$, the signer needs to do _less work_ to compute $\sigma_i = H^{x_i}(p_i)$, while the verifier must do _more work_ to compute $H^{w-1-x_i}(\sigma_i)$. This could be a hinderance for a blockchain application like Bitcoin, because one signer could disproportionately emburden thousands of verifiers (nodes).

### Modifications

**Compact public keys:** WOTS lends itself well to compacting public keys via hashing. A Winternitz signature gives the verifier everything they need to reconstruct the signer's public key $P = \\{P_1 ... P_\ell\\}$, and so we can represent a WOTS key succinctly with its hash, in exchange for an one additional unit of work for the verifier.

$$P' = H(P) = H(\\{P_1 ... P_\ell\\}) $$

This decreases the public key size from $n \cdot \ell$ bits to merely $n$ bits.

**Deterministic key-gen**: Like with Lamport signatures, WOTS secret keys can be generated from a seed with only $\ell$ invocations of $H(x)$.

**Smaller and more secure signatures**: To improve performance and security, one should consider using [WOTS+](https://eprint.iacr.org/2017/965), a variant of WOTS which adjusts the hash-chain construction to XOR each of the intermediary hashes in every hash chain with a _randomization_ vector. [This odd choice allows the security proof to reduce forgeries to second preimage extraction](https://crypto.stackexchange.com/questions/64719/wots-why-does-it-xor-before-running-data-through-the-hash-function): If someone can forge a WOTS+ signature, they can also break the second-preimage resistance of $H(x)$. The security of WOTS+ thus relies on _weaker_ assumptions than standard WOTS, which assumes a forging adversary cannot break _collision resistance_ of $H(x)$ (easier to do than finding a second-preimage). Broadly speaking, weaker assumptions lead to better security.

This means we can get away with using WOTS+ with smaller, faster hash functions which have broken collision resistance but are still believed to be second-preimage resistant, as long as one can accept the lower security level implied by their shorter output. Or WOTS+ can be instantiated with larger hash functions, and for only a modest increase in signature size and verification complexity, we gain the added security of weaker assumptions.

WOTS+ relies on a set of $n$-bit randomization elements $r = \\{r_1 ... r_{w-1}\\}$ and an HMAC key $k$ which can all be generated pseudorandomly with $H$ and a seed, just like the vanilla WOTS secret key $p$.

Instead of computing the intermediate values of the hash-chains as $H^d(p_i)$, WOTS+ uses a keyed hash function $H_k(x)$ (think of it as an HMAC). The _chaining_ function $c_k^d(p_i, r)$ XORs the output of each keyed-hash on $p_i$ with a randomization element $r_i$ before proceeding with the next iteration.

$$ c_k^{0}(p_i, r) = p_i $$
$$ c_k^{d}(p_i, r) = H_k(c_k^{d-1}(p_i, r) \oplus r_d) $$

For instance, $c_k^2(p_i, r)$ would be:

$$
\begin{align}
c_k^2(p_i, r) &= H_k(c_k^1(p_i, r) \oplus r_2) \\\\
              &= H_k(H_k(c_k^0(p_i, r) \oplus r_1) \oplus r_2) \\\\
              &= H_k(H_k(p_i \oplus r_1) \oplus r_2) \\\\
\end{align}
$$

WOTS+ appends the tuple $(r, k)$ to the public key, so that verifiers may also compute $c_k^d(x, r)$. To improve space-efficiency for public and secret keys, we can instead derive $(r, k)$ from a public seed $s$ (which is itself probably derived from a secret seed). The signer distributes $s$ as part of their signature.

$$ \sigma = \\{s, \sigma_1, ..., \sigma_\ell\\} $$

The compact WOTS+ public key $P'$ can then be defined as a simple $n$-bit hash.

$$ P' = H(\\{c_k^{w-1}(p_1)\ ...\ c_k^{w-1}(p_\ell)\\}) $$

**More efficient signatures using brute-force compression:** [This paper](https://ieeexplore.ieee.org/stamp/stamp.jsp?tp=&arnumber=10179381) suggests modifying the WOTS signing algorithm so that the signer repeatedly hashes the input message $x$ along with an incrementing 32-bit salt/counter $s$, until the resulting WOTS message checksum $c = \sum_{i=1}^{\ell_1} \left( w - 1 - x_i \right)$ equals some fixed static value, e.g. zero. The signer appends the salt $s$ to the signature and the verifier confirms the resulting checksum is zero.

This allows the signer to omit the checksum portion of the WOTS signature, because the checksum is verified to always work out to a fixed static value. Messages without this fixed checksum are not valid, and so the checksum itself does not need to be signed. This approach is called "WOTS with Compression" (WOTS+C).

The effect of this compression is to reduce the overall runtime of the scheme on average across keygen, verification, _and signing,_ while also reducing signature size by removing the $\ell_2$ checksum hash chains from the construction completely. One would think signing WOTS+C would take _more_ time, due to the signer's brute-force search for the salt $s$. But the signer now needs to compute only $\ell_1$ intermediate hashes for the signature, instead of $\ell = \ell_1 + \ell_2$. These effects offset each other. At least, it does according to the paper authors, I have not yet validated this myself.

The authors of WOTS+C even propose ways for the signer to further reduce the size of their signature by removing additional chains from their signature, at the cost of additional work to find an appropriate message salt.

### Comparisons

The following table shows some concrete examples of time/space tradeoffs for various kinds of Winternitz signatures. In these examples, I'll set $m = n = 256$, to emulate the results using the well-known hash function SHA256. All sizes are in bits.

| Algorithm | Signature size | Public key size | Secret key size |
|:---:|:---------------:|:-:|:-:|
| Vanilla WOTS $t=2$ | $n \cdot \ell = 34048$ | $n \cdot \ell = 34048$ | $n \cdot \ell = 34048$ |
| Compact WOTS $t=2$ | $n \cdot \ell = 34048$ | $n = 256$ | $n = 256$ |
| Compact WOTS $t=4$ | $n \cdot \ell = 17152$ | $n = 256$ | $n = 256$ |
| <div style="background-color: rgba(25, 125, 125, 0.3); border-radius: 4px;">Compact WOTS $t=8$</div> | $n \cdot \ell = 8704$ | $n = 256$ | $n = 256$ |
| Compact WOTS $t=16$ | $n \cdot \ell = 4608$ | $n = 256$ | $n = 256$ |
| ... ||||
| Vanilla WOTS+ $t=2$ | $n \cdot \ell = 34048$ | $n \cdot (\ell + 2^t) = 35072$ | $n \cdot (\ell + 2^t) = 35072$ |
| Compact WOTS+ $t=2$ | $n \cdot (\ell + 1) = 34304$ | $n = 256$ | $n = 256$ |
| Compact WOTS+ $t=4$ | $n \cdot (\ell + 1) = 17408$ | $n = 256$ | $n = 256$ |
| <div style="background-color: rgba(25, 125, 125, 0.3); border-radius: 4px;">Compact WOTS+ $t=8$</div> | $n \cdot (\ell + 1) = 8960$ | $n = 256$ | $n = 256$ |
| Compact WOTS+ $t=16$ | $n \cdot (\ell + 1) = 4864$ | $n = 256$ | $n = 256$ |
| ... ||||
| Compact WOTS+C $t=2$ | $n \cdot \ell_1 + 32  = 32800$ | $n = 256$ | $n = 256$ |
| Compact WOTS+C $t=4$ | $n \cdot \ell_1 + 32  = 16416$ | $n = 256$ | $n = 256$ |
| <div style="background-color: rgba(25, 125, 125, 0.3); border-radius: 4px;">Compact WOTS+C $t=8$</div> | $n \cdot \ell_1 + 32 = 8224$ | $n = 256$ | $n = 256$ |
| Compact WOTS+C $t=16$ | $n \cdot \ell_1 + 32  = 4128$ | $n = 256$ | $n = 256$ |


Below I note the worst-case time complexity of each flavor of Winternitz signatures in terms of the number of invocations of the hash function $H(x)$ (or $H_k(x)$ for WOTS+).

For the sake of brevity, let $h = 2^t - 1$ be the total number of hashes in each chain.

| Algorithm | Keygen time | Signing time | Verification time |
|:-:|:-:|:-:|:-:|
| Vanilla WOTS | $O(\ell h)$ | $O(\ell  h)$ | $O(\ell h)$ |
| Compact WOTS | $O(\ell (h + 1) + 1)$ | $O(\ell h)$ | $O(\ell h + 1)$ |
| Vanilla WOTS+ | $O(\ell h)$ | $O(\ell  h)$ | $O(\ell  h)$ |
| Compact WOTS+ | $O(\ell (h + 1) + h +  2)$ | $O(\ell  h)$ | $O(\ell h + 1)$ |
| Compact WOTS+C | $O(\ell_1 (h + 1) + h + 2)$ | $O(\ell_1  h + w^\ell / v)$ \* | $O(\ell_1 h + 2)$ |

<sub>The additional $h + 1$ operations in Compact WOTS+ keygen are caused by derivation of $(r, k)$.</sub>

\* $v$ is the number of possible message hashes which result in a zero checksum. See [page 6 of the SPHINCS+C paper](https://ieeexplore.ieee.org/stamp/stamp.jsp?tp=&arnumber=10179381).


### Viability for Bitcoin

Winternitz signatures are significantly smaller than Lamport signatures. With compaction and deterministic key-generation, the public and private keys can be condensed down to the same constant size ($n$ bits).

Compact WOTS+ with $t=8$ seem like the best compromise between speed and signature size. Assuming we use SHA256 as our hash function, WOTS+ with $t=8$ could be instantiated with signatures of **size slightly more than 1KB**, with 32-byte public and private keys. Verification would require at most 8670 hash invocations, which takes only a few milliseconds on most modern machines. WOTS+C could be used to compress signatures even further, and verification can be parallelized across hash chains since they are independent.

However, like Lamport signatures, WOTS is a stateful one-time signature scheme, so it inherits all the same security concerns as Lamport signatures regarding address reuse ergonomics.

## Hash to Obtain Random Subsets (HORS)

HORS is a _few-time_ signature protocol based on Lamport Signatures which relies on complexity theory to make signatures smaller and provably resilient to forgery.

To generate a HORS key, the signer samples some large number $t$ random preimages $\\{p_0 ... p_{t-1}\\}$, and gives out the hashes of those preimages as their public key $P$.

$$ P_i = H(p_i) $$
$$ P = \\{P_0 ... P_{t-1}\\} $$

To sign a specific message, the signer reveals a specific _subset_ of $k$ preimages. Which subset to reveal is dictated by the message to sign.

$t$ tells us the _total_ number of preimages in the secret key, while $k$ is the number of _selected_ preimages per signature. Notice there's a space tradeoff between HORS signature and pubkey size. Increasing $k$ means larger signatures. Increasing $t$ means larger public and private keys.

These parameters also affect the security of the HORS scheme. With $t$ total preimages, we have $\binom{t}{k} = \frac{t!}{k! (t-k)!}$ possible [unordered combinations](https://en.wikipedia.org/wiki/Binomial_coefficient) of $k$ preimages - This is the number of possible signatures. If we have a message space $m$ bits wide, we should choose $t$ and $k$ so that $\binom{t}{k} \ge 2^m$; otherwise there would be collisions where one signature is valid for more than one message.

The key ingredient of HORS is a _subset selection_ algorithm $S(x)$. Given a message $0 \le x < \binom{t}{k}$, this function returns a unique subset of $k$ random elements in the set $\\{0 ... t-1\\}$

$$ S(x) \rightarrow \\{h_1 ... h_k\\} : 0 \le h_j \lt t $$

[The HORS paper](https://www.cs.bu.edu/~reyzin/papers/one-time-sigs.pdf) suggests two [bijective functions](https://en.wikipedia.org/wiki/Bijection) which fulfill the subset-selection role of $S(x)$ with perfect OTS security, ensuring that each message uniquely corresponds to a $k$-element subset of $\\{0...t-1\\}$.

However these bijective functions are not one-way functions, so if a signer provides two or more signatures from the same key it is trivial for an observer to forge new signatures by working backwards to determine which messages they can now sign using the signer's revealed preimages.

To address this, HORS instead uses a one-way hashing function $S_H(x)$ to select subsets - hence the name Hash-to-Obtain-Random-Subsets. Here's how you might implement $S_H$. The signer computes the hash of the input message $h = H(x)$, and then parses $h$ into $\log_2(t)$-bit integers $\vec{h} = \\{h_1 ... h_k\\}$. The output of $H$ is an $n$ bit string, so this gives us at most $\frac{n}{\log_2 t}$ bit groups per message hash, but we can extend the output of $H$ to arbitrary lengths (e.g. by chaining it) so this isn't really a hard limit.

Because the output of $S_H(x)$ is pseudorandom, it's possible that the integer set $\vec{h}$ we parse from it could contain duplicate elements. If this occurs, we simply discard the duplicates and allow for shorter signatures. So really HORS signatures contain _at most_ $k$ preimages, but possibly fewer. The lower $t$ is, the more likely duplicates are to occur. This actually has been the subject of certain attacks in which the attacker intentionally tries to find messages for which the set $\vec{h}$ is small, so that they don't need as many preimages to forge a signature.

After computing $\vec{h} = S_H(x)$, the HORS signer maps the integers $\vec{h} = \\{h_1 ... h_k\\}$ to a subset $\\{p_{h_1} ... p_{h_k}\\}$ of their secret key preimages. This forms the signature $\sigma$ on message $x$.

$$ \sigma_i = p_{h_i} $$
$$
\begin{align}
\sigma &= \\{\sigma_1 ... \sigma_k\\} \\\\
       &= \\{p_{h_1} ... p_{h_k}\\} \\\\
\end{align}
$$

<img src="/images/quantum-hbs/hors.svg">

A HORS verifier with a public key can then verify the message by recomputing $h = S_H(x)$ as the signer did, and checking $P_{h_i} = H(\sigma_i)$ for each preimage in $\sigma$.

### Properties

Unlike previous signature schemes, using a HORS signing key to sign more than one message does not immediately compromise the key's security, it merely reduces security. An attacker who sees two or more signatures from the same secret key will need to _brute-force the hash function_ $H$ to figure out which alternative messages they can forge signatures on using the revealed preimages. This is why HORS is designated a "few-time" signature (FTS) scheme, instead of a _one-time_ signature (OTS) scheme. The hash-to-subset approach is what enables the few-time property of HORS.

The signer still has to be cautious though, because as the attacker sees more signatures, their guess-and-check attack will get progressively easier. The HORS paper describes exactly how much easier. The following expression gives the bits of security for a HORS public key after an attacker has seen $r$ distinct message signatures.

$$
k(\log_2 t - \log_2 k - \log_2 r ) = k \cdot \log_2 \left( \frac{t}{kr} \right)
$$

Usually $r$ is small (less than 10 signatures) but $r$ _can_ be increased relatively safely by also increasing either $t$ or $k$. This quickly blows up the size of keys and signatures though.

**Size.** HORS signatures have bit size $kn$, while public and private keys have bit size $tn$.

If we fix $r = 1$ (so $\log_2 r = 0$), and we fix a constant security level of $b$ bits, then we can plot the key size $t$ as a function of signature size $k$.

$$
\begin{align}
k(\log_2 t - \log_2 k - \log_2 r ) &= b \\\\
k(\log_2 t - \log_2 k ) &= b \\\\
k \log_2 t - k \log_2 k  &= b \\\\
k \log_2 t &= k \log_2 k + b  \\\\
\log_2 t &= \frac{k \log_2 k + b}{k}  \\\\
\log_2 t &= \log_2 k + \frac{b}{k} \\\\
t &= 2^{(\log_2 k + b/k)} \\\\
\end{align}
$$

<img src="/images/quantum-hbs/hors-sig-size.png">

<sub>X axis is the signature size $k$. Y axis is the key size $t$. Exercise to the reader: How would you use this information to deduce the smallest possible combined key + signature size which still achieves $b$ bits of security?</sub>

**Runtime.** The HORS keygen procedure requires $O(t)$ evaluations of the hash function $H$. Signing is extremely fast, just a single evaluation of the subset selection algorithm $S_H(x)$, and then the signature elements are picked from a set of preimages the signer already knows. Verification is also fast, with just $O(k)$ invocations of $H$, and $k$ is usually much lower than $t$.

### Modifications

**Deterministic key-gen:** As with previous examples, we can derive the HORS secret key preimages from a single $n$-bit seed. This reduces secret key size to $n$ bits but at the cost of $O(t)$ additional hash invocations during key generation.

**Compact public keys:** A modified version of HORS called "HORS with Trees" (HORST) was proposed by the authors of the [SPHINCS signature scheme](https://eprint.iacr.org/2014/795.pdf). Instead of representing the public key plainly as $t$ hashes each of $n$ bits, the public key is defined as the merkle-tree root of those $t$ hashes. Signatures must be lengthened to supply merkle-tree membership proofs for each element of the signature $\sigma_i$, but this trade-off greatly decreases the public key length from $tn$ bits to only $n$ bits.

### Comparisons

The following table shows some concrete examples of time/space trade-offs for HORS signatures. In these examples, I'll aim for a security level of approximately $k(\log_2 t - \log_2 k - \log_2 r ) \approx 128$ bits when $r=1$ (one signature). The hashed message size $m$ will vary to accommodate different parameters. All sizes are in bits.

| Algorithm | Signature size | Public key size | Secret key size |
|:---:|:---------------:|:-:|:-:|
| Vanilla HORS $k=48$, $t=320$ | $kn = 12288$  | $tn = 81920$ | $tn = 81920$ |
| Vanilla HORS $k=32$, $t=512$ | $kn = 8192$  | $tn = 131072$ | $tn = 131072$ |
| Vanilla HORS $k=28$, $t=640$ | $kn = 7168$  | $tn = 163840$ | $tn = 163840$ |
| Vanilla HORS $k=24$, $t=1024$ | $kn = 6144$  | $tn = 262144$ | $tn = 262144$ |
| Vanilla HORS $k=16$, $t=4096$ | $kn = 4096$  | $tn = 1048576$ | $tn = 1048576$ |
| Vanilla HORS $k=14$, $t=8192$ | $kn = 3584$  | $tn = 2097152$ | $tn = 2097152$ |
| Vanilla HORS $k=8$, $t=65536$ | $kn = 2560$  | $tn = 16777216$ | $tn = 16777216$ |
| Compact HORST $k=48$, $t=320$ | $kn + g(x) \approx 73588$ \* | $n = 256$ | $n = 256$ |
| Compact HORST $k=32$, $t=512$ | $kn + g(x) \approx 57344$ \* | $n = 256$ | $n = 256$ |
| Compact HORST $k=28$, $t=640$ | $kn + g(x) \approx 53508$ \* | $n = 256$ | $n = 256$ |
| Compact HORST $k=24$, $t=1024$ | $kn + g(x) \approx 51200$ \* | $n = 256$ | $n = 256$ |
| Compact HORST $k=16$, $t=4096$ | $kn + g(x) \approx 45056$ \* | $n = 256$ | $n = 256$ |
| Compact HORST $k=14$, $t=8192$ | $kn + g(x) \approx 43520$ \* | $n = 256$ | $n = 256$ |
| Compact HORST $k=8$, $t=65536$ | $kn + g(x) \approx 39936$ \* | $n = 256$ | $n = 256$ |

Below I note the time complexity of HORS signatures in terms of the number of invocations of the hash function $H(x)$.

| Algorithm | Keygen time | Signing time | Verification time |
|:-:|:-:|:-:|:-:|
| Vanilla HORS   | $O(t)$ | $O(1)$ | $O(k)$ |
| Compact HORST  | $O(2t - 1)$ | $O(2t - 1)$ | $O(k (\log_2 t - x + 1) + 2^x - 1)$ \* |

<sub>The exact amount of bits by which the HORST signature size grows (and thus verification time as well) is determined by the function $g(x) = n(k(\log_2 t - x + 1) + 2^x)$ ([see page 9 of the SPHINCS paper for more info](https://eprint.iacr.org/2014/795.pdf)).</sub>

### Viability for Bitcoin

HORS is conceptually refreshing, because it demonstrates that hash-based signatures can be quantifiably secure even when secret keys are reused. Since Bitcoin signing keys are typically only used a few dozen times at most, a few-time signature scheme like HORS might be acceptable for the vast majority of Bitcoin use cases, especially if each signature decreases security by a predictable and incremental amount, rather than the all-or-nothing security risks of reusing an OTS secret key (like with WOTS or Lamport).

However Vanilla HORS compromises significantly on public key sizes, while the more compact HORST experiences huge increases in signature key sizes as a trade-off. By comparison, Compact WOTS provided public keys of the same size with signatures roughly a quarter of the signature size HORST has. Safely supporting additional signatures ($r > 1$) would require even larger signatures.

HORS is not a stateful signature scheme, but the signer should know roughly how many times they have used a given key pair so that they can avoid over-exposing their key. On the coattails of this assumption ride the same security issues as WOTS and Lamport signatures regarding address reuse in a Bitcoin context. The problem with HORST is really that to make a key secure for reasonably large numbers of signatures, we must make our parameters very large which inflates either the keygen/signing runtime, or the signature size.

## Forest of Random Subsets (FORS)

FORS is another few-time signature scheme based on HORST (discussed above). It was first introduced as a component within the [SPHINCS+ paper](https://sphincs.org/data/sphincs+-paper.pdf) in 2017, but it deserves a definition on its own as it improves on HORST to reduce signature sizes dramatically.

The primary distinction between HORST and FORS is that FORS public keys are represented as the hash of _several_ merkle trees - hence the use of the term "forest". Each leaf node of these trees is, like HORST, the hash of a secret preimage, and we sign data by revealing specific preimages along with their merkle tree membership proofs.

Let $k$ be the number of merkle trees and let $t = 2^a$ be the number of preimages in each tree, for a total of $kt$ preimages. The trees will all have height $a$.

This construction gives us $k$ merkle tree root hashes $\\{R_1 ... R_k\\}$. We hash these roots to derive the FORS public key $P = H(R_1 ... R_k)$.

To sign a message $x$, we hash $x$ using a randomized subset-selection algorithm $S_H(x)$ to obtain $\vec{h} = \\{h_1 ... h_k\\}$ where each digit $0 \le h_i \lt t$ (as in HORST). But whereas HORST uses those digits as indexes into a _single tree,_ FORS uses those digits as indexes into _separate_ merkle trees - one index per tree - to select which preimage to reveal from each tree. This ensures that FORS signatures always have a constant size (unlike HORS or HORST).

<img src="/images/quantum-hbs/fors.svg">

FORS is designed to generate the secret preimages from a small seed, giving constant secret key size. Given a secret FORS seed $s$ we can compute the $i$-th preimage as $p_i = H(s, i)$. After computing $\\{p_0 ... p_{tk-1}\\}$, we can group these preimages into sets of length $t$, and then construct the $k$ merkle trees from them.

<div style="background-color: rgba(255, 40, 90, 0.05); padding: 10px; border-radius: 8px;">
<b>Safety Notice:</b> FORS is designed to use <i>tweaked</i> hash functions which prevent multi-target attacks where an adversary can exploit precomputation to do a drag-net attack on multiple keys in parallel. Do not naively implement FORS without properly tweaking (namespacing) each hash invocation. This risk applies to HORS and other signature schemes as well, but was not well understood until recently.

Note especially that the subset selection algorithm $S_H(x)$ must be tweaked with a <b>secret</b> value, to prevent adaptive chosen-message attackers from selecting messages which would trick the signer into revealing specific preimages desired by the attacker. <a href="https://eprint.iacr.org/2020/564.pdf">Reference</a>.
</div>

### Properties

**Security.** Like its predecessors, FORS is a few-time scheme which means the signer can confidently quantify the security of their public key even after revealing some signatures. The bit security of a FORS public key against a signature forging attack (with attacker-chosen messages) after revealing $r$ signatures is:

$$ b = k(a - \log_2 r) $$

<sub><a href="https://eprint.iacr.org/2020/564">Source</a></sub>

By fixing a security level of $b$ bits given $r$ signatures, we can compute the required tree height $a$ as a function of the number of trees in the "forest".

$$
\begin{align}
k(a - \log_2 r) &= b \\\\
a - \log_2 r &= \frac{b}{k} \\\\
a &= \frac{b}{k} + \log_2 r \\\\
\end{align}
$$

<img src="/images/quantum-hbs/fors-security.png">

<sub>X axis is $k$ (number of trees). The Y axis is $a$ (height of each tree). This graph was computed with $r = 128$ and $b = 128$ (i.e. 128 bits of security after 128 signatures)</sub>

For instance, with $k=32$ trees and $r=128$ signatures, we would need trees of height $a=11$, for a total of $32 \cdot 2^{11} = 2^{16} = 65536$ preimages.

$$ a = \frac{128}{32} + \log_2 128 = 4 + 7 $$

**Size.** Public and secret FORS keys are both a constant size of $n$ bits each.

A FORS signature consists of $k$ preimages, plus $k$ merkle tree proofs containing $a$ hashes each, for a total of $nk(a + 1)$ bits per signature.

**Runtime.** Key generation requires deriving $kt = k \cdot 2^a$ secret preimages, hashing $kt$ preimages, and then computing $k$ merkle tree roots therefrom. With one final hash to compress the merkle roots into the public key, this gives a total key-gen runtime of:

$$ O(3k \cdot 2^a + 1) $$

Signing requires a call to $S_H(x)$ (presumably a single hash invocation) to select which preimages to reveal, along with constructing $k$ merkle-tree membership proofs. If a signer can cache the internal nodes of the merkle trees in memory, they can compute a signature with only a single invocation of $H$.

If on the other hand the signer starts from just the seed (pre-keygen), then to construct a merkle proof for a single tree, they must first derive the $2^a$ preimages for that tree. Then they recompute $2^a-1$ hashes on level 0 of a tree, then $2^{a-1}-1$ hashes on level 1, then $2^{a-2}-1$ hashes on level 2, and so on until level $a-1$ where they only need to compute a single hash, finally arriving at the merkle root of the tree. Expressed more generally, this would require $2^a + \sum_{i=1}^{a} (2^i - 1) = 3 \cdot 2^a - a - 2$ invocations of $H$ per merkle proof. The signer must construct $k$ merkle proofs, so the total worst-case signer runtime is:

$$ O(k(3 \cdot 2^a - a - 2) $$

The verifier's runtime is _much_ smaller. The verifier must run $S_H(x)$ to compute the selected preimage indexes. They must hash each of the $k$ preimages from the signature, and verify the $k$ merkle proofs with $a$ hash invocations each. With one final hash to compute the expected signer's pubkey, this gives a total verifier runtime of:

$$ O(k(a + 1) + 2) $$

Check out the following graph which compares the time/space performance of FORS signatures. For this visualization, I fixed the FORS security parameters $r = 128$ and $b = 128$ (i.e. 128 bits of security expected after 128 signatures), with a hash output size of $n= 256$.

<img src="/images/quantum-hbs/fors-performance.png">

Along the X axis is an input $k$, for the number of FORS trees. The tree height $a$ is computed as before as a function of $k$ to achieve our desired security level.

- The <b style="color: orange;">orange curve</b> is $kt = k \cdot 2^a$, representing the total number of preimages the signer must generate and hash into their public key. This curve is directly proportional to both key-generation runtime and signer runtime (or memory usage if caching is used), but it does not affect public/secret key size.
- The <b style="color: #bc15ef;">pink line</b> is the signature bit-size $nk(a + 1)$, which grows linearly with $k$.
- The <b style="color: cyan;">blue line</b> hugging the X axis is the verifier's runtime $O(k(a + 1) + 2)$. It grows linearly with $k$, but for all reasonable choices of $k$ the verifier needs to evaluate at most a thousand hashes or so.

This suggests that for the $b$ and $r$ parameters we fixed here, we likely would want to set $8 \le k \le 64$. Any lower, and signers would experience an exponential runtime blowup. Any higher and we get diminishing returns in signer runtime savings.

Playing around with the parameters a little, we can see that using fewer but larger trees (lower $k$ w/ higher $t$) gives signers another advantage besides small signatures. Like with HORS, lower $k$ means fewer preimages revealed per signature, which means the security bit-level $b$ decreases more slowly as signatures are revealed.

See the following visualization with $r$ as an input on the logarithmic-scale X axis.

<img src="/images/quantum-hbs/fors-security-r.png">

On the Y axis is the expected security level $b$ after $r$ signatures. The different lines represent the declining security of different FORS parameter sets. FORS tree heights were computed with $a = \frac{b}{k} + \log_2 r$ setting $b = 128$ and $r=128$ (same as before), but this graph shows what happens before _and after_ a signer has issued their 128 signatures.

- The <b style="color: #bc15ef;">pink line</b> is FORS with $k = 8$, $a = 23$.
- The <b style="color: green;">green line</b> is FORS with $k = 16$, $a = 15$.
- The <b style="color: orange;">orange line</b> is FORS with $k = 32$, $a = 11$.
- The <b style="color: cyan;">blue line</b> is FORS with $k = 64$, $a = 9$.
- The white dashed line is $y = 80$ bits of security, which represents an **approximate** boundary below which forgery might be practically achievable for currently available hardware.

Note how the $k=8$ FORS signer (<b style="color: #bc15ef;">pink line</b>) can create almost $10^4 = 10,000$ signatures before their key's expected security drops below 80 bits. At the opposite extreme, the $k=64$ signer (<b style="color: cyan;">blue line</b>) can only create 214 signatures before crossing the same boundary. Even though the tree height $a$ was computed the same way for all four signers, the security of signers with fewer trees decreases much more slowly.

### Modifications

**Security against adaptive chosen-message attacks:** The authors of [this paper](https://eprint.iacr.org/2020/564.pdf) suggest modifying the FORS signing algorithm to make the subset-selection function $S_H(x)$ dependent on the signature itself, using a chain. They call this algorithm "Dynamic FORS" (DFORS). But they also note that a simple pseudorandom salt as used in SPHINCS+ is sufficient for safety against adaptive chosen-message attacks. As such I have elected not to go into detail as the DFORS modification seems unnecessary.

**More efficient signatures using brute-force compression:** [This paper](https://ieeexplore.ieee.org/stamp/stamp.jsp?tp=&arnumber=10179381) suggests modifying the FORS signing algorithm so that the signer repeatedly hashes the input message $x$ along with an incrementing 32-bit salt/counter $s$, until $S_H(x \parallel s) \rightarrow \\{h_1 ... h_k\\}$ outputs a set of index digits with a trailing zero digit $h_k = 0$ at the end (i.e. the last $a$ bits of the salted message hash are zero). The signer can then FORS-sign the set of digits $\\{h_1 ... h_{k-1}\\}$, omitting $h_k$, and including the salt $s$ in their signature. The verifier recomputes and checks the final digit matches the requirement $h_k = 0$.

Because $h_k = 0$ is also enforced by the verifier, the signer can omit the last preimage and merkle proof on $h_k$ from the signature, as that digit of the message is presumed static (A message which never changes does not need to be signed). Indeed the signer doesn't need to even _have_ a final $k$-th tree.

The effect of this modification is to reduce signatures size by approximately $n(a+1)$ bits, and reduce signing/verifying runtime as well (though I have not verified the runtime-reduction claim). The authors call this modification "FORS with compression" (FORS+C).

The authors have also noted that if the signer wishes to further reduce signature size, they can perform additional work to reduce the size of the 2nd-to-last tree by forcing more trailing bits to hash to zero.

Intuitively, this compression mechanism has a larger impact when the trees are larger (when $t = 2^a$ is larger), because pruning the last tree from the signature construction makes a comparatively larger impact. Of course the trade-off is that we must do more work to find a salt which produces a message hash with $a$ trailing zero bits. On average to find a hash with $a$ trailing zeros, we must compute $2^{a-1}$ hashes, with $2^a$ hash invocations at the very worst.

**Smaller signatures using Winternitz chains:** [This paper](https://eprint.iacr.org/2022/059.pdf) suggests extending the leaves of each FORS tree with a chain of hashes, much like the Winternitz OTS scheme. This extra dimension gives a new parameter, the length of the Winternitz chains $w$, with which to expand the space of possible signatures. Now signatures are composed of intermediate hashes within the chains hanging from the FORS tree leaves.

More possible signatures for the same size message means in theory that signatures should be more secure. This modified scheme is called "Forest of Random Chains" (FORC). One could think of standard FORS as a FORC instance with chains of length $w=1$.

The authors demonstrate that this extension improves reduces probability of two signatures colliding within a tree from $1/t$ (one chance per leaf) with standard FORS, to $(1/t) \cdot \frac{w+1}{2w}$ with FORC, where $w$ is the length of the Winternitz chains.

Unfortunately the FORC authors did not provide an explicit formula for the bit-security of FORC after $r$ signatures, so we will have to work that out for ourselves.

<details>
  <summary><h4>Click here to see my derivation</h4></summary>

Recall the FORS security level of $b$ bits over all $k$ trees after $r$ signatures:

$$ b = k(a - \log_2 r) $$

Convert this to the probability that $r$ signatures allow a forgery:

$$
\begin{align}
2^{-b} &= 2^{-k(a - \log_2 r)} \\\\
       &= (2^{(a - \log_2 r)})^{(-k)} \\\\
       &= (2^{a} \div 2^{\log_2 r})^{(-k)} \\\\
       &= (t \div r)^{(-k)} \\\\
       &= \left(\frac{r}{t}\right)^{k} \\\\
\end{align}
$$

With FORC, the inner per-tree probability $r/t$ (the chance of $r+1$ preimage indexes colliding within a tree) is multiplied by the factor $\frac{w+1}{2w}$.

$$
\begin{align}
2^{-b} &= \left(\frac{r}{t} \cdot \frac{w+1}{2w} \right)^{k} \\\\
\end{align}
$$

Converting back from a probability into bits of security:

$$
\begin{align}
2^b &= \left(\frac{r}{t} \cdot \frac{w+1}{2w} \right)^{-k} \\\\
2^b &= \left(\frac{t}{r} \cdot \frac{2w}{w+1} \right)^{k} \\\\
b &= \log_2 \left(\frac{t}{r} \cdot \frac{2w}{w+1} \right)^{k} \\\\
\end{align}
$$

Use the logarithm identities $\log \frac{x}{y} = \log x - \log y$ and $\log xy = \log x + \log y$:

$$
\begin{align}
b &= k \cdot \log_2 \left( \frac{t}{r} \cdot \frac{2w}{w+1} \right) \\\\
  &= k \cdot \left( \log_2 \left(\frac{t}{r} \right) + \log_2 \left( \frac{2w}{w+1} \right) \right) \\\\
  &= k \cdot \left( \log_2 t - \log_2 r + \log_2 \left( \frac{2w}{w+1} \right) \right) \\\\
  &= k \cdot \left( a - \log_2 r + \log_2 \left( \frac{2w}{w+1} \right) \right) \\\\
\end{align}
$$

Thus, the bits of security we receive by extending the leaves of a FORS tree with Winternitz chains of length $w$ is exactly $b = k \cdot \left( a - \log_2 r + \log_2 \left( \frac{2w}{w+1} \right) \right)$. This improves on standard FORS by exactly $\log_2 \left( \frac{2w}{w+1} \right)$ bits, which evaluates to zero if $w=1$.

</details>

After working it out, FORC's security level is $b = k \cdot \left( a - \log_2 r + \log_2 \left( \frac{2w}{w+1} \right) \right)$ bits .

This improves on standard FORS by exactly $\log_2 \left( \frac{2w}{w+1} \right)$ bits, which evaluates to zero if $w=1$.

For a given set of security parameters $b$ and $r$ we can compute a surface in a 3-dimensional FORC configuration space. I'm too lazy to diagram it, sorry, you'll have to get imaginative. This surface represents the possible choices for $(k, a, w)$ which fulfill those security parameters. The security earnings from higher values of $w$ can be exploited to achieve the same level of security with smaller or fewer FORS trees.

The savings diminish quickly as $w$ grows though. It seems like $w=16$ is about the limit of usefulness beyond which the security savings earn little in terms of signature size reduction. The majority of savings are earned by the first few hashes in the chains. Winternitz chains with as few as $w=4$ hashes can reduce signature sizes by several thousand bits.

In exchange for these security/size savings, FORC signers must process the hash chains for each of the FORS leaves. Keygen and signing runtime is multiplied by a factor of $w$, as the signer must now compute $w$ hash invocations per leaf instead of just 1. Verification is slowed by (at worst) $k(w-1)$ extra hash invocations, which can be minimized with reasonable choices of $k$ and $w$.

### Comparisons

The following table shows some concrete examples of time/space trade-offs for FORS signatures. In these examples, we will fix a security level of $b = 128$ bits after different numbers of $r$ signatures. The output size of the primitive hash function $H$ is set to $n = 256$ bits, and all sizes are also listed in bits.

| Algorithm | Signature size | Public key size | Secret key size |
|:---:|:---------------:|:-:|:-:|
| FORS $k = 8$, $t = 2^{18}$, $r=4$ | $nk(a + 1) = 38912$ | $n = 256$ | $n = 256$ |
| FORS $k = 8$, $t = 2^{19}$, $r=8$ | $nk(a + 1) = 40960$ | $n = 256$ | $n = 256$ |
| FORS $k = 8$, $t = 2^{20}$, $r=16$ | $nk(a + 1) = 43008$ | $n = 256$ | $n = 256$ |
| FORS $k = 8$, $t = 2^{21}$, $r=32$ | $nk(a + 1) = 45056$ | $n = 256$ | $n = 256$ |
| ... |||
| FORS+C $k = 8$, $t = 2^{18}$, $r=4$ | $n(k-1)(a + 1) = 34048$ | $n = 256$ | $n = 256$ |
| FORS+C $k = 8$, $t = 2^{19}$, $r=8$ | $n(k-1)(a + 1) = 35840$ | $n = 256$ | $n = 256$ |
| FORS+C $k = 8$, $t = 2^{20}$, $r=16$ | $n(k-1)(a + 1) = 37632$ | $n = 256$ | $n = 256$ |
| FORS+C $k = 8$, $t = 2^{21}$, $r=32$ | $n(k-1)(a + 1) = 39424$ | $n = 256$ | $n = 256$ |
| ... |||
| FORS $k = 16$, $t = 2^{10}$, $r=4$ | $nk(a + 1) = 45056$ | $n = 256$ | $n = 256$ |
| FORS $k = 16$, $t = 2^{11}$, $r=8$ | $nk(a + 1) = 49152$ | $n = 256$ | $n = 256$ |
| FORS $k = 16$, $t = 2^{12}$, $r=16$ | $nk(a + 1) = 54248$ | $n = 256$ | $n = 256$ |
| FORS $k = 16$, $t = 2^{13}$, $r=32$ | $nk(a + 1) = 57344$ | $n = 256$ | $n = 256$ |
| ... |||
| FORS+C $k = 16$, $t = 2^{10}$, $r=4$ | $n(k-1)(a + 1) = 42240$ | $n = 256$ | $n = 256$ |
| FORS+C $k = 16$, $t = 2^{11}$, $r=8$ | $n(k-1)(a + 1) = 46080$ | $n = 256$ | $n = 256$ |
| FORS+C $k = 16$, $t = 2^{12}$, $r=16$ | $n(k-1)(a + 1) = 49920$ | $n = 256$ | $n = 256$ |
| FORS+C $k = 16$, $t = 2^{13}$, $r=32$ | $n(k-1)(a + 1) = 53760$ | $n = 256$ | $n = 256$ |
| ... |||
| FORS $k = 32$, $t = 2^{6}$, $r=4$ | $nk(a + 1) = 57344$ | $n = 256$ | $n = 256$ |
| FORS $k = 32$, $t = 2^{7}$, $r=8$ | $nk(a + 1) = 65536$ | $n = 256$ | $n = 256$ |
| FORS $k = 32$, $t = 2^{8}$, $r=16$ | $nk(a + 1) = 73728$ | $n = 256$ | $n = 256$ |
| FORS $k = 32$, $t = 2^{9}$, $r=32$ | $nk(a + 1) = 81920$ | $n = 256$ | $n = 256$ |
| ... |||
| FORS+C $k = 32$, $t = 2^{6}$, $r=4$ | $n(k-1)(a + 1) = 55552$ | $n = 256$ | $n = 256$ |
| FORS+C $k = 32$, $t = 2^{7}$, $r=8$ | $n(k-1)(a + 1) = 63488$ | $n = 256$ | $n = 256$ |
| FORS+C $k = 32$, $t = 2^{8}$, $r=16$ | $n(k-1)(a + 1) = 71424$ | $n = 256$ | $n = 256$ |
| FORS+C $k = 32$, $t = 2^{9}$, $r=32$ | $n(k-1)(a + 1) = 79360$ | $n = 256$ | $n = 256$ |

I have omitted concrete sizes for the FORC variant of FORS, as they would not be fairly comparable. We would need to use a slightly higher or slightly lower security bit-level $b$, in order to fix integer parameters for $k$ and $a$. FORC signature sizes are comparable to FORS+C: A little smaller for some parameter sets, a little larger for others.

Below I note the time complexity of FORS signatures in terms of the number of invocations of the hash function $H(x)$.

| Algorithm | Keygen time | Signing time (worst case) | Verification time |
|:-:|:-:|:-:|:-:|
| FORS | $O(3k \cdot 2^a + 1)$ | $O(k(3 \cdot 2^a - a - 2))$ | $O(k(a + 1) + 2)$ |
| FORS+C | $O(3(k-1) \cdot 2^a + 1)$ | $O((k-1)(4 \cdot 2^a - a - 2))$ | $O((k-1)(a + 1) + 3)$ |
| FORC | $O(3kw \cdot 2^a + 1)$ | $O(k((w+3) \cdot 2^a - a - 2))$ | $O(k(w + a + 1) + 2)$ |

### Viability for Bitcoin

The FORS protocol allows for much more robust keys than HORST. The same size signatures provide much stronger few-time security, permitting more signatures per key before exhaustion. FORS is also a well-studied protocol, with many variants and higher-level protocols based on it.

This few-time scheme might be a possible candidate for usage on Bitcoin, if but for the large signature sizes. Even the smallest FORS+C signature with $b=128$, $r=4$, $k=8$, $a=18$ still results in a signature which is 4256 bytes long, 66x the size of a BIP340 Schnorr signature, and 4x the size of a WOTS signature (albeit with much cheaper verification and viable multi-use security). The compression afforded by FORS+C is significant but ultimately cannot compete with traditional ECC.

Combining the principles of FORS+C and FORC could result in smaller signatures and merits further investigation, but this seems unlikely to shave more than beyond a few thousand bits off of each signature.

## Merkle Signature Scheme (MSS)

MSS is our first example of a "many-time" signature (MTS) scheme, in contrast to the _one-time_ or _few-time_ schemes we've seen until now. It was first [proposed by Ralph Merkle in 1979](https://www.ralphmerkle.com/papers/Thesis1979.pdf) (the same man after whom the "merkle tree" data structure itself is named).

The remarkably simple premise of MSS is this: By unifying many _one-time_ signature (OTS) public keys as _the leaves of a merkle tree,_ we can use each OTS key only once, but succinctly prove any OTS key's membership in the merkle tree's root hash. Our master public key is then defined to be the root hash of this merkle tree. If $h$ is the height of the merkle tree, then the signer may produce up to $2^h$ signatures valid under that public key.

<img src="/images/quantum-hbs/mss.svg">

The signer first samples $2^h$ random OTS private keys $\\{p_1 ... k_{2^h}\\}$, and computes their public keys $\\{P_1 ... P_{2^h}\\}$. The hashes $\\{H(P_1) ... H(P_f{2^h})\\}$ of those public keys are then used as leaf nodes to construct a merkle tree root $P$, which is finally used as the MSS public key.

There are many flavors of MSS, the most well-known of which being the [Extended Merkle Signature Scheme, or XMSS](https://eprint.iacr.org/2011/484.pdf), which instantiates MSS using Winternitz as its one-time signature scheme. The next candidate protocol, SPHINCS, may also be argued to be an instantiation of MSS, though SPHINCS is so radically evolved from Merkle's original scheme that it might be best to group it into a completely separate class of its own.

Due to the promising candidate which follows, I will omit any specific long-winded protocol explanations here. If you would like a detailed example of an MSS protocol, I highly recommend reading the [XMSS paper](https://eprint.iacr.org/2011/484.pdf).

### Viability for Bitcoin

Although MSS schemes give us our first tantalizing glimpse at truly scalable hash-based signatures, they still suffer from the effects of statefulness. To safely use any Merkle Signature Scheme, the signer must always remember which leaf OTS keys they have or have not used - usually implemented with a simple counter. If they lose this state, the signer cannot safely continue using the key. If the signer were to issue more than one MSS signature with the same state, it could compromise the leaf OTS key, which in turn compromises the whole key.

However, the _principle_ of MSS is incredibly flexible, which is why so many modern hash-based signature protocols are based on the core ideas of MSS, including the next one.

## SPINCS+

[SPHINCS+](https://sphincs.org/data/sphincs+-paper.pdf) is a state-of-the-art hash-based signature system which leverages concepts from the previous signature schemes I've described earlier. SPHINCS+ is currently the only hash-based signature (HBS) protocol to have been finalized by NIST as an [approved post-quantum digital signature standard](https://doi.org/10.6028/NIST.FIPS.205). In NIST's terminology, SPHINCS is referred to as "SLH-DSA", or "StateLess Hash-based Digital Signature Algorithm". You see, SPHINCS is also special because unlike most many-time signature (MTS) schemes which use hashes, SPHINCS _does not require signers to keep state._

SPHINCS+ key-generation starts from three secret random values:

- $\textbf{SK}.\text{seed}$
- $\textbf{SK}.\text{prf}$
- $\textbf{PK}.\text{seed}$

The signer constructs their public key by building an MSS tree deterministically from $\textbf{SK}.\text{seed}$, where each leaf is a WOTS+ public key. If the tree has height $h'$ then the signer must derive $2^{h'}$ WOTS+ secret keys. The root hash of that tree, $\textbf{PK}.\text{root}$, along with $\textbf{PK}.\text{seed}$, is the SPHINCS+ public key.

If one were to use these WOTS+ keys to simply sign messages directly, then this is just a particular flavor of MSS, but SPHINCS takes things further.

Instead of signing messages, each of the WOTS+ leaf keys are used to _certify a child MSS tree,_ each of whose leaves are also WOTS+ public keys, and so on, eventually terminating after $d$ trees with a set of $2^h$ leaves. The higher-order _tree-of-trees_ is typically referred to as the "hyper-tree" (bonus points for cool-sounding jargon) and its overall height summing the height of all internal trees and the root tree is $h$. The height of each internal tree in the hyper-tree is $h/d$.

The advantage of this approach, rather than a simple MSS tree, is that to sign a message with the bottom-level leaves of the hyper-tree, the signer does not need to re-derive the entire hyper-tree - they only need to derive the specific certified trees along the path from leaf to root. All other trees can be ignored.

The final $2^h$ leaf WOTS+ keypairs _could_ be used to sign messages directly, but SPHINCS uses them instead as a final certification layer to sign a set of FTS keypairs. Specifically with the modern NIST-approved SPHINCS+ variant, those final FTS keypairs use the Forest of Random Subsets (FORS) algorithm, which we discussed earlier.

The entire SPHINCS+ signature is a package, consisting of:

- a FORS signature on the actual message
- $d$ WOTS+ certification signatures
- $d$ merkle tree membership proofs - one for each WOTS+ certification pubkey
- a randomizer $\textbf{R}$ (explained below)

See the following diagrammed example with $d = 3$ and $h = 6$. To sign a given message, the signer only needs to re-derive three trees with four keys each. His total tree has height $h=6$, and so he actually has $2^h = 64$ possible leaf keys available to sign with. The signer doesn't need to re-derive most of them because they are located in hidden trees which are irrelevant to the particular leaf key he is signing with.

<img src="/images/quantum-hbs/sphincs.svg">

The components of the SPHINCS signature (plus the message) allow a verifier to reconstruct the root node of the hypertree, which is then compared to the root tree node hash in the SPHINCS public key, $\textbf{PK}.\text{root}$.

> why mix two signing algorithms? why not use only FORS?

SPHINCS uses WOTS+ to certify intermediate trees (and FORS keys), because WOTS+ provides very small signatures as far as HBS schemes go. Depending on the number of layers in the hypertree, we may need several WOTS+ certification signatures, so keeping them small is very beneficial. The fact that WOTS+ is a _one-time_ signature scheme is not a problem, because the trees and keys we use WOTS+ to certify are generated deterministically from $\textbf{SK}.\text{seed}$. Each time we sign a message, we _re-derive_ a specific set of keys and trees, and so no WOTS+ key pair will ever be used to certify two different trees (or two different FORS keys).

SPHINCS is entirely deterministic once the initial key seed values have been generated. This includes the selection of which FORS key to sign with. When we are given a message $M$, we compute an $n$-bit _randomizer_ $\textbf{R} = H(\textbf{SK}.\text{prf}, M)$ from our secret PRF (pseudorandom-function) seed. Then we use a special hash function $H_{\text{msg}}$ to compute both the message digest $\text{MD}$ and the address $\text{idx}$ of the FORS key we will use to sign it.

$$ (\text{MD}, \text{idx}) = H_{\text{msg}}(\textbf{R}, \textbf{PK}.\text{seed}, \textbf{PK}.\text{root}, M) $$

The randomizer $\textbf{R}$ is added to the SPHINCS signature, so that the verifier can recompute $(\text{MD}, \text{idx})$.

### Properties

SPHINCS sounds like it should be a stateful signature scheme - After all the signature on the actual message is issued with a few-time signature protocol, FORS, so ought not signers to know roughly how many times to use each FTS key pair?

But actually SPHINCS is advertised as a stateless signing protocol. You see, if they increase the overall height $h$ of the hyper-tree - often to as much as 64 - a SPHINCS signer will have so many FORS keys at its disposal that picking one at random for every signature will result in a statistically negligible likelihood of key reuse. And even if by severe bad luck one does happen to reuse a FORS key, the few-time security of FORS makes it still extremely unlikely that the two FORS signatures could be used to create a forgery.

We can afford to increase the height of the hypertree this large because of the key-certification trick which saves us from re-deriving all leaf FTS. Even with heavy use, most of the possible FTS keys are never even derived, let alone used. But the fact that they _could_ be used allows for this _probabilistic_ statelessness property.

The modern SPHINCS+ variant of SPHINCS specifically has very small public and secret keys. Pubkeys are only $2n$ bits, while secret keys are $4n$ bits.

However SPHINCS signatures are very large. Exact sizes depend on a large number of parameters:

- Security parameter $n$ (hash output size)
- SPHINCS parameters $d$ and $h$
- WOTS+ parameters $w$ and $\ell$
- FORS parameters $k$ and $t = 2^a$

The total SPHINCS+ signature size is given by:

$$ n(h + k(a + 1) + d \ell + 1) $$

[Reference](https://sphincs.org/data/sphincs+-round2-specification.pdf) (see page 36).

For different parameter sets, this can result in signatures varying in size from **8 kilobytes** with the lowest security parameters up to **49 kilobytes** for the highest security. [See page 43 of the FIPS standard](https://doi.org/10.6028/NIST.FIPS.205) for concrete parameter sets recommended by NIST and their resulting signature sizes.

### Viability for Bitcoin

SPHINCS is extremely powerful, and has numerous advantages. Stateless signing would make it a drop-in replacement for existing signature algorithms like Schnorr, so signers would not need to think about exhausting a key or tracking signature counters. The fact that SPHINCS+ is a fully standardized, open source and NIST-recommended signing algorithm would lend more credibility to arguments for adoption.

In the recommended parameter sets, NIST sets $h \ge 63$ which creates so many FORS leaf keys that one could sign billions of messages per second for decades and still never use the same FORS key twice. This is the point of SPHINCS's trade-offs in signature size and complexity: to permit signers to reuse public keys like this, issuing billions of signatures, with no meaningful loss of security.

Not even the most heavily used public keys in Bitcoin's history have signed so many transactions... Except perhaps for the context of the Lightning network, where 2-of-2 multisignature contract participants sign sometimes hundreds of commitment transactions per minute - Though the Bitcoin blockchain rarely ever sees these transactions publicly (perhaps this fact might be useful).

However, SPHINCS's downfall is its huge signature size. Even the smallest SPHINCS signatures with 128 bit security are around double the size of a FORS signature, and over 100x the size of BIP340 Schnorr.

## Analysis

Some of the more modern hash-based signature schemes described above fulfill the hard requirements of Bitcoin:

- Small public and secret keys
- Fast signature verification time

Namely those schemes are:

- **WOTS** / **WOTS+** / **WOTS+C** (OTS)
- **FORS** / **FORS+C** (FTS)
- **SPHINCS+** (MTS)

The primary trade-off points between these schemes are:

- Signing and key generation runtime performance
- Signature size
- Number of signatures a signer may safely publish before forgeries become feasible

Here is a brief example to demonstrate scaling problems with hash-based signatures. If every transaction in a Bitcoin block were small-as-possible 1-input-1-output transactions (about 320 weight units before witness data), and each of those transactions used a single signature as their input's witness, then Bitcoin's block size limit of 4,000,000 weight units would be exhausted by:

- **490 transactions** if they each used a SPHINCS+128 signature of **7856 witness bytes**, or
- **875 transactions** if they each used a FORS+C signature of **4256 witness bytes**, or
- **2976 transactions** if they each used a WOTS+C signature of **1028 witness bytes**, or
- **10000+ transactions** if they each used a BIP340 signature of **64 witness bytes**

As of writing, blocks mined today are generally filled with some 3000-5000 transactions each, many of which spend large numbers of inputs.

It seems clear that using hash-based signatures of any kind would necessitate either a significant decrease in overall network throughput, or a significant increase in block size. The increase in block size could be pruned though, as large hash-based signatures could be attached as part of the segregated block _witness_ and not the raw blocks themselves.

# Upgrading Bitcoin

None of the above schemes matter unless it can be applied to build a real quantum-resistant upgrade to Bitcoin. In this section, I'll propose one potential option for upgrading Bitcoin to use post-quantum hash-based cryptography while maintaining compatibility with existing elliptic-curve crypto (ECC) for as long as possible (to minimize performance loss over time).

I am not necessarily advocating to upgrade Bitcoin to use HBS in this particular way; I am merely trying to demonstrate what one possible *realistic* quantum resistance upgrade to Bitcoin _might_ look like, knowing what I know today. There are far smarter people than me also working on this problem, who will probably have much to say about the methods I describe here.

## Digests as Secret Keys (DASK)

Digests as Secret Keys (DASK) is my invented name (feat. a pronounceable acronym) for a hypothetical quantum-resistant upgrade path for Bitcoin. As far as I know, nobody else has proposed this idea before, but I would love to be proven wrong. Whether this idea is feasible or not, I would hope at least that I'm not alone.

DASK does not require any immediate consensus changes, but instead encourages a client-side specification change, modifying the way Bitcoin wallets derive their EC secret keys. A consensus change would be required _later_ to retroactively change spending rules, and **users would need to migrate their coins to a DASK-supported wallet before that fork,** but the on-chain output scripts to which coins are paid would not change, so DASK would not impact Bitcoin's fungibility, scalability, or consensus rules in the way a brand new output script format would.

Until the DASK consensus change is activated, Bitcoin transactions using EC signatures would look exactly the same as they do today. If large quantum computers never materialize for some reason, DASK need never be activated.

### Background

A Bitcoin wallet is typically derived from a secret seed encoded as a mnemonic phrase. The wallet software uses the [BIP32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki) and [BIP44](https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki) standards to derive child secret/public key pairs from this seed, using a system of hashing and additive tweaking.

I am oversimplifying here, but basically the wallet starts with a secret key $k$ and a chain code $c$. To compute a child secret-key / chain-code tuple $(k', c')$, we hash the parent key/code with a 32-bit integer $i$, adding the resulting hash on top of the parent secret key.\*

$$ (k', c') = k + H(c, k, i) $$

<sub>\* This describes <i>hardened</i> BIP32 derivation. Unhardened derivation hashes the _public_ key instead of the _secret_ key.</sub>

BIP32 encourages wallets to do this recursively, generating a large tree of practically unlimited size and depth, so that clients will never run out of available fresh signing keys. Once a suitable child secret key is derived, the wallet will typically use the EC secret key $k$ to compute an EC public key $K = kG$, and then compute an address of some format (e.g. P2PKH/P2WPKH/P2TR) based on $K$.

### DASK Description

**The idea of Digests as Secret Keys is to derive a _hash-based signature algorithm pubkey_ (or a hash thereof) and use that in place of the _elliptic curve secret key_ $k$. Instead of BIP32, these keys are derived using a hash-based deterministic algorithm (like with FORS or SPHINCS) from the BIP39 seed.**

For example, let's say we compute $k$ as a FORS public key: We sample our preimages, construct merkle trees from them, and compute $k$ as the hash of the forest's roots. We can then interpret $k$ as an EC secret key, and use it to issue ECDSA or Schnorr signatures for the public key $K = kG$.

<img src="/images/quantum-hbs/dask.svg">

<sub>A simplified diagram of the DASK concept. Further layers of derivation after the BIP39 seed $s$ and before HBS keys would likely be needed for versioning and compatibility.</sub>

> why?

This approach gives us a fallback option to authenticate a user in the event a quantum adversary appears who can invert our EC public key $K$ into our "secret key" $k$. The QA can find $k$, but $k$ is itself an HBS public key, which the QA _cannot_ invert.

In a post-quantum world, the Bitcoin network can activate a consensus change which enforces new hash-based spending rules on all addresses: **disable ECDSA/Schnorr, and instead require a signature from the HBS public key $k$.**

Since FORS, WOTS, and other HBS verification algorithms typically involve recomputing a specific hash digest and comparing that to the HBS public key, a verifying Bitcoin node could recompute the EC secret key $k$ from the hash-based signature, and then recompute $K = kG$, to compare $K$ against whatever output script is being unlocked.

Think of the _outer_ EC pubkey $K$ as the outer wall or moat of a castle, and the _inner_ HBS pubkey $k$ as the inner sanctum or keep: A highly secure fallback location, where one may safely retreat to if the first line of defense were to be breached.

<img style="border-radius: 8px;" src="/images/quantum-hbs/castle.webp">

<sub><a href="https://en.wikipedia.org/wiki/Siege_of_Kenilworth">Kenilworth Castle</a> Reconstruction. <a href="https://www.reddit.com/r/castles/comments/woztt/reconstruction_of_kenilworth_castle_later_middle/">Source</a>.</sub>

The exception to the above is taproot, where an output public key $K'$ is typically additively tweaked with a hash of an internal key $K$. DASK would not work out-of-the-box with P2TR, because whatever HBS key $k$ the verifier computes from the HBS signature may not be the correct discrete log (secret key) of the actual curve point (pubkey) $K'$ encoded in the P2TR output script. The verifier must also know the tapscript merkle root $m$ such that they can compute $K' = kG + H(kG, m) \cdot G$.

There are various ways we could handle this, the most obvious being to simply append the tapscript MAST root $m$ to the HBS signature witness in some way. For most P2TR users, $m$ would just be an empty string.

Until Q-Day, Bitcoin users would be free to continue signing with ECDSA and Schnorr exactly as they do today. After Q-Day, the fallback HBS mechanism would allow a straightforward and secure way for users to retain control over their money.

### Benefits

The main benefit of DASK is that the Bitcoin network does not need to implement any consensus changes today. Instead a client-side spec for DASK would be needed, and then users can opt into DASK-supported wallets at their leisure, without meaningful changes to user experience. Bitcoin wallet clients could even encourage this migration passively, by paying user change outputs to DASK-supported addresses instead of to pre-quantum BIP32 addresses, and by generating new receive addresses using DASK instead of BIP32. Wallets would be free to migrate coins well ahead of DASK activation. If the DASK consensus changes are never activated, users would not be in any worse position than they were before migrating to DASK.

DASK could also be applied to other post-quantum algorithms besides hash-based cryptography. For instance, an EC secret key $k$ could be derived from the hash of a [CRYSTALS](https://pq-crystals.org) public key (lattice cryptography). $k$ could even be the merkle tree root of some set of public keys from completely different algorithms.

For even better flexibility, the network might treat the hash-based pubkey $k$ as a *certification key,* using a one-time signature algorithm with short signatures which we already know to be secure, such as WOTS. When Q-Day comes, the OTS key $k$ can be used to certify a new public key of some yet-to-be-defined algorithm which the community can finalize at the time of DASK activation.

After all, it seems probable that we will have access to more efficient post-quantum signing algorithms on Q-Day than we do today, and WOTS signatures are a relatively small, secure, future proof, and simple way to endorse some undefined future pubkey we don't know how to derive yet. This _certification_ idea mirrors the SPHINCS framework's approach of using WOTS keys to endorse child keys without needing to know (rederive) the child keys, so there is at least some well-documented research on this use case of HBS.

### Drawbacks

**Consensus Complexity.** Some ingenuity and compromises might be needed to activate DASK as a soft fork rather than as a hard fork. It seems like transactions mined after DASK which include hash-based signatures would be rejected by older Bitcoin nodes, which expect only an EC signature to claim the same output. I'm not sure whether this is even possible and would love to hear suggestions as to what a DASK soft fork might look like.

**Performance.** A DASK-supported EC key $k$ might take more computational work to derive than an equivalent child key derived via BIP32, because hash-based signing algorithms generally require a lot of hashing to generate public keys, especially WOTS, which pays for its small signature size with worse runtime complexity.

More investigation and empirical benchmarking would be needed to make hard performance claims here. It seems to me at least that any reasonably small trade-off in key-derivation performance would be a price worth paying for quantum resistance.

**HD wallets.** There is one notable and certain drawback to DASK though: Without unhardened BIP32, extended public keys (xpubs) will no longer be a thing.

We will be forced to drop BIP32 before Q-Day, because existing wallet software treats BIP32 xpubs as safe to distribute. For example, hardware and multisig wallets surrender them frequently as part of normal UX paths. As discussed earlier, when a QA learns a user's xpub, they can invert it and then derive all child secret keys. Deriving HBS keys with BIP32 would be counterproductive; a defensive wall built atop quicksand.

Instead we would need a new hierarchical-deterministic wallet standard which uses only cryptographic primitives known to be quantum-secure. Currently the only option I know of would be to hash the secret seed, which obviously cannot be shared publicly.

This could negatively affect various use cases in the Bitcoin ecosystem which frequently depend on the ability to independently derive public keys for wallets which a machine might not know the raw private keys for.

- Watch-only wallets
- Hardware wallets and other airgapped signing devices
- Multisignature wallets

However, this is neither a surprising nor insurmountable problem. Other post-quantum solutions share this issue, and further research will be needed to optimize UX or to build an alternative way to non-interactively derive child addresses from public data.

## Conclusion

This deep dive into hash-based cryptography has been an incredible horizon-broadening experience for me. Previously, I saw post-quantum cryptography as a dark art, foreign to my understanding, but upon inspection I found the base premises to be elegant and simple. Hopefully this article has demonstrated that post-quantum cryptography need not be magic. We can use systems we already rely on today, in new and inventive ways, to (we hope) defeat future quantum adversaries.

I'm incredibly grateful to the numerous researchers who have poured thousands of hours into inventing, proving, attacking, and standardizing the HBS algorithms I've explored in this article. Check out some of the papers linked in this post, and you will see for yourself the creativity and ingenuity which has gone into their designs.

This post has been weeks in the making and yet still there are numerous ideas I have left out. For instance, I may have discovered an optimization to the Winternitz OTS scheme, which might further reduce its signature size, but to give myself enough time to investigate this properly demands I leave it for another day.

I have also neglected other sectors of post-quantum cryptography like Lattice cryptography, STARKS, and many more. The exciting promises they offer and the worrying trade-offs they demand require greater attention than I can afford them in this post. For further reading in this broad domain, check out [the Wikipedia article on post-quantum cryptography](https://en.wikipedia.org/wiki/Post-quantum_cryptography).

## More Resources

- https://bitcoinops.org/en/topics/quantum-resistance/
- https://delvingbitcoin.org/t/proposing-a-p2qrh-bip-towards-a-quantum-resistant-soft-fork/956/2
- https://bitcoin.stackexchange.com/a/93047
- https://gist.github.com/harding/bfd094ab488fd3932df59452e5ec753f
- https://lists.linuxfoundation.org/pipermail/bitcoin-dev/2018-February/015758.html
- https://bitcoinops.org/en/newsletters/2024/05/08/#consensus-enforced-lamport-signatures-on-top-of-ecdsa-signatures
