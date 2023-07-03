---
title: MuSig1 - A Reasonably Secure Multisig Scheme
date: 2023-06-29
mathjax: true
categories:
  - cryptography
---

# Introduction

In [my last post](/cryptography/schnorr/) I droned on about how well Schnorr Signatures kick ECDSA in the teeth. I left off with a cliffhanger: Schnorr's oh-so-great _linear signature aggregation_ seems to be vulnerable to whomever shares their public key last.

Thus I felt it would be appropriate to drone on today over the elegant solution offered by MuSig. MuSig is a protocol [proposed by Maxwell, Poelstra, Seurin and Wuille](https://eprint.iacr.org/2018/068) which allows co-signers to cooperatively sign a common message without the need to trust each other, or prove _Knowledge-of-Secret-Key_ (KOSK).

There are currently three iterations of MuSig:

1. [InsecureMuSig - An _outdated and insecure_ 2-round version](https://eprint.iacr.org/archive/2018/68/20180118:124757)
2. [MuSig1 - The secure 3-round variant](https://eprint.iacr.org/2018/068)
3. [MuSig2 - The faster but slightly less secure 2-round variant](https://eprint.iacr.org/2020/1261)

\* <sub>The term _rounds_ means the number of communication round-trips required for a signing session.</sub>

This post covers _MuSig1:_ the secure 3-round multisignature variant. My goal is to make the at-first tricky-looking math behind MuSig1 feel more intuitive and approachable. To that end, you're in luck: MuSig1 is much simpler compared to MuSig2, which will make my job easier. MuSig2 is more arcane and will require a deal more work to firmly grasp. That's a task for another day though.

We will start from [the naive example of signature aggregation which I illustrated in the last article](/cryptography/schnorr/#Naive-Example), and solve one problem at a time to arrive at MuSig1.

## Notation

Just so we're all on the same page:

| Notation | Meaning |
|:--------:|---------|
| $G$ | The [base-point of the secp256k1 curve.](https://bitcoin.stackexchange.com/questions/58784/how-were-the-secp256k1-base-point-coordinates-decided) |
| $m$ | The message we're trying to sign (a byte array). |
|$H(x)$ | The SHA-256 hash function. |
|$n$ | The [_order_ of the secp256k1 curve](https://crypto.stackexchange.com/questions/53597/how-did-someone-discover-n-order-of-g-for-secp256k1). There are $n - 1$ possible valid non-zero points on the curve, plus the 'infinity' point (AKA zero). |
|$x \leftarrow \mathbb{Z}\_{n}$ | Sampling $x$ randomly from the set of integers modulo $n$. Note that we exclude zero when sampling. |
| $a\ \|\|\ b$ | Concatenation of the byte arrays $a$ and $b$. |

MuSig relies on _namespaced hash functions,_ which are denoted $H_{\text{foo}}(x)$ where $\text{foo}$ is the namespace of the hash. A namespaced hash function is a normal cryptographic hash function, but with some constant bits added to every hashed message which ensure that the output of the namespaced hash function can't be reused for other namespaces. One could define a namespaced hash function like so.

$$
H_{\text{foo}}(x) := H(\text{"foo"}\ \|\|\ H(x))
$$

# Rogue Keys

Let's return to Alice, Bob, and Carol in [my example from the Schnorr article](/cryptography/schnorr/#Naive-Example).

Our alphabet friends all anticipate signing the same messages but they do not yet know each other's public keys. They don't trust each other to give their honest public keys. Nobody is willing to share their public key yet, because others might collude to contribute a rogue key which gives the malicious parties sole ownership of the final aggregated pubkey.

| Name | Public Key | Private Key |
|:----:|:----------:|:-----------:|
| Alice | $D_a$ | $d_a$ |
| Bob   | $D_b$ | $d_b$ |
| Carol | $D_c$ | $d_c$ |

For example, Carol could wait for Alice and Bob to expose their public keys, and then declare hers as $D_c' = D_c - D_a - D_b$. After summing up all the public keys, Alice and Bob would compute an aggregated public key $D = D_c$, which gives sole to Carol.

The first and most obvious dragon we need to slay is the _Rogue Key Attack,_ [which I also introduced in my Schnorr Signatures article](/cryptography/schnorr/#HOWEVER).

## Option 1: KOSK

Rogue Keys can be avoided naively by requiring that each co-signer to prove she knows the private key for her public key. Such an affirmation is called _Knowledge-of-Secret-Key_ (KOSK).

> why does that work?

Carol picked $D_c'$ based on Alice and Bob's pubkeys, but the point she happened to choose is effectively a randomly sampled point on the curve, whose secret key Carol does not know. Forcing Carol to prove KOSK would prevent Alice and Bob from accepting such a maliciously-computed rogue key.

### The Problem

This is flawed because not every key I want to aggregate with is going to be fully under my control all the time. Perhaps I want to aggregate a public key right now, but I can only expect to learn its secret key next week (e.g. in a [Discreet Log Contract](https://dci.mit.edu/smart-contracts)). Perhaps I want to aggregate a public key which _is itself an aggregated key,_ whose component secret keys are owned by 3rd parties who are not online right now.

Ideally, we'd like to _avoid_ forcing co-signers to prove Knowledge-of-Secret-Key, because their keys may not wholly belong to them but they still want to be able to sign cooperatively with those keys. Yet at the same time, we cannot allow co-signers to compute their public keys based on the keys of their peers. So what's a cypherpunk to do?

## Option 2: Key Commitments

A slightly-less-obtuse solution would be to require each co-signer to commit to their public key ahead of time. Everyone shares their public keys only after everyone else in the cohort has already committed to theirs.

Imagine everyone putting their pubkeys into envelopes and placing those envelopes on a table for all to see. Once everyone has put their envelopes on the table (e.g. everyone is fully committed), the co-signers can start tearing them open and revealing pubkeys. Any pubkeys which weren't committed to (by placing them on the table) cannot be trusted.

By _committing in-advance_ to a public key, and then verifying the commitments of others, the co-signers ensure that nobody in their signing cohort has computed their public keys as a function of each other's public keys - i.e. every public key is chosen independently of each other.

### Example

A simple way to implement a key-commitment scheme would be to require each co-signer to provide a _namespaced hash of their public key_ before seeing anyone else's pubkey.

To lock each co-signer into their choice of pubkey, co-signers would each send this hash (AKA a _commitment_) to one-another before revealing their pubkeys. Once each co-signer receives commitments from everyone else, they can confidently share their pubkey with the rest of their peers. Upon receiving public keys from their peers, they verify all the commitments to make sure everyone behaved honestly in selecting their pubkeys.

$$
\begin{aligned}
& \text{Alice} &&
  \text{Bob}   &&
  \text{Carol} \\\\
& c_a = H_{\text{com}}(D_a) &&
  c_b = H_{\text{com}}(D_b) &&
  c_c = H_{\text{com}}(D_c) \\\\
\end{aligned}
$$

From Alice's perspective, she shares $c_a$ and receives $(c_b, c_c)$ from Bob and Carol. Once she has Bob and Carol's commitments she shares $D_a$ and receives $(D_b, D_c)$. She then check that $c_b = H_{\text{com}}(D_b)$ and that $c_c = H_{\text{com}}(D_c)$. If $D_b$ or $D_c$ do not match their respective commitments, Alice won't accept them.

This format prevents the "who-goes-first" problem: It no longer matters who exposes their commitments or keys first, _as long as each participant has everyone else's commitments in hand before sharing their pubkey._ The output of a namespaced hash function can't be used to compute a rogue pubkey. The namespacing also makes the commitments useless for anything except verifying key commitments. At the same time, it locks Alice, Bob, and Carol into their choice of pubkeys, which they committed to _before_ seeing each other's pubkeys.

### The Problem

This does work on paper, but not so well on silicon. It has a glaring gotcha: **Public keys cannot be reused between signing sessions.**

If Alice reveals her pubkey with Bob and Carol, then she can no longer safely use that key with a new unknown co-signer Dave. Dave comes into the co-signing cohort fresh, so Alice doesn't know his public key yet. Dave now has an opportunity to collude with Bob or Carol.

If Dave can convince Bob or Carol to give him Alice's pubkey $D_a$, Dave can compute a rogue public key to exclude Alice from the new aggregated key.

$$
\begin{align}
D_d' &= D_d - D_a                    \\\\
 D   &= D_a + D_b + D_c + D_d'       \\\\
     &= D_a + D_b + D_c + (D_d- D_a) \\\\
     &= D_b + D_c + D_d              \\\\
\end{align}
$$

Dave is able to do this before ever communicating with Alice, because he can learn her pubkey from Bob or Carol. Thus, we must now confront the practical problem of the key-commitment solution: **Once Alice has exposed her public key to _anyone,_ she can only ever use it to co-sign with pubkeys which were committed to before she revealed hers.** Any other new pubkeys could be rogue.

## Key Coefficients

Instead of committing to public keys ahead of time, what if the final aggregated key couldn't be predicted by a malicious party? This way, even if rogue keys can be selected by some co-signers, the resulting aggregated key would not be usable. This would be [the same result as if the malicious party had instead been a foolish party](https://en.wikipedia.org/wiki/Hanlon%27s_razor), having selected a random pubkey for which they knew of no existing secret key.

### Example

To arrange this, we might use _a namespaced hash of the co-signers' keys_ to scramble the final aggregated key. Let's say $L$ is a determinstic (e.g. lexically-sorted) encoding of Alice, Bob and Carol's public keys.

$$
L := \\{ D_a, D_b, D_c \\}
$$

Each co-signer could compute a namespaced hash of $L$ once all parties have shared their pubkeys.

$$
\alpha = H_{\text{agg}}(L)
$$

Some of the pubkeys in $L$ might be rogue, but that won't matter because of the next step. When computing the aggregated key, all parties multiply the whole sum of pubkeys by $\alpha$. This forms the final aggregated key $D$.

$$
D = \alpha(D_a + D_b + D_c)
$$

If $H$ is cryptographically secure, it will be [_preimage resistant_](https://crypto.stackexchange.com/questions/1173/what-are-preimage-resistance-and-collision-resistance-and-how-can-the-lack-ther). Carol will not be able to find a rogue key which would result in a compromised aggregated key, because she cannot predict the output of $H_{\text{agg}}(L)$. Even if Carol has a large set of keys which she controls, the best Carol can do is simply guess and check random rogue keys until she finds one which produces a compromised aggregated key $D$.

Nonces would be computed as they were in the naive aggregation example.

$$
\begin{aligned}
& \text{Alice} &&
  \text{Bob}   &&
  \text{Carol} \\\\
& r_a \leftarrow \mathbb{Z}\_n &&
  r_b \leftarrow \mathbb{Z}\_n &&
  r_c \leftarrow \mathbb{Z}\_n \\\\
& R_a = r_a G &&
  R_b = r_b G &&
  R_c = r_c G \\\\
\end{aligned}
$$

After sharing their public nonces with one-another, co-signers could each compute the aggregated nonce $R$.

$$
R = R_a + R_b + R_c
$$

Recall from [the previous article](/cryptography/schnorr/#Schnorr-Signatures) that a Schnorr signature $(R,s)$ on a message $m$ from public key $D$ can be verified with the following assertions.

$$e = H(R\ \|\|\ D\ \|\|\ m)$$
$$sG = R + eD$$

To make aggregated signatures valid for those equations, the signature must be aggregated in a way that allows $e$ to be factored out of the keys. To achieve this, partial signatures on a message $m$ could be computed as follows.

$$
\begin{aligned}
& \text{Alice} &&
  \text{Bob}   &&
  \text{Carol} \\\\
& s_a = r_a + \alpha e d_a &&
  s_b = r_b + \alpha e d_b &&
  s_c = r_c + \alpha e d_c \\\\
\end{aligned}
$$

The final signature would be aggregated so that $\alpha$ factors out alongside $e$.

$$
\begin{align}
s &= \overbrace{r_a + \alpha e d_a}^{s_a} +
     \overbrace{r_b + \alpha e d_b}^{s_b} +
     \overbrace{r_c + \alpha e d_c}^{s_c}                           \\\\
  &= r_a + r_b + r_c + \alpha e d_a + \alpha e d_b + \alpha e d_c   \\\\
  &= \underbrace{r_a + r_b + r_c}\_{\text{Nonces}} +
     e \alpha (\underbrace{d_a + d_b + d_c}\_{\text{Private Keys}}) \\\\
\end{align}
$$

We've really gotten somewhere with this idea! Rogue key attacks are no longer feasible against our fledgling multisignature protocol, because an attacker must play guess and check to figure out which rogue public key to declare to influence the resulting aggregated key, all while the attacker's peers are waiting impatiently for her response.

# A Subtler Attack

Guessing and checking isn't that great of an option, and so Carol can't practically trick Alice and Bob into using a key she fully controls. This _seems_ like it should accomplish all our goals, but _beware!_

Carol still has a chance to manipulate Alice and Bob into *signing* something they didn't intend to. When we're talking signatures with Bitcoin, a forgery is tantamount to the complete loss of one or more UTXOs. This attack is harder to understand than a Rogue Key attack, but don't let its obscurity fool you: The threat is very real. It is called [Wagner's Generalized Birthday Attack](https://www.iacr.org/archive/crypto2002/24420288/24420288.pdf).

This attack's inner workings are sophisticated, and it took me a deal of effort to fully comprehend them. I'll summarize here, and post another article later which will go into more detail on how the math works.

At first, Wagner's Attack seems similar to a Rogue Key Attack in that it requires the attacker to wait for other co-signers to reveal something first, and compute a response based on the revealed information. Although this attack requires some heavy computation, most of the work can be pre-computed in-advance by the attacker.

After opening a number of concurrent signing sessions with Alice and Bob, Carol waits for her co-signers to first reveal their nonces $(R_a, R_b)$. Carol gives Alice and Bob a phony nonce $R_c'$. Alice and Bob, none-the-wiser, sign a number of apparently benign messages using $R_c'$. If executed correctly, Carol can aggregate the signatures on those benign messages into a _forged signature_ on an evil message which Alice and Bob never saw. Luckily for Carol's CPU she can pre-compute most of the aforementioned heavy computations _before_ asking Alice and Bob to sign anything, and the more concurrent signing sessions she can open, the less work she must do in the pre-computation stage.

The fact that this works seems quite magical, but it's nothing more than some very eloquent analytical math working in tandem with an elegant search algorithm (Wagner's algorithm, to be exact). See [this paper](https://eprint.iacr.org/2018/417) for a full description of this attack applied to the CoSi algorithm, which is similar to MuSig1 but built on the assumption that each co-signer must provide a Knowledge-of-Secret-Key proof to avoid Rogue Key Attacks.

In the interest of brevity, I've omitted a full accounting of how this attack works, but know the important part is this: ***Wagner's attack depends on the attacker learning his victims' public nonces before revealing his own.*** If the attacker cannot choose his nonce as a function of his victims' nonces, all the precomputation he did will be wasted.

## Nonce Commitments

To prevent Carol from computing $R_c'$ as a function of $(R_a, R_b)$, we can reuse the concept of _commitments_ from [option 2](#Option-2-Key-Commitments), but applied to nonces instead of pubkeys.

Rather than having each co-signer share their public nonce directly, they must first _hash_ their nonce and send the hash output as a commitment to their peers. Upon receiving commitments from _all_ of their co-signers, co-signers can expose their real public nonces. Once everyone has shared commitments and then nonces, all can verify and rejoice, confident that nobody in the co-signing cohort attempted to change their nonce.

This avoids Wagner's Attack because the attacker cannot control the final aggregated nonce used in each concurrent signing session. As long as at least _one party_ in the signing cohort is honest, the final aggregated nonce will be an unbiased random curve point, chosen collaboratively by every co-signer (as it should be).

### Example

Alice, Bob and Carol each sample a random secret nonce, and use it to compute their public nonce as before.

Unlike the earlier protocols, they do not share their $R$ values with each other immediately. Instead they compute commitments $(t_a, t_b, t_c)$ as follows.

$$
\begin{aligned}
& \text{Alice} &&
  \text{Bob}   &&
  \text{Carol} \\\\
& r_a \leftarrow \mathbb{Z}\_n &&
  r_b \leftarrow \mathbb{Z}\_n &&
  r_c \leftarrow \mathbb{Z}\_n \\\\
& R_a = r_a G &&
  R_b = r_b G &&
  R_c = r_c G \\\\
& t_a = H_{\text{com}}(R_a) &&
  t_b = H_{\text{com}}(R_b) &&
  t_c = H_{\text{com}}(R_c) \\\\
\end{aligned}
$$

They share $(t_a, t_b, t_c)$ with one-another, in no particular order. Because each commitment reveals no information about its preimage (the nonce), no party learns anything by waiting to receive the commitments of others first.

Alice for example is not at risk, provided she receives $(t_b, t_c)$ before sharing $R_a$, and provided upon receiving $R_b$ and $R_c$ that she verifies they match the commitments $t_b$ and $t_c$. Note that Alice must not expose her nonce $R_a$ until she has _both_ $t_b$ _and_ $t_c$. Even if she receives $t_b$ from Bob, she cannot send $R_a$ to him, because Bob and Carol might be colluding, or they might be the same person. Giving $R_a$ to Bob before Carol commits to $t_c$ might allow Carol to give a rogue nonce.

Signatures would then be computed and aggregated as discussed in the last section.

$$
\begin{aligned}
& \text{Alice} &&
  \text{Bob}   &&
  \text{Carol} \\\\
& s_a = r_a + \alpha e d_a &&
  s_b = r_b + \alpha e d_b &&
  s_c = r_c + \alpha e d_c \\\\
\end{aligned}
$$

$$
s = s_a + s_b + s_c
$$

## One Last Caveat

Alright, I have to admit I'm stumped about the next design choice. As it is, this protocol seems secure, but there is still one minor difference between the co-signing protocol I've described and the official protocol described in [the MuSig1 paper](https://eprint.iacr.org/2018/068).

Recall we defined $L$ to be a determinstic (sorted) encoding of Alice, Bob and Carol's public keys.

$$
L := \\{ D_a, D_b, D_c \\}
$$

We then hashed $L$ to produce the signing cohort's key coefficient. This coefficient is multiplied with each party's public key to produce the aggregated pubkey $D$.

$$
\alpha = H_{\text{agg}}(L)
$$
$$
D = \alpha(D_a + D_b + D_c)
$$

When computing signatures, each co-signer computes their partial signature by multiplying their private key by the same key coefficient $\alpha$.


$$
\begin{aligned}
& \text{Alice} &&
  \text{Bob}   &&
  \text{Carol} \\\\
& s_a = r_a + \alpha e d_a &&
  s_b = r_b + \alpha e d_b &&
  s_c = r_c + \alpha e d_c \\\\
\end{aligned}
$$


### Would the _Real_ MuSig Please Stand Up?

In the protocol I just described, we have been using a single key coefficient $\alpha$ which is common to the whole cohort. In the real MuSig1 protocol, _each co-signer has their own key coefficient,_ which everyone else can compute independently.

Co-signer-specific key coefficients $(\alpha_a, \alpha_b, \alpha_c)$ are computed as a hash of $L$ concatenated with the public key of one particular co-signer.


$$
\begin{aligned}
& \text{Alice} &&
  \text{Bob}   &&
  \text{Carol} \\\\
& \alpha_a = H_{\text{agg}}(L\ \|\|\ D_a) &&
  \alpha_b = H_{\text{agg}}(L\ \|\|\ D_b) &&
  \alpha_c = H_{\text{agg}}(L\ \|\|\ D_c) \\\\
\end{aligned}
$$

When aggregating public keys, $D$ will be the sum of each public key multiplied by its respective key coefficient.

$$
D = \alpha_a D_a + \alpha_b D_b + \alpha_c D_c
$$

Each co-signer can easily compute the key coefficients of their peers and determine $D$ independently, provided they have a full list $L$ of the cohort's pubkeys.

When signing, each co-signer computes a partial signature by multiplying their private key by **their own key coefficent**.

| Name | Signature |
|:----:|:---------:|
| Alice | $s_a = r_a + \alpha_a e d_a$ |
| Bob   | $s_b = r_b + \alpha_b e d_b$ |
| Carol | $s_c = r_c + \alpha_c e d_c$ |

The aggregated signature can be broken down as follows.

$$
\begin{align}
s &= \overbrace{r_a + \alpha_a e d_a}^{s_a} +
     \overbrace{r_b + \alpha_b e d_b}^{s_b} +
     \overbrace{r_c + \alpha_c e d_c}^{s_c}                              \\\\
  &= r_a + r_b + r_c + \alpha_a e d_a + \alpha_b e d_b + \alpha_c e d_c  \\\\
  &= \underbrace{r_a + r_b + r_c}\_{\text{Nonces}} +
     e (\underbrace{\alpha_a d_a + \alpha_b d_b + \alpha_c d_c}\_{\text{Private Keys and Key Coefficients}}) \\\\
\end{align}
$$

> but why?

Great question. I found no justification for this decision anywhere online, including the MuSig1 whitepaper. The only algebraic distinction between this approach and a global key coefficient $\alpha$ is that with key-specific coefficients, they cannot be factored out from the private keys alongside $e$, since they are distinct in each term $\alpha_a d_a$, $\alpha_b d_b$, etc. But the motivation for this apparently intentional design choice is not clear to me. A global key coefficient would be faster for large signing cohorts, since each co-signer would only need to run $H(L)$ once, instead of running it once for every co-signer in the cohort.

It's possible the MuSig1 authors made this choice to streamline their security proof, and not because it was essential for the security of the scheme itself. Nevertheless, best not to go off and implement MuSig1 with global key coefficients, just in case.

If anyone is aware of the intent behind this choice or why a global key coefficient $\alpha$ would be Bad News™, please [let me know](mailto:conduition@proton.me)! Or [submit a pull request to fix this article](https://github.com/conduition/conduition.io).

# The Real MuSig1 Protocol

After a long journey, we've arrived at the _almost_ fully justified MuSig1 protocol. Let's give Alice, Bob and Carol one more try at signing cooperatively.

## 1. Key Aggregation

Co-signers share their public keys with one-another. Everyone can now compute each other's key coefficients, and thereby compute the aggregated pubkey.

$$
\begin{align}
       L &= \\{ D_a, D_b, D_c \\}                      \\\\
\alpha_a &= H_{\text{agg}}(L\ \|\|\ D_a)               \\\\
\alpha_b &= H_{\text{agg}}(L\ \|\|\ D_b)               \\\\
\alpha_c &= H_{\text{agg}}(L\ \|\|\ D_c)               \\\\
       D &= \alpha_a D_a + \alpha_b D_b + \alpha_c D_c \\\\
\end{align}
$$

The pseudo-random key coefficients $(\alpha_a, \alpha_b, \alpha_c)$ prevent any co-signers from executing a Rogue Key Attack, because they cannot analytically determine which rogue public key to offer to bring $D$ under their control.

## 2. Nonce Commitments

Each co-signer samples a random secret nonce and privately computes the corresponding public nonce. They hash the public nonce into a commitment.

$$
\begin{aligned}
& \text{Alice} &&
  \text{Bob}   &&
  \text{Carol}                    \\\\
& r_a \leftarrow \mathbb{Z}\_n &&
  r_b \leftarrow \mathbb{Z}\_n &&
  r_c \leftarrow \mathbb{Z}\_n    \\\\
& R_a = r_aG &&
  R_b = r_bG &&
  R_c = r_cG                      \\\\
& t_a = H_{\text{com}}(R_a) &&
  t_b = H_{\text{com}}(R_b) &&
  t_c = H_{\text{com}}(R_c)       \\\\
\end{aligned}
$$

The nonce commitments $(t_a, t_b, t_c)$ are shared at will amongst co-signers. _Note that nonce commitments can be safely cached and pre-shared en masse to improve round-trip performance without endangering security._

## 3. Message Choice

The message to sign $m$ must be agreed upon.

It is important that $m$ is fixed _before_ nonces are revealed, otherwise [Wagner's Attack will rear its ugly head once more](https://medium.com/blockstream/insecure-shortcuts-in-musig-2ad0d38a97da).

## 4. The Big Nonce Reveal

Co-signers reveal their nonces $(R_a, R_b, R_c)$ to one-another and verify the nonces match their respective commitments $(t_a, t_b, t_c)$.

$$
\begin{aligned}
& \text{Alice} &&
  \text{Bob}   &&
  \text{Carol}                 \\\\
& t_b = H_{\text{com}}(R_b) &&
  t_a = H_{\text{com}}(R_a) &&
  t_a = H_{\text{com}}(R_a)    \\\\
& t_c = H_{\text{com}}(R_c) &&
  t_c = H_{\text{com}}(R_c) &&
  t_b = H_{\text{com}}(R_b)    \\\\
\end{aligned}
$$

If anyone's nonce does not match their commitment, the protocol must enforce that the exposed nonces are discarded and will not be used again. One could also retry from step 2 with fresh nonces.

Once a co-signer possesses the public nonces of their peers, they can compute the aggregated public nonce $R$.

$$
\begin{align}
R &= R_a + R_b + R_c       \\\\
  &= r_a G + r_b G + r_c G \\\\
  &= (r_a + r_b + r_c)G    \\\\
\end{align}
$$

## 5. Challenge Hashing

The nonce $R$, the aggregated pubkey $D$, and the message $m$ are hashed with a namespaced hash function to produce the challenge $e$.

$$
e = H_{\text{sig}}(R\ \|\|\ D\ \|\|\ m)
$$

Each co-signer can compute $e$ independently once $m$ is agreed upon and all nonces are known.

## 6. Partial Signing

Co-signers compute their partial signatures $(s_a, s_b, s_c)$ by multiplying their key coefficient, their private key, and the challenge $e$. They add their secret nonces on top to obscure their private key.

$$
\begin{aligned}
& \text{Alice} &&
  \text{Bob}   &&
  \text{Carol}                  \\\\
& s_a = r_a + \alpha_a e d_a &&
  s_b = r_b + \alpha_b e d_b &&
  s_c = r_c + \alpha_c e d_c    \\\\
\end{aligned}
$$

## 7. Signature Aggregation

The partial signatures can be shared with other participants at will.

Once each co-signer has $(s_a, s_b, s_c)$, they can aggregate them into the final signature $(R, s)$.

$$
s = s_a + s_b + s_c
$$

Co-signers already learned the aggregated nonce $R$ in step 4.

Note that there is a "who-goes-first" problem here. Alice, Bob and Carol cannot all learn each other's partial signatures simultaneously. Whomever is last to share their signature could "run off with the bag", so to speak, learning the final aggregated signature secret $s$ without letting anyone else compute it.

This is commonly called a _free option problem,_ and unfortunately there is no way around it: Someone is going to learn $s$ first, so whatever the cohort is signing had better be set up with the expectation that one party might have the option to use the signature while others cannot.

## 8. Signature Verification

Verifying this signature is exactly the same as verifying any normal Schnorr Signature $(R, s)$ with a single public key $D$, provided the verifier knows to use the correct hash function $H_{\text{sig}}$.

$$
e = H_{\text{sig}}(R\ \|\|\ D\ \|\|\ m)
$$
$$
sG = R + eD
$$

This will be correct for the aggregated signature.

$$
\begin{align}
s &= \overbrace{r_a + \alpha_a e d_a}^{s_a} +
     \overbrace{r_b + \alpha_b e d_b}^{s_b} +
     \overbrace{r_c + \alpha_c e d_c}^{s_c}                              \\\\
  &= r_a + r_b + r_c + \alpha_a e d_a + \alpha_b e d_b + \alpha_c e d_c  \\\\
  &= \underbrace{r_a + r_b + r_c}\_{\text{Nonces}} +
     e (\underbrace{\alpha_a d_a + \alpha_b d_b + \alpha_c d_c}\_{\text{Private Keys and Key Coefficients}}) \\\\
\end{align}
$$

Recall the definition of the aggregated nonce and aggregated public key.

$$
\begin{align}
R &= R_a + R_b + R_c       \\\\
  &= r_a G + r_b G + r_c G \\\\
  &= (r_a + r_b + r_c)G    \\\\
D &= \alpha_a D_a + \alpha_b D_b + \alpha_c D_c    \\\\
  &= (\alpha_a d_a + \alpha_b d_b + \alpha_c d_c)G \\\\
\end{align}
$$

Therefore:

$$
\begin{align}
sG &= (r_a + r_b + r_c)G &&+ e(\alpha_a d_a + \alpha_b d_b + \alpha_c d_c)G \\\\
   &= R                  &&+ eD                                             \\\\
\end{align}
$$

## Conclusion

I have a soft-spot for MuSig1 over MuSig2, because it is dumb-simple compared to the magic of MuSig2.

MuSig2 has some fancy sauce that helps it avoid the whole nonce-commitment issue, without leaving it vulnerable to Wagner's Attack. Perhaps another day I'll discuss MuSig2, but I think next I want to cover Wagner's Attack in more detail. It's surprising how such an apparently implausible attack is made trivial by something as simple as a list-searching algorithm, and I find the mechanics very much worth discussing.
