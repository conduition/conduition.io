---
title: A Dive Into the Math Behind Bitcoin Schnorr Signatures
date: 2023-06-23
mathjax: true
categories:
  - cryptography
---

# Introduction

Many culture articles in the Bitcoin space will extol the sound byte:

> Schnorr signatures will improve Bitcoin's privacy for multisignature transactions!

...and yet most choose to omit the clever math which makes this statement true. The math isn't mind-bogglingly complex. One needs only a basic grasp of [elliptic curve cryptography](/cryptography/ecc-resources/), and the benefits of Schnorr Signatures quickly become very exciting.


## Preliminaries

Just so we're all on the same page:

| Notation | Meaning |
|:--------:|---------|
| $G$ | The [base-point of the secp256k1 curve.](https://bitcoin.stackexchange.com/questions/58784/how-were-the-secp256k1-base-point-coordinates-decided) |
| $m$ | The message we're trying to sign (a byte array). |
|$H(x)$ | The SHA-256 hash function. |
|$n$ | The [_order_ of the secp256k1 curve](https://crypto.stackexchange.com/questions/53597/how-did-someone-discover-n-order-of-g-for-secp256k1). There are $n - 1$ possible valid non-zero points on the curve, plus the 'infinity' point (AKA zero). |
|$x \leftarrow \mathbb{Z}\_{n}$ | Sampling $x$ randomly from the set of integers modulo $n$. Note that we exclude zero when sampling. |
| $a\ \|\|\ b$ | Concatenation of the byte arrays $a$ and $b$. |

In general, upper-case variables like $X$ refer to points on the elliptic curve, while lower case letters like $x$ refer to ordinary natural numbers, called _scalars._

## Enter the Frankenstein

To understand how delicious Schnorr Signatures are for Bitcoin developers, we need to compare it to what we have now: ECDSA. I'll forgive you if you choose to skip this part.


<details>
  <summary><i>Show me the ugly ECDSA math!</i></summary>

I guess you're really gonna make me huh? Best get this over with, then. <sub><i>\*drinking intensifies</i></sub>

The old ECDSA protocol signs messages like so:

1. Choose our private key, $d$, which is just a random integer in $\mathbb{Z}\_{n}$.

$$
d \leftarrow \mathbb{Z}\_{n}
$$


2. Compute the hash of the message and interpret it as an integer $z$.

$$
z = H(m)
$$


3. Sample a random nonce $k$.

$$
k \leftarrow \mathbb{Z}\_{n}
$$

4. Multiply $k$ by the base point $G$.

$$
(x_1, y_1) = kG
$$

5. Take the $x_1$ coordinate from that computation modulo $n$.


$$
r = x_1 \mod{n}
$$

\* <sub>If $r = 0$, return to step 4 and choose a new nonce $k$.</sub>


7. Signing time! Compute this mess.

$$
s = k^{-1}(z + rd) \mod n
$$

\* <sub>If $s = 0$, return to step 4 and choose a new nonce $k$.</sub>

\*\* <sub>$k^{-1}$ is the [modular multiplicative inverse](https://en.wikipedia.org/wiki/Modular_multiplicative_inverse) of $k$.</sub>

**The final signature is the awful pair of integers** $(r, s)$.

Verifying the signature goes (painfully) as follows:

1. Find (or compute) the public key.

$$
D = dG
$$

2. Check that both $r$ and $s$ are integers in $\mathbb{Z}\_{n}$.

$$
\begin{eqnarray}
0 < r < n \\\\
0 < s < n \\\\
\end{eqnarray}
$$

3. Compute the hash of the message that was signed, just as the signer would have.

$$
z = H(m)
$$

4. Compute these intermediate "u-values".

$$
\begin{align}
u_1 &= zs^{-1} \mod n \\\\
u_2 &= rs^{-1} \mod n \\\\
\end{align}
$$

5. Multiply $u_1$ and $u_2$ by the base point and public key respectively.

$$
\begin{align}
U_1 &= u_1G \\\\
U_2 &= u_2D \\\\
\end{align}
$$


6. Sum both points to get a verification point.

$$
(x_1, y_1) = U_1 + U_2
$$

7. Verify the X-coordinate of that point is equivalent to the signature's $r$ component when taken modulo $n$.

$$
r \equiv x_1 \mod n
$$

If so, then wham you've got a valid signature. _"That was easy wasn't it?"_ <sub><i>he mused ironically...</i></sub>

> but why does that work?

-I hear you ask.

I am not a masochist, so I will spare myself more work rewriting a proof for an algorithm which I'm taking such pains to paint as awful. Instead, go check out [this proof of ECDSA in Doctor Nakov's _Practical Cryptography for Developers_ e-book](https://cryptobook.nakov.com/digital-signatures/ecdsa-sign-verify-messages#the-math-behind-the-ecdsa-sign-verify).

</details>

> but why is ECDSA so awful?

For starters, it requires computing [modular multiplicative inverses](https://en.wikipedia.org/wiki/Modular_multiplicative_inverse) of the nonce $k$ when signing, and of the signature $s$ when verifying. _Yuck._ Well, more accurately, _yawn._ MMI's are very slow compared to other discrete math operations.

Furthermore, just look at the number of steps I had to write out above. It's less a signing algorithm than a _surgical procedure_ which happens to involve your private keys.

Also, ECDSA signatures are _malleable._ $(r, s)$ is a valid signature, but so is $(r, n - s)$! This can mess with some applications if they expect signatures not to change. Legacy Bitcoin P2PKH addresses are still vulnerable to this - any transaction which spends from P2PKH can have its transaction ID changed if the signature $s$ value is inverted.

Furtherermore, [ECDSA has pretty weak security proofs](https://crypto.stackexchange.com/questions/71029/are-dsa-and-ecdsa-provably-secure-assuming-dl-security).

Furtherestmore, ECDSA (and its forerunner DSA) were originally published in the early nineties to get around the patent on Schnorr Signatures, which finally lapsed in 2008. _Bitcoin has been using a knock-off of Schnorr since the genesis block._ It's time to finally upgrade to the brand-name.

# Schnorr Signatures

Compared to ECDSA, Schnorr Signatures are a breath of fresh air for their elegant simplicity.

1. Sample a random nonce $r$.

$$
r \leftarrow \mathbb{Z}\_n
$$

2. Multiply $r$ by the base-point $G$.

$$
R = rG
$$

3. Hash the the nonce point $R$, the signing public key $D$, and the message $m$ to get the challenge $e$.

$$
e = H(R\ \|\|\ D\ \|\|\ m)
$$

\* <sub>If you read about Schnorr Signatures elsewhere online, you might see the challenge computed as $e = H(R\ \|\|\ m)$. The variant used in Bitcoin is called _Key-Prefixed Schnorr,_ where the challenge also commits to the signing key.</sub>

4. Compute the signature using the private key $d$.

$$
s = r + ed \mod n
$$

**The final signature is the tuple** $(R, s)$, where $R$ is a point on the curve and $s$ is a scalar value.

Verifying Schnorr Signature is easy-peezy. Just multiply both sides of the above equation by $G$ and check for equality.

$$e = H(R\ \|\|\ D\ \|\|\ m)$$
$$sG = R + eD$$

The verifier is assumed to know the public key $D$ and the message $m$ - otherwise what are they verifying, anyways? Verifying is as fast as a hash, followed by two point-multiplication operations and one point-addition operation.

It's pretty easy to prove that the signature is valid by simply factoring out $G$.

$$
\begin{align}
sG &= \overbrace{rG}^{R} + e\overbrace{dG}^{D}   \\\\
sG &= (r + ed)G  \\\\
s  &= r + ed     \\\\
\end{align}
$$


Thanks to the properties of cryptographically secure elliptic curves like secp256k1, factoring a curve point to find its discrete logarithm isn't computationally feasible (yet). This is why signatures cannot be forged without knowing the private key $d$, but they can be easily verified using $G$.

> but why do these particular equations work?

Far be it from me to reverse-justify Schnorr's design, but perhaps I can at least point out what each step and each variable is doing from the perspective of someone attempting to attack the scheme.

Recall the definition of a Schnorr Signature.

$$
\begin{aligned}
& d \leftarrow \mathbb{Z}\_n \quad &&
  r \leftarrow \mathbb{Z}\_n \\\\
& D = d G \quad &&
  R = rG                    \\\\
\end{aligned}
$$
$$
\begin{align}
e &= H(R\ \|\|\ D\ \|\|\ m) \\\\
s &= r + ed                 \\\\
\end{align}
$$

Note that:

- $r$ and $d$ are both randomly sampled from the set of modulo $n$, AKA $\mathbb{Z}\_n$.
- The nonce $r$ changes for every signature whereas the private key $d$ remains consistent.
- $e$ can be computed by anyone who knows the (presumably) public parameters $(R, D, m)$.

When the signer multiplies their private key $d$ with the challenge $e$, this results in another scalar value somewhere in $\mathbb{Z}\_n$ which they could only have computed if they knew $d$. For instance, someone with only $D$ and $e$ would have no idea how to compute $e \cdot d$.

So what's the point of adding $r$? Why not make the signature $s = ed$? Because $e$ is public, so any observer could compute the private key by inverting $e$.

$$
d = s \cdot e^{-1}
$$

This is why $r$ must be secret and uniformly random: These properties prevent an observer from being able to compute the signer's private key from the signature.

If an observer knew the $r$ value used on a signature $s$, they could compute the signer's private key.

$$
\begin{align}
 s &= r + ed        \\\\
ed &= s - r         \\\\
 d &= e^{-1}(s - r) \\\\
\end{align}
$$

Another common gotcha: $r$ must be different for every signature. If the same nonce $r$ is used in two different signatures $(s_1, s_2)$ made by the same private key on distinct messages $(m_1, m_2)$, then an observer can easily compute the private key used to sign both messages by solving a system of equations.

$$
\begin{aligned}
& e_1 = H(R\ \|\|\ D\ \|\|\ m_1) &&
  e_2 = H(R\ \|\|\ D\ \|\|\ m_2) \\\\
& s_1 = r + e_1 d &&
  s_2 = r + e_2 d \\\\
& r = s_1 - e_1 d &&
  r = s_2 - e_2 d \\\\
\end{aligned}
$$

$$
\begin{align}
  s_1 - e_1 d &= s_2 - e_2 d      \\\\
e_1 d - e_2 d &= s_1 - s_2        \\\\
 d(e_1 - e_2) &= s_1 - s_2        \\\\
 d &= \frac{s_1 - s_2}{e_1 - e_2} \\\\
\end{align}
$$

Interestingly, that definition of $d$ indicates something quite unexpected. $d$ is the _slope_ of the line connecting the points $(e_1, s_1)$ and $(e_2, s_2)$ on the Cartesian plane, but only if $r$ is reused between both signatures.

Contrastingly, if we used two different nonces $(r_1, r_2)$ when creating the two signatures, an observer cannot solve for $d$ without knowing either $r_1$ or $r_2$, because there is no usable system of equations.

$$
\begin{aligned}
& s_1 = r_1 + e_1 d &&
  s_2 = r_2 + e_2 d \\\\
& e_1 d = s_1 - r_1 &&
  e_2 d = s_1 - r_2 \\\\
& d = \frac{s_1 - r_1}{e_1} &&
  d = \frac{s_1 - r_2}{e_2} \\\\
\end{aligned}
$$

What if we used different nonces to sign the same message? Would this result in any Bad News™? No, because remember that the challenge $e$ also commits to the nonce.

$$
e = H(R\ \|\|\ D\ \|\|\ m)
$$

If the nonce changes, so does $e$. Even if $e$ only committed to $D$ and $m$, an attacker would still need to know $r_1$ or $r_2$ to compute $d$.

> but why is this so cool?

1. Schnorr is faster.
2. Schnorr is simpler to implement than ECDSA.
3. Schnorr signatures aren't malleable.
4. Schnorr [has very solid security proofs](https://eprint.iacr.org/2012/029).
5. <u>***Schnorr permits linear signature aggregation.***</u>

I bolded \#5 there because that one feature is _incredibly important_ for the future potential of Bitcoin.

## Aggregator or Crocodile?

Signature aggregation is ~not possible~ [very difficult](https://medium.com/cryptoadvance/ecdsa-is-not-that-bad-two-party-signing-without-schnorr-or-bls-1941806ec36f) in ECDSA. [ECDSA _Threshold signatures_ are perfectly achievable](https://eprint.iacr.org/2020/1390), and these are handy but nowhere near as easy or as fast as linear signature aggregation with Schnorr. And as if it needed to flex even harder, [Schnorr can do threshold signatures even better than ECDSA](https://eprint.iacr.org/2022/550).

When I say Schnorr Signatures are _linear,_ this means that the only operations needed for Schnorr are simple scalar addition and multiplication. Verification is the same: one only needs point-addition and point-multiplication to verify the signature. ECDSA on the other hand, requires modular multiplicative inversion to sign and verify.

This opaque-sounding explanation can be boiled down to one highly consequential fact:

**The sum of a set of Schnorr signatures on a given message is a _valid signature_ under the sum of the public keys which made those signatures.**

In other words, if a bunch of different signers cooperatively sign the same message, those signatures can be summed up to produce an _aggregated signature._ If one also sums up the pubkeys of those who signed to get an _aggregated pubkey,_ the aggregated signature will be valid under the aggregated pubkey.

## Naive Example

Let's say you have three parties with their own private and public key pairs. They each sample their own private random nonce.

| Name | Public Key | Private Key | Nonce |
|:----:|:----------:|:-----------:|:-----:|
| Alice | $D_a$ | $d_a$ | $r_a$ |
| Bob   | $D_b$ | $d_b$ | $r_b$ |
| Carol | $D_c$ | $d_c$ | $r_c$ |

They all want to sign the same message $m$, and naturally have agreed on the base point $G$ and hash function $H(x)$.

1. They each compute their own public nonce points independently.


$$
\begin{aligned}
& \text{Alice} &&
  \text{Bob}   &&
  \text{Carol} \\\\
& R_a = r_a G &&
  R_b = r_b G &&
  R_c = r_c G \\\\
\end{aligned}
$$

2. They agree on an aggregated nonce point $R$.

$$
\begin{align}
R &= R_a + R_b + R_c    \\\\
  &= r_aG + r_bG + r_cG \\\\
  &= (r_a + r_b + r_c)G \\\\
\end{align}
$$

3. They agree on an aggregated public key $D$.

$$
\begin{align}
D &= D_a + D_b + D_c     \\\\
  &= d_aG + d_bG + d_cG  \\\\
  &= (d_a + d_b + d_c)G  \\\\
\end{align}
$$

4. They each hash the message with this aggregated nonce point and pubkey.

$$
e = H(R\ \|\|\ D\ \|\|\ m)
$$

5. They each compute their share of the signature.

$$
\begin{aligned}
& \text{Alice} &&
  \text{Bob}   &&
  \text{Carol} \\\\
& s_a = r_a + e d_a &&
  s_b = r_b + e d_b &&
  s_c = r_c + e d_c \\\\
\end{aligned}
$$

6. They send each other their $s$ values and aggregate by summing them all up.

$$
s = s_a + s_b + s_c
$$

The final aggregated signature is $(R, s)$.

To verify, recall that a signature $(R, s)$ from pubkey $D$ is valid on message $m$ if:

$$e = H(R\ \|\|\ D\ \|\|\ m)$$
$$sG = R + eD$$

And this is going to be the case for our aggregated signature. Recall how Alice, Bob and Carol aggregated $s$.

$$
\begin{align}
s &= \overbrace{r_a + ed_a}^{s_a} +
     \overbrace{r_b + ed_b}^{s_b} +
     \overbrace{r_c + ed_c}^{s_c}              \\\\
  &= r_a + r_b + r_c + ed_a + ed_b + ed_c    \\\\
  &= \underbrace{r_a + r_b + r_c}\_{\text{Nonces}} +
     e(\underbrace{d_a + d_b + d_c}\_{\text{Private Keys}})    \\\\
\end{align}
$$

Our verification works out because by aggregating the signatures, we also aggregated the individual nonces and the private keys (multiplied by $e$). We can then factor out $e$, meaning we kinda multiplied it with an _aggregated private key,_ and added an _aggregated secret nonce,_ even though participants never exposed their private keys or secret nonces to one another.

Multiplying $s$ and $G$ will thus satisfy the equality.

$$
\begin{alignat}{3}
sG &= R                  &&+ eD                  \\\\
sG &= (r_a + r_b + r_c)G &&+ e(d_a + d_b + d_c)G \\\\
 s &= r_a + r_b + r_c    &&+ e(d_a + d_b + d_c)  \\\\
\end{alignat}
$$

## HOWEVER

This example has a hidden flaw if used as a multisignature protocol under adversarial conditions (when co-signers don't trust each other). _Can you see why?_

<sub><i>hint:</i> the attack vector is very early in the aggregation procedure.</sub>


<details>
  <summary><i>Tell me the answer already!</i></summary>

A naive protocol like this is vulnerable to a _Rogue Key Attack_ when co-signing with untrusted peers. This attack can be performed by whomever is _last_ to share their public key with the other signers.

Let's return to Alice, Bob, and Carol.

- Alice tells Bob and Carol her pubkey $D_a$.
- Bob tells Alice and Carol his pubkey $D_b$.
- Alice and Bob now expect Carol to share her public key.

Carol has a sneaky option here. She can give Alice and Bob a phony public key $D_c'$ which is actually the same as her public key but with Alice's key and Bob's key _subtracted from it_.

$$
D_c' = D_c - D_a - D_b
$$

Carol doesn't know the discrete log (private key) of $D_c'$, but that's OK, because when everyone computes the final aggregated public key, they'll sum each other's keys together, and _Alice and Bob's keys will cancel out._

$$
\begin{align}
D &= D_a + D_b + D_c'              \\\\
  &= D_a + D_b + (D_c - D_a - D_b) \\\\
  &= D_c                           \\\\
\end{align}
$$

Carol has just fooled Alice and Bob into agreeing to use an apparently aggregated key which _only Carol controls._

Neither Alice nor Bob would be able to distinguish between Carol's authentic key $D_c$ and the phoney key $D_c'$ because they don't know $D_c$ belongs to Carol! That's why they were sharing the keys in the first place.

Carol could also collude with Bob to exclude Alice's key from the final aggregated key, like so.

$$
\begin{align}
D_c' &= D_c - D_a               \\\\
D    &= D_a + D_b + D_c'        \\\\
     &= D_a + D_b + (D_c - D_a) \\\\
     &= D_b + D_c               \\\\
\end{align}
$$

### The Solution

Rogue Key Attacks can be fixed naively by requiring that each signer to prove she knows the private key for her public key. Such an affirmation is called _Knowledge-of-Secret-Key_ (KOSK). This is flawed because not every key I want to aggregate with is going to be fully under my control all the time. Perhaps I want to aggregate a public key right now, but I can only expect to learn its secret key next week (e.g. in a [Discreet Log Contract](https://dci.mit.edu/smart-contracts). Perhaps I want to aggregate a public key which _is itself an aggregated key,_ whose component secret keys are owned by 3rd parties.

Instead modern Bitcoin developers use a kind of commitment protocol to avoid the risk of rogue keys. This is what [_MuSig_](https://tlu.tarilabs.com/cryptography/The_MuSig_Schnorr_Signature_Scheme) offers. ~I'm looking forward to discussing MuSig in another post~ Take a look at [my article about MuSig](/cryptography/musig) to learn what all the fuss is about.

</details>

## Benefits

In combination with [Taproot](https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki), developers can embed arbitrary combinations of aggregated public keys into a single tweaked public key which encodes a highly complex array of possible spending conditions, but still looks like any old normal public key when used under normal conditions.

Bitcoin developers can use multisignature signing schemes like [MuSig](/cryptography/musig) and threshold signing protocols like [ROAST](https://eprint.iacr.org/2022/550) with much greater efficiency, security, and privacy than has ever been possible before with ECDSA.

Any given public key can now be an aggregation of colossal numbers of child keys and scripts and threshold public keys and much much more.
