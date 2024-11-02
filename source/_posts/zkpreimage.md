---
title: Verifiably Buy Solutions to NP Problems with Bitcoin
date: 2024-11-02
mathjax: true
category: bitcoin
description: Using zero-knowledge proofs to convert a standard HTLC into the purchase of a secret with arbitrary properties.
---

The word "preimage" refers to the input of a cryptographic hash function, like SHA256. For instance, the SHA256 hash of the string "foo" is:

```
2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae
```

The byte array `2c26b46...` is the _hash_ and the string "foo" is the _preimage._

The [Bitcoin Lightning Network](https://lightning.network) is, in a functional sense, a really big and complex marketplace for buying SHA256 preimages. Under the hood, when [a Lightning Network invoice](https://github.com/lightning/bolts/blob/master/11-payment-encoding.md) is generated, the payee samples a _random preimage,_ and then runs that preimage through SHA256 to produce a _payment hash._ This _payment hash_ is embedded into the final Lightning Network invoice (alongside other important data fields). When the buyer parses the LN invoice, they see the payment hash.

<img style="width: 70%; border-radius: 10px;" src="/images/zkpreimage/bolt11-breakdown.png">

<sub><a href="https://www.bolt11.org/">Source</a></sub>

A Lightning invoice is effectively an offer which claims:

> If you can pay me this many satoshis, I will reveal the preimage of this payment hash.

The really useful feature of the lightning network is that the receiver _cannot_ claim the payment without also revealing the preimage - the payment is _atomic,_ thanks to the use of [Hash Time Lock Contracts (HTLCs)](https://bitcoinops.org/en/topics/htlc/).

You can build lots of cool stuff on top of this, but ultimately hash-locks are limited. Knowing a preimage of some hash isn't intrinsically useful unless you also know that preimage has some _other_ properties. Sometimes we can engineer those properties:

- Atomic swaps use a common preimage to unlock coins or tokens on a different blockchain.
- Lightning-based invoicing systems use lightning preimages as proof-of-payment.
- The Lightning network incentivizes trustless routed payments by giving each node in the route a way to earn fees for routing payments, once they learn a given preimage.

However, these properties are often limited in scope because the preimage can only ever be provably linked with a single function: the SHA256 hash function.

But if we permit ourselves to use zero-knowledge proofs (ZKPs), we can engineer _almost any property we want_ by proving arbitrary statements about the preimage itself.

## Enter the ZKP

A [zero-knowledge proof](https://en.wikipedia.org/wiki/Zero-knowledge_proof) (ZKP) system can prove and verify arbitrary computational claims about secret data without necessarily revealing the secret data itself. A common use for ZKPs is proving knowledge of a preimage to a given hash without revealing the preimage, for example.

This is a novel ability, because proving properties of a preimage - even proving that a preimage _exists in the first place_ - usually necessitates revealing that preimage. In the context of the Lightning Network, that would obviously not be possible, because the receiver can't reveal the preimage until the sender offers a payment. Similarly, the sender won't want to offer payment until they're sure that the preimage they're buying actually _has_ the property they desire. ZKPs can bridge this gap.

## Zero-Knowledge Proof Systems

Zero-knowledge proof systems can generally be grouped into two categories: *STARKs* and *SNARKs*.

- STARK: "Zero-Knowledge **Scalable Transparent** Argument of Knowledge"
- SNARK: "Zero-Knowledge **Succinct Non-interactive** Argument of Knowledge"

|    Properties     |   ZK-STARKs   |       ZK-SNARKs      |
|-------------------|---------------|----------------------|
| Prover Speed      | Slow          | Slow                 |
| Verifier Speed    | Fast          | Instant              |
| Proof size        | 100s of bytes | 100s of **kilobytes**|
| Quantum Resistant | Yes           | No                   |
| Trusted Setup \*  | No            | Yes                  |

\* SNARKs require a "trusted setup ceremony", where one or more parties generate some public and private parameters needed to make the whole scheme work. They are then expected to publish the public parameters, and securely erase the private parameters, often called the "toxic waste". As long as at least one of the trusted parties does securely dispose of their toxic waste (private parameters) then the SNARK proofs generated with the corresponding set of <i>public</i> parameters should be sound.

You might think that a "trusted setup ceremony" disqualifies ZK-SNARKs from applicability to a trustless environment like Bitcoin - But you're wrong. SNARKs can still be used in a **fully trustless** way in certain scenarios, including ours.

For a verifier to be confident that a SNARK proof is sound without trusting any third parties, they simply need to **participate in the setup ceremony themselves.** This way they can be certain that at least one set of private parameters were securely erased. If a ZK protocol has multiple verifiers, than every verifier needs to participate in the trusted setup. Any verifiers who *do not* participate could theoretically be defrauded by the verifiers who _did_ participate.

ZK-STARKs do not have this requirement at all though: A STARK proof is fully *transparent,* requiring no trusted setup beyond agreement on the computation to be proven. As a bonus, they're also post-quantum-secure! On the down-side, STARK proofs are usually 10s or 100s of kilobytes large, compared to only a few hundred bytes for most SNARKs.

## ZKP Abstraction

In this article, I'm going to treat all ZKP systems as black boxes, without caring about their inner workings. If you want to know how zero-knowledge proofs work internally, break out your Google-Fu and dive down that rabbit hole - It goes pretty deep.

Instead, I just care about the practical effect of a ZKP system used with Bitcoin Lightning, so I'm going to flatten all the SNARK/STARK systems (of which there are many) down to a generic set of three algorithms: **Setup**, **Prove**, and **Verify**.

### Setup

$$ \mathbf{Setup}(\text{Prog}) \rightarrow C $$

The Setup algorithm takes in a *program* $\text{Prog}$, and outputs a *public parameters object* $C$ needed to run the Prove and Verify algorithms on $\text{Prog}$ later. I use the variable $C$ here because the public parameters are often referred to as a "Common Reference String" in the ZK lore.

In the case of **SNARKs**, the $\mathbf{Setup}$ algorithm could be run by the verifier, who would give $C$ to the prover so that they can generate a proof that the verifier might accept as sound.

In the case of **STARKs**, this algorithm is a no-op, and the public parameters object $C$ is null, so no communication round is needed.

### Prove

$$ \mathbf{Prove}(\text{Prog}, C, s, P) \rightarrow Z $$

The Prove algorithm takes in:

- a *program* $\text{Prog}$
- a set of *public parameters* $C$ (from the $\mathbf{Setup}$ algorithm)
- *secret* input/output data $s$
- *public* input/output data $P$

...and outputs a zero-knowledge proof object $Z$ provided $\text{Prog}$ can be executed with the given input/output data constraints.

In the case of STARKs, $C$ is always null.

Note how $s$ and $P$ aren't restricted to being _inputs_ to $\text{Prog}$. They can also be outputs. For example, I could prove I computed the $n$-th fibonacci number, without revealing the number itself. In this case $P = n$ is the public input, and $s = \text{Fib}(n)$ is the secret output.

### Verify

$$ \mathbf{Verify}(\text{Prog}, C, Z, P) \rightarrow  \text{true/false} $$

The Verify algorithm takes in:

- a *program* $\text{Prog}$
- a set of *public parameters* $C$ (from the $\mathbf{Setup}$ algorithm)
- a *zero-knowledge proof* $Z$
- *public* input/output data $P$

...and outputs true if $Z$ correctly proves the program $\text{Prog}$ was executed with public input/output data $P$.

The secret data $s$ used by the prover as input to (or output of) the program $\text{Prog}$ remains unknown to the verifier.

In the case of STARKs, $C$ is always null.

## Example

Let's see a concrete example of how a zero-knowledge proof could be used to make a lightning preimage more valuable.

Alice (the *seller*) wants to sell a Bitcoin private key $k$ to Bob (the *buyer*) via Lightning.

The hash of this private key is $h = \text{SHA256}(k)$.

The correct corresponding public key is $K = kG$, where $G$ is [the secp256k1 curve generator point](https://bitcoin.stackexchange.com/questions/58784/how-were-the-secp256k1-base-point-coordinates-decided). A public key is simply a secret key (integer) multiplied by the generator point $G$.

Alice gives Bob a lightning invoice with the payment hash $h = \text{SHA256}(k)$. If Bob pays this Lightning invoice, Alice must reveal the preimage $k$ in order to claim the payment, and so in theory Bob should learn the secret key of $K = kG$ in this event.

But Bob should be skeptical. How does Bob know that the preimage of the hash $h$ is at all related to the pubkey $K$ in the way Alice claims? Without some proof that $K = kG$, Alice could have generated a random preimage unrelated to the claimed pubkey $K$, and Bob would have no way of knowing. If Bob purchases the preimage of $h$ he might learn nothing about the actual secret key of $K$.

So Alice and Bob construct a program $\text{Prog}$ which Bob expect Alice to compute (pseudocode):

```python
G = secp256k1_curve_base_point()
n = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141 # Curve order

def Prog(k: int) -> (bytes, PublicKey):
  assert 0 < k < n
  h = sha256(k.to_bytes(32))
  K = k * G
  return (h, K)
```

The public output of $\text{Prog}$ is the hash $h$ and the pubkey $K$, and the computation steps in $\text{Prog}$ assert that both are computed from the same secret key $k$.

If applicable, Bob generates the public parameters $C = \mathbf{Setup}(\text{Prog})$, and sends $C$ to the seller, Alice.

Alice can compute a proof $Z = \mathbf{Prove}(\text{Prog}, C, k, (h, K))$ - i.e. proving she executed $\text{Prog}$ on secret input $k$ and got $(h, K)$ as the public output.

Bob can run $\mathbf{Verify}(\text{Prog}, C, Z, (h, K))$ and if it outputs success, then Bob can be confident $h = \text{SHA256}(k)$ and $K = kG$ are related as Alice claimed.

In theory this works. There's just one small problem: Running secp256k1 point multiplication (`K = k * G`) inside a zero-knowledge proof compiler is **very** slow. I tested this exact approach with the [RISC0](https://github.com/risc0/risc0) STARK proof system, and it took **47 minutes** to prove the computation.

### Optimizing

Thankfully we have an easy optimization available: [Schnorr signatures](/cryptography/schnorr/) are already a valid zero-knowledge proof of knowledge for a secret key $k$, given a public key $K$. Alice doesn't need to prove $K = kG$; she just needs to prove $k$ *was used to build a Schnorr signature,* which Bob can validate against $K$.

As a quick refresher, a Schnorr signature $(R, s)$ on a message $m$ is computed from a random nonce $r$ and a secret key $k$ as follows:

$$ R = rG \quad K = kG $$
$$ e = \text{SHA256}(R, K, m) $$
$$ s = r + ek $$

> sounds like point multiplication with extra steps. why is this any better?

Because constructing a Schnorr signature inside a zero-knowledge proof compiler can be done with simple integer arithmetic - No secp256k1 point multiplication required.

To make our earlier $\text{Prog}$ more suitable for computing a fast zero-knowledge proof, we pass it secret inputs $(k, r)$, and pass the challenge $e$ as a public input. The program returns a Schnorr signature scalar $s$ as a public output in addition to the hash $h$ (also public).

|        |   Input  | Output   |
|:------:|:--------:|:--------:|
| Secret | $(k, r)$ |          |
| Public | $e$      | $(h, s)$ |

```python
n = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141 # Curve order

def Prog(secret_inputs: (int, int), public_input: int) -> (bytes, int):
  (k, r) = secret_inputs
  assert 0 < k < n

  h = sha256(k.to_bytes(32))

  e = public_input
  s = (r + k*e) % n
  return (h, s)
```

To compute a proof, Alice first samples a random nonce $r$ and computes $R = rG$. Then Alice computes the Schnorr challenge $e = \text{SHA256}(R, K)$. She isn't signing a specific message, so Alice can omit $m$ in the challenge hash. She takes these steps on her own, not in zero-knowledge - just regular computing so far.

Next Alice computes $(h, s) = \text{Prog}((k, r), e)$ and generates a zero-knowledge proof $Z = \mathbf{Prove}(\text{Prog}, C, (k, r), (e, h, s))$ - i.e. proving she executed $\text{Prog}$ on secret inputs $(k, r)$ and public input $e$, which produced $(h, s)$ as the public output.

Alice packages together the Schnorr signature $(R, s)$ with the zero-knowledge proof $Z$, and sends $(Z, R, s)$ to Bob.

Bob can recompute the Schnorr challenge $e = \text{SHA256}(R, K)$, and verifies the Schnorr signature by asserting that:

$$ sG = R + eK $$

<sub><a href="/cryptography/schnorr/#Schnorr-Signatures">Click here for an explanation of why this proves knowledge of $k$</a></sub>

If the Schnorr signature is valid, Bob runs $\mathbf{Verify}(\text{Prog}, C, Z, (e, h, s))$ to verify Alice's claim about the signature's relationship to $h$. If it outputs success, then Bob knows the Schnorr signature value $s$ was computed using $k$ (the preimage of $h$) as the secret key. He is then confident $h = \text{SHA256}(k)$ and $K = kG$ are related as Alice claimed.

This approach radically reduces our performance overhead. Instead of 47 minutes, this proof takes only about 3 minutes on my machine, and this could likely be optimized further with lower-level proof systems.

## Pseudo-PTLCs

The above example (proving a preimage is also the secret key for a given public key) is of particular interest for Bitcoin Lightning users.

There is an upgrade to Lightning called [Point Time Lock Contracts](https://bitcoinops.org/en/topics/ptlc/) which improves Lightning scaling & routing privacy, while also enabling more complex scriptless smart contracts. The basic premise of a PTLC is similar to that of an [HTLC](https://bitcoinops.org/en/topics/htlc/), except instead of the receiver divulging a hash preimage in exchange for payment, they must divulge a certain secret key - more specifically, a signature adaptor secret. See [the original PTLC proposal here](https://github.com/BlockstreamResearch/scriptless-scripts/blob/master/md/multi-hop-locks.md) for more info.

Besides improving the scaling & privacy of LN payments, PTLCs enable all kinds of power features and advancements in protocols adjacent and above the Lightning Network. For instance, PTLCs allow users to verifiably purchase:

- signatures on Bitcoin transactions
- signatures on altcoin transactions (if they also use the secp256k1 curve)
- attestations from [a Discreet Log Contract oracle](https://bitcoinops.org/en/topics/discreet-log-contracts/)
- shares of a multisignature wallet
- [tickets for entry in an off-chain Discreet Log Contract](/scriptless/ticketed-dlc/)
- [statechain](https://bitcoinops.org/en/topics/statechains/) transaction signatures

> sounds great! how do I use them?

You don't. At least, not yet.

PTLCs are impossible until the Lightning network has more widespread support for taproot channels. If you're running a recent version of [LND](https://github.com/lightningnetwork/lnd) for example, you can manually enable taproot channels by putting this into your `lnd.conf` file:

```toml
[Protocol]
protocol.simple-taproot-chans=1
```

...and when opening channels, you can pass `--channel_type taproot` to open a taproot channel, if your peer supports it.

But even then, there is no BOLT specification document yet for PTLC routing, let alone an implementation. For now, PTLCs are a hypothetical pipe-dream of higher-level protocol engineers (leeches) like myself, who like to build things on top of lightning. One day, we'll have PTLCs, and it will be awesome. For now, we are stuck with preimages as our only viable payment proofs.

The zero-knowledge proof example I gave earlier allows LN users to bridge the gap without waiting on the slow grind of the LN protocol development cycle, and without the need for intermediate nodes in the Lightning Network to upgrade.

No, we don't gain the privacy and scaling benefits of full-blown PTLCs on LN. But if a preimage salesman has enough time, computational resources, and incentive to generate a zero-knowledge proof that his preimage is also a specific secret key, then the buyer and seller gain enormous flexibility, inherited by the capacity to purchase arbitrary discrete logarithms (secret keys) from each other.

## I'm Long on NP

Besides the specific case of proving a preimage is a secret key, a preimage salesman could also prove other arbitrary properties of their preimage. In fact, I'll show you how a buyer can verifiably purchase a solution to _any_ [NP-complete problem](https://en.wikipedia.org/wiki/NP-completeness), using only the Lightning HTLCs we have today, and the principles used in the earlier example.

For instance, we could prove an LN preimage would reveal:

- a solution to a rubiks cube
- a solution to a sudoku puzzle
- a valid TLS certificate
- the prime factors of a large composite number
- a preimage for a completely different hash function
- the nonce (proof of work) needed to mine a bitcoin block
- a neural network trained on a given set of data
- a schedule satisfying a set of availability constraints
- an efficient travel route to reach a destination within a certain time or distance
- an optimal set of expenses to best utilize a given budget
- a genome which shares certain common DNA sequences with another

To clarify, zero-knowledge proofs won't _solve_ any of these problems for us - They'll merely allow us to _verifiably purchase_ a solution, which someone must find first. Once we have a solution, we can use zero knowledge proofs to assert the solution is valid and that the LN preimage would reveal it.

Here's how the seller sets up the proof.

1. Find a `solution` to the buyer's desired NP-Complete problem.
1. Sample a random 32-byte encryption key $k$.
1. Encrypt the `solution` using $k$, such that $k$ is a viable decryption key.
1. Create a zero-knowledge proof that the secret $k$ satisfies the following program (pseudocode).

```python
# Test if a solution to our NP-complete problem is valid.
def np_problem_test_solution(solution: Solution) -> bool:
  ...

# Decrypt an encrypted solution.
def decrypt(encrypted_solution: bytes, k: bytes) -> Solution:
  ...

def PreimageDecrypt(k: bytes, encrypted_solution: bytes) -> bytes:
  assert len(k) == 32
  h = sha256(k)

  solution = decrypt(encrypted_solution, k)
  assert np_problem_test_solution(solution)

  return h
```

- $k$ is the only secret input.
- the `encrypted_solution` is a public input.
- the hash $h = \text{SHA256}(k)$ is a public output.

The LN seller proves execution of $\mathbf{PreimageDecrypt}$ in order to assert a given hash preimage will decrypt a valid input to the `np_problem_test_solution` function. If the LN buyer is given the `encrypted_solution`, then they have an incentive to learn the preimage $k$.

<sub>One can also prove <i>encryption</i> instead of <i>decryption</i>, asserting instead that a public output ciphertext was generated by symmetrically encrypting a secret input `solution` using the `preimage` as key. This must imply that the ciphertext can also be decrypted with the `preimage`. We're free to select whichever approach is more efficient for our encryption algorithm.</sub>

> why does this work for _any_ NP-complete problem?

NP-Complete problems are those for which we have efficient ways to _check_ solutions, but no efficient deterministic option for _finding_ a solution. Since checking a solution is fast, we should be able to build fast-ish zero-knowledge proofs to assert a solution is valid without exposing the solution. We would run the actual search computation outside of the zero-knowledge proof system, and then use a ZKP to prove the solution is correct (and related to the LN preimage).

This is always possible because [any NP-statement can be proven in zero knowledge](https://doi.org/10.1007/3-540-47721-7_11).

> why not use the solution as the preimage? why bother encrypting it?

That _can_ be done in some cases, but it may not be safe. [Lightning preimages must always be exactly 32-bytes long](https://bitcoin.stackexchange.com/questions/119892/why-does-miniscript-add-an-extra-size-check-for-hash-preimage-comparisons). If our search space of possible solutions is at most size $2^{256}$, we could encode the solution as a 32-byte (256-bit) lightning preimage, but there are problems with this.

If the entropy of the `solution` is too low, or if the `np_problem_test_solution` function is faster than running `sha256`, then an intermediary LN routing node could use these advantages to speed up a search for the preimage $k$. If successful, they could take the buyer's payment without routing it to the intended receiver.

The easiest way to get around this is for the seller to give some kind of shared state to the buyer, which is needed to fully transform the preimage $k$ into the `solution`. This prevents intermediary LN routing nodes from gaining any advantage in guessing $k$. In the case of my above general program, that "shared state" is the `encrypted_solution`, but one could do it in other more efficient ways too, depending on the use-case.

## Modularity

Everything we've discussed above applies not only to Bitcoin Lightning, but also to any other payment protocol which has a cryptographically verifiable proof-of-payment similar to LN.

For instance, the buyer and seller could create an on-chain PTLC, bypassing the need for native Lightning PTLC support, and the seller can prove the adaptor signature secret has arbitrary properties. For some ZKP systems, this might be significantly more efficient because (as demonstrated earlier) discrete logs can be proven in zero knowledge compilers very efficiently using simple integer arithmetic, whereas SHA256 proofs are often hard for ZKP compilers to optimize.

I focused on the Lightning Network in particular because LN is probably the largest, most mature, most liquid, and most agile marketplace for secrets (SHA256 preimages) in the world today, with all the APIs already in-place needed to practically authenticate and then sell arbitrary secrets.

[LND](https://github.com/lightningnetwork/lnd)'s command line interface, `lncli` and the LND REST API both support arbitrary preimages when creating invoices. For example, this command creates a BOLT11 invoice with a custom preimage, using the big-endian representation of the number `4`.

```
lncli addinvoice 1000 0000000000000000000000000000000000000000000000000000000000000004
```

When paying an LN invoice, most LN clients and APIs will give the buyer access to the preimage as a form of receipt to prove they completed the payment. This accessibility and flexibility around preimages makes it easy to build a zero-knowledge application which uses those preimages, on top of Lightning.

## Trade Offs

ZKPs come with drawbacks. Proving and verifying in zero-knowledge is a very mathematically complex process, regardless of which protocol is used. The code needed to implement them in the real-world is usually very big, slow, and involves many moving parts which can present large attack surfaces.

In more pragmatic terms:

- The $\mathbf{Prove}$ algorithm often takes seconds, minutes, or even hours, depending on the runtime complexity of the $\text{Prog}$ being proven.
- The $\mathbf{Verify}$ algorithm is sensitive to implementation faults, which might lead it to accept false proofs.
- In the case of STARKs, the proof $Z$ is often very large. A relatively simple STARK proving knowledge of a SHA256 preimage is **100+ kilobytes** when serialized. Adding further constraints on the preimage would increase the proof size even more.

It wouldn't be practical for LN receivers to generate zero-knowledge proofs for every single payment request, as that would open them up to denial-of-service attacks. Most lightning micropayments just don't need this kind of firepower to back the seller's claim: I don't care if the [100 sats I pay for a ChatGPT conversation](https://ppq.ai/) will actually answer my NP-complete question about seating arrangements at a wedding.

However, if I'm paying for something much more valuable, then perhaps the extra compute overhead would be worthwhile for the seller to convince me. Perhaps if I'm buying something expensive like a genome, or a ransomware decryption key, or an advanced neural network, I'd like to be a little more certain that my purchase is going to be genuine, especially if the seller I'm buying from lacks credibility.

And of course, for this to be at all practical, searching for a solution must take significantly *more* time than it would take to compute a zero-knowledge proof that an existing solution is valid - otherwise why would the buyer not simply compute a solution himself?

## Soundness

ZKPs have a high cognitive overhead. That's fancy-speak for "they're hard to understand".

Because of their technical complexity, it is not easy to audit open source ZKP implementations for flaws, nor to write secure implementations from scratch. This means would-be ZKP users have few safe options.

The READMEs of most zero-knowledge proof implementation available today are plastered with various warnings disclaiming their suitability for real-world use.

- _"DO NOT USE IN PRODUCTION"_ -[distaff](https://github.com/GuildOfWeavers/distaff)
- _"has not yet undergone extensive review or testing"_ -[libsnark](https://github.com/scipr-lab/libsnark)
- _"has not been reviewed or audited. It is not suitable to be used in production"_ -[Noir Lang](https://github.com/noir-lang/noir)
- _"has not been audited and may contain bugs and security flaws"_ -[Miden VM](https://github.com/0xPolygonMiden/miden-vm)
- _"still under construction ... don't recommend using it in production"_ -[Triton VM](https://github.com/TritonVM/triton-vm)
- _"has not been thoroughly audited and should not be used in production"_ -[o1-labs/snarky](https://github.com/o1-labs/snarky)
- _"should not be used in any production systems"_ -[0xPolygonZero/plonky2](https://github.com/0xPolygonZero/plonky2#security)
- _"unstable and still needs to undergo an exhaustive security analysis"_ -[dusk-network/plonk](https://github.com/dusk-network/plonk)
- _"contains multiple serious security flaws, and should not be relied upon"_ -[libSTARK](https://github.com/elibensasson/libSTARK) (a STARK library written by _the inventor of ZK-STARKs_)

<sub>Ironically, many ZKP systems _are_ being used in production systems, usually altcoins.</sub>

With this fragility in mind, a buyer may ask the seller for multiple proofs from distinct ZKP implementations, and reject the claim if any proofs fail to validate.

Intuitively, if the seller's claim is true, she should be able to create valid proofs using any general ZKP system. This improves the buyer's confidence that the seller's claim about the preimage is sound. Even if every ZKP implementation they use is flawed, the chance of the seller knowing those zero days for _all_ of them is very small.

Assume any given ZKP system/implementation has a probability $\frac{1}{x}$ of being vulnerable to fraudulent proofs, even when used perfectly. This simulates the chance of an implementation zero-day.

Say we use $n$ different systems and the seller's zero-knowledge proofs are valid under all of them. Then the probability of all $n$ proof systems being fraudulent simultaneously is $\left(\frac{1}{x}\right)^n$.

This makes practical attacks against the buyer _exponentially_ harder, at the expense of a linear increase in proof-generating time for the seller.

The buyer could also randomly select one or more proof systems from a set of candidate systems, and then demand the seller prove properties of the preimage using his chosen systems. This could improve performance, because the seller doesn't necessarily need to build proofs under every candidate ZKP system - Just a subset selected by the buyer.

## Conclusion

I'm unsure to what extent this approach is practically useful today, largely due to the slow proving time of most ZKP systems, but the optionality it provides is enormously significant. Perhaps this could fill a niche in commerce which deals with the exchange of valuable secret data, such as in the zero-day market, or in the world of AI, where purchasing secrets is normally a difficult thing to do safely. It can also be used as a bridge, connecting protocols which were previously incompatible.

Avoiding ZKPs is the best general advice for Bitcoin protocol design, because ZKPs introduce more problems than they solve in most cases. But Bitcoiners should keep this idea in their pocket though, and be aware of the new possibilities we see when we widen our perspective.

## Resources

For those interested in exploring real-world ZKP systems, I've appended a list of some well-known projects below.

### STARK Systems

- https://github.com/facebook/winterfell
- https://github.com/TritonVM/triton-vm
- https://github.com/risc0/risc0
- https://github.com/GuildOfWeavers/distaff
- https://github.com/0xPolygonMiden/miden-vm
- https://github.com/valida-xyz/valida
- https://github.com/starkware-libs/cairo-lang

### SNARK systems

- https://github.com/ConsenSys/gnark
- https://github.com/scipr-lab/libsnark
- https://github.com/zkcrypto/bellman
- https://github.com/Zokrates/ZoKrates
- https://github.com/microsoft/Spartan
- https://zkwasmdoc.gitbook.io/
- https://github.com/ProvableHQ/leo
- Circom ecosystem
  - https://docs.circom.io/
  - https://github.com/iden3/circom
  - https://github.com/iden3/snarkjs
  - https://github.com/iden3/rapidsnark

### Other ZK Links

- https://github.com/ventali/awesome-zk
- https://github.com/matter-labs/awesome-zero-knowledge-proofs
