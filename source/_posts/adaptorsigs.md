---
title: The Riddles of Adaptor Signatures
date: 2023-09-08
mathjax: true
category: scriptless
description: A detailed description of the math behind Schnorr Adaptor Signatures.
---

One of the most powerful tricks unlocked by [Schnorr Signatures](/cryptography/schnorr/) is the concept of Adaptor Signatures. They are a quintessential building block of modern Bitcoin scriptless contract design, used in [off-chain payment channels](https://eprint.iacr.org/2020/476.pdf), [atomic swaps](https://github.com/BlockstreamResearch/scriptless-scripts/blob/master/md/atomic-swap.md), and [Discreet Log Contracts](https://suredbits.com/discreet-log-contracts-part-2-how-they-work-adaptor-version/).

Adaptor Signatures have been thoroughly covered in numerous other resources. In my opinion, the best resource for the detail-oriented reader is [this paper by Lloyd Fournier](https://raw.githubusercontent.com/LLFourn/one-time-VES/master/main.pdf), although [the original post by Andrew Poelstra](https://lists.launchpad.net/mimblewimble/msg00086.html) is still very interesting. [Bitcoin Optech has an article on adaptor signatures as well](https://bitcoinops.org/en/topics/adaptor-signatures/).

This horse has already been kicked well beyond death. Others have done a much better job than I could in covering the mechanics of adaptor signatures. The unique take I would like to bring to the table are some questions (and solutions) regarding how adaptor signatures work in different edgecases common to modern Bitcoin contract design.

When designing scriptless smart contracts on Bitcoin, perhaps one might wonder:

- How would we use adaptor signatures in aggregated multisignature schemes like [MuSig](/cryptography/musig/)?
- How do we use adaptor signatures to reveal multiple secrets at once instead of only one?
- How can an adaptor signature be meaningfully revoked?

In this article, I'll give a review of the math governing adaptor signatures, and then use this as a springboard to answer those burning questions. Let's dive in.

# Review

It wouldn't be right for me to just assume everyone knows what an adaptor signature is, so I'll briefly describe how they work mechanically. If you are already familiar with adaptor signature basics, [click here to skip ahead](#Multisignature).

The ECC math behind adaptor signatures is pretty simple. If you know the difference between a _point_ and a _scalar_, you should be fine. If you don't, then before continuing, I would very much suggest a perusal of my [elliptic curve cryptography resources](/cryptography/ecc-resources/), should you not already happen to be familiar with elliptic curves.

## The VES Concept

An adaptor signature is also known (perhaps more intuitively) as a _verifiably encrypted signature_, or VES. In the context of most modern Bitcoin usage, it is a [Schnorr signature](/cryptography/schnorr/) made by a given key on a message, but _encrypted_ so that it will only be considered valid by other Bitcoin clients if some special secret number is added to the signature.

Signatures can be _encrypted_ in this way in an asymmetric fashion, such that one only needs a public key, called an adaptor point, to encrypt a signature.

While the signature is not valid under the traditional Schnorr verification algorithm, it retains the very useful property of still being verifiable, just not as a normal Schnorr signature would be. This allows a party who receives an adaptor signature to be 100% confident that if they receive the decryption key, they'll have a valid signature.

The signature and the decryption key are also bound together. If one is revealed, so is the other. This is very useful for use cases on Bitcoin and other cryptocurrencies, where signatures tend to be broadcast onto a _public_ blockchain.

We'll be constructing our adaptor signatures using Schnorr signature algorithms. Before continuing, if you're not already familiar with Schnorr signatures, I would highly recommend reading [my article on Schnorr](/cryptography/schnorr/) which explains how Schnorr signatures are created normally.

## Procedure

- Let $G$ be the secp256k1 curve generator point.
- Let $n$ be the order of the curve.
- Let $\mathbb{Z}\_n$ be the set of integers mod $n$.
- Let $x \leftarrow \mathbb{Z}\_n$ denote sampling a random scalar from $\mathbb{Z}\_n$.
- Let $H_{\text{sig}}(x)$ be a cryptographically secure hash function, specifically used for computing Schnorr signature hashes.
- Let $m$ be the message to be signed.
- Let $a \in \mathbb{Z}\_n$ be the private key of the signer, Alice.
- Let $A = aG$ be Alice's public key.
- Let $Y$ be the adaptor point, AKA the encryption key which Alice will use to lock her signature.
- Let $y$ be the discrete log (secret key) of $Y$, such that $Y = yG$.
  - ***Alice does not need to know $y$.***

Alice wants to create a verifiably encrypted signature (VES) on some message $m$. She wants the signature to only be usable by someone who knows $y$ (the discrete log of the adaptor point $Y$). Maybe Alice knows $y$ herself, or maybe not - depends on the use-case.

To create an adaptor signature, Alice follows the same the protocol as to create a normal Schnorr Signature, except she modifies her nonce so that the signature won't be considered valid by itself.

She starts by sampling a random nonce $r$.

$$ r \leftarrow \mathbb{Z}\_n $$

However, unlike a traditional Schnorr signature, we will denote the public nonce point as $\hat{R}$, with the little hat signifying that this public nonce is _encrypted_.

$$ \hat{R} = r G $$

Next, Alice computes the true _adapted_ public nonce point, by adding the adaptor point $Y$.

$$ R = \hat{R} + Y $$

Alice computes the encrypted Schnorr signature by committing the challenge $e$ to the _adapted public nonce_.

$$ e = H_{\text{sig}}(R\ \|\|\ A\ \|\|\ m) $$
$$ \hat{s} = r + e a $$

Alice can now distribute the VES, AKA the adaptor signature, $(\hat{R}, \hat{s})$.

## Exploration

By setting $R = \hat{R} + Y$, Alice locks the signature scalar $\hat{s}$ to $Y$, such that it will only be canonically valid if we also add $y$ to it. Nobody will be able to use the signature until they know $y$.

To see why, try to verify the encrypted signature $(\hat{R}, \hat{s})$ on the public key $A$ using the standard Schnorr signature verification equation.

$$ e' = H_{\text{sig}}(\hat{R}\ \|\|\ A\ \|\|\ m) $$
$$
\begin{align}
\hat{s} G &\stackrel{?}{=} \hat{R} + e' A \\\\
          &\stackrel{?}{=} r G + e' a G \\\\
          &\stackrel{?}{=} (r + e' a) G \\\\
\end{align}
$$

But Alice computed her challenge $e$ using the _adapted public nonce_ $R$, not the encrypted nonce $\hat{R}$.

$$ e = H_{\text{sig}}(R\ \|\|\ A\ \|\|\ m) $$

This verification will fail because $e' \ne e$, so $\hat{s} G \ne \hat{R} + e' A$.

Okay, what if we add $Y$ to the encrypted nonce $\hat{R}$, and try to verify the signature as $(R, \hat{s})$? Since $Y$ is a _public key_ it should not be hard to learn. Will the signature verify correctly then?

$$ R = \hat{R} + Y $$
$$ e = H_{\text{sig}}(R\ \|\|\ A\ \|\|\ m) $$
$$
\begin{align}
\hat{s} G &\stackrel{?}{=} R + e A \\\\
          &\stackrel{?}{=} \hat{R} + Y + e A \\\\
          &\stackrel{?}{=} r G + y G + e a G \\\\
          &\stackrel{?}{=} (r + y + e a) G \\\\
\end{align}
$$

This does not pass verification either, but this time we observe how we could adjust $\hat{s}$ to make the signature valid. Alice computed $\hat{s}$ as $r + e a$, but the right side of the equation clearly expects $y$ to be included. A valid signature scalar should thus be $s = \hat{s} + y$. This would pass verification, combined with the adapted public nonce $R$.

$$ R = \hat{R} + Y $$
$$ e = H_{\text{sig}}(R\ \|\|\ A\ \|\|\ m) $$
$$
\begin{align}
s &= \hat{s} + y \\\\
  &= r + e a + y \\\\
\end{align}
$$
$$
\begin{align}
s G &= R + e A \\\\
    &= \hat{R} + Y + e A \\\\
    &= r G + y G + e a G \\\\
    &= (r + y + e a) G \\\\
\end{align}
$$

We can denote the correct _adapted_ signature as $(R, s)$. This signature appears to any outside observer to be a normal, valid, Schnorr signature.

## Verification

Say Alice creates a Bitcoin transaction with an adaptor signature $(\hat{R}, \hat{s})$ and gives it to Bob. Bob will be able to use $(\hat{R}, \hat{s})$ to publish the transaction if he knows $y$, and can compute $s = \hat{s} + y$.

However, what if Bob does _not yet know_ $y$, but can expect to learn it in the future? $y$ might only be revealed through some future event. Bob must be able to _verify_ that $(\hat{R}, \hat{s})$ will become usable if he learns $y$. This is where the "verifiably" in "verifiably encrypted signatures" comes in.

If given the adaptor point $Y$, Bob can verify $(\hat{R}, \hat{s})$ is a valid adaptor signature from Alice's key $A$ on the message $m$.

$$ R = \hat{R} + Y $$
$$ e = H_{\text{sig}}(R\ \|\|\ A\ \|\|\ m) $$
$$
\begin{align}
\hat{s} G &= \hat{R} + e A \\\\
          &= rG + e a G \\\\
          &= (r + e a) G \\\\
\end{align}
$$

If this check passes, Bob is certain that upon learning $y$, he can _adapt_ Alice's signature $(\hat{R}, \hat{s})$ into a valid signature $(R, s)$.

## Revealing

Adaptor signatures have a property which is very useful for any public-ledger cryptocurrency like Bitcoin. If a decrypted signatures $(R, s)$ is revealed to someone who knows the _encrypted_ signature $(\hat{R}, \hat{s})$ such as Alice, that party can compute the adaptor secret $y$.

$$ y = s - \hat{s} $$

This helpful property is exploited heavily in Bitcoin scriptless smart contract design. I won't go into any examples for now as I believe there are plenty of other resources on the subject. [Check out the Bitcoin Optech article](https://bitcoinops.org/en/topics/adaptor-signatures/) for more relevant links.

## Deferred Encryption

It is also possible to encrypt a valid Schnorr signature $(R, s)$ after the fact, without access to the private key which created it, as long as we know the adaptor secret $y$.

If we know $y$, we can simply reverse the decryption process to compute an encrypted signature.

$$ \hat{R} = R - Y $$
$$ \hat{s} = s - y $$


# Multisignature

How do adaptor signatures work for multisignature contexts?

Say Alice and Bob have some funds locked in a simple 2-of-2 multisignature contract which is spendable if Alice and Bob both sign the transaction. Alice knows the adaptor point $Y = yG$ and wants to give Bob an adaptor signature which he can use to claim the funds if Bob learns the adaptor secret $y$. If Bob does use $y$ to decrypt the signature and publish the transaction, Alice wants to be able to also learn $y$.

In this section we'll examine how to use adaptor signatures to address this scenario in both legacy and modern multisignature protocols.

## On-Chain (legacy)

In legacy Bitcoin contracts, it was common practice to use on-chain multisig script opcodes, such as `OP_CHECKMULTISIG`. Anyone claiming the contract would submit a threshold number of ECDSA signatures from a selection of keys hardcoded into the locking script.

To use an adaptor signature in our example scenario context is relatively straightforward. Alice simply signs whatever transaction she wants to lock behind the adaptor point $Y$ using the adaptor-signing protocol I described above. Alice forwards this signature to Bob and she's done.

If Bob uses $y$ to decrypt the signature and publish the transaction, Alice can easily identify it on the blockchain and learn $y$ from her decrypted signature, as the adapted signature scalar $s$ will be included right there plain-as-day in the spending script.

## Off-Chain (modern)

With support for [Schnorr signatures](/cryptography/schnorr/) now active in Bitcoin's Mainnet for several years, this practice is being phased out in favor of off-chain aggregated multisignature protocols like [MuSig](/cryptography/musig/) and [FROST](https://eprint.iacr.org/2020/852). Signatures created by aggregation appear to be normal Schnorr signatures: completely indistinct from signatures created by solo-signers. This is a huge boost to user privacy, because it makes all transactions more fungible. One cannot tell from simply observing the public blockchain whether a Schnorr signature was the product of aggregating hundreds of signatures from disparate parties, or the signature of a single person.

But if her signature is aggregated with Bob's, how can Alice learn $y$ when Bob reveals the whole signature?

### Example

Let's walk through an example signing session with MuSig1 to find out how an adaptor signature is created with MuSig. If you're not already familiar with MuSig, [check out my article](/cryptography/musig/) to learn how and why this approach works.

- Let $b$ be Bob's secret key, with corresponding public key $B = bG$.

1. Alice and Bob compute their aggregated public key $D$.

$$ L = \\{ A, B \\} $$
$$
\alpha_a = H_{\text{agg}}(L\ \|\|\ A) \quad \quad
\alpha_b = H_{\text{agg}}(L\ \|\|\ B)
$$
$$ D = \alpha_a A + \alpha_b B $$

2. Alice and Bob sample their random nonces $r_a$ and $r_b$.

$$ r_a \leftarrow \mathbb{Z}\_n \quad \quad r_b \leftarrow \mathbb{Z}\_n $$

3. Alice and Bob compute their public nonces $R_a$ and $R_b$.

$$ R_a = r_a G \quad \quad R_b = r_b G $$

4. Alice and Bob send each other their nonce commitments $t_a$ and $t_b$

$$ t_a = H_{\text{com}}(R_a) \quad \quad t_b = H_{\text{com}}(R_b) $$

5. Alice and Bob agree on a message $m$ to sign.

6. Once they have received each other's commitments, Alice and Bob send each other their nonces $R_a$ and $R_b$.

***ADAPTOR STUFF STARTS HERE.***

7. Alice and Bob can independently compute the aggregated encrypted public nonce $\hat{R}$, and the _adapted_ public nonce $R$.

$$ \hat{R} = R_a + R_b $$
$$ R = \hat{R} + Y $$


8. Alice and Bob each use the adapted public nonce to independently compute the challenge hash $e$.

$$ e = H_{\text{sig}}(R\ \|\|\ D\ \|\|\ m) $$

9. Alice and Bob both compute their partial signatures $s_a$ and $s_b$ on the message.

$$
s_a = r_a + e \alpha_a a \quad \quad
s_b = r_b + e \alpha_b b \\\\
$$

10. Each co-signer can now ([cautiously](#Free-Option-Problem)) share their partial signatures and aggregate them to produce the aggregated encrypted signature scalar $\hat{s}$.

$$ \hat{s} = s_a + s_b $$

The final aggregated adaptor signature can now be computed as $(\hat{R}, \hat{s})$, which is effectively the same as any other adaptor signature from a solo-signer. Once Bob knows $y$, he can adapt it by computing

$$ R = \hat{R} + Y $$
$$ s = \hat{s} + y $$

The adapted signature $(R, s)$ will verify correctly, just as with a regular MuSig signature.

$$ e = H_{\text{sig}}(R\ \|\|\ D\ \|\|\ m) $$
$$
\begin{align}
sG &= R + e D \\\\
   &= \hat{R} + Y + e D \\\\
   &= R_a + R_b + Y + e D \\\\
   &= r_aG + r_bG + yG + e (\alpha_a a + \alpha_b b)G \\\\
   &= (r_a + r_b + y + e (\alpha_a a + \alpha_b b))G \\\\
   &= (r_a + r_b + e \alpha_a a + e \alpha_b b + y)G \\\\
   &= (\underbrace{r_a + e \alpha_a a}\_{\text{Alice's signature}} + \underbrace{r_b + e \alpha_b b}\_{\text{Bob's signature}} + y)G \\\\
   &= (s_a + s_b + y)G \\\\
   &= (\hat{s} + y)G \\\\
\end{align}
$$

The encrypted signature $(\hat{R}, \hat{s})$ can even be independently verified by someone who knows $Y$.

$$ R = \hat{R} + Y $$
$$ e = H_{\text{sig}}(R\ \|\|\ D\ \|\|\ m) $$
$$ \hat{s}G = \hat{R} + e D $$

### Free Option Problem

**Care must be taken at the final step.** Whichever party shares their partial signature first might _lose the ability to learn the adaptor secret $y$._

For example if Alice were to send $s_a$ first to Bob, then Bob might take Alice's partial signature and refuse to give his own to Alice. Bob could wait to learn $y$ and once he does, he can use it to compute the adapted signature scalar $s$.

$$ \hat{s} = s_a + s_b $$
$$ s = s_a + s_b + y $$

Bob can publish $s$ to the blockchain, but upon seeing $s$, Alice won't be able to compute $y = s - \hat{s}$ from it, because _Alice never learned Bob's partial signature $s_b$,_ and so cannot compute $\hat{s}$.

In an adversarial multisignature scenario where one party - Bob, in our example - already knows, or is expected to learn the adaptor secret $y$ first, it is crucial for his counterparty Alice to enforce that Bob must give his partial signature first.

Bob should have no problem doing this. If Bob generated $y$, he can be sure Alice does not yet know $y$, and thus she cannot adapt his signature to make use of it on-chain without further help from Bob. Similarly, if Bob expects to learn the adaptor secret $y$ through a private channel which Alice cannot eavesdrop on, he can be reasonably confident his partial signature will not be of material benefit to Alice without Bob's cooperation.

If both parties expect to learn $y$ simultaneously at the same time in the future, such as through a Discreet Log Contract Oracle, then the order of signature sharing is not as important.

## Generalizing

The same essential principle of this approach holds for any other aggregated multisignature schemes like MuSig2 or [FROST](https://eprint.iacr.org/2020/852): We follow the same steps as the normal protocol, but _adapt_ the aggregated nonce $\hat{R}$ with the adaptor point $Y$ _before_ hashing it. Everyone in the signing group who does this will generate partial signatures which, once aggregated, will only be valid if the adaptor secret $y$ is added to the final aggregated signature.

## Cooperation

If some in the signing group are unaware of the adaptor point $Y$ and do not cooperate to construct the aggregated adaptor signature, they will instead compute the challenge hash as $e' = H_{\text{sig}}(\hat{R}\ \|\|\ D\ \|\|\ m)$. Signatures created in this way will be just like a standard (non-adaptor) partial signature, and won't be compatible with the partial signatures created by those who _are_ using the adaptor point $Y$.

It is important that every co-signer cooperates and is aware of the same adaptor point $Y$ which should be used to adapt the aggregated nonce.

Technically it is possible for one co-signer to surreptitiously adapt their public nonce before committing to and sharing it with other co-signers. In the above example, Alice could compute her public nonce as $R_a = r_a G + Y$ without Bob knowing. Alice and Bob's partial signatures would then sum to the same aggregated adaptor signature $(\hat{R}, \hat{s})$.

However, if other co-signers are not aware of this, they will lay blame on the individual who did so without the consent of the rest of the signing cohort. Alice's partial signature $s_a = r + e \alpha_a a$ will not be considered valid by the rest of the group, who may not be aware of the adaptor point $Y$.

Here we see there is a slight disadvantage to using an aggregated multisignature approach with adaptor signatures: ***We require interactive cooperation from other signers*** to be able to construct valid adaptor signatures. Otherwise, the construction is quite simple.

# Multi-Adaptors

A single adaptor signature usually corresponds to a single adaptor point and secret pair $(y, Y)$. Revealing the adaptor secret $y$ reveals the signature scalar $s$, and vice-versa.

But what if we want a single adaptor signature to require knowledge of _two_ separate secrets $y_1$ and $y_2$ to decrypt? Or if we want _either_ secret to be sufficient?

## The "And" Case

Let's consider a case where Bob knows two secrets $y_1$ and $y_2$, and wants to give Alice an adaptor signature which requires her to know both $y_1$ AND $y_2$ to decrypt Bob's signature.

This approach is simple: Merely aggregate the two secrets together and use the sum $y'$ as the adaptor secret.

$$ y' = y_1 + y_2 $$
$$ Y_1 = y_1 G \quad \quad Y_2 = y_2 G $$
$$
\begin{align}
Y' &= Y_1 + Y_2 \\\\
   &= y_1 G + y_2 G \\\\
   &= (y_1 + y_2) G \\\\
   &= y' G \\\\
\end{align}
$$

Alice and Bob can then construct an adaptor signature with the adaptor point $Y'$. Alice would need to know both $y_1$ and $y_2$ to compute $y'$ and thus decrypt the signature successfully. Alice could verify that $Y_1 + Y_2 = Y'$, confirming that learning the secrets $y_1$ and $y_2$ would give her $y'$, and thus the means to decrypt the signature. If $y_1$ and $y_2$ are unrelated random secrets, then learning $y_1$ or $y_2$ individually would reveal no information about the sum adaptor secret $y'$.

This is a one-way trick though. When the adapted signature scalar $s$ is revealed, an observer who knows only the encrypted signature $\hat{s}$ would learn only $y' = s - \hat{s}$, without learning anything about its composite values $y_1$ or $y_2$.

$$
\begin{align}
s &= \hat{s} + y' \\\\
y' &= s - \hat{s} \\\\
   &= \overbrace{y_1}^{?} + \overbrace{y_2}^{?} \\\\
\end{align}
$$

Perhaps we _want_ the adaptor signature bearer to learn both $y_1$ and $y_2$ when the decrypted signature $s$ is broadcast. Can we give the adaptor signature holder some extra _hint_ to let them compute $y_1$ and $y_2$?

Yes we can!

## The "Or" Case

As the adaptor signature bearer, Alice know the relationship $y' = y_1 + y_2$, but does not know $y_1$ or $y_2$. This gives her one equation with two unknowns. As is, this is not solvable, but it _would_ be if she had a second equation, which is what Bob can give to her.

Although, by giving this hint, Bob must relax his earlier requirement that the Alice would need _both_ secrets $y_1$ and $y_2$ to recover the adaptor secret $y'$. He must instead allow _either_ secret $y_1$ OR $y_2$ to be sufficient to recover $y'$.

Bob generates a _hint_ $z$ which he can give to Alice. He computes it as the difference between $y_1$ and $y_2$.

$$
\begin{align}
z &= y_2 - y_1 \\\\
\end{align}
$$

When Bob sends Alice his partial signature, Bob can pass the hint $z$ to give Alice a second equation to work with.

Alice receives $z$ and can verify Bob computed it correctly.

$$
\begin{align}
zG &= Y_2 - Y_1 \\\\
   &= y_2 G - y_1 G \\\\
   &= (y_2 - y_1) G \\\\
\end{align}
$$

Such a _hint_ is a special bonus for Alice. It means she now only needs to know _one_ of the two secrets $y_1$ OR $y_2$ to decrypt an adaptor signature encrypted with $Y'$.

Let's say Alice learns $y_1$. She can use the hint $z$ to compute the full adaptor secret $y'$ by solving a system of equations.

$$
\begin{align}
z &= y_2 - y_1 \\\\
z + y_1 &= y_2 \\\\
\end{align}
$$
$$
\begin{align}
y' &= y_1 + y_2 \\\\
y' &= y_1 + z + y_1 \\\\
y' &= 2 y_1 + z \\\\
\end{align}
$$

The same is true if Alice learns $y_2$.

By extension, Alice also learns both component secrets $y_1$ and $y_2$ if either one is revealed.

### Exclusivity

If we wanted to adjust our construction so that _either_ secret could decrypt the signature, but only _one_ of them is revealed by learning $s$, we can simply create two entirely separate adaptor signatures - one for either adaptor secret - with distinct nonces on each.

## Generalizing

The above methods can be generalized to any number of secrets $t$, not just two.

The "And" case is straightforward: sum all the component adaptor secrets together to form the aggregated adaptor secret $y'$.

The "Or" case requires more thought. If we have $t$ secrets, any of which should suffice to decrypt a signature, but all of which must be revealed if the signature is revealed, then we must supply $t - 1$ _hints_ which can be used to systematically reconstruct every adaptor secret, including the sum $y'$.

# Revocation

Consider a situation where Alice and Bob have both jointly signed a transaction, and that signature is encrypted with the point $Y$. Bob knows the adaptor secret $y$. Alice is aware that Bob knows $y$ and could broadcast the transaction any time he wishes. Is there anything Bob can do to convince Alice that he will _not_ broadcast the transaction?

As broadcasting the transaction would reveal $y$, Bob could give Alice some way of punishing him if he reveals $y$. This is a common practice in [some newer off-chain payment channel designs](https://eprint.iacr.org/2020/476.pdf), where a channel peer can revoke old channel state transactions by revealing a revocation key. The adaptor secret is sometimes referred to as a _publication secret_ in these contexts, because it is revealed by _publishing_ a specific transaction.

A revocation key in combination with its corresponding publication secret provides compact proof that someone published a transaction which they claimed they would never publish. In payment channels, peers build their transactions with _punishment paths_ which allow a wronged party to sweep the money of the misbehaving peer, if they can provide such proof.

## Key Exposure Threat

But what about situations where Bob has no money on the line in the first place? Bob cannot be punished financially if he has nothing available to forfeit.

We can still punish Bob if he commits to exposing something he doesn't want to be public knowledge: his _private key._

There are numerous ways to enforce exposure of a private key, and not all of them depend on adaptor signatures. I'll briefly cover a few.

### Revealing the Nonce

This method is not directly related to adaptor signatures, but I figured I should mention it anyway.

- Let $x$ be a private key.
- Let $r$ be a private random nonce.
- Let $R$ be the public nonce $R = rG$.
- Let $X$ be the public key $X = xG$.
- Let $e$ be some challenge hash $e = H_{\text{sig}}(R\ \|\|\ X\ \|\|\ m)$ on a message $m$.

Consider the simple Schnorr signature $(R, s)$, where $s = r + ex$.

If we are given $(R, s)$ _and_ the secret nonce $r$, we can compute the key $x$ which made the signature.

$$
\begin{align}
s &= r + ex \\\\
s - r &= ex \\\\
e^{-1}(s - r) &= x \\\\
\end{align}
$$

Clearly then, if the private key $x$ is secret and sensitive, its bearer will not want to reveal both $r$ and $s$, because knowing both is equivalent to knowing the private key $x$.

Suppose we are given the public nonce $R$ _in advance,_ and told to expect either:

- A valid signature scalar $s$, such that $sG = R + eX$, OR
- The secret nonce $r$, such that $rG = R$.

We could be reasonably confident (if the owner of $x$ cares about their private key's secrecy) that we will only learn _one_ of those values from the owner of the key $x$.

We can use this to revoke an adaptor signature.

Suppose Bob gives Alice an adaptor signature $(\hat{R}, \hat{s})$ to which he knows the adaptor secret $y$.

Alice knows the _true_ public nonce will be $R = \hat{R} + Y$, where $Y$ is the public adaptor point $Y = yG$.

If Bob reveals the value $r' = r + y$, then Alice can be confident that Bob will _never_ reveal the signature $s$ OR the adaptor secret $y$. Alice learns nothing about Bob's private key or adaptor secret by learning $r'$, except that if we reveal $s$ or $y$, then either would in turn reveal our private key $x$.

$$ r' = r + y $$

<sub>If Bob reveals the signature $s$:</sub>
$$
\begin{align}
s &= r + y + ex \\\\
s &= r'+ ex \\\\
s - r' &= ex \\\\
e^{-1}(s - r') &= x \\\\
\end{align}
$$

<sub>If Bob reveals the adaptor secret $y$:</sub>

$$
\begin{align}
\hat{s} &= r + ex \\\\
\hat{s} + y &= r + y + ex \\\\
\hat{s} + y &= r' + ex \\\\
\hat{s} + y - r' &= ex \\\\
e^{-1}(\hat{s} + y - r') &= x \\\\
\end{align}
$$

Given $r'$, Alice can easily verify its authenticity against the adaptor signature.

$$ r' G = \hat{R} + Y $$

### Secret Hint

The above method hints toward a more general approach. We can directly link knowledge of the adaptor secret $y$ to knowledge of a private key, or of any other arbitrary secret for that matter.

Let $x$ be that arbitrary secret. Bob can give Alice a _hint_ towards $x$, as a way of committing the adaptor secret $y$ to also reveal $x$. If Alice learns $y$, she learns $x$, and vice-versa.

Bob computes a hint $z$.

$$ z = y + x $$

Alice can verify the hint if she knows the public key of the secret, $X = xG$.

Alice then knows if she can learn $y$, either by Bob broadcasting a transaction and revealing $y$ through adaptor signatures, or entirely independently, then Alice will also learn $x$.

$$ z = y + x $$
$$ x = z - y $$

## Committing to a Key

Perhaps Bob can convince us that he'll forfeit a private key if he misbehaves. But private keys are just random numbers, and there are absurdly many of them. Bob can generate new ones on demand at any time. Bob's commitment to expose $x$ is hollow unless he can also convince Alice that he has something to lose by exposing it.

This leads us to a new question: How can Bob _meaningfully_ convince ALice that this key $x$ is valuable to him, and that he doesn't want to expose it? This is a complex topic, [worth discussing in a separate article](/scriptless/keycommit/).

Most commonly, _financial commitment_ is the de-facto standard. Bob must intentionally place himself at risk of losing money if $x$ is exposed. This will help convince Alice that, provided Bob is a rational actor, he won't attempt to cheat.

Bob might commit to forfeit money directly to Alice, or Bob might commit to _burning_ funds if he misbehaves. Although direct compensation to Alice would be preferable, the threat of burning funds is better than no threat at all, and can sometimes be more practical to implement.

## Conclusion

Adaptor signatures are a small and simple tool, but they are incredibly flexible.

I believe we're only just seeing the tip of the iceberg of adaptor signature use cases.

<details>
  <summary>Sources</summary>

- [_One-Time Verifiably Encrypted Signatures AKA Adaptor Signatures_ - Lloyd Fournier](https://raw.githubusercontent.com/LLFourn/one-time-VES/master/main.pdf)
- [_Generalized Channels from Limited Blockchain Scripts and Adaptor Signatures_ - Aumayr et al](https://eprint.iacr.org/2020/476.pdf)
- [_Lightning in Scriptless Scripts_ - Andrew Poelstra](https://lists.launchpad.net/mimblewimble/msg00086.html)

</details>
