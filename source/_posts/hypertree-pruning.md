---
title: Pruning Hypertrees for the Lax and Lazy
date: 2026-04-20
mathjax: true
category: cryptography
description: How to generate and sign with SLH-DSA very quickly, with only mild side effects.
---

Happy 4/20 nerds!

In [a previous article](/code/fast-slh-dsa/), I showed we can use parallelism to accelerate the hash-based signature system SLH-DSA by several orders of magnitude, so that generating keys on a modern CPU takes only a millisecond or so, and signing takes only 12 milliseconds. As far as I know, this is the best-performing open-source CPU implementation of SLH-DSA available anywhere today.

The one problem with the techniques I used in my experiments is that _the best optimizations depend on parallelism hardware features,_ like SIMD, multithreading, or GPUs. Without parallelism, every one of the 2.1 million hash compressions needed to sign with SLH-DSA-SHA2-128s must be done _sequentially,_ and if our hardware can't hash quickly, we are doomed to a much worse performance profile.

**Or are we?**

This article demonstrates a hacky algorithmic trick I call _hypertree pruning_ which SLH-DSA signer implementations can use to electively reduce a key's signature use limit in exchange for better signing and/or keygen performance.

<div style="background-color: rgba(100, 100, 155, 0.2); padding: 16px; border-radius: 5px;">If you prefer a powerpoint-presentation style of learning, check out <a href="https://www.youtube.com/watch?v=y2JQO17LgHk">this recording</a> of a talk I gave during the Ethereum Foundation's weekly PQ discussion call.</div>

**Hypertree pruning _does not_ affect verifier compatibility:** Signatures produced by anyone using this trick will still verify correctly using the vanilla, standardized SLH-DSA verification algorithm - Although, they _are_ statistically distinguishable, and so hypertree pruning is noticeable to anyone observing multiple signatures over time from the same keypair.

The security trade-off can be parameterized to favor signing or keygen performance improvement, and the intensity of the trade-off may be tuned based on the number of signatures each keypair is expected to make over its lifetime.

As a result, the ideal use-cases for hypertree pruning are situations where verifier behavior is fixed, but the signer lacks hardware powerful enough to produce SLH-DSA keys or signatures using the verifier's prescribed SLH-DSA parameter set. Hypertree pruning can empower signers who otherwise wouldn't be able to produce compatible keys or signatures in a reasonable amount of time. Examples include low-power embedded hardware systems, legacy CPUs lacking hardware acceleration, or high-throughput applications which must be able to produce many signatures from multiple keys very quickly.

More plainly, hypertree pruning allows a signer to produce valid SLH-DSA keys and signatures which standard verifiers will accept, at the cost of a smaller limit on the number of signatures that each keypair can safely produce.

**Disclaimers:** This concept has not been peer-reviewed for security. Pruning breaks compatibility with NIST's recommended SLH-DSA key generation and signing algorithms. Using hypertree pruning imperils your signing key because it intentionally reduces a keypair's safe signature query limit in exchange for better performance. While I believe I have spelled out and proven the security considerations at play in this article, readers should _use this technique only with the utmost care._

## SLH-DSA Review

[My prior article](/code/fast-slh-dsa/#SLH-DSA-Design) goes more in-depth on how SLH-DSA works. I highly suggest you read that section before proceeding with this article.

For those too lazy to open a new tab, have a look at this visualization of the SLH-DSA (SPHINCS) hypertree:

<img src="/images/quantum-hbs/sphincs.svg">

SLH-DSA keys are a merkle tree of merkle trees, often called a _hypertree._ The root hash of the root tree is called `pk_root`, and it is the most critical piece of the SLH-DSA public key, because it is what verifiers compare against when validating signatures.

The bottom-level leaves of this hypertree are FORS (Forest Of Random Subsets) keypairs, which are used to sign messages.

To verifiably connect `pk_root` to any given FORS keypair, the signer provides a chain of [XMSS (eXtended Merkle Signature Scheme)](/cryptography/quantum-hbs/#Merkle-Signature-Scheme-MSS) certification signatures.

Confused? Read [this section of the previous article](/code/fast-slh-dsa/#SLH-DSA-Design). Otherwise from here onward I will assume readers already know how SLH-DSA works.

## XMSS Pruning

Let's zoom in on XMSS for a moment.

<img src="/images/quantum-hbs/mss.svg">

The leaves of an XMSS tree are [Winternitz one-time signature (WOTS)](/cryptography/quantum-hbs/#Winternitz-One-Time-Signatures-WOTS) public keys, which are hashed into a merkle tree that can be used to succinctly prove each leaf keypair's membership.

Each WOTS leaf node can sign at most one message. In SLH-DSA, these WOTS leaf keys are used to _certify lower level XMSS trees._

The most computationally intensive part of SLH-DSA or XMSS is, by far, generating _WOTS leaves._ Even leaves which are not used to sign a message must still be generated so that we can reconstruct the rest of the XMSS tree's internal nodes, and so compute the merkle authentication path needed for a valid XMSS signature.

_However,_ if a signer doesn't need the entire XMSS tree, she can get away with discarding the WOTS leaves she does not need, replacing them with arbitrary hashes which have no cryptographic utility but are very fast to generate compared to WOTS keys. I call this technique _pruning._

<img src="/images/hypertree-pruning/xmss-pruning.svg">

A signer can effeciently _prune_ unneeded WOTS leaf nodes by deriving pseudorandom hashes from her keypair's `sk_seed`, and inserting those in the place of the pruned WOTS leaves. The replacement hashes are called _surrogates._ To a verifier, a surrogate hash appears indistinguishable from a real WOTS public key hash, but they are basically dead voids which are much quicker for the signer to generate.

This technique reduces the number of signatures which can be issued by the XMSS tree. If we prune $n$ leaves, we reduce the signing capacity of the XMSS tree by precisely $n$ one-time signatures. In the most extreme case, if we prune all but one WOTS leaf, the XMSS tree can issue at most one signature, and then its capacity would be exhausted. This is called _maximal pruning._

## Hypertree Pruning

We can apply the above pruning technique to the XMSS layers in an SLH-DSA hypertree too, and we can do so to optimize SLH-DSA keygen and/or signing at the cost of security. Let's optimize keygen first, since that is most straightforward to analyze.

Keygen is a very expensive process for SLH-DSA, and one which any signer will need to do before they can even distribute a public key to verifiers, let alone create signatures. Sometimes the key may never be used to sign, or it may only be used a few times. In this case the effort of keygen was mostly wasted. This is one of many realistic use-cases where the signer may wish to optimize SLH-DSA keygen and may be willing to make trade-offs to do so.

SLH-DSA key generation is fundamentally the same process as XMSS key generation applied to the SLH-DSA root tree, so it's easy to see we can apply XMSS pruning there. Any leaf WOTS key of the root tree can be replaced by a surrogate, effectively skipping the difficult work of WOTS key generation for that leaf. This can be done to many leaves, to adjust performance as desired.

Pruning the root tree reduces the overall size of the SLH-DSA hypertree though. By pruning a leaf from the root tree, we remove our ability to sign any messages using FORS leaf nodes below that branch of the hypertree. In SLH-DSA, the message is hashed to select which FORS leaf to use, so if we prune some of those FORS leaves, we may find the message hashes to a FORS leaf which no longer exists!

Thankfully, SLH-DSA signatures include a _randomizer,_ which the signer can grind using rejection sampling until she finds a randomizer which routes the message certification path to a valid (not-pruned) FORS leaf.

### Examples

In the most extreme case, we can prune a root tree of height $h'$ maximally, so that it contains only 1 leaf by simply generating $h'$ pseudorandom hashes, and using those as the XMSS merkle authentication path. Hashing these together iteratively, we generate our `pk_root` in a small fraction of the time normally required for SLH-DSA keygen - about $\frac{1}{2^{h'}}$ to be exact.

This diagram shows the structure of a SPHINCS (SLH-DSA) hypertree signature, with all but one leaf of the root tree pruned. The merkle authentication path can thus be replaced by surrogate hashes.

<img src="/images/hypertree-pruning/sphincs-pruning.svg">

To put this in more concrete terms, let's see an worked-out example of SLH-DSA keygen using a standard non-pruned root tree, and then optimize it with pruning.

- In the SLH-DSA-SHA2-128s parameter set, each XMSS tree has a height of $h' = 9$, meaning it has $2^9 = 512$ WOTS leaf nodes.
- Each WOTS key has 35 hash chains which must be iterated 16 times to produce a WOTS public key, plus 8 extra SHA256 compressions to hash the WOTS public key into an XMSS leaf node, for a total of 568 SHA256 compressions.
- We'd normally need 1024 more compressions to construct the merkle tree up to the `pk_root` node.
- In total this works out to about $568 \cdot 512 + 1024 = 291,840$ SHA256 compressions to generate the root XMSS tree.

Now with maximal pruning, where all but one leaf are surrogates:

- Generating the one valid WOTS leaf takes 568 SHA256 compressions.
- We must run $h' = 9$ compressions to generate surrogate hashes and build the merkle path.
- We compute a `pk_root` by running $h' = 9$ additional compressions.
- In total this works out to $568 + 2 \cdot 9 = 586$ SHA256 compressions.

The maximally pruned tree is about *500x faster* to generate than the full non-pruned tree. **Keygen can be done in a few _microseconds,_ instead of a few milliseconds.**

### To Optimize Signing

The above description prunes to optimize SLH-DSA keygen, but it also speeds up signing slightly. Since the root tree is very fast to generate, the overall workload for signing is reduced because the root tree does not have to be generated on-demand. It is as though the root tree were always cached. Mikhail Kudinov helpfully pointed out that maximal root tree pruning also makes it feasible to efficiently cache the only remaining XMSS tree in the 2nd-to top layer, which can improve signing performance even more.

However, this improvement is minor compared to what we can achieve if we prune the hypertree specifically to optimize signing.

For instance, if we prune half the leaves of every XMSS tree used when signing, this is functionally equivalent to reducing the height of each XMSS tree $h'$ by 1. _Since each hypertree only costs half as much work to generate, this means we only need to do half as much work to sign_ - not counting the minority work needed for FORS signing. See this diagram:

<img src="/images/hypertree-pruning/sphincs-pruning-sign.svg">

## Security

The main drawback to pruning is that it reduces security. More specifically: By shrinking the pool of FORS leaf nodes available to sign with, we increase the probability that any one FORS leaf will be used for a given signature. If a FORS leaf is used too much, it may permit forgery.

- Let $d$ be the number of layers of XMSS trees in the hypertree.
- Let $h'$ be the height of each XMSS tree layer in the hypertree.
- Prior to any hypertree pruning, we have $2^{d \cdot h'}$ FORS leaves available for signing.
  - Each FORS leaf would have one chance in $2^{d \cdot h'}$ to be used.
- If we prune $p$ FORS leaves, we will have $2^{d \cdot h'} - p$ usable FORS leaves remaining.
  - When signing, each unpruned FORS leaf will have 1 chance in $2^{d \cdot h'} - p$ of being used.

Thus, by pruning $p$ FORS leaves, we multiply the probability that any given unpruned FORS leaf is used by a factor of $\frac{2^{d \cdot h'}}{2^{d \cdot h'} - p}$.

Recall that in SLH-DSA we have a security parameter $q_s$: the signature query limit, AKA the maximum number of signatures we can safely generate for the keypair, beyond which the classical security degrades below a given threshold $\lambda$. SLH-DSA parameter sets are designed so that after $q_s$ signatures, the expected number of signatures for every FORS leaf keypair falls below some critical bound, such that the expected forgery probability for every FORS keypair remains smaller than 1 chance in $2^{\lambda}$.

Therefore, if we want to retain the same security level $\lambda$ as the unpruned equivalent, we must reduce $q_s$ by a factor of $\frac{2^{d \cdot h'}}{2^{d \cdot h'} - p}$.

$$ q_s' = \frac{q_s \left( 2^{d \cdot h'} - p \right)}{2^{d \cdot h'}} $$

Each FORS leaf keypair would then be used the same number of times on average as it would've been if we had not used hypertree pruning.

$$
\begin{align}
q_s' \cdot \overbrace{\frac{1}{2^{d \cdot h'} - p}}^{\text{FORS hit prob.}} &=
  \frac{q_s \left( 2^{d \cdot h'} - p \right)}{2^{d \cdot h'}} \cdot \frac{1}{2^{d \cdot h'} - p} \\\\
&= \frac{q_s }{2^{d \cdot h'}} \\\\
\end{align}
$$

Thus, after $q_s'$ signatures, any given FORS leaf of the pruned keypair is just as likely to admit a FORS forgery as any FORS leaf of the full unpruned keypair would be after $q_s$ signatures.

<!-- ### Formal Reduction

This is a short security reduction showing pruned SLH-DSA reduces to the security of regular SLH-DSA. The original sketch for this reduction was due to Jonas Nick.

We can show that any adversary $\mathcal A$ who can forge signatures on pruned SLH-DSA after $q_s'$ signing queries with advantage $\eta$ can be used to also forge signatures on standard SLH-DSA with the same advantage.

- Pick a message $m$
- Assume we have access to a signing oracle $\mathcal O$ who produces signatures
- Ask $A$ to forge a signature on $m_i$ repeatedly until $\mathcal A$ provides a signature from an unpruned FORS leaf.
- -->


### Example

Let's draw up an example with maximal pruning on the root tree, and see how that impacts security.

By pruning all but one leaf of the root tree, we have effectively decreased the parameter $d$ (the number of layers in the hypertree) by 1, which means the hypertree now contains a small fraction $\frac{1}{2^{h'}}$ as many bottom-level FORS leaf keys. In other words, we have decreased the overall height of the hypertree by $h'$.

Without pruning, the probability for a FORS leaf to be used would be 1 chance in $2^{d \cdot h'}$, and so the expected number of signatures per FORS leaf after $q_s$ signatures would be $\frac{q_s}{2^{d \cdot h'}}$.

But when the root tree is maximally pruned, then the FORS leaves which we did not prune are $2^{h'}$ times more likely to be used to sign any given message, meaning the probability of any one signature hitting a given FORS leaf is:

$$ \frac{2^{h'}}{2^{d \cdot h'}} = \frac{1}{2^{(d-1) h'}} $$

To retain the same security level as the unpruned equivalent, we reduce $q_s$ by a factor of $2^{h'}$.

$$ q_s' := \frac{q_s}{2^{h'}} $$

Then after $q_s'$ signatures, each FORS leaf keypair would then be used the same number of times on average as it would've been if we had not used hypertree pruning.

$$
\begin{align}
q_s' \cdot \frac{1}{2^{(d-1) h'}} &= \frac{q_s}{2^{h'}} \cdot \frac{1}{2^{(d-1) h'}} \\\\
&= \frac{q_s}{2^{d \cdot h'}} \\\\
\end{align}
$$

After $q_s'$ signatures, the pruned hypertree is just as likely to admit a FORS forgery as the full keypair would be after $q_s$ signatures.

Working with SLH-DSA-SHA2-128s as a concrete parameter set to illustrate:

- With parameters $d = 7$ and $h' = 9$, we have 7 XMSS layers of height-9 trees, leading to an overall hypertree height of $7 \cdot 9 = 63$ - a total of $2^{63}$ FORS leaves.
- Each of the WOTS leaves of the XMSS root tree would normally certify a child hypertree of height $6 \cdot 9 = 54$, containing $2^{54}$ FORS leaves.
- By maximal pruning of the root tree, we remove all but one of those height-54 child hypertrees.
- This leaves us with exactly $2^6 \cdot 2^9 = 2^{54}$ usable unpruned FORS leaf nodes which are $2^9 = 512$ times as likely to be used for each signature.
- Consequently, the keypair's safe signature limit should be reduced from $q_s = 2^{64}$ by a factor of $2^9$, down to $q_s' = 2^{55}$ signatures.
- After $q_s' = 2^{55}$ signatures, we expect each FORS to have issued $\frac{q_s'}{2^{(d-1) h'}} = \frac{2^{55}}{2^{54}} = 2$ signatures on average.
  - This is exactly the same as an unpruned SLH-DSA-SHA2-128s key, where the expected number of FORS signatures per leaf is $\frac{q_s}{2^{d \cdot h'}} = \frac{2^{64}}{2^{63}} = 2$.


## Privacy

The most obvious way to implement pruning is to always prune all but the first $x$ leaves for a given XMSS layer. This naive approach leaks information.

If an implementation always prunes the same set of leaves for every keypair, this makes the implementation's signatures easy to fingerprint and identify to any observers who see a signature. To reduce fingerprinting, leaves should be pseudorandomly selected for pruning, in a manner unique to each keypair.

For example, signers could pseudorandomly derive a fixed-size subset of leaf positions for each unique XMSS tree being pruned, by hashing the XMSS tree address with the secret `sk_seed`. The signer can use that subset to select which leaves of a tree will or will not be pruned. This makes it harder for an observer to recognize and fingerprint a signer's pruning behavior based on seeing a single signature.

However, after seeing multiple signatures, an observer may notice the signatures always reuse the same hypertree paths, so as more signatures are revealed the observer can become more and more confident that the signer is using a pruned SLH-DSA key. He may not be able to prove it conclusively though, and he won't know for sure the exact pruning structure the signer used either.

## Verifier Compatibility

Hypertree pruning is essentially a way to improve SLH-DSA performance at the cost of signature count, while maintaining verifier compatibility.

Verifier compatibility is an explicit core goal of hypertree pruning. If verifier compatibility were not needed, hypertree pruning is not needed either: If the signer could tell the verifier which SLH-DSA parameter set to use, then the signer could pick whatever SLH-DSA parameters they want, optimizing the parameters for performance, security, or signature size as needed. Hypertree pruning is always a worse option than selecting a tailored parameter set, because signatures using hypertree pruning will be unnecessarily larger than those of an equivalent bespoke parameter set.

However, in many real-world scenarios, signers may run into inflexible verifiers who are fixed to one or more specific SLH-DSA parameter sets. For example, in US government applications, only certain parameter sets are standardized and approved by NIST for official use. Hypertree pruning gives low-power signers a way to comply with these fixed standards at the cost of reduced signing capacity per keypair.

## Signer Incompatibility

Hypertree pruning comes at a cost to signer compatibility. Two signer implementations may import the same SLH-DSA secret key, but if one uses hypertree pruning and the other does not, then both may generate _different public keys_ and will create _incompatible signatures._ In other words, because hypertree pruning modifies the keygen and signing algorithms, it is _incompatible_ with standard SLH-DSA signer implementations.

This incompatibility is important because it leads to a security footgun.

- Given an SLH-DSA secret key `(sk_seed, pk_seed, sk_prf)`
- Let there be two signer implementations who use the same SLH-DSA secret key: one using hypertree pruning and one who uses standard baseline SLH-DSA algorithms. We call these the _pruning signer_ and the _standard signer_ respectively.
- Assume the pruning signer prunes at least one XMSS layer _other than the root XMSS tree._ Then those pruned trees will have _different merkle root hashes_ than those of the standard signer.
- If both signers create signatures involving the same intermediate (non-root) XMSS trees, then it it is feasible for the signers to _accidentally reuse a WOTS key to certify distinct XMSS root hashes._ This would break the security of the entire SLH-DSA scheme.
- A similar pitfall can occur if the same keypair is reused with different pruning techniques.

### Mitigations

The first and most obvious way to mitigate is to simply encode any pruned secret key in a non-standard format, e.g. by adding a version number which identifies the key as pruned, and also identifies the specific pruning technique that key uses. Standard SLH-DSA implementations should not accept such irregular keys, and pruned signers would not import standard SLH-DSA keys, and so there is no risk of WOTS key reuse between the two. This approach has the benefit of failing cleanly with recognizable errors.

If an application derives SLH-DSA keys pseudorandomly from some higher-level seed value, then the derivation process could be adjusted to scope keypairs specifically for pruned signing with a certain pruning technique. This keeps pruned keys completely separate from unpruned keys, and proper context separation in the derivation procedure can also ensure the same key is never reused with different pruning techniques.

If secret keys _must_ be importable between incompatible signer implementations, then the pruning signer can mitigate the risk algorithmically. Notice the footgun only exists because both signers _sometimes_ generate the same WOTS leaf keys, but the two signers may not generate the exact same sets of XMSS leaf nodes. We can use this fact. The signer need only randomize their `sk_seed` with a context string unique to their specific pruning algorithm. e.g. `sk_seed = H(sk_seed, "my pruning algo")`. Because `sk_seed` is used as a seed to generate all WOTS keys in the protocol, the pruning signer's WOTS leaf keys will then be completely disjoint to those of the standard signer, and so there is no risk of WOTS key reuse between the two implementations. This also means `pk_root` hashes will always be different too.

## Grinding Efficiently

While all pruning setups shown above result in efficiency gains, some pruning structures may result in a _less efficient signer,_ because they demand an unrealistic amount of randomizer grinding.

Remember, we can prune as much as we like, but for a verifier to accept our signature, we must first find a randomizer which selects a valid and usable FORS leaf on the bottom layer of the hypertree. SLH-DSA does not let the signer select this leaf explicitly though. The best she can do is to grind the signature randomizer value until she lucks out and finds one which selects an unpruned FORS leaf.

The probability of such a hit is exactly $\frac{2^{d \cdot h'} - p}{2^{d \cdot h'}}$ where $p$ is the number of FORS leaves we have pruned, and the expected number of tries needed to find this hit will be the inverse:

$$ \frac{2^{d \cdot h'}}{2^{d \cdot h'} - p} $$

Thus it turns out the expected time needed for randomizer grinding grows exponentially as we prune more FORS leaves (the graph looks a lot like that of $y = \frac{1}{1-x}$).

This also means the grinding efficiency of a pruned SLH-DSA keypair is closely linked to the security of the keypair, which also depends on the number of usable FORS keypairs.

### Diminishing Returns

As we prune more and more FORS leaves, the growth in grinding difficulty results in diminishing performance returns, and can even become computationally infeasible.

For instance, let's say we maximally prune the first two XMSS layers in a SLH-DSA-SHA2-128s hypertree. This reduces the overall hypertree height by $9 \cdot 2 = 18$, so we have shrunken our pool of usable FORS leaves by a factor of $2^{18} = 262144$, down to $2^{45}$ leaves.

To sign with this keypair, we must find a randomizer which routes the verifier to one of the remaining $2^{45}$ FORS leaves. Each attempt when grinding the randomizer has a success probability of $\frac{2^{45}}{2^{63}} = \frac{1}{2^{18}} = \frac{1}{262144}$, so we can expect this to take around 262144 attempts before we find a valid randomizer. Each attempt takes one SHA256 compression call.

But generating an XMSS tree takes around 291000 compressions anyway, so we have only saved about 30,000 compressions by maximally pruning the penultimate XMSS layer. Contrast this with the 290,000 compressions we saved in an earlier example by maximally pruning the root XMSS tree.

If we maximally prune the 3rd XMSS layer from the top as well, then we would expect to need $2^{27}$ SHA256 compressions before we find a valid randomizer - that's about 134 million compressions, or around _64 times more work_ than running the entire stock SLH-DSA-SHA2-128s signing algorithm without any pruning.

Clearly, there is a point beyond which pruning becomes more of a hassle than it is worth in performance gains.

## Optimal Pruning

Keygen efficiency gains are easy to reason about.

Let $\ell$ be the number of WOTS hash chains in a WOTS keypair, and let $w$ be the length of those hash chains. For each leaf of the root XMSS tree we prune, the number of hash compressions needed for keygen is reduced by at least $\ell \cdot w$. Therefore, to maximize keygen performance (at cost of security), we may simply use maximal pruning: prune all but one leaf of the XMSS root tree.

It is more difficult to quantify the net signing efficiency improvement from pruning, because we must balance the savings from pruning against the losses from randomizer grinding. In this section we will venture to find the _optimal pruning technique_ to maximize SLH-DSA signing speed, assuming we are willing to sacrifice some security.

> How do we do _optimal pruning?_
> What technique offers the best tradeoff ratio of security to signing speed?

We should first define what "optimal pruning" even means.

Signing runtime is majority dominated by:

1. WOTS key generations, and
1. (asymptotically) the randomizer grinding difficulty

WOTS key generations are easy to quantify. Each WOTS keypair is composed of $\ell$ hash chains of length $w$. The majority of the work needed to produce a WOTS pubkey is in iterating those hash chains, requiring at least $\ell \cdot w$ hash compression calls per WOTS key. Therefore we define the cost function $\omega(k)$ which takes in the number of WOTS pubkeys $k$ which we must generate in total across all layers of the hypertree, and returns the minimum number of SHA256 calls needed to produce all those keys.

$$ \omega(k) = k \cdot \ell \cdot w $$

The randomizer grinding difficulty is proportional to the reduction in the size of the FORS leaf pool relative to the default FORS leaf pool size. We define this as the _randomizer_ cost function $R(p)$ which takes in the number of pruned FORS leaf nodes $p$, and returns the average expected number of SHA256 calls needed to find a valid randomizer.

$$ R(p) = \frac{2^{d \cdot h'}}{2^{d \cdot h'} - p} $$

Note also that $R(p)$ represents a "security cost factor": it is the factor by which we must reduce our key's signature query limit $q_s$ in order to preserve security bounds.

$$ q_s' = \frac{q_s}{R(p)} $$

Given these cost functions, our overall goal is then to minimize the net cost function $C(k, p)$

$$
\begin{align}
C(k, p) &= \omega(k) + R(p) \\\\
        &= k \cdot \ell \cdot w + \frac{2^{d \cdot h'}}{2^{d \cdot h'} - p} \\\\
\end{align}
$$

However, the two parameters $k$ and $p$ are not independent. Pruning a WOTS leaf node across a layer decreases $p$ by one and so improves performance by a fixed increment, but also increases $k$ by some amount which worsens performance. _Optimal pruning_ thus means finding a pruning algorithm which minimizes the growth of $p$ while also maximizing the growth of $k$, such that we find a minimum of $C(k, p)$.

In the following section, I will describe a pruning algorithm that prioritizes signing speed, and prove it is optimal.

<sub>Note I leave aside the possibility of pruning layers with internal selectivity, where we might prune some XMSS trees more or less than others in the same layer. Instead I assume pruning is consistent inside any given XMSS layer, not necessarily at the same leaf positions, but at least to the same degree. This means every XMSS tree inside a given layer of a hypertree always has the same number of leaves.</sub>

### Symmetry

<div id="regular-definition"></div>

Let's define a new term: An _$n$-regular hypertree_ is a hypertree for which _all XMSS layers_ have the same number $n$ of (unpruned) leaf nodes. For example, standard SLH-DSA hypertrees are all $2^{h'}$-regular.

I will now show that pruning a leaf across any layer of an $n$-regular hypertree has the same effect on the cost function $C(k, p)$, i.e. the same effect on signer performance, regardless of which layer is pruned.

Towards this end, here are two key facts:

1. _Pruning any WOTS leaf across any layer of any hypertree will always have the same effect on $\omega(k)$ regardless of which layer we prune:_ It saves a single WOTS key generation during signing, and so $k$ is decreased by 1.

This fact is hopefully self-evident and needs no proof.

2. _Pruning a leaf across any layer of an $n$-regular hypertree has the same effect on $R(p)$ regardless of which layer we prune._

**Proof of (2):** Let $d$ be the number of layers in the $n$-regular hypertree. Pruning a leaf on the root tree will remove $n^{d-1}$ FORS leaf nodes. This is the same number of FORS leaves we'd remove if we prune 1 leaf from the $n$ 2nd-to-top layer XMSS trees, because each such leaf is the parent of $n^{d-2}$ bottom-level FORS leaves: $n \cdot n^{d-2} = n^{d-1}$. The same logic applies to any XMSS layer further down, including if we prune a single FORS leaf from each of the $n^{d-1}$ bottom layer XMSS trees. Thus, pruning any layer of an $n$-regular hypertree with $d$ layers results in increasing the number $p$ of pruned FORS leaves by $n^{d-1}$, and therefore results in a proportional change to $R(p)$.

The above facts imply layer choice doesn't affect the cost function $C(k, p) = \omega(k) + R(p)$ (doesn't affect signer performance) when pruning an $n$-regular hypertree. Pruning any given layer of an $n$-regular hypertree affects signing performance and security equally as much as pruning any other layer.

The only distinction between layers in this case is that pruning the root tree also improves keygen performance as well as signing performance. Thus we derive the first rule of our optimal pruning algorithm:

> If the hypertree is _[regular](#regular-definition),_ then always prune from the root tree first.

Since SLH-DSA trees are $2^{h'}$-regular, this means pruning a single leaf from the root tree is always the first step in any optimal pruning algorithm.

After pruning one leaf from the root tree, we have pruned $p = 2^{(d-1)h'}$ FORS leaves, and we've saved 1 WOTS key generation during signing: $k = d \cdot 2^{h'} - 1$. Which layer should we prune next?

First notice the overall hypertree is no longer $2^{h'}$-regular, **but** we can recursively invoke the symmetric properties of hypertree pruning on the lower layers. If we think of the XMSS layers below the root tree as independent child hypertrees with $d-1$ layers, where each XMSS layer has height $h'$, then it is clear these child hypertrees are $2^{h'}$-regular. Thus, pruning any given layer of those child hypertrees would be equivalent to pruning any other layer, at least in terms of the impact on the number of FORS leaves $p$ that we prune.

Therefore, we have only two material choices for where to prune next: Do we prune another leaf from the root tree again, or do we prune a leaf from a lower-level XMSS layer?

### Asymmetry

Both choices are equivalent in their effect on the WOTS keygen cost $\omega(k)$, because they both decrement $k$ by 1.

But curiously, the two choices are _not_ equivalent in their effect on the number $p$ of pruned FORS leaves, and thus on the randomizer grinding cost $R(p)$ (AKA the security cost factor).

If we prune another leaf from the root tree, we will remove $2^{(d-1)h'}$ usable FORS leaves, as before, and so increase $R(p)$ proportionally. However, pruning a leaf from any of the lower-level XMSS layers has a different effect.

Without loss of generality, assume we prune a leaf from the 2nd-to-top XMSS layer. Since we already pruned one leaf from the root tree, there are now only $2^{h'} - 1$ such unpruned XMSS trees remaining in the 2nd-to-top layer. Pruning a leaf of one such tree will remove $2^{(d-2) h'}$ FORS leaves. Thus, pruning a leaf from each of the $2^{h'} - 1$ XMSS trees in the 2nd-to-top layer will result in removing $2^{(d-2) h'} (2^{h'} - 1) = 2^{(d-1) h'} - 2^{(d-2) h'}$ FORS leaves - _Exactly $2^{(d-2) h'}$ leaves fewer than if we had pruned the root tree again!_

Therefore, the optimal choice to minimize the number $p$ of pruned FORS leaves - and therefore minimize the cost $R(p)$ - would be to leave the root tree as-is, and instead prune one of the lower-level XMSS layers, all of which are equivalent.

If we do prune a leaf from the 2nd-to-top layer, then this same reasoning can be applied recursively to show the optimal follow-up is to prune a leaf from the 3rd-to-top XMSS layer, and then again with the 4th-to-top XMSS layer. This proceeds until we have pruned one leaf from every XMSS layer in the hypertree, whereupon every layer has the same number of leaves: $2^{h'} - 1$.

After pruning every layer once, we will have acquired a $2^{h'} - 1$-regular hypertree, and so we can resume pruning from the top of the tree again, since at that point layer choice has no effect on the cost functions.

More generally: The best choice of pruning to minimize $R(p)$ for any given partially-pruned hypertree is to _always prune a leaf from whichever XMSS layer has the most unpruned WOTS leaf nodes remaining._

This gives us our only other necessary algorithmic pruning rule:

> If the hypertree is not _regular,_ then prune from the layer with the most unpruned leaves, highest first.

### Visual Example

Tree-based algorithms are always easier to clock with a fully diagrammed example.

This is a 4-regular hypertree with 3 layers.

<img src="/images/hypertree-pruning/optimal-pruning-diagram-1.svg">

You can see visually why pruning a leaf from the top layer removes the same number of bottom-level leaf nodes as pruning one leaf across any other layer (always 16 leaves).

<img src="/images/hypertree-pruning/optimal-pruning-diagram-2.svg">
$$ \Updownarrow $$
<img src="/images/hypertree-pruning/optimal-pruning-diagram-3.svg">
$$ \Updownarrow $$
<img src="/images/hypertree-pruning/optimal-pruning-diagram-4.svg">

Assume we've already pruned one leaf from the top-level tree. Notice what happens when we prune a second leaf from the top-level tree.

<img src="/images/hypertree-pruning/optimal-pruning-diagram-5.svg">

This removed an additional 16 leaf nodes. Contrast that with the effect of pruning one leaf from each of the three remaining 2nd-layer trees.

<img src="/images/hypertree-pruning/optimal-pruning-diagram-6.svg">

Pruning a leaf across the 2nd layer removed only 12 leaf nodes.

This pattern is recursive. Applying the same technique again, we can see pruning a leaf across each of the 9 remaining trees on the bottom layer results in the removal of only 9 leaf nodes.

<img src="/images/hypertree-pruning/optimal-pruning-diagram-7.svg">

We have acquired a 3-regular hypertree, so we can return to pruning from the top layer, and repeat the process of pruning from top to bottom over and over until we have pruned as many WOTS leaves as we desire. The result is the optimal pruning technique to maximize signing efficiency.

### TLDR

Practically speaking, this means the pruning technique which best optimizes signing is to prune all XMSS layers in equal amounts, with a slight bias to prune the root tree first, since that will speed up keygen as well. This approach minimizes the effects on security while maximizing the signing performance improvement by pruning.

As an example, the [earlier suggestion I gave to optimize signing](#To-Optimize-Signing) just happened to be an instance of optimal pruning, because each XMSS layer was pruned to exactly half its ordinary size.

However, as we're about to see, that isn't the absolute limit on how far we can optimize. The details of how many leaves we can prune per layer depend on the SLH-DSA parameter sets we use.

## Parameter Set Suitability

Now that we know how to prune optimally, we can work out the upper limits of hypertree pruning, when applied to tune the performance and security of different SLH-DSA parameter sets. It turns out, not all parameter sets are equally receptive to pruning.

Note that optimizing keygen is again straightforward to analyze here. We can achieve optimal keygen by using maximal pruning of the root tree. In this case:

- keygen runtime is multiplied by $\frac{1}{2^{h'}}$
- signing runtime is multiplied by $\frac{d-1}{d}$
- signature limit is reduced to $\frac{q_s}{2^{h'}}$

...recalling that $h'$ is the height of each XMSS tree, $d$ is the number of XMSS layers, and $q_s$ is the signature use limit.

It is totally feasible to prune the root tree only partially, reserving some security at a cost to keygen performance. To this end, I leave the details as an exercise to the reader.

Instead I will focus on the far more interesting and subtle use-case of optimally pruning different parameter sets to eke out the best possible signing performance (at expense to security).

Since we know optimal pruning for signing involves pruning every XMSS layer equally, [as proven earlier](#Optimal-Pruning), I will redefine the net cost function in terms of the number of WOTS leaves to prune per XMSS layer, which I'll call the _pruning degree_ and denote it with $x$. A pruning degree of $x$ means we prune $x$ WOTS leaves from every XMSS tree in the hypertree - not necessarily in the exact same leaf _positions,_ but the always in the same quantity of leaves per XMSS tree.

This implies we will use hypertrees which are always $\left( 2^{h'} - x \right)$-_regular,_ and that has several advantages:

- It makes it easier to write both the number of pruned FORS leaves and the number of WOTS keygens saved.
- It allows us to define the net cost function as a univariate function $\mathcal C(x)$, so we can graph it in the Cartesian plane.
- It makes implementation easier because every layer of the hypertree uses the same number of leaves, allowing for parallelization and other software optimizations.

Here is our new definition of the net cost function:

$$
\mathcal{C}(x) = \\\\
  \overbrace{d \ell w \left( 2^{h'} - x \right)}^{\text{WOTS keygen cost}} + \\\\
  \overbrace{\frac{2^{d \cdot h'}}{\left(2^{h'} - x \right)^d}}^{\text{Grinding cost}}
$$

We can also compute $q_s'$, the signing query limit after pruning, as follows:

$$ q_s' = \frac{q_s \left( 2^{h'} - x \right)^d}{2^{d \cdot h'}} $$

Think of this as multiplying the original signing query limit $q_s$ with the fraction $\frac{\left( 2^{h'} - x \right)^d}{2^{d \cdot h'}}$ which is the fraction of FORS leaves that remain unpruned and usable.

With concrete formulas in hand, let's apply them to some real-world SLH-DSA parameter sets and see what we can learn about the effects of hypertree pruning.

First, we'll look at the NIST-standardized [SLH-DSA-SHA2-128s](https://csrc.nist.gov/pubs/fips/205/final) parameter set: $d = 7$, $h' = 9$, $\ell = 35$, $w = 16$, $q_s = 2^{64}$.

<img id="slh-dsa-128s" style="border-radius: 10px;" src="/images/hypertree-pruning/slh-dsa-128s-optimal-pruning.png">

Fascinating! The net cost function appears to decay almost linearly, until we've pruned around 400 of the 512 WOTS leaves per XMSS tree, at which point the grinding cost term starts to explode exponentially as $x$ increases, quickly dwarfing the WOTS cost which decays linearly with $x$.

The net cost minimum occurs around $x \approx 405$, while the first meaningful diminishing return in performance gain caused by grinding (i.e. where $\mathcal C(x)$ starts to diverge from the straight line defined by $d \ell w \left( 2^{h'} - x \right)$) occurs beyond $x \ge 350$.

This means any pruning degree $x \le 405$ is viable for this parameter set, though as $x$ approaches 405, improvements in performance come at an increasingly severe cost to security.

Here is a table of results for how SLH-DSA-SHA2-128s signer performance and pruned signing query limit $q_s'$ would be impacted by different choices of pruning degree $x$:

| Leaves pruned per layer | HT<sup>\*</sup> signing speedup | Signature limit ($q_s'$) |
|:-:|:-:|:-:|
|$x = 0$|   1.000x  |$2^{64}$|
|$x = 1$|   1.002x  |$\approx 2^{64}$|
|$x = 16$|  1.032x  |$\approx 2^{63.7}$|
|$x = 64$|  1.142x  |$\approx 2^{62.6}$|
|$x = 128$| 1.333x  |$\approx 2^{61.1}$|
|$x = 256$| 2.000x  |$2^{57}$|
|$x = 288$| 2.284x  |$\approx 2^{55.7}$|
|$x = 350$| 3.144x  |$\approx 2^{52.4}$|
|$x = 384$| 3.874x  |$2^{50}$|
|$x = 405$| 4.209x  |$\approx 2^{48.2}$|

<sub><sup>\*</sup> "HT" stands for hypertree. The speedup ratios given here do not take external factors such as FORS signing or Merkle path construction into account. For most SLH-DSA parameter sets though, WOTS keygen consumes the bulk of the signer's runtime, so this approximation should roughly match real benchmarks.</sub>

Now let's look at the [SHRINCS-B](https://github.com/BlockstreamResearch/shrincs-specification/) parameter set: $d = 2$, $h' = 12$, $\ell = 16$, $w = 256$, $q_s = 2^{20}$.

<img id="shrincs-b" style="border-radius: 10px;" src="/images/hypertree-pruning/shrincs-b-optimal-pruning.png">

This graph looks almost like a "sharper" copy of the SLH-DSA standard parameter set. Never mind the negative cost values on the other side of the pole beyond $x \ge 4096$ - these are artifacts of the graphing tool.

The minimum of the SHRINCS-B parameter set's pruning net cost function is at exactly $x = 4080$, where we'd prune all but 16 of the 4096 leaves from both of the two XMSS layers. The cost starts to diverge from its linear decay beyond $x \ge 4040$.

Here is another efficiency tradeoff table for SHRINCS-B:

| Leaves pruned per layer | HT signing speedup | Signature limit ($q_s'$) |
|:-:|:-:|:-:|
|$x = 0$|    1.000x  |$2^{20}$|
|$x = 64$|   1.016x  | $\approx 2^{20}$ |
|$x = 256$|  1.067x  | $\approx 2^{19.8}$ |
|$x = 512$|  1.143x  | $\approx 2^{19.6}$ |
|$x = 1024$| 1.333x  | $\approx 2^{19.2}$ |
|$x = 2048$| 2.000x  | $2^{18}$ |
|$x = 3072$| 4.000x  | $2^{16}$ |
|$x = 3584$| 8.000x  | $2^{14}$ |
|$x = 3840$| 16.000x | $2^{12}$ |
|$x = 4000$| 42.567x  | $\approx 2^{9.17}$ |
|$x = 4040$| 72.300x  | $\approx 2^{7.61}$ |
|$x = 4080$| 170.667x | $2^{4}$ |

Here is the cost function graph for the [SHRINCS-B32](https://github.com/BlockstreamResearch/shrincs-specification/) parameter set: $d = 4$, $h' = 8$, $\ell = 16$, $w = 256$, $q_s = 2^{32}$.

<img id="shrincs-b32" style="border-radius: 10px;" src="/images/hypertree-pruning/shrincs-b32-optimal-pruning.png">

Its minimum is at exactly $x = 240$, leaving 16 WOTS leaves unpruned per layer. The net cost function starts to diverge from linear beyond $x \ge 225$.

Here is an efficiency tradeoff table for SHRINCS-B32:

| Leaves pruned per layer | HT signing speedup | Signature limit ($q_s'$) |
|:-:|:-:|:-:|
|$x = 0$|    1.000x  |$2^{32}$|
|$x = 1$|    1.004x  |$\approx 2^{32}$|
|$x = 4$|    1.016x  |$\approx 2^{31.9}$|
|$x = 8$|    1.032x  |$\approx 2^{31.8}$|
|$x = 32$|   1.143x  |$\approx 2^{31.2}$|
|$x = 64$|   1.333x  |$\approx 2^{30.3}$|
|$x = 96$|   1.600x  |$\approx 2^{29.3}$|
|$x = 128$|  2.000x  |$2^{28}$|
|$x = 160$|  2.667x  |$\approx 2^{26.3}$|
|$x = 192$|  4.000x  |$2^{24}$|
|$x = 224$|  7.938x  |$2^{20}$|
|$x = 240$|  12.800x |$2^{16}$|

### Discussion

Each parameter set supports a $q_s$ security cost factor of $\approx 2^{16}$ at the most extreme pruning degrees - i.e. $q_s' \approx \frac{q_s}{2^{16}}$. But interestingly, the SHRINCS-B and SHRINCS-B32 parameter sets seem to permit a much greater degree of signing speedup compared to SLH-DSA-SHA2-128s. SLH-DSA maxes out at 4.2x speedup, and SHRINCS-B32 permits a maximum speedup of 12.8x, while SHRINCS-B can go far harder with a max speedup of over 170x.

Of course, the obvious caveat is that both the SHRINCS parameter sets are completely ineffective as stateless signature schemes if we prune them to such extreme degrees. SHRINCS-B with pruning degree $x = 4080$ would permit only 16 signatures before the key's security starts to degrade below the prescribed security level. SHRINCS-B32 with $x = 240$ is a bit better with $q_s' = 2^{16} = 65536$.

Realistically, any signers who need to use pruning would likely want to compromise somewhere in the middle, and pick a pruning degree which suits their use-case.

## Hybrid Pruning

In some contexts, it may be desirable to use _hybrid pruning,_ which is where we prune the root tree and the lower-level XMSS trees with different pruning degrees. This allows us to balance keygen and signing optimization.

For example, a signer might want to maximally prune her root XMSS tree by removing $2^{h'} - 1$ WOTS leaves, so that SLH-DSA keygen is very fast. If she has extra security budget she doesn't need, she may also elect to prune the lower-level XMSS trees by a variable amount.

In this case, the net cost function $\mathcal C(x, y)$ is a bivariate generalization of $\mathcal C(x)$, where $y$ is the pruning degree for the root XMSS tree and $x$ is the pruning degree for all the other lower-level XMSS layers.

$$
\mathcal{C}(x, y) = \\\\
  \overbrace{\ell w \left( 2^{h'} - y \right)}^{\text{root keygen cost}} + \\\\
  \overbrace{\ell w (d-1) \left( 2^{h'} - x \right)}^{\text{lower keygen cost}} + \\\\
  \overbrace{\frac{2^{d \cdot h'}}{ \left( 2^{h'} - y \right) \left(2^{h'} - x \right)^{d-1}}}^{\text{Grinding cost}}
$$

We can adjust the signing query limit for a hybrid pruning setup as follows:

$$ q_s' = \frac{q_s \left( 2^{h'} - y \right) \left(2^{h'} - x \right)^{d-1}}{2^{d \cdot h'}} $$

Optimizing hybrid pruning is a more subtle matter than pruning for signing speed alone. I feel this article is long enough as is, and I've spent enough time on the subject, so I will leave further examination of hybrid pruning as a future exercise and an open problem for anyone interested in pursuing it.

## Conclusion

Despite SLH-DSA's reputation for being slow, there are tricks we can do to speed it up. Some techniques like those I showed in [my previous article](/code/fast-slh-dsa/) are rooted in the principle of maximizing hardware usage.

Hypertree pruning is a unique new addition to the optimizer's tookit though: Even for platforms who have already maximized their available hardware, we can still improve SLH-DSA performance, albeit at the expense of signature capacity.
