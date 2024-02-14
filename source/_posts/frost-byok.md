---
title: How to Bring Your Own Key to a FROST Signing Group
date: 2024-02-14
mathjax: true
category: cryptography
---

Someone posted [this great question on Nostr](https://primal.net/e/note15nsyy4d5ck4804w0tp75v5sjd3raq68rsqxc3jjztkg3kselnfpqvkqpgn) the other day:

> Does FROST allow you to BYOK (make that meme for bring your own key)?

...And being the nerd I am, I couldn't resist the challenge of working out how to actually do it.

## Prerequisites

This article will assume quite a bit of background knowledge.

If you're not already familiar with elliptic curve cryptography, this article is not for you. Check out [my ECC resources page](/cryptography/ecc-resources/) for more beginner-friendly guides.

I'll assume you're familiar with the polynomial-driven mathematics which underlies [Shamir Secret Sharing](/cryptography/shamir/), as FROST relies on very closely related principles.

## Background

[FROST](https://eprint.iacr.org/2020/852.pdf) is a threshold multisig protocol which allows a group of mutually distrusting parties to co-sign a message in unison, producing an aggregated Schnorr signature. This signature can be validated using a single public key which is controlled collectively by the whole group, so third-party verifiers don't need to care how the signatures are produced - only that they are valid Schnorr signatures.

Sounds a lot like [MuSig](/cryptography/musig), right? Well, in MuSig, all signers in the group _must be online_ to sign a message ($n$-of-$n$). A FROST group on the other hand can set an arbitrarily low _security threshold,_ commonly denoted as $t$. This threshold determines how many signers must be online and cooperating to sign a message ($t$-of-$n$). This is helpful in situations where some signers might not be online or cooperative all the time, but a single unified signing key is still needed.

The FROST protocol is split into two sub-protocols:

1. The distributed key generation (or "DKG") protocol
2. The signing protocol

The DKG protocol sets up the signing group so that each party receives a fairly-computed and verifiable _signing share._ The signing protocol utilizes at least $t$ of those signing shares to construct a signature.

For this article, we won't look to hard at the signing protocol. We really only need to care about the DKG, and whether it outputs secure signing shares in different use cases.

## Notation

Just so we're all on the same page:

| Notation | Meaning |
|:--------:|---------|
| $G$ | The [base-point of the secp256k1 curve.](https://bitcoin.stackexchange.com/questions/58784/how-were-the-secp256k1-base-point-coordinates-decided) |
|$H(x)$ | The SHA-256 hash function. |
|$q$ | The [_order_ of the secp256k1 curve](https://crypto.stackexchange.com/questions/53597/how-did-someone-discover-n-order-of-g-for-secp256k1). There are $q - 1$ possible valid non-zero points on the curve, plus the 'infinity' point (AKA zero). |
|$x \leftarrow \mathbb{Z}\_{q}$ | Sampling $x$ randomly from the set of integers modulo $q$. Note that we exclude zero when sampling. |
| $x_i = ...\ \forall\ 1 \le i \le n$ | Define the set of all $x_i$ for every number $i$ in the range from $1$ to $n$. |
| $[a, b]$ | Inclusive range notation, i.e. all numbers between $a$ and $b$ including $a$ and $b$. |
| $(a, b)$ | Exclusive range notation, i.e. all numbers between $a$ and $b$ excluding $a$ and $b$. |
| $A \cup B$ | The _union_ of sets $A$ and $B$. |

# DKG Review

<p style="font-size: 80%;">
This section is mostly a review of <a href="https://eprint.iacr.org/2020/852.pdf#page=12">Section 5.1 Figure 1 in the FROST whitepaper</a>. Feel free to <a href="#Hypothetical-Crypto-Ahead-%E2%9A%A0%EF%B8%8F">skip ahead to the new stuff</a> if you're already familiar with FROST.
</p>

The canonical FROST DKG protocol (also known as a _Pedersen DKG_) starts with each of the prospective signing group members generating $t$ random coefficients. Each uses these coefficients to define a degree $t-1$ polynomial.


$$ a_{(i, j)} \leftarrow \mathbb{Z}\_{q} \ \forall \ 0 \le j \lt t $$
$$
\begin{align}
f_i(x) :=&\ a_{(i,\ 0)} + a_{(i,\ 1)} x + ... + a_{(i,\ t-1)} x^{t-1} \\\\
        =&\ \sum_{j = 0}^{t-1} a_{(i,\ j)} x^j
\end{align}
$$

- $i$ denotes the index of the signer, which should _never_ be zero.
- $j$ denotes coefficient indexes starting from zero.
- Each $a_{(i,\ j)}$ denotes the random coefficient at index $j$ chosen by signer $i$.
- $f_i(x)$ is the polynomial defined by these coefficients.

Each signer then computes a _commitment polynomial_ $F_i(x)$, which is essentially a public version of their secret keygen polynomial $f_i(x)$.

$$ \phi_{(i,\ j)} = a_{(i,\ j)} G $$
$$
\begin{align}
F_i(x) :=&\ \phi_{(i,\ 0)} + \phi_{(i,\ 1)} x + ... + \phi_{(i,\ t-1)} x^{t-1} \\\\
        =&\ \sum_{j = 0}^{t-1} \phi_{(i,\ j)} x^j \\\\
        =&\ \sum_{j = 0}^{t-1} a_{(i,\ j)} x^j G \\\\
        =&\ f_i(x) \cdot G \\\\
\end{align}
$$

Each signer computes a proof that they know $a_{(i,\ 0)}$ - the constant term of $f_i(x)$. This prevents [rogue key attacks](/cryptography/musig/#Rogue-Keys). In simpler terms, they sign a message to confirm they know their secret coefficient $a_{(i,\ 0)}$.

$$
\begin{align}
k_i &\leftarrow \mathbb{Z}\_{q} \\\\
R_i &= k_i G \\\\
\end{align}
$$
$$ c_i = H(i, \beta, \phi_{(i,\ 0)}, R_i) $$
$$ s_i = k_i + a_{(i,\ 0)} \cdot c_i $$
$$ \sigma_i = (R_i, s_i) $$

- $k_i$ is a random nonce.
- $\beta$ is a context string unique to this DKG execution, which prevents replay attacks.
- $\sigma_i$ is the resulting proof - AKA signature - which demonstrates the signer knows $a_{(i,\ 0)}$.

Each signer publishes the proof $\sigma_i$ and the commitment polynomial $F_i(x)$ to their fellow co-signers. Signers wait to receive all commitment polynomials and verify all proofs before continuing. These proofs can be validated quite easily by checking the signature against the pubkey $F_i(0) = \phi{(i,\ 0)}$, in exactly the same manner as verifying a normal Schnorr signature.

$$ s_i G = R_i + c_i \cdot \phi_{(i,\ 0)} $$

Once all proofs have been verified, and all commitment polynomials are available and consistent across the group, each signer computes _evaluations_ using their secret keygen polynomial $f_i(x)$, for every signer index in the group. Each evaluation is sent to _only_ the one signer.

For instance, signer $i$ would compute $f_i(j)$ and give that evaluation _only_ to signer $j$. Repeat for every signer in the group, including one evaluation which they keep to themselves: $f_i(i)$

If there are $n$ signers in the group, then each signer receives $n$ evaluations of different polynomials, all of which should have the same degree ($t-1$), but _totally unrelated random coefficients._

Each evaluation must then be verified. Every signer has the full set of commitment polynomials, $\\{F_1(x), F_2(x), ... F_n(x)\\}$. Each polynomial commitment can be used to verify the evaluation given by its original sender.

Let's say we're signer $i$, and we received an evaluation from signer $j$. This evaluations should be $f_j(i)$. We can verify it easily using $F_j(x)$ to assert the following statement.

$$ F_j(i) = f_j(i) \cdot G $$

If that holds, then we know the evaluation we received from signer $j$ is authentic, or at least consistent with their commitment polynomial.

If it holds for _every_ evaluation received from all $n$ signers (including themselves), then signer $i$ can at long last compute their final FROST signing share $s_i$ by summing up these evaluations.

$$
\begin{align}
s_i &= f_1(i) + f_2(i) + ... + f_n(i) \\\\
    &= \sum_{j=1}^n f_j(i) \\\\
\end{align}
$$

The FROST group also has a public verification polynomial $F(x)$, which can be computed by any signer as:

$$
\begin{align}
F(x) &= F_1(x) + F_2(x) + ... + F_n(x) \\\\
     &= \sum_{i=1}^n F_i(x) \\\\
\end{align}
$$

- $F(i)$ outputs the FROST public verification share for signer $i$.
- $F(0)$ outputs the FROST group's collective public key.

The DKG succeeds if all signers correctly verified their new signing shares, and can all agree on the same verification polynomial $F(x)$.

## What's Going On Here?

This has a surprising result.

Every FROST signer in the group ends up with a Shamir Secret Share $(i, s_i)$ of a hypothetical commonly-generated secret $s_0$. None of the signers ever learned $s_0$. If at least one signer chose their constant term $a_{(i,\ 0)}$ randomly, then $s_0$ is totally random.

Here's an analogy for you. Every signer rolls a die and puts their die in a hat. The shared secret is the sum of all those dice, mod 6. If even one player rolls their die fairly, then it's impossible to guess what that shared secret is with any better than a $\frac{1}{6}$ chance. Also the hat is protected by a magical spell so that you can't look inside it without at least $t$ of the signers cooperating. Yeah, cryptography is magic.

FROST keygen is kind of like [Shamir Secret Sharing](/cryptography/shamir/), except where the group's shared secret is constructed randomly, and collectively, instead of by a trusted dealer.

How did [Shamir Secret Sharing](/cryptography/shamir/) sneak in there? Well FROST signing shares are exactly the same mathematical objects as Shamir Secret Shares. Each signing share is an input/output tuple $(i, f(i))$, where $f(i)$ is the evaluation of some hypothetical key-generating polynomial $f(x)$, whose constant term is $f(0) = s_0$ i.e. the group's collective secret key. If $t$ or more signers were to cooperate, they could use Shamir Secret Sharing to reconstitute the group secret key $s_0$.

This works because the group's _collective_ keygen polynomial $f(x)$ is defined by adding up all the _individual_ secret keygen polynomials chosen by the signers.

$$ f(x) = f_1(x) + f_2(x) + ... + f_n(x) $$

Summing two polynomials is just a matter of adding their terms together. Graphically, this feels like adding up the distance from the X-axis between the graphs of both functions.

<img src="/images/frost-byok/fn-addition.gif">

By adding up the evaluations they received $s_i = f_1(i) + f_2(i) + ... + f_n(i)$, the signer is composing an evaluation (AKA a share) of $f(x)$.

The only difference between SSS and FROST is that FROST provides an interactive signing protocol to sign messages _without_ reconstituting $s_0$ (which is the really novel part of FROST). Fundamentally, any SSS group is also a FROST group, and _could_ sign messages as a group if they so chose.

-----

Now that we understand how FROST's DKG works within its intended domain of usage, let's examine how we might modify it to support Bring-Your-Own-Key (BYOK). In pursuit of such lofty goals, we're going to be bending FROST's DKG in ways it wasn't intended. With that in mind, here's a big fat disclaimer.

## Hypothetical Crypto Ahead ⚠️

Everything you're about to read below is completely hypothetical cryptography which I completely made up myself. Nobody has peer reviewed this. Nobody has audited this. As far as I know, there is no precedent for the operations I'm doing here (If there is, please [let me know!](mailto:conduition@proton.me)). I'm not a PhD-bearing expert. Even if I were, you shouldn't implement cryptography you read about on some guy's blog. I'm writing this to spur discussion and to theorize, _not_ as reference material for production-grade crypto. **Stick to battle-tested and peer-reviewed protocols.**

# BYOK

To BYOK, some subset $m$ of the $n$ signers must enter the FROST group with a-priori fixed signing and verification shares. The role of the DKG then, is to compute signing and verification shares for the other non-BYOK signers, and also to verify each other's shares are valid.

## Limitations

One corollary of the [Fundamental Theorem of Algebra](https://en.wikipedia.org/wiki/Fundamental_theorem_of_algebra) is that any $t$ points can only be interpolated by a polynomial of degree $t-1$ or higher. We can use this to put an upper bound on $m$.

The group keygen polynomial $f(x)$ must interpolate (pass through) every signing share $(i, f(i))$. If $m$ of those shares are fixed at arbitrary values _before_ the DKG protocol is executed, then $f(x)$ must have degree at least $m-1$.

$$ m \le t \le n $$

In practice, this simply means no more than $t$ signers can BYOK to a FROST group with threshold $t$.


## Flipping the DKG

Let $y_i$ denote an a-priori fixed secret signing share, brought by one of these $m$ signers to the DKG. They must keep $y_i$ secret, otherwise it has no value.

Without loss of generality, I'll assume that signers $[1, m]$ are the BYOK signers, and signers $[m+1, n]$ are the standard FROST signers who are OK with generating fresh keys.

We need a way to guarantee that $f(i) = y_i$ specifically for the set of signers who BYOK, but not necessarily for the other standard FROST signers. We also can't compromise the security of the DKG by doing this.

The FROST DKG assumes each signer generates their keygen polynomial $f_i(x)$ by choosing $t$ random coefficients and then using them to produce evaluations, but they can do just as well starting the other way around: by going from evaluations to coefficients.

The most obvious way to do this is to have every signer $j$ design their keygen polynomial $f_j(x)$ so that it outputs $f_j(i) = 0$ specifically at all BYOK indexes $1 \le i \le m$. Each BYOK signer $i$ can adjust their keygen polynomial to output $f_i(i) = y_i$. The result is that $f(i) = y_i$, because all the other evaluations cancel out.

$$ f(i) = \sum_{j=1}^n f_j(i) = f_i(i) $$

This sounds challenging, but it's actually relatively easy to design polynomials in this way, by using methods like [Lagrange Interpolation](/cryptography/shamir/#Interpolation-1), and none of this requires a-priori knowledge of the public keys being brought to the group (meaning we should still be safe against rogue key attacks).

## Interpolating

Assume we have some black box interpolation algorithm $I(P) \rightarrow g$ which takes in some set of $d$ points called $P$, and spits out a unique polynomial $g(x)$ which has degree at most $d - 1$.

Each FROST signer $i$ first samples a set of $t-m$ random evaluations $\\{b_{(i,\ m+1)} ... b_{(i,\ t)} \\}$ which together constitute their contribution to the group keygen polynomial.

$$ b_{(i,\ j)} \leftarrow \mathbb{Z}\_q\ \forall\ m \lt j \le t$$

They can compute their individual keygen polynomial $f_i(x)$ by interpolating those points, plus the zero-evaluations at indexes $1 \le i \le m$ needed to enable BYOK.

$$ K = \\{(j, 0)\\}\_{1 \le j \le m} $$
$$ P_i = \\{(j, b_{(i,\ j)})\\}\_{m \lt j \le t} $$
$$ U_i = K \cup P_i $$
$$ I(U_i) \rightarrow f_i $$

- $P_i$ is the set of evaluations chosen by the signer which contribute to the randomness of $f(x)$
- $K$ is the set of zero evaluations which enable BYOK for some signers.
- $U_i$ is the _union_ (that's the $\cup$ operator) of $P_i$ and $K$
- $I$ is an interpolation mechanism which spits out our signer's desired keygen polynomial $f_i(x)$

For a signer $i$ who is bringing their own fixed key, they simply amend $K$ to include the appropriate evaluation output $(i, y_i)$.

Other differences from the standard DKG process:


1. Each signer constructs their keygen polynomial $f_i(x)$ by interpolating a set of $t$ points in total. This is to ensure $f_i(x)$ (and by extension, $f(x)$) will have degree $t-1$, but it also has an interesting security implication. If $t = m$ (the threshold is the same as the number of signers who BYOK), then $P_i$ is an _empty set._ This implies that a group of $m = t$ signers who BYOK are _entirely determining everyone's keygen polynomials,_ and thus also determining the final group keygen polynomial $f(x)$.

  This sounds pretty bad. Couldn't those BYOK signers collude to poison the group key? Well if $m = t$, then those same BYOK signers could run off with the whole key even if we used the standard FROST DKG anyway. No new opportunities there.

2. When sending evaluations, signers can skip the BYOK indexes $1 \le i \le m$, because those have already been fixed ahead of time.

Other than this, the protocol runs exactly the same as the standard FROST DKG.

- Commitment polynomials are still $F_i(x) = f_i(x) \cdot G$
- The knowledge-of-secret-key signature $\sigma_i$ is still required and must be verified.
- Evaluations must still be sent to those who did not BYOK.
- Individual signing shares (which are not BYOK) are still computed as $s_i = \sum_{i=1}^n f(i)$
- The group verification polynomial $F(x) = \sum_{i=1}^n F_i(x)$ is still constructed by summing all commitment polynomials.
- The group's public key is still computed as $F(0)$.

The math works out correctly. The big question is whether this is secure or not.

## Security

The main approach I considered when trying to attack this protocol was whether a colluding subset of $m \lt t$ BYOKers could somehow backdoor the group key. Although they are able to reduce the overall entropy involved in the DKG process (because only $1$ of the evaluations used to interpolate $f_i(x)$ is random), I am unsure how that could be exploited. Even if their entropy is decreased, the group key and signing shares produced by the DKG are still randomly distributed, and so they should be secure (?).

Far be it from me to authoritatively declare whether this approach is secure or not. Intuitively it _feels_ secure, because I can't think of a way to attack it effectively with less than $t$ signers.

But this is not a solid metric. These days, cryptographic security is best when it can be proven definitively under clear assumptions. I would love if those more experienced than myself could inspect this idea and possibly prove whether the approach is secure.

## Use Cases

If FROST BYOK is secure, what can you do with it? Well there's one thing it might be _very_ handy for.

BYOK would allow us to build _hierarchical_ FROST groups _from the bottom-up,_ in the same way we can currently do with [MuSig key aggregation](/cryptography/musig/). A hierarchical FROST group is one where signing shares are themselves split among a threshold of "sub-signers". For example, this diagram illustrates a 2-of-3 multisig with nested subwallets, each of them a FROST wallet.


```
                            ┌───────────────────┐
                            │                   │
                            │ wallet A (2-of-3) │
                            │                   │
                            └─────────┬─────────┘
                                      │
                                      │
            ┌─────────────────────────┼───────────────────────────────┐
            │                         │                               │
            │                         │                               │
            │                         │                               │
┌───────────┴──────────┐  ┌───────────┴──────────┐         ┌──────────┴───────────┐
│                      │  │                      │         │                      │
│ subwallet 1 (1-of-2) │  │ subwallet 2 (1-of-2) │         │ subwallet 3 (2-of-3) │
│                      │  │                      │         │                      │
└──────────┬───────────┘  └───────────┬──────────┘         └──────────┬───────────┘
           │                          │                               │
     ┌─────┴──────┐             ┌─────┴──────┐           ┌────────────┼────────────┐
     │            │             │            │           │            │            │
┌────┴────┐  ┌────┴────┐   ┌────┴────┐  ┌────┴────┐ ┌────┴────┐  ┌────┴────┐  ┌────┴────┐
│signer 1A│  │signer 1B│   │signer 2A│  │signer 2B│ │signer 3A│  │signer 3B│  │signer 3C│
└─────────┘  └─────────┘   └─────────┘  └─────────┘ └─────────┘  └─────────┘  └─────────┘
     X                                                   X            X
```

If each of the signers marked with an `X` agreed to sign some data, then in theory they could trustlessly sign as the top-level `wallet A`. Signer 1A can sign as subwallet 1, while signers 3A and 3B can sign as subwallet 3.

This is not anything new: Normal FROST signing shares from the DKG can be split into Shamir Secret Shares and distributed to new keyholders to form such a hierarchy. The signing protocol becomes more complicated, but it's completely doable. However, with standard FROST, participants must always generate a completely _fresh signing share_ when creating a new FROST group. Pre-existing FROST groups cannot join together trustlessly into a higher-order FROST hierarchy without abandoning their existing group keys.

What's novel about this approach I described above is that BYOKing allows existing FROST or MuSig group keys to be composed into hierarchical FROST groups, albeit with an upper limit on the number of allowed BYOKs ($m \le t$).

As to how this could be used in the real-world, I'm not sure. Perhaps BYOK could enable things like higher-order [Fedimints](https://fedimint.org/), to enable composing multiple Fedimint instances together into a _SuperMint™_.

## Contact

[Hit me up via email](mailto:conduition@proton.me), or [on Nostr](https://primal.net/p/npub1l6uy9chxyn943cmylrmukd3uqdq8h623nt2gxfh4rruhdv64zpvsx6zvtg) to chime in on this subject! You're also welcome to [file a pull request or issue for this website](https://github.com/conduition/conduition.io) if you notice any mistakes or would like to add something.
