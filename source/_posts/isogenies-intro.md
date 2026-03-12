---
title: Bitcoin Devs Should Be Learning Isogeny Cryptography
date: 2026-03-12
mathjax: true
category: cryptography
description: How isogenies can solve Bitcoin's Quantum problems
---

In this article I want to convince Bitcoiners that we really ought to be learning more about isogeny based cryptography and contributing to this field like we have contributed to the field of classical elliptic curve cryptography.

I'll make this argument by showing that many of the problems which bubble up when we consider integrating post-quantum cryptosystems into Bitcoin can be mostly resolved if we use isogeny-based cryptography. This means it will be a naturally strong competitor when Bitcoiners someday seek a more flexible and algebraically structured cryptosystem than the current leading candidate, [hash-based signatures](/cryptography/quantum-hbs/).

I'll start with a bit of background on isogeny crypto - not rigorous, but a high-level overview which I hope will be approachable to anyone with a basic understanding of classical elliptic curve cryptography. In particular, as case studies we will be looking at the cutting edge [SQIsign protocol](https://sqisign.org/) and [its NIST submission document](https://sqisign.org/spec/sqisign-20250707.pdf) (last updated 2025-07), as well as the newer and less well-understood [PRISM signature system](https://eprint.iacr.org/2025/135).

Once we understand the basics of isogenies and how they're used to build efficient protocols, we can start talking about how isogenies may someday replace common cryptographic tricks which Bitcoin developers think of as forfeit under most PQC schemes, like key-tweaking, BIP32 xpub derivation, and silent payments, all with compact signatures and pubkeys.

## Disclaimer

Since this is a technical article, I'm assuming that readers are already familiar with classical elliptic curve cryptography (ECC) and hash functions as they're used in Bitcoin. If that's not you, I'm sorry, this might be a touch hard to read. Refer to [my ECC resources page](/cryptography/ecc-resources/) for background.

# Isogeny Cryptography

An _isogeny_ is (informally) a function which maps points from one elliptic curve to points on another elliptic curve.

Yes, that's right, we're using elliptic curves (ECs) again.

> wait. aren't elliptic curves vulnerable to quantum computers?

No. ECs aren't "vulnerable" to quantum computers or to anything really, because they have no nothing to protect. ECs are just mathematical objects.

_Cryptosystems_ like signatures or key-exchange which are built using elliptic curves can be vulnerable to attack, but it depends on the mathematical assumptions which the cryptosystem relies on.

Classical elliptic curve cryptography (ECC) assumes the _Elliptic Curve Discrete Log Problem_ (ECDLP) is hard, but due to Peter Shor's namesake algorithm, we now know it can be solved efficiently with a quantum computer.

Isogeny-based cryptography (IBC) assumes the _Supersingular Isogeny Path Problem_ (SIPP) is hard. SIPP asks us:

**Given two supersingular elliptic curves $E_1$ and $E_2$, can you find an isogeny from $E_1$ to $E_2$?**

As fas as we know, there is no efficient quantum algorithm to solve this problem efficiently. As such, most IBC systems use _supersingular_ elliptic curves to make use of that hardness assumption. I will sidestep the rabbit hole by failing to elaborate on what "supersingular" means, but for now just think of them as "nice" elliptic curves.

## High Level

Isogeny-based cryptography (IBC) has the benefit of inheriting a cache of lingo from classical elliptic curve cryptography. Still, the ground rules change. Instead of working with points and scalars, we're working with ECs and isogenies between them.

|| Secret keys | Public Keys |
|-|-|-|
| **Classical ECC**  | Scalars modulo a prime | Points on a fixed curve  |
| **Isogeny Crypto** | Isogenies | Entire elliptic curves |

In IBC, we typically start with a well-known base elliptic curve $E_0$. To generate a keypair, a user would generate a secret isogeny $\varphi$ which maps points on $E_0$ to points on some other curve $E$. We write this more succinctly as:

$$ \varphi : E_0 \rightarrow E_{\text{pk}} $$

**The isogeny $\varphi$ is the user's secret key, and the curve $E_{\text{pk}}$ is their public key.**

Signatures typically consist of a non-interactive zero-knowledge proof that the user knows the secret isogeny, by computing and revealing some other isogeny which they wouldn't have otherwise been able to know, in such a way that the revealed isogeny is bound to a message.

### Ground Rules

To understand how signing works in the world of isogenies, we must learn about some curious results which mathematicians have discovered about isogenies. You'll have to take my word for now as we don't have the required background to fully prove them, but these facts have been proven and are well-known.

1. Every isogeny has a _kernel,_ which is some finite set of points that the isogeny maps to infinity on its codomain (output curve). Isogenies can be almost-uniquely identified by their kernel, and the kernel itself can typically be represented efficiently using a pair of _torsion basis points_ (not going that deep yet).
1. Every isogeny $\varphi: E_1 \rightarrow E_2$ has a _dual_ $\widehat{\varphi} : E_2 \rightarrow E_1$ (denoted by a little hat), which you can think of as an inverse, though it's not exactly that. $\widehat{\varphi}$ can be efficiently computed knowing only $\varphi$.
1. An isogeny $\alpha : E \rightarrow E$ from an elliptic curve $E$ back to itself is called an _endomorphism_. Any elliptic curve defined over a finite field has some finite (but very large) set of possible endomorphisms.
1. The endomorphisms of an EC form a structured group, specifically a [_ring_](https://en.wikipedia.org/wiki/Ring_(mathematics)), if you compose and add them together (as polynomial functions). The endomorphism ring of a curve $E$ is denoted $\text{End}(E)$.
1. Some supersingular elliptic curves have well-known and friendly endomorphism rings. One such curve is $E_0: y^2 = x^3 + x$
1. Computing $\text{End}(E)$ given only $E$ is generally a very hard problem, now dubbed the _endomorphism ring problem._
1. The endomorphism ring problem is equivalent to the isogeny path problem. Specifically:
    - Given curves $E_1$ and $E_2$ and their endomorphism rings $\text{End}(E_1)$, $\text{End}(E_2)$, we can efficiently compute an isogeny $\varphi : E_1 \rightarrow E_2$ (or $E_2 \rightarrow E_1$).
    - Given curves $E_1$ and $E_2$, one endomorphism ring $\text{End}(E_1)$ and an isogeny $\varphi : E_1 \rightarrow E_2$, we can efficiently compute the endomorphism ring $\text{End}(E_2)$.

With a secret key $\varphi_\text{sk} : E_0 \rightarrow E_{\text{pk}}$, we can make use of our knowledge of $\text{End}(E_0)$ to compute $\text{End}(E_{\text{pk}})$. Now we have some new powers which nobody else in the universe, hopefully even quantum-enabled attackers, can do:

- if given an isogeny $\phi_1: E_{\text{pk}} \rightarrow E'$, we can efficiently compute an isogeny $\psi_1: E_0 \rightarrow E'$
- if given an isogeny $\phi_2: E_0 \rightarrow E'$, we can efficiently compute an isogeny $\psi_2: E_{\text{pk}} \rightarrow E'$


### Naive (Unsafe) Signing

From here, knowing the basic rules of isogenies, maybe you can already see how a signature scheme might work.

- Hash the public key curve $E_{\text{pk}}$ and a message $m$ to generate a pseudorandom _challenge_ isogeny $\phi_{\text{chl}}: E_{\text{pk}} \rightarrow E_{\text{chl}}$ which maps the public key to an arbitrary challenge curve $E_{\text{chl}}$
- Use knowledge of $\text{End}(E_{\text{pk}})$ and $\phi_{\text{chl}}$ to compute the challenge curve's endomorphism ring $\text{End}(E_{\text{chl}})$
- Use knowledge of $\text{End}(E_0)$ and $\text{End}(E_{\text{chl}})$ to compute a _response_ isogeny $\phi_{\text{rsp}}: E_0 \rightarrow E_{\text{chl}}$
- The signature is $\phi_{\text{rsp}}$. The verifier recomputes $\phi_{\text{chl}}: E_{\text{pk}} \rightarrow E_{\text{chl}}$ and checks that $\phi_{\text{rsp}}$ is indeed an isogeny mapping $E_0 \rightarrow E_{\text{chl}}$

<img src="/images/isogenies/naive.svg">

This results in very succinct keys and signatures. Keys are simply elliptic curves, which have very compact representations (as small as one scalar), and signatures are simply isogenies, which as I mentioned earlier can be compressed down to two elliptic curve points, which themselves can be compressed further if the isogeny has [_smooth_](https://en.wikipedia.org/wiki/Smooth_number) degree.

Take care though, this naive scheme will be insecure. On one hand, yes, this procedure _does_ prove the signer knew $\varphi_{\text{sk}}$ - She would've never been able to compute $\text{End}(E_{\text{chl}})$ otherwise. In cryptographic parlance, the proof is _sound._

However, it is _not zero-knowledge._ By revealing the response isogeny $\phi_{\text{rsp}}: E_0 \rightarrow E_{\text{chl}}$, the signer also revealed her secret key.

- The attacker presumably knows $\text{End}(E_0)$ since it is a fixed parameter of the scheme.
- Knowing $\text{End}(E_0)$ and $\phi_{\text{rsp}}: E_0 \rightarrow E_{\text{chl}}$, the attacker can compute $\text{End}(E_{\text{chl}})$
- A verifier must know the message $m$ and public key $E_{\text{pk}}$, and so can compute $\phi_{\text{chl}}: E_{\text{pk}} \rightarrow E_{\text{chl}}$
- From $\phi_{\text{chl}}$ the attacker can compute its dual $\widehat{\phi_{\text{chl}}}: E_{\text{chl}} \rightarrow E_{\text{pk}}$
- Knowing $\text{End}(E_{\text{chl}})$ and $\widehat{\phi_{\text{chl}}}: E_{\text{chl}} \rightarrow E_{\text{pk}}$, the attacker can compute $\text{End}(E_{\text{pk}})$ (uh oh)
- The attacker can now forge signatures using $\text{End}(E_{\text{pk}})$.

Let's see how SQIsign fixes this naive scheme and turns it into a secure signature scheme which can be proven to be both _sound_ and _zero-knowledge._

## SQIsign

[SQIsign](https://sqisign.org/) (pronounced "ski-sign") is the leading isogeny-based signature protocol, developed in collaboration by several dozen researchers, many of them renowned experts in the field of isogenies. It is currently in the running for NIST's PQC signature standardization competition.

### SQIsign Size

SQIsign should be of special interest to Bitcoiners, as it provides by far the smallest key+signature sizes of any post-quantum signature protocol under consideration by NIST.

| Parameter Set | Security Level (bits) | Public Key | Signature | Pk+Sig |
|:-:|:-:|:-:|:-:|:-:|
| NIST I | 128 bit | 65 bytes | 148 bytes | 213 bytes |
| NIST III | 192 bit | 97 bytes | 224 bytes | 321 bytes |
| NIST V | 256 bit | 129 bytes | 292 bytes | 421 bytes |

Minimizing pubkey+sig size is crucial for blockchain-based cryptocurrencies like Bitcoin, because this metric directly affects the transaction throughput of the entire system, as we typically need at least one pubkey+signature pair for every UTXO spent.

Compare this to the next smallest non-trivial signature scheme SNOVA (NIST-I level), whose pubkey+sig size at NIST-I level alone is 1264 bytes. SNOVA has been weakened by many attacks - The next smallest scheme which has some degree of public confidence in its design is Falcon-512, with a pubkey+sig size of 1563 bytes.

To compare other PQC schemes, see [Thom Wigger's PQC Zoo](https://pqshield.github.io/nist-sigs-zoo/).

### SQIsigning

SQIsign fixes the naive scheme we drew up earlier by adding a couple extra steps to the signing algorithm:

- Hash the public key curve $E_{\text{pk}}$ and a message $m$ to generate a pseudorandom _challenge_ isogeny $\phi_{\text{chl}}: E_{\text{pk}} \rightarrow E_{\text{chl}}$ which maps the public key to an arbitrary challenge curve $E_{\text{chl}}$
- Use knowledge of $\text{End}(E_{\text{pk}})$ and $\phi_{\text{chl}}$ to compute the challenge curve's endomorphism ring $\text{End}(E_{\text{chl}})$
- **Generate a random secret _commitment_ isogeny $\phi_{\text{com}} : E_0 \rightarrow E_{\text{com}}$ mapping $E_0$ to an arbitrary commitment curve $E_{\text{com}}$.**
- **Use knowledge of $\text{End}(E_0)$ and $\phi_{\text{com}}$ to compute the commitment curve's endomorphism ring $\text{End}(E_{\text{com}})$**
- Use knowledge of $\boldsymbol{\text{End}(E_{\text{com}})}$ and $\text{End}(E_{\text{chl}})$ to compute a _response_ isogeny $\phi_{\text{rsp}}: \boldsymbol{E_{\text{com}}} \rightarrow E_{\text{chl}}$
- The signature is $\phi_{\text{rsp}}$. The verifier recomputes $\phi_{\text{chl}}: E_{\text{pk}} \rightarrow E_{\text{chl}}$ and checks that $\phi_{\text{rsp}}$ is indeed an isogeny mapping $\boldsymbol{E_{\text{com}}} \rightarrow E_{\text{chl}}$

<img src="/images/isogenies/sqisign.svg">

Note how adding $\phi_\text{com}$ created a kind of _buffer_ separating the base curve $E_0$ from the response isogeny $\phi_\text{rsp}$. Since the attacker doesn't know $\phi_\text{com}$, they cannot find an isogeny path from $E_0$ to $E_\text{pk}$. This step lets us prove zero-knowledge of the signature scheme, making it fully secure.

The commitment isogeny $\phi_\text{com}$ and its codomain $E_{\text{com}}$ _must_ be unique for every signature, and never reused. Think of it playing a similar role to a nonce in classical Schnorr signatures: If we reuse a commitment for two distinct signatures, we reveal a non-trivial endomorphism of $E_{\text{pk}}$, which [can be used to extract the full endomorphism ring of $\text{End}(E_{\text{pk}})$](https://arxiv.org/pdf/2309.11912v4).

There are plenty of details and important steps I glossed over, especially the whole _Deurring Correspondence_ thing and the relationship between supersingular elliptic curves and quaternion algebras, but this is the high-level view of SQIsign's protocol. By far the best description I've read comes from the [SQIsign NIST submission document](https://sqisign.org/spec/sqisign-20250707.pdf) (page 5), which I duplicated here with some aesthetic changes and omissions. In the NIST submission, the authors describe SQIsign as a _sigma protocol_ which they convert into a non-interactive signature scheme using the Fiat-Shamir transform.

However, those details are not necessary to understand the rest of this article. If you want to learn more about SQIsign, maybe also check out their [original paper](https://eprint.iacr.org/2020/1240), [their reference implementation](https://github.com/SQISign/the-sqisign), or [this blog](https://learningtosqi.github.io/).

## PRISM

SQIsign is awesome, but even its authors will admit the scheme is incredibly complex and difficult to implement. PRISM is a new-kid-on-the-block scheme which offers a much simpler implementation with compact pubkeys and signatures, and performance comparable to SQIsign.

| Parameter Set | Security Level (bits) | Public Key | Signature | Pk+Sig |
|:-:|:-:|:-:|:-:|:-:|
| NIST I | 128 bit | 66 bytes | 189 bytes | 255 bytes |
| NIST III | 192 bit | 98 bytes | 288 bytes | 386 bytes |
| NIST V | 256 bit | 130 bytes | 388 bytes | 518 bytes |

_The PRISM authors note in [page 26 of their paper](https://eprint.iacr.org/2025/135) that signatures can be compressed even more (about 20%) using a pairing function (SQIsign does this), at the cost of extra complexity and slower performance._

Like SQIsign, PRISM's secret key is also a secret isogeny $\varphi_\text{sk}: E_0 \rightarrow E_{\text{pk}}$. A PRISM signature is also an isogeny which only the holder of $\varphi_\text{sk}$ could've created. PRISM even uses the same finite field as SQIsign and borrows their key-generation algorithm. This compatibility curiously means that a SQIsign key can be used to create or verify PRISM signatures, and vice-versa.

However PRISM uses an additional security assumption beyond those of SQIsign. SQIsign depends mainly on the supersingular isogeny path problem (and equivalently, the endomorphism ring problem). In addition to SIPP, PRISM also depends on the assumption that given a supersingular elliptic curve $E$ and a large prime $q$, it is hard to find an isogeny of _degree_ $q$ with domain (input curve) $E$.

<details>
  <summary>What is the "degree" of an isogeny?</summary>
An isogeny can be thought of as a pair of <i>rational</i> polynomials which act on a curve point's $x$ and $y$ coordinates:

$$ \varphi((x, y)) = \left(\frac{g_1(x)}{h_1(x)}, y \frac{g_2(x)}{h_2(x)} \right) $$

Where:
- $g_1$, $h_1$, $g_2$, $h_2$ are polynomials
- $g_1$ and $h_1$ are coprime
- $g_2$ and $h_2$ are coprime
- $h_1$ and $h_2$ have the same roots

The _degree_ of an isogeny $\varphi$, denoted $\deg(\varphi)$ is simply:

$$ \deg(\varphi) = \max(\deg(g_1), \deg(h_1)) $$

An isogeny's degree is also related to its _kernel,_ but let's leave that discussion for later.
</details>

We know this problem can be easily solved if you know $\text{End}(E)$. While the PRISM authors make decent arguments that finding prime-degree isogenies is likely hard without knowing $\text{End}(E)$, there is no rigorous reduction of this problem to the SIPP or ERP. A new assumption is necessary, and a new oracle must be instantiated for the security proof to work.

Risks aside, if this assumption holds we can create a very simple hash-and-sign signature scheme.

- Construct a hash function $H$ which hashes binary input into large prime numbers.
- Given a message $m$ and public key $E_{\text{pk}}$, compute a prime $q = H(E_{\text{pk}}, m)$
- The signer uses her knowledge of $\text{End}(E_{\text{pk}})$ to find an isogeny $\phi_{\text{sig}}: E_{\text{pk}} \rightarrow E_{\text{sig}}$ such that $\deg(\phi_{\text{sig}}) = q$
- The signature is $\phi_{\text{sig}}$. The verifier checks that $\deg(\phi_{\text{sig}}) = H(E_{\text{pk}}, m)$

<img src="/images/isogenies/prism.svg">

This is much simpler to implement and reason with than SQIsign, but its security is clearly harder to prove conclusively. It is also a newer protocol, with [new attacks](https://eprint.iacr.org/2025/1602) always a possibility.

Speaking of attacks...

## The SIDH Attack

Most people who have heard of isogeny-based cryptography may remember hearing news headlines in 2022 about SIKE/SIDH being ["broken with a 10-year-old laptop"](https://www.quantamagazine.org/post-quantum-cryptography-scheme-is-cracked-on-a-laptop-20220824/). The leading isogeny-based public-key-exchange cryptosystem SIDH (supersingular isogeny Diffie-Helman) [was broken with a very devastating attack by Wouter Castryck and Thomas Decru](https://eprint.iacr.org/2022/975) which could be executed quickly and efficiently on a regular old classical computer. [Here is an excellent talk by Decru on how the attack works](https://www.youtube.com/watch?v=mx9qNHm3mco), which I found very approachable without much background.

People often cite this attack as evidence that isogeny-based crypto is too young to be safe for real-world use. While I partially agree, the context matters a lot.

### Rediscovering Kani's Lemma

What Castryck and Decru found was actually a very _old_ result, due to [a paper by Ernst Kani in 1997](https://mast.queensu.ca/~kani/papers/numgenl.pdf), which had been forgotten by modern isogenists. This 25-year-old paper proved a very important statement, now known as _Kani's Lemma,_ which is (not in fully generality) that:

_Given elliptic curves $E$, $E'$, $F$, $F'$, and the following commutative\* isogenies between them:_

<img src="/images/isogenies/kani.svg">

_...then there exists a higher-dimensional isogeny $\Phi$ of degree $N = d_1+d_2$ between the **products** of elliptic curves:_

$$ \Phi: E \times E' \rightarrow F \times F' $$


_...which is given by a 2x2 matrix of isogenies:_

$$
\Phi = \begin{pmatrix}
\phi & \widehat{\psi}' \\\\
-\psi & \widehat{\phi}'
\end{pmatrix}
$$

_...with kernel:_

$$
\begin{align}
\ker(\Phi) &= \\{\ (\widehat{\phi}(P), \psi'(P)) : P \in F[N] \ \\} \\\\
           &= \\{\ (d_1 P, \psi'(\phi(P))) : P \in E[N] \ \\} \\\\
\end{align}
$$

Here $E[N]$ and $F[N]$ are the $N$-torsion subgroups of $E$ and $F$ respectively.

Understanding torsion subgroups isn't critical, but an important fact to remember is that _isogenies can be uniquely identified by their kernel, and if you know its kernel you can evaluate the isogeny efficiently._

Kani's lemma showed the world that torsion point images (evaluations) from an isogeny are effectively an expression of that isogeny's kernel when it is _embedded_ in some higher-dimensional isogeny.

It just so happened that SIDH worked by exchanging torsion point images between participants in the key exchange. I will skip over the details of this now-broken cryptosystem with you - Decru himself does a much better job explaining the details in his talk - but this rediscovery naturally broke the fundamental assumptions of SIDH and allowed efficient attacks by computing high-dimensional isogenies from the torsion point images which peers are required by SIDH to share.

You can read more about Kani's lemma [here](https://www.math.auckland.ac.nz/~sgal018/kani.pdf) and [here](https://eprint.iacr.org/2025/1706.pdf), in [Castryck and Decru's SIDH attack paper](https://eprint.iacr.org/2022/975), and in [this talk by Decru](https://www.youtube.com/watch?v=mx9qNHm3mco).

### Evolutions

This attack did not endanger most other isogeny-based cryptosystems for the simple reason that most other protocols (unless based on SIDH) did not involve exchanges of torsion point images. Even the similarly-named CSIDH protocol was unaffected because it works by completely different means.

Rather, the 2022 attack by Castryck and Decru _massively accelerated the progress of IBC._ Much of modern research now involves around clever ways to use Kani's lemma and higher-dimensional isogenies to create new schemes and accelerate existing schemes.

For example, the SQIsign authors made use of higher-dimensional isogenies to dramatically improve signing and verification performance in the v2 version of the SQIsign protocol. SQIsigning used to take more than a second, and now it takes only a few milliseconds. PRISM would not exist without Kani's lemma, using it as an efficient means to generate and evaluate prime-degree isogenies. Many other IBC cryptosystems benefited and flourished because of this renaissance.

# Old Tricks, New Crypto

While we could spend many hours exploring the inner workings of SQIsign, PRISM, SIDH, and the mathematical proofs underlying isogeny cryptography, this is not essential to the point of this article. Remember: I'm trying to argue that _Bitcoiners_ should be learning about and investing resources in isogeny-based cryptography. We should get to that.

Now we are equipped with some understanding of how isogeny-based keypairs and signature schemes work, we've seen how they can be attacked, and how they can be proven secure. We know the ground rules.

We can finally discuss how isogenies can be used to replace existing classical ECC tricks commonly used on Bitcoin.

## Rerandomizable Public Keys

Perhaps surprisingly, many higher-level cryptographic constructions used across the Bitcoin ecosystem can be abstracted as one simpler building block, called a _rerandomizable_ public key scheme, which can and has been instantiated with IBC schemes.

A _rerandomizable public key scheme_ is a public key cryptosystem for which we have the following algorithms:

- $\text{KeyGen}(sk) \rightarrow pk$ which generates a key pair.
- $\text{RerandomizePublic}(pk, r) \rightarrow pk'$ where $r$ is a random salt.
- $\text{RerandomizeSecret}(sk, r) \rightarrow sk'$ where $r$ is a random salt.

For *correctness* of a rerandomizable pubkey scheme, given $pk = \text{KeyGen}(sk)$, we need that:

$$ \text{KeyGen}(\text{RerandomizeSecret}(sk, r)) = \text{RerandomizePublic}(pk, r) $$

In plain english: _A rerandomized secret key must correctly relate to the rerandomization of its public key._

It's trivial to construct a _correct_ rerandomizable pubkey scheme. Just define $\text{RerandomizeSecret}(sk, r)$ to output a random secret key derived from $sk$ and $r$, and then define $\text{RerandomizePublic}(pk, r) := \text{KeyGen}(\text{RerandomizeSecret}(sk, r))$.

But obviously this will not be secure. Any adversary who knows $pk$ and $r$ could re-derive the rerandomized secret key and so sign messages.

For full privacy and security, we also need the properties of _unlinkability_ and _unforgeability_ respectively.

- **"Unlinkability"** means the rerandomized keys are indistinguishable from independently generated random keys, unless you know the salt $r$ used to rerandomize the key.
- **"Unforgeability"** means attackers cannot forge signatures for rerandomized public keys unless they also know the (possibly rerandomized) secret key.

### Motivation

Rerandomization generalizes the essence of the many cryptographic techniques used in Bitcoin:

| Technique | Rerandomized Equivalent |
|:-:|-|
|Taproot key tweaking (BIP341)| $\text{RerandomizePublic}(pk, H(pk, m)) \rightarrow pk'$ where $m$ is the merkle root of a merkle tree. The rerandomized pubkey $pk'$ is then a hiding & binding commitment to $m$ which can be opened by revealing $(pk, m)$. |
|$\ $|$\ $|
| Hardened (secret) child key derivation (BIP32) | $\text{RerandomizeSecret}(sk, H(sk, c, i)) \rightarrow sk'$ where $c$ is a chaincode (pseudorandom salt) and $i$ is a 32-bit integer. The rerandomized secret key $sk'$ is a child key which can only be derived if you know the parent secret key $sk$ and chaincode $c$. |
|$\ $|$\ $|
| Unhardened (public) child key derivation (BIP32) | $\text{RerandomizePublic}(pk, H(pk, c, i)) \rightarrow pk'$ where $c$ is a chaincode (pseudorandom salt) and $i$ is a 32-bit integer. The rerandomized pubkey $pk'$ is a child key which can only be derived if you know the parent pubkey $pk$ and chaincode $c$. |
|$\ $|$\ $|
| Silent Payments (BIP352) | $\text{RerandomizePublic}(pk, ss) \rightarrow pk'$ where $ss$ is a "shared-secret" known by sender Alice and receiver Bob, typically generated with a diffie-helman style key exchange. |

This generality of rerandomizable pubkey schemes leads us to conclude: If we can instantiate a correct, unlinkable, and unforgeable rerandomization system using isogenies, then we immediately inherit post-quantum replacements for BIP32, BIP341 key tweaking, and - with some caveats - BIP352 silent payments.

### Prior Work

Classical ECC implementations (including in Bitcoin) typically instantiate rerandomization as follows:

- Let $G$ be a base point of an elliptic curve of prime order $n$
- Construct a collision-resistant hash function $H_n: \\{0, 1\\}^\* \rightarrow \mathbb{Z}\_n$ which maps arbitrary inputs to integers mod $n$.
- Given $sk \leftarrow \mathbb{Z}\_n$, define $\text{KeyGen}(sk) := sk \cdot G$
- Given $pk = \text{KeyGen}(sk)$ and
    - Define $\text{RerandomizeSecret}(sk, r) := sk + H_n(r)$
    - Define $\text{RerandomizePublic}(pk, r) := pk + H_n(r) \cdot G = (sk + H_n(r)) \cdot G$

While there has been some work on rerandomizable keys in the post-quantum lattice cryptography context, the technique is always hobbled by the unergonomic structure of lattice-based public keys. Attempts to introduce structure to lattice-based keypairs seem to hinder compactness of keys and signatures. For instance, [this recent paper](https://eprint.iacr.org/2026/380) (also see [this accompanying blog post](https://blog.projecteleven.com/posts/lattice-hd-wallets-post-quantum-bip32-hierarchical-deterministic-wallets-from-lattice-assumptions)) gives a rerandomizable signature scheme and instantiates it for unhardened BIP32 key derivation, but at the cost of 16kb pubkeys and 20kb signatures (more than 8x bigger than ML-DSA).

For lattices, key rerandomization also affects security and requires we impose usage limitations:

> Remark 2. Although the construction with Raccoon-G allows public key rerandomization, this increases the noise of the keys and changes the distribution of signatures. This affects the maximum depth at which the signature distribution can be argued to be indistinguishable, which is part of the unlinkability argument. One can instead consider a “hybrid” approach where non-hardened derivations are limited per public key generated with $\text{DetKeyGen}$.

## Isogeny Rerandomization

We can make efficient and secure post-quantum rerandomization with isogenies.

Let $\varphi : E_0 \rightarrow E$ be a secret isogeny mapping the base curve $E_0$ to a public key curve $E$.

Let $\mathcal{H}(E, r)$ be a hash function which returns a uniformly random isogeny with domain (input curve) $E$.

To rerandomize a public key curve $E$ - without knowing the secret key - given random salt $r$, we derive an isogeny $\psi = \mathcal{H}(E, r)$ which maps $E \rightarrow E'$ and use the codomain (output) curve $E'$ as the updated public key. Pretty simple.

To rerandomize the secret key isogeny $\varphi$ is more subtle. Given the salt $r$ we can rederive the isogeny $\psi = \mathcal{H}(E, r)$. Because we know our public key's endomorphism ring $\text{End}(E)$, and an isogeny $\psi: E \rightarrow E'$, we can compute $\text{End}(E')$. Knowing $\text{End}(E_0)$ by common knowledge as well, we can now find a secret isogeny $\varphi': E_0 \rightarrow E'$, which is our new secret key.

<img src="/images/isogenies/rerandomization.svg">

<sub><i>A useful general fact to know about isogenies: If you know an isogeny path from any curve $E_1$ to any other curve $E_n$, even if that path involves many intermediate isogenies between other curves $E_2, E_3, E_4, ...$ it is relatively easy to compute a new succinct isogeny directly from $E_1$ to $E_n$, as long as you know the endomorphism ring of at least one curve somewhere along the isogeny path, and not necessarily that of the first or last curves.</i></sub>

Somewhat more concretely:

- Define $KeyGen(\varphi) := \text{Codomain}(\varphi)$
- Define $\text{RerandomizePublic}(E, r)$:
    - Compute $\psi = \mathcal{H}(E, r): E \rightarrow E'$
    - Return $E' = \text{Codomain}(\psi)$
- Define $\text{RerandomizeSecret}(\varphi, r)$:
    - Compute $E = \text{KeyGen}(\varphi)$
    - Compute $\text{End}(E)$ using $\text{End}(E_0)$ and $\varphi$
    - Compute $\psi = \mathcal{H}(E, r): E \rightarrow E'$
    - Compute $\text{End}(E')$ using $\text{End}(E)$ and $\psi$
    - Compute $\varphi': E_0 \rightarrow E'$ using $\text{End}(E_0)$ and $\text{End}(E')$
    - Return $\varphi'$

It's easy to see that correctness holds. The public key generated by rerandomizing $\varphi$ is the same curve $E'$ which you can find by rerandomizing the original public key $E$.

$$ \text{KeyGen}(\text{RerandomizeSecret}(\varphi, r)) = \text{RerandomizePublic}(E, r) $$

### Properties

The isogeny-based $\text{RerandomizePublic}$ algorithm is fast and simpler to implement, as we only need to generate a pseudorandom isogeny and compute its codomain, a well-known task with efficient algorithms readily available. Technically we do not even need to evaluate the isogeny.

$\text{RerandomizeSecret}$ is much more involved and computationally expensive, though still ultimately polynomial time. I don't know how fast in real terms, but based on the performance of SQIsign, I could guess it would probably be measured in milliseconds.

### Security

This technique has been described in a couple of papers such as [this one](https://eprint.iacr.org/2024/400) (page 3), and [this one](https://eprint.bbiacr.org/2023/1915) (oriented isogenies only, page 10), though always in an encryption context rather than with a signature scheme. The concept still applies equally well to signing keys as well though.

Proving unlinkability would be a matter of proving that $\text{RerandomizePublic}(E, r)$ results in an updated curve $E'$ which is indistinguishable from a uniform random distribution of supersingular elliptic curves. The details will start mattering more here, such as the degree of the isogenies used. While I am not a cryptographer, I believe this is an easy proof if you use facts from supersingular isogeny graph theory. SQIsign already proves similar facts around the distribution of challenge curves. Proving unforgeability would depend on the signature scheme you choose.

Still given this technique's novelty and relative obscurity in the literature, there is work to be done proving security before this can be relied upon in the real-world. The lack of available implementations means we cannot assess performance. All this is open future work.

## Examples

To give examples, let's consider a world where SQIsign and/or PRISM verification algorithms are standardized in Bitcoin's consensus.

### BIP32 HD Wallets

Hierarchical-deterministic (HD) wallets could function much as they do today, by starting with a single master secret isogeny $\varphi_m: E_0 \rightarrow E_m$ and master chain code $cc_m$ derived from a human-readable seed:

$$ (\varphi_m, cc_m) = H(\text{seed}) $$

Hardened child keys could be derived by rerandomizing the master key, salted with $cc_m$, a child index $i$, and the secret key itself as in BIP32's `CKDpriv`.

$$ (r, cc_i') = H(\varphi_m, cc_m, i) $$
$$ \varphi_i' = \text{RerandomizeSecret}(\varphi_m, r) $$

Unhardened child keys could be derived by rerandomizing the master key, salted with $cc_m$, a child index $i$, and the public key as in BIP32's `CKDpub`.

$$ (r, cc_i) = H(E_m, cc_m, i) $$
$$ \varphi_i = \text{RerandomizeSecret}(\varphi_m, r) $$


Observers who have an extended public key $(E_m, cc_m)$ can derive unhardened child pubkeys:

$$ (r, cc_i) = H(E_m, cc_m, i) $$
$$ E_i = \text{RerandomizePublic}(E_m, r) $$

The result is an almost exact drop-in replacement for classical BIP32 HD wallets which should be quantum-secure, at the cost of slower key derivation.

### BIP341 Key Tweaking

Someday, if have a lot more confidence in isogeny crypto, we could consider a future upgrade which hides an isogeny-based commitment to a script tree inside of bare-pubkey outputs, much like how taproot works today.

A bare pubkey posted on-chain would be an elliptic curve $E'$ (66 bytes or so). To anyone looking at $E'$ on-chain, it appears randomly selected and opaque. The keyholder could perform a _key-path spend_ by publishing a signature which validates under $E'$: PRISM, SQIsign, or whatever is standardized at the time.

Or, instead of a bare signature, the spender could reveal a second curve $E$ which I'll suggestively call the _internal key_ and a merkle tree root $m$ such that

$$
E' = \text{RerandomizePublic}(E, m)
$$

The merkle tree root $m$ can now be used to prove the UTXO was also committed to some previously-obscured spending condition like a timelock, multisig, or covenant script, and this would be called a _script-path spend._ All this is closely analagous to how BIP341 taproot addresses work today.

There are some complications though. There is no isogeny-based equivalent to the Nothing-Up-My-Sleeve (NUMS) points used by some taproot addresses to disable key-path spending. To date, nobody has yet found a transparent algorithm to generate a supersingular elliptic curve with an unknown endomorphism ring - a _NUMS curve._

It's possible the Bitcoin community could do something similar to the [Perpetual Powers-of-Tau ceremony](https://github.com/privacy-ethereum/perpetualpowersoftau) run by the Ethereum community to produce some evolving set of semi-trustworthy canonical NUMS curves, which are occasionally committed to the blockchain via something like OpenTimestamps.

If interested parties can interact, they could run [a multiparty protocol to generate a NUMS curve](https://eprint.iacr.org/2022/1469.pdf) by walking from a starting curve $E_0$ to some final curve $E_n$, each of the $n$ parties contributing one intermediate isogeny $\phi_i: E_{i - 1} \rightarrow E_i$ and - for security - a simple proof that they know $\phi_i$. Each party promises to forget their isogeny $\phi_i$ after the ceremony concludes.

Any honest agent who participated in the setup ceremony should be confident the resulting curve is indeed unspendable, because if even one party did indeed honestly erase their contribution isogeny, then there is exists no known path from $E_0$ to $E_n$, and so $\text{End}(E_n)$ is also unknown. However, this protocol requires all interested parties to participate in the ceremony, even if asynchronously, which can be troublesome in practice.

### Silent Payments

Silent payments conceptually works as follows:

- Bob posts a static _silent payment_ address containing public key $B$ somewhere online - social media, github, etc.
- Alice sees $B$ and wants to send money to Bob without interacting with him.
- Alice has a UTXO at an address with pubkey $A$.
- Knowing her own secret key $a$, Alice computes a shared secret $ss$ using a diffie-hellman key exchange between her key and Bob's key.
- Alice _rerandomizes_ Bob's public key $B' = \text{RerandomizePublic}(B, ss)$ and sends coins to $B'$.
- Bob scans the blockchain for payments to his silent payment address by brute-force search, computing shared secrets for every transaction which might possibly be a silent-payment to him.
- Eventually Bob tests Alice's transaction, computes the same shared secret $ss$, and finds his derived key $B' = \text{RerandomizePublic}(B, ss)$ matches one of the outputs in Alice's transaction.

While conceptually this is possible to do with isogenies, it is much more difficult than other examples we've seen so far. The rerandomization part is possible, as we've seen, but agreement on a shared secret is hard to do while preserving privacy of both participants.

Many secure key exchange protocols do exist in the world of IBC - see [CSIDH](https://eprint.iacr.org/2024/624), [POKE](https://eprint.iacr.org/2024/624), [QFESTA](https://eprint.iacr.org/2023/1468.pdf), and many others - but none of these key-exchanges are directly compatible with SQIsign or PRISM public keys.

To agree on a randomized key which Bob controls, Alice and Bob must exchange information. Bob starts the conversation by communicating his silent payment address. This occurs off-chain, so it could be almost anything we want, and within reason it could be quite large - as long as it fits in a QR code. For instance, this could be a 66 byte PRISM public key and a 64 byte CSIDH-512 public key attached, for a total of 130 bytes.

Alice can easily compute a shared secret once she sees Bob's CSIDH key, because the CSIDH key exchange is non-interactive. But _how does Alice communicate her CSIDH public key to Bob?_ Without it, Bob cannot compute the shared secret, and cannot identify Alice's payment.

Alice might attach her 64-byte CSIDH pubkey on-chain, in her payment transaction to Bob, e.g. via OP_RETURN, or an inscription envelope. However this is bad for the privacy of both parties, because now on-chain observers can heuristically identify Alice's payment as a silent payment transaction - though they can't prove Bob was the recipient.

Alice could send her CSIDH pubkey to Bob off-chain, but if Alice can communicate with Bob off-chain, why not simply ask Bob for a fresh address of his own choice? This would also endanger Alice's network-level privacy - Alice may prefer not to connect to Bob over the internet, for fear of Bob tracking her by IP address.

In an ideal world, there would be some way to create a hybrid keypair, such that the key encodes both a valid key-exchange pubkey _and_ a valid signing pubkey. Such systems do exist; There are [signature schemes which interoperate with CSIDH keys](https://eprint.iacr.org/2019/498), however these schemes are typically less performant and produce much larger signatures than SQIsign and PRISM. [Here is a cutting edge paper which may help bridge this gap](https://eprint.iacr.org/2025/1737). Alternatively, maybe there could be some way for Alice to embed a CSIDH public key in her signature in a way only Bob could extract. As yet this problem remains elusive.

Another problem is performance. For this system to work at all, Bob must be able to scan every candidate transaction in every block, to identify payments. [Much work has gone into optimizing the CSIDH key exchange](https://ctidh.isogeny.org/), but still it takes on the order of tens or hundreds of milliseconds to execute depending on hardware. For the sender Alice this is no biggie - she need only run the key exchange once - but Bob may have to repeat this key exchange thousands of times to identify payments, unless he is given some extraneous hint from senders.

## Drawbacks

I would be foolish not to acknowledge the limitations of the IBC state-of-the-art.

First and foremost, verification performance is not great. While it has improved a lot in recent years, SQIsign's verification algorithm still requires a good deal of computational power and even optimized code takes more than a millisecond to verify a single signature. This could be offset to some extent with parallelization, but is still definitely the Achilles Heel of isogeny crypto generally.

Another thing to note is that SQIsign has malleable signatures:

> Note that SQIsign does not target strong unforgeability security, and indeed given a valid signature on a message, one can efficiently produce a second distinct valid signature on the same message by manipulating the auxiliary isogeny. Replacing the auxiliary isogeny with any other isogeny of the same degree yields a valid signature. The role of the auxiliary isogeny in the signature is only to enable a two-dimensional representation of the response, but it does not contribute to the security of the protocol. In other words, two-dimensional representations are inherently not unique: given such a representation, in most instances it is easy to find a different representation of the same isogeny. For this reason, SQIsign cannot achieve strong unforgeability.
>
> \- [SQIsign NIST submission](https://sqisign.org/spec/sqisign-20250707.pdf), page 93

I believe the same is true of PRISM, because PRISM signatures are also represented with a two-dimensional isogeny for compactness.

However, this should not affect 2nd-layer protocols like Lightning, because these days signatures are included only in witness data, which does not affect TXID computation.

While I have been lauding the prospects of IBC's cryptographic flexibility, one thing still lacking in the IBC landscape is compact multisignature schemes. While some isogeny-based multisignature schemes do exist, such as [CSI-SharK](https://eprint.iacr.org/2022/1189), they are not nearly as space-efficient as SQIsign and PRISM.

As discussed before, it seems difficult to generate valid NUMS public keys in an isogeny setting. We can do multiparty setup ceremonies, but still it'd be nice if we could simply hash to find a NUMS supersingular curve like we can today hash into NUMS points on a curve.

Finally, it's worth acknowledging the approachability problem of IBC. Compared to something more elementary like hash-based signatures, isogeny crypto comes with a very high barrier to entry for anyone who is not a trained mathematician. I am myself a seasoned cryptographic developer and engineer, but without the necessary math background I've been struggling to wrap my mind around IBC for the past few months. Hash-based signatures were a cakewalk by comparison.

This problem seems to stem from a lack of beginner-friendly educational resources. Most information I've found has been in scholarly papers and hour-long videotaped powerpoint presentations.

## Conclusions

Most info about isogeny crypto still lives in the secluded bastions of mathematical academia. I hope this article provides a more accessible and intuitive glimpse into this world.

To any professional isogenists reading: I apologize if I let any inaccuracies slip by. I left some things unsaid to reduce verbosity. Please [contact me](mailto:conduition@proton.me) to correct any grievous errors! I would love to chat with you.

Now that we've seen some of what isogeny crypto can do, I hope you'll understand why I named this article as I did. If you care about the future of Bitcoin after big quantum computers appear, you should be spending at least some fraction of your resources learning about what systems may someday replace classical ECC, and I believe isogenies are ahead of the pack here.

More explicitly, I am arguing that:

- **Bitcoin businesses which rely on classical ECC features** should spend money researching how to replace those features with quantum-safe alternatives. Can you _isogenize_ it?
- **Bitcoin developers** should learn about isogenies so they can write secure software which uses isogeny crypto some day.
- **Bitcoin layer-two protocol engineers** should think longer term. Don't spend years building ECC-based protocols only for quantum computers to tear it all down in a decade or two. Build something which at least stands a chance to outlive you.
- **Bitcoin core developers** should be thinking about what cryptography we want to use as a basis for long-term scaling and expressibility of future on-chain spending after ECC dies. As many readers know, [I love SLH-DSA](/code/fast-slh-dsa/), I think it is a great fallback and stopgap, but long-term, we can do better.
- **Bitcoin Venture Capital investors** should be thinking about the future of the companies they are funding. Startups bootstrapped in the next few years might be the first generation of pre-IPO Bitcoin companies impacted directly by quantum computing, or at the very least, the first to be majorly hobbled by quantum FUD. If a CEO doesn't have a solid quantum-readiness plan, you should be skeptical.
- **Bitcoin custodians** like Coinbase, Fidelity, Gemini, Anchorage et al should be funding research into secure post-quantum replacements for their complex offline and multisig custody models. These companies' wallets will be highest on the hit-list if a CRQC holder decides to start attacking Bitcoin. They have the most to lose, and the most incentive to invest in building scalable PQ-secure wallets.
- **Bitcoin users** should be salivating at the possibility that we might be able to efficiently replace classical ECC. We get to keep most of the nice things we've gotten used to over the years, and at relatively little cost compared to the billions of dollars being spent on quantum computing R&D.


As a freelance Bitcoin researcher focused on replacing classical ECC, I realize this may come off as me asking you to buy me lunch, but I'm not talking about myself and my own work necessarily. Though if you're interested defs [contact me](mailto:conduition@proton.me).

I'm talking about human brainpower, and the money which incentivizes the focus of many smart people. The Bitcoin industry today is a force to be reckoned with, and as fragmentary as the community may be, our collective resources are enormous. If we bring them to bear and apply pressure where it gives the most leverage, I have every confidence Bitcoin can and will survive coming cryptanalytic breakthroughs.

As we all know, those who invest in novel powerful technologies early take the most risk, but also reap the most reward.

## Other Sources about Isogenies

- https://arxiv.org/pdf/1711.04062
- https://www.pdmi.ras.ru/~lowdimma/BSD/Silverman-Arithmetic_of_EC.pdf
- https://www.math.auckland.ac.nz/~sgal018/crypto-book/ch25.pdf
- https://ocw.mit.edu/courses/18-783-elliptic-curves-fall-2025/mit18_783_f25_lec04.pdf
- https://troll.iis.sinica.edu.tw/ecc24/slides/1-02-intro-isog.pdf
- https://math.mit.edu/classes/18.783/2019/LectureNotes5.pdf
- https://cs-uob.github.io/COMSM0042/assets/pdf/Isogeny-based%20Cryptography_Advanced%20Cryptology.pdf
- https://eprint.iacr.org/2023/671.pdf
