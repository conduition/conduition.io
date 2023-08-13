---
title: Wagner's Birthday Attack - How to Break InsecureMuSig
date: 2023-08-13
mathjax: true
category: cryptography
---

# Introduction

_MuSig_ is a protocol which allows mutually distrustful parties to safely create _aggregated_ digital signatures together. I highly recommend you read [my MuSig article](/cryptography/musig) before diving into this one, as it lays down the context. If you're already familiar with MuSig and Schnorr, carry on!

The MuSig protocol has several iterations:

1. [InsecureMuSig - An _outdated and insecure_ 2-round version](https://eprint.iacr.org/archive/2018/68/20180118:124757)
2. [MuSig1 - The secure 3-round variant](https://eprint.iacr.org/2018/068)
3. [MuSig2 - The faster but slightly less secure 2-round variant](https://eprint.iacr.org/2020/1261)

InsecureMuSig - the original form of MuSig - was [proven insecure by Drijvers et al in 2018](https://eprint.iacr.org/2018/417). The attack described in their paper depended on the fact that under InsecureMuSig, co-signers could manipulate the final aggregated nonce used for signing by submitting _rogue nonces,_ computed as a function of their peers' nonces. In response, the authors of MuSig amended their paper with a third nonce-commitment round of communication, thus preventing co-signers from providing rogue nonces.

[This Blockstream article](https://medium.com/blockstream/insecure-shortcuts-in-musig-2ad0d38a97da) briefly summarizes the approach used by the attack, but only from the perspective an attack on an insecure implementation of MuSig1, in which nonces themselves are pre-shared before the message to sign is chosen. For a time, this article led me to mistakenly assume that it was the pre-sharing of nonces which made InsecureMuSig so insecure. However, that is not the approach used by Drijvers et al in their original paper. In the paper, Drijvers et al made no mention of nonce pre-sharing at all.

To my knowledge, there does not yet exist a full approachable explanation of how Wagner's Attack broke InsecureMuSig. That is what I hope this article will be.

Bear in mind that I am no expert on Wagner's Algorithm, but merely a tourist inclined to investigate algorithms which I find interesting. If you notice any mistakes, please [suggest an edit on Github](https://github.com/conduition/conduition.io/blob/main/source/_posts/wagner.md), or [email me](mailto:conduition@proton.me)! I'd be very grateful for the help.

## Notation

Just so we're all on the same page:

| Notation | Meaning |
|:--------:|---------|
| $x \in A$ | The value $x$ is a member of set $A$. |
| $\sum_{i=1}^n x_i$ | The sum of all $x_i$ from $i$ to $n$. i.e. $x_1 + x_2 + x_3 + ... x_n$ |
| $a + b \equiv c \mod n$ | $a + b$ is equivalent to $c$ modulo $n$. |
| $G$ | The [base-point of the secp256k1 curve.](https://bitcoin.stackexchange.com/questions/58784/how-were-the-secp256k1-base-point-coordinates-decided) |
|$n$ | The [_order_ of the secp256k1 curve](https://crypto.stackexchange.com/questions/53597/how-did-someone-discover-n-order-of-g-for-secp256k1). There are $n - 1$ possible valid non-zero points on the curve, plus the 'infinity' point (AKA zero). |
|$H_{\text{foo}}(x)$ | A cryptographically secure namespaced hash function under the namespace $\text{foo}$. Returns an integer mod $n$. |
|$x \leftarrow \mathbb{Z}\_{n}$ | Sampling $x$ randomly from the set of integers modulo $n$. Note that we exclude zero when sampling. |
|$X \leftarrow \mathbb{S}\_{n}$ | Sampling $X$ randomly from the set of secp256k1 curve points. Note that we exclude the point at infinity (AKA zero) when sampling. |
| $a\ \|\|\ b$ | Concatenation of the byte arrays $a$ and $b$. |
| $\\{1 ... k\\}$ | The set of all integers from $1$ to $k$ (inclusive), i.e. every $i$ such that $1 <= i <= k$ |
| $\forall x \in Y$ | "For every element $x$ in set $Y$." |
| $\|L\|$ | The order of (AKA number of elements in) set $L$. |

# The Attack

## The Setup

Alice, Bob and Carol have an aggregated public key $D$ defined as per the normal MuSig1 protocol.

$$
L = \\{ D_a, D_b, D_c \\}
$$
$$
\begin{aligned}
& \alpha_a = H_{\text{agg}}(L\ \|\|\ D_a) &&
  \alpha_b = H_{\text{agg}}(L\ \|\|\ D_b) &&
  \alpha_c = H_{\text{agg}}(L\ \|\|\ D_c) \\\\
\end{aligned}
$$
$$
D = \alpha_a D_a + \alpha_b D_b + \alpha_c D_c
$$

Carol has some evil message $m'$ she wants to sign using the aggregated key, but which Alice and Bob would never agree to sign. Perhaps a signature on $m'$ would steal all of Alice and Bob's Bitcoins. Perhaps it would sign a TLS certificate which only Carol shouldn't actually have. Perhaps it is the string _"Alice sucks and must not be invited to parties"._ You get the idea.

## Requirements

Carol will execute her dastardly attack by opening a number of concurrent signing sessions with Alice and Bob, and providing a set of carefully chosen _rogue nonces._ Rogue nonces behave similarly to [rogue keys, which I highlighted in my MuSig article](/cryptography/musig/#Rogue-Keys). If Carol learns Alice's nonce $R_a$ and Bob's nonce $R_b$ _before_ revealing her own nonce $R_c$, then Carol can offer up a rogue nonce which fools Alice and Bob into computing the aggregated nonce to be whatever Carol desires. When Carol does this, she can cause Alice and Bob's signatures on $m$ to change in a way she _fully_ controls, albeit unpredictably.

**The "fully controls" part is particularly important.** For Wagner's Attack to work Carol _must_ learn Alice and Bob's public nonces before choosing her own, otherwise she cannot control the challenge $e$ and her attack will not work.

This is why InsecureMuSig was insecure: Unlike MuSig1, InsecureMuSig didn't have a nonce-commitment phase. Co-signers simply exchanged their public nonces at will with no additional commitment phase or scrambling involved.

## The Procedure

OK enough babbling. Let's dive right in and see how Carol attacks this system.

1. Carol opens $k$ concurrent signing sessions with Alice and Bob, in which she proposes to sign $k$ innocuous messages $\\{m_1, m_2, ..., m_k\\}$ which Alice and Bob would be perfectly agreeable to signing. $k$ can be any power of two - higher is generally more efficient, but riskier for Carol. $k$ should approach but not exceed the maximum number of concurrent signing sessions that Alice and Bob can safely handle.

2. Carol waits for Alice and Bob to share their public nonces $\\{(R_{a,1}, R_{b,1}), (R_{a,2}, R_{b,2}), ..., (R_{a,k}, R_{b,k})\\}$ with her in every one of the $k$ signing sessions.

3. Carol picks a nonce of her own which will protect her private key once the forgery is complete.

$$ r_c \leftarrow \mathbb{Z}\_n $$
$$ R_c = r_c G $$

4. Carol runs [Wagner's Algorithm](https://link.springer.com/content/pdf/10.1007/3-540-45708-9_19.pdf) to find $k$ different curve points $\\{X_1, X_2, ..., X_k\\}$ which hash to $k$ challenges $\\{e_1, e_2, ..., e_k\\}$ which sum to an evil challenge $e'$.

$$
\begin{align}
R' &=  \sum\_{i=1}^k (R_{a, i} + R_{b, i}) + R_c \quad \forall i \in \\{1 ... k\\} \\\\
e_i &= H_{\text{sig}}(X_i\ \|\|\ D\ \|\|\ m_i)   \quad \forall i \in \\{1 ... k\\} \\\\
\end{align}
$$
$$
\begin{align}
e' = H_{\text{sig}}(R'\ \|\|\ D\ \|\|\ m') =&\ \sum\_{i=1}^k e_i         \\\\
                              =&\ H_{\text{sig}}(X_1\ \|\|\ D\ \|\|\ m_1) + \\\\
                               &\ H_{\text{sig}}(X_2\ \|\|\ D\ \|\|\ m_2) + \\\\
                               &\ ... +                        \\\\
                               &\ H_{\text{sig}}(X_k\ \|\|\ D\ \|\|\ m_k)   \\\\
\end{align}
$$

- $R'$ is the "evil nonce" which will eventually be used for Carol's forged signature. It is the sum of all of Alice and Bob's nonces across all signing sessions, plus Carol's own nonce $R_c$.
- Each $X_i$ is hashed with the message $m_i$ to produce a challenge $e_i = H_{\text{sig}}(X_i\ \|\|\ D\ \|\|\ m_i)$ for signing session $i$.
- Through the wonder of Wagner's Algorithm, the sum of all those $e_i$ hashes _equals another hash which Carol has chosen_ based on an evil message $m'$ (which Alice and Bob never see).

5. Carol calculates a set of rogue nonces $\\{R_{c, 1}, R_{c, 2}, ..., R_{c, k}\\}$, one for each signing session.

$$
R_{c, i} = X_i - R_{a, i} - R_{b, i} \quad \forall i \in \\{1...k\\}
$$

The purpose of each rogue nonce $R_{c, i}$ is to fool Alice and Bob into using the point $X_i$ as the aggregated nonces for signing session $i$. Alice and Bob, upon receiving $R_{c, i}$, will compute the aggregate nonce as:

$$
\begin{align}
R_i &= R_{a, i} + R_{b, i} + R_{c, i} \\\\
    &= R_{a, i} + R_{b, i} + (X_i - R_{a, i} - R_{b, i}) \\\\
    &= X_i \\\\
\end{align}
$$

Alice and Bob do not know to avoid $X_i$. Because InsecureMuSig lacks nonce commitments, Alice and Bob do not know whether Carol provided a genuine nonce or a rogue one.

Carol can thus convince Alice and Bob to sign $\\{m_1, m_2, ..., m_k\\}$ with the "aggregated" nonces $\\{X_1, X_2, ..., X_k\\}$ chosen by Carol. She can do this because she waited for Alice and Bob to expose their nonces to her, so she can easily compute her nonces as a function of theirs.

By now, perhaps you are starting to see why why Carol needed to open those $k$ signing sessions _concurrently_ (at the same time), rather than sequentially. She needs to know _all_ of Alice and Bob's nonces $\\{(R_{a, 1}, R_{b, 1}), (R_{a, 2}, R_{b, 2}), ..., (R_{a, i}, R_{b, i})\\}$ in order to compute the points $\\{X_1, X_2, ..., X_k\\}$ with Wagner's Algorithm, so she had to at least _start_ the $k$ signing sessions before she could perform step 4. However, she also can't _conclude_ any signing session until she knows which point $X_i$ to aim for with her rogue nonce. Thus, the signing sessions must be concurrent.

6. Carol awaits the resulting $k$ pairs of partial signatures $\\{(s_{a,1}, s_{b,1}), (s_{a,2}, s_{b,2}), ..., (s_{a,k}, s_{b,k})\\}$ from Alice and Bob.

Let $r_{a, i}$ and $r_{b, i}$ denote Alice and Bob's secret nonces for signing session $i$. We can assume these are honestly random and unknown to Carol.

Alice and Bob will have computed their partial signatures as follows.

$$ \forall i \in \\{1 ... k\\} $$
$$
\begin{align}
R_i &= R_{a, i} + R_{b, i} + R_{c, i} \\\\
    &= X_i \\\\
\end{align}
$$
$$
\begin{align}
e_i &= H_{\text{sig}}(R_i\ \|\|\ D\ \|\|\ m_i) \\\\
    &= H_{\text{sig}}(X_i\ \|\|\ D\ \|\|\ m_i) \\\\
\end{align}
$$
$$
\begin{aligned}
& \alpha_a = H_{\text{agg}}(L\ \|\|\ D_a) &&
  \alpha_b = H_{\text{agg}}(L\ \|\|\ D_b) \\\\
& s_{a, i} = r_{a, i} + e_i \alpha_a d_a &&
  s_{b, i} = r_{b, i} + e_i \alpha_b d_b \\\\
\end{aligned}
$$

See how by selecting rogue nonces, Carol convinced her peers to sign the challenges $\\{e_1, e_2, ..., e_k\\}$ which were selectively chosen by Carol, such that $H_{\text{sig}}(R'\ \|\|\ D\ \|\|\ m') = \sum_{i=1}^k e_i$.

7. Carol sums Alice and Bob's partial signatures from those $k$ signing sessions to create a usable forged signature $s'$ which verifies under the aggregate key $D$ on Carol's chosen message $m'$ and evil nonce $R'$. Carol must add her own partial signature $s_c$ to complete the forgery.

$$ s_c = r_c + \alpha_c e' d_c $$
$$
\begin{align}
s' &= \sum_{i=1}^k (s_{a, i} + s_{b, i}) + s_c \\\\
   &= (s_{a, 1} + s_{b, 1}) + (s_{a, 2} + s_{b, 2}) + ... + (s_{a, k} + s_{b, k}) + s_c \\\\
\end{align}
$$

This seems a bit too easy. How could this possibly work? Let's expand $s'$ to see why it would be valid.

$$
\begin{align}
s' &= \sum_{i=1}^k (s_{a, i} + s_{b, i})
   &&
   &&+ s_c \\\\
   &= \sum_{i=1}^k (r_{a, i} + r_{b, i}
   &&+ \alpha_a e_i d_a + \alpha_b e_i d_b)
   &&+ r_c + \alpha_c e' d_c \\\\
\end{align}
$$

<sub>Group the private nonces all on the left, Alice and Bob's private key terms in the middle, and Carol's private key term on the right.</sub>

$$
\begin{align}
s' &= \sum_{i=1}^k (r_{a, i} + r_{b, i}) + r_c
   &&+ \sum_{i=1}^k (\alpha_a e_i d_a + \alpha_b e_i d_b)
   &&+ \alpha_c e' d_c \\\\
   &= \sum_{i=1}^k (r_{a, i} + r_{b, i}) + r_c
   &&+ \sum_{i=1}^k e_i(\alpha_a d_a + \alpha_b d_b)
   &&+ \alpha_c e' d_c \\\\
   &= \sum_{i=1}^k (r_{a, i} + r_{b, i}) + r_c
   &&+ (\alpha_a d_a + \alpha_b d_b) \cdot \sum_{i=1}^k e_i
   &&+ \alpha_c e' d_c \\\\
\end{align}
$$

> that doesn't look like a valid Schnorr signature.

Not yet! But what if we...

## Substitute All The Things

Here's where the magic of Wagner's Algorithm makes itself felt. Recall how Carol used Wagner's Algorithm to find the the challenges $\\{e_1, e_2, ..., e_k\\}$ so that they sum to her evil challenge $e'$.

$$
e' = H_{\text{sig}}(R'\ \|\|\ D\ \|\|\ m') = \sum\_{i=1}^k e_i
$$

<sub>Wondering how Carol did this? [We'll get there eventually.](#Wagner%E2%80%99s-Algorithm)</sub>

This relationship allows Carol to factor out $e'$ from the aggregated partial signatures, just as with a regular aggregated Schnorr signature, except this time they are ***super-duper aggregated*** - a rigorous technical term which denotes that the signatures came from many signing sessions and from multiple peers.

$$
\begin{align}
s' &= \sum_{i=1}^k (r_{a, i} + r_{b, i}) + r_c
   &&+ (\alpha_a d_a + \alpha_b d_b) \cdot \sum_{i=1}^k e_i
   &&+ \alpha_c e' d_c \\\\
   &= \sum_{i=1}^k (r_{a, i} + r_{b, i}) + r_c
   &&+ (\alpha_a d_a + \alpha_b d_b) \cdot e'
   &&+ \alpha_c e' d_c \\\\
\end{align}
$$

Oh look. Now we can merge the middle and right groups of terms by factoring out $e'$.

$$
s' = \sum_{i=1}^k (r_{a, i} + r_{b, i}) + r_c + e'(\alpha_a d_a + \alpha_b d_b + \alpha_c d_c)
$$

_This is starting to look suspiciously similar to a valid Schnorr signature._

> what about that first term with the sum of the secret nonces?

Remember how we defined the evil nonce $R'$ as the sum of Alice and Bob's public nonces $\\{(R_{a,1}, R_{b,1}), (R_{a,2}, R_{b,2}), ..., (R_{a,k}, R_{b,k})\\}$, plus Carol's nonce.

$$
R' = \sum\_{i=1}^k (R_{a, i} + R_{b, i}) + R_c
$$

Although Carol doesn't know the actual value of $\sum_{i=1}^k (r_{a, i} + r_{b, i}) + r_c$, she knows it must be the discrete logarithm (secret key) of the evil nonce $R'$. Let's simplify by denoting that secret evil nonce as $r'$.

$$
\begin{align}
 r' &= \sum\_{i=1}^k (r_{a, i} + r_{b, i}) + r_c \\\\
r'G &= G \cdot \sum\_{i=1}^k (r_{a, i} + r_{b, i}) + r_c G \\\\
    &= \sum\_{i=1}^k (r_{a, i}G + r_{b, i}G) + r_c G \\\\
    &= \sum\_{i=1}^k (R_{a, i} + R_{b, i}) + R_c \\\\
    &= R' \\\\
\end{align}
$$

We can substitute $r'$ into the signature equation to represent the hypothetical aggregated secret nonce, which is obscured but is still part of the forged signature.

$$
\begin{align}
s' &= \sum_{i=1}^k (r_{a, i} + r_{b, i}) + r_c &&+ e'(\alpha_a d_a + \alpha_b d_b + \alpha_c d_c) \\\\
s' &= r' &&+ e'(\alpha_a d_a + \alpha_b d_b + \alpha_c d_c) \\\\
\end{align}
$$

We can further simplify by denoting the hypothetical aggregated private key as $d = \alpha_a d_a + \alpha_b d_b + \alpha_c d_c$.

$$
s' = r' + e' d \\\\
$$

The forged signature $s'$ can be verified as with any standard ol' Schnorr signature.

$$
\begin{align}
s'G &= ( r' + e' d ) G \\\\
    &= r'G + e' dG \\\\
    &= R' + e' D \\\\
\end{align}
$$

If you understand everything above, then congratulations: You've just grasped the clever attack that forced some of the most famous cryptography experts in the Bitcoin community to backtrack and rework their original InsecureMuSig algorithm. You could close the page here, and give your brain a little _"good job!"_ affirmation for grasping such an outlandish cryptographic attack.

But the perversely curious among you may wonder,

> how did Carol find those curve points $\\{X_1, X_2, ..., X_k\\}$?
>
> how did she know they would result in challenges which sum to $e'$?

If these questions are eating at you, read on to learn more. But beware! Here be dragons...

# Wagner's Algorithm

From an attentive reading of the [attack procedure](#The-Attack), I hope you'll agree that the secret sauce seems to come in the form of some black box which I referred to as _Wagner's Algorithm._ Carol used it to find a set of points that she used to fool Alice and Bob into signing challenges _which Carol chose._ This resulted in a forgery.

This black box is an algorithm [originally described in David Wagner's 2002 paper on the Generalized Birthday Problem](https://link.springer.com/content/pdf/10.1007/3-540-45708-9_19.pdf) in which he demonstrates a probabilistic search algorithm which can be used to find additively related elements in lists of random numbers.

> what the hell does that mean?

Let's back up a bit and sketch out the high-level game plan here. Wagner's original paper is quite dense. I made several attempts at this section of the article before landing on what I believe to be a reasonably intuitive but also succinct description of Wagner's Algorithm. It will help if I outline our approach before I describe the algorithm itself.

- First we will review some principles of probability theory which we'll need to make use of.
- We'll generate a bunch of lists of random hashes.
- We'll define a merging operation to merge pairs of lists together into another list of _about_ the same size as either parent list.
- Those merged lists will contain sums of hashes which are close to zero mod $n$.
- We'll repeat this merging operation recursively in a tree-like structure until the hash-sums approach zero.
- We'll follow pointers back back up the tree to the original lists, and find inputs which, when hashed, should sum to any number we want mod $n$.


## Probabilities

Before we dive into a probability-driven algorithm, let's review some probability theory!

### Probability of Modular Sums

Imagine you have three D6 dice $\\{d_1, d_2, d_3\\}$ and roll them all independently. What are the odds that those three dice face values add up to a number which is divisible by six?

$$d_i \leftarrow \\{1...6\\} \quad \forall i \in \\{1 ... 3\\}$$
$$Pr \left[ \sum_{i=1}^{3} d_i \mod 6 \equiv 0 \right] =\ \?$$

Assuming all the dice are evenly weighted and rolled independently, there are $6^3$ equally likely outcomes.

| $d_1$ | $d_2$ | $d_3$ |
|:-----:|:-----:|:-----:|
|   1   |   1   |   2   |
|   1   |   1   |   3   |
|   1   |   1   |   4   |
|   1   |   1   |   5   |
|   1   |   1   |   6   |
|   1   |   2   |   1   |
|   1   |   2   |   2   |
|   1   |   2   |   3   |
|   1   |   2   |   4   |
|   1   |   2   |   5   |
|   1   |   2   |   6   |
|   1   |   3   |   1   |
|  ...  |  ...  |  ...  |
|   6   |   6   |   5   |
|   6   |   6   |   6   |


This works out such that each possible sum mod 6 $\\{0...5\\}$ is equally likely, i.e.

$$
Pr \left[ \sum_{i=1}^{3} d_i \mod 6 \equiv c \quad \forall c \in \\{0...5\\} \right] = \frac{1}{6}
$$

There's nothing special about a modular sum of zero here. You can pick any constant $c \in \\{0...5\\}$ and your odds of rolling a modular sum of $c$ are the same: $\frac{1}{6}$.

Imagine rolling one die. That event has an exact $\frac{1}{6}$ probability of rolling any $d_1 \in \\{1 ... 6\\}$. Take that value mod 6, and it maps 1:1 to $\\{0...5\\}$ with exactly the same probability.

Roll a second die and add it to the first. This adds some $d_2 \in \\{1 ... 6\\}$ again with uniform probability, which brings the modular sum once more to $\\{0...5\\}$ with the exact same probability distribution. Repeat ad infinitum. Thus, the probability distribution of a modular sum does not change _no matter how many dice are summed._

### Expected Values

The [_expected_ value](https://en.wikipedia.org/wiki/Expected_value) of some variable is the value you can expect it to hold _on average._ It can be calculated by taking a weighted sum of every possible outcome value, multiplied by the probability of that outcome.

For example, if you were to roll a six-sided die $d$, its expected value would be the weighted sum of each possible die face value. The expected value of a dice roll turns out to be $3.5$.

$$
\begin{align}
d &\leftarrow \\{1...6\\} \\\\
E[ d ] &= \frac{1}{6} \left( 1 \right) + \frac{1}{6} \left( 2 \right) + \frac{1}{6} \left( 3 \right) + \frac{1}{6} \left( 4 \right) + \frac{1}{6} \left( 5 \right) + \frac{1}{6} \left( 6 \right) \\\\
&= \frac{1 + 2 + 3 + 4 + 5 + 6}{6} \\\\
&= \frac{21}{6} \\\\
&= \frac{7}{2} = 3.5 \\\\
\end{align}
$$

The [Linearity of Expectation](https://brilliant.org/wiki/linearity-of-expectation/) property of Probability Theory tells us that the _expected value_ of a sum of random variables is simply the sum of their respective expected values. Sounds weird when you say it like that, but an example should help.

Roll two six-sided dice and sum them together. What's the expected value of that sum? It's the sum of each die's own expected values, i.e. $3.5 + 3.5 = 7$. So the expected value of the two summed dice is $7$.

$$
\begin{align}
d_1 &\leftarrow \\{1...6\\} \\\\
d_2 &\leftarrow \\{1...6\\} \\\\
E[ d_1 + d_2 ] &= E[d_1] + E[d_2] \\\\
&= 3.5 + 3.5 \\\\
&= 7 \\\\
\end{align}
$$

Here's another way to conceptualize Linearity of Expectation. You roll a six-sided die 100 times. How many times would you expect to roll a five?

The probability of rolling a five on any given roll is obviously $\frac{1}{6}$, but you're doing it 100 times. Each time you roll, you'll either roll a five with probability $\frac{1}{6}$, or you don't. Counting the number of five's you roll is the same as a weighted average of 100 possible binary outcomes, where the event's value is zero if you don't roll a five, or one if you _do_ roll a five. Each event has the same probability $\frac{1}{6}$.

$$
\frac{1}{6}(1) + \frac{1}{6}(1) + \frac{1}{6}(1) + ... [\text{repeat 97 more times}]
$$
$$ \frac{1}{6} \cdot 100 $$
$$ \frac{100}{6} \approx 16.66 $$

Therefore, after 100 rolls you can expect about 16 or 17 dice to roll a five (or any other number from 1 to 6, for that matter).

Review done! Not so bad, right? On to Wagner's Algorithm.

## List Generation

In our effort to forge an aggregate signature, the main thing Carol needs is some set of nonces $\\{X_1, X_2, ..., X_k\\}$, which, combined with aggregated pubkey $D$ and innocuous messages $\\{m_1, m_2, ..., m_k\\}$, hash into the challenges $\\{e_1, e_2, ..., e_k\\}$ for each of the $k$ signing sessions, such that all the challenges sum to some evil challenge $e'$.

$$ e_i = H_{\text{sig}}(X_i\ \|\|\ D\ \|\|\ m_i) \quad \forall i \in \\{1...k\\} $$
$$
e' = H_{\text{sig}}(R'\ \|\|\ D\ \|\|\ m') \equiv \sum_{i=1}^k e_i \mod n
$$

If Carol can find such a set of nonces, she can use it to produce a forged signature by sending rogue nonces to Alice and Bob as described earlier.

The catch is that Carol can't predict the output of $H_{\text{sig}}$, so the challenges appear to be generated completely randomly. Even though she can use rogue nonces to influence part of the input of $H_{\text{sig}}$, Carol cannot wholly dictate the _output_ of $H_{\text{sig}}$. Carol needs some better method to find inputs which hash into numbers which then sum to $e'$.

Wagner's Algorithm can do exactly this. It works by finding patterns in lists of random numbers. Turns out, even perfectly random data can still behave predictably if we massage the data properly.

So first things first - We need to generate those random numbers. In our case, we aren't using truly random numbers. Instead we will use the _pseudo-random hashes_ generated by $H_{\text{sig}}$. If $H_{\text{sig}}$ is cryptographically secure, its output will behave exactly like a random number generator.

We'll run $H_{\text{sig}}$ on some important input data, namely:

- the curve points $\\{X_1, X_2, ..., X_k\\}$
- the aggregated public key $D$
- the benign messages $\\{m_1, m_2, ..., m_k\\}$
- the evil message $m'$ (the one which lets Carol steal from Alice and Bob if she can forge a signature on it)
- the evil nonce $R'$

Carol cannot influence the aggregated pubkey $D$. She _might_ be able to influence the benign messages $\\{m_1, m_2, ..., m_k\\}$, but she is limited in this domain as the messages she chooses must be acceptable for Alice and Bob to sign. There may not be a large space of messages which Alice and Bob would be okay with signing.

As we discussed previously, Carol can use rogue nonces to trick Alice and Bob into using any point $X_i$ as the aggregated signing nonce for signing session $i$. Nonces are random-seeming curve points with no restrictions on their validity aside from that they must be on the secp256k1 curve. There are $n-1 \approx 2^{256}$ possible valid nonces - a very large space of possibilities to draw from. This point of control over the aggregated signing nonce is how Carol will generate the lists of (pseudo) random numbers for the attack.

Let $\mathbb{S}\_n$ denote the set of all non-zero points on the secp256k1 curve.

Carol generates $k - 1$ lists $\\{L_1, L_2, ..., L_{k - 1}\\}$. These lists will each contain $\lambda$ <sub>(pronounced lambda)</sub> _candidate hashes_ generated by hashing random _candidate nonces_ $\\{\hat{X}\_{i,j}\\}$ sampled from $\mathbb{S}\_n$.

$$ \forall i \in \\{1 ... k - 1\\} \quad \forall j \in \\{1 ... \lambda\\} $$
$$ \hat{X}\_{i, j} \leftarrow \mathbb{S}\_n $$
$$
\begin{align}
\hat{e}\_{i, j} &= H_{\text{sig}}(\hat{X}\_{i, j}\ \|\|\ D\ \|\|\ m_i) \\\\
L_i &= \\{\hat{e}\_{i, 1}, \hat{e}\_{i, 2}, ..., \hat{e}\_{i, \lambda}\\} \\\\
\end{align}
$$

\* <sub>Notice how I've denoted the candidate nonces $\\{\hat{X}\_{i, j}\\}$ and candidate hashes $\\{\hat{e}\_{i, j}\\}$ with a little hat to signify that they are only candidates, and not the final chosen nonces $\\{X_i\\}$ or hashes $\\{e_i\\}$.</sub>

Carol generates the last list $L_k$ in the same way, but this time she subtracts $e'$ from each candidate hash $\hat{e}\_{k, j}$.

$$ \forall j \in \\{1 ... \lambda\\} $$
$$ \hat{X}\_{k, j} \leftarrow \mathbb{S}\_n $$
$$
\begin{align}
\hat{e}\_{k, j} &= H_{\text{sig}}(\hat{X}\_{k, j}\ \|\|\ D\ \|\|\ m_k) - e' \mod n\\\\
L_k &= \\{\hat{e}\_{k, 1}, \hat{e}\_{k, 2}, ..., \hat{e}\_{k, \lambda}\\} \\\\
\end{align}
$$

This is part of the setup process to ensure we end up with a set of hashes which sum specifically to $e'$. The reasoning behind this will make more sense later.

> how is the list length $\lambda$ chosen?

Patience. I'll return to that one in a bit.

Carol should store pointers back to the candidate nonces $\hat{X}\_{i, j}$ which were used to create each hash $\hat{e}\_{i, j}$, so she can reference them once she finds the correct set of hashes which sums to $e'$. Carol will use those nonces to compute the rogue nonces to give to Alice and Bob in the concurrent signing sessions.

The lists of hashes will look like this.

| Lists ||||||
|:-:|:-:|:-:|:-:|:-:|:-:|
| $L_1$ | $\hat{e}\_{1, 1} \rightarrow \hat{X}\_{1, 1}$ | $\hat{e}\_{1, 2} \rightarrow \hat{X}\_{1, 2}$ | $\hat{e}\_{1, 3} \rightarrow \hat{X}\_{1, 3}$ | ... | $\hat{e}\_{1, \lambda} \rightarrow \hat{X}\_{1, \lambda}$ |
| $L_2$ | $\hat{e}\_{2, 1} \rightarrow \hat{X}\_{2, 1}$ | $\hat{e}\_{2, 2} \rightarrow \hat{X}\_{2, 2}$ | $\hat{e}\_{2, 3} \rightarrow \hat{X}\_{2, 3}$ | ... | $\hat{e}\_{2, \lambda} \rightarrow \hat{X}\_{2, \lambda}$ |
| $L_3$ | $\hat{e}\_{3, 1} \rightarrow \hat{X}\_{3, 1}$ | $\hat{e}\_{3, 2} \rightarrow \hat{X}\_{3, 2}$ | $\hat{e}\_{3, 3} \rightarrow \hat{X}\_{3, 3}$ | ... | $\hat{e}\_{3, \lambda} \rightarrow \hat{X}\_{3, \lambda}$ |
|  ...  | ... | ... | ... | ... | ... |
| $L_k$ | $\hat{e}\_{k, 1} \rightarrow \hat{X}\_{k, 1}$ | $\hat{e}\_{k, 2} \rightarrow \hat{X}\_{k, 2}$ | $\hat{e}\_{k, 3} \rightarrow \hat{X}\_{k, 3}$ | ... | $\hat{e}\_{k, \lambda} \rightarrow \hat{X}\_{k, \lambda}$ |

<sub>In the above table, the $\rightarrow$ symbols denote pointers back to the original input data used to produce the hash $\hat{e}\_{i, j}$.</sub>

It doesn't actually matter whether Carol knows the discrete log (secret key) of each aggregated nonce $X_i$, so she is free to sample them by whatever means are most efficient for her.

## Solution Counting

Let's simplify: Say we have two lists of hashes $L_1$ and $L_2$, each of length $\lambda$ generated in the way described above. We want to find a hash chosen from each list $e_1 \in L_1$ and $e_2 \in L_2$ such that $e_1 + e_2 \equiv e' \mod n$. How long would these lists need to be for a solution to exist?

If we were to merely sample 2 random numbers $\hat{e}\_1$ and $\hat{e}\_2$ from $\mathbb{Z}\_n$, the odds of them both adding up to our target $e'$ modulo $n$ would be about $\frac{1}{n}$.

_Why?_ [Recall the dice example](#Probability-of-Modular-Sums): Since we're summing $\hat{e}\_1$ and $\hat{e}\_2$ modulo $n$, the distribution of $\hat{e}\_1 + \hat{e}\_2$ is just as perfectly uniform as $\hat{e}\_1$ or $\hat{e}\_2$ themselves are. Both elements are equally likely to roll anything in the range $\\{0...n-1\\}$, so their sum mod $n$ is also uniformly distributed in the range $\\{0...n-1\\}$.

$$
\begin{align}
\hat{e}\_1 &\leftarrow \mathbb{Z}\_n \\\\
\hat{e}\_2 &\leftarrow \mathbb{Z}\_n \\\\
\end{align}
$$
$$ Pr\left[ \hat{e}\_1 + \hat{e}\_2 \equiv e' \mod n \right] = \frac{1}{n} $$

With a totally random approach like that, we'd need to attempt (on average) $n$ random permutations to find $\hat{e}\_1$ and $\hat{e}\_2$ which sum to $e' \mod n$.

If our two lists $L_1$ and $L_2$ are randomly generated, or in our case generated using a hash function on unique inputs, the probability of any two elements randomly sampled from those lists summing to $e' \mod n$ will _also_ be $\frac{1}{n}$.

$$
\begin{align}
\hat{e}\_1 &\leftarrow L_1 \\\\
\hat{e}\_2 &\leftarrow L_2 \\\\
\end{align}
$$
$$ Pr\left[ \hat{e}\_1 + \hat{e}\_2 \equiv e' \mod n \right] = \frac{1}{n} $$

The _product of the length of both lists_ $|L_1| \cdot |L_2| = \lambda^2$ represents the number of possible permutations of two elements chosen from $L_1$ and $L_2$. One might think of this as each element in $L_1$ having $|L_2|$ possible _mates_ it could pair with.

By the [Linearity of Expectation](https://brilliant.org/wiki/linearity-of-expectation/) property of Probability Theory, we can infer the _expected_ number of solutions in $L_1$ and $L_2$ will be _the number of possible permutations_ of two elements sampled from $L_1$ and $L_2$ (i.e. the number of random guesses we could possibly make), multiplied by the probability that each permutation could be a solution: $\frac{1}{n}$.

$$
\begin{align}
E \left[| e_1 \in L_1,\ e_2 \in L_2 | : e_1 + e_2 \equiv e' \mod n \right] &= \frac{|L_1| \cdot |L_2|}{n} \\\\
&= \frac{\lambda^2}{n} \\\\
\end{align}
$$

This tells us pretty clearly that we want $\lambda^2 \ge n$ for our expected number of solutions to be at least 1.

If instead of two lists, we had $k$ lists of hashes $\\{L_1, L_2, ..., L_k\\}$, the same basic truths still hold as with two lists. The probabilities will be the same, except instead of the number of permutations being only $|L_1| \cdot |L_2|$, the number of combinations is the product of the lengths of _all lists_ $\prod_{i=1}^k |L_i| = |L_1| \cdot |L_2| \cdot |L_3| \cdot ... \cdot |L_k|$.

The probability of a random set of hashes among those lists summing to $e'$ remains fixed at $\frac{1}{n}$, as discussed in the Probability Theory review section.

Assume each list has the same length $\lambda$.

$$ |L_i| = \lambda \quad \forall i \in \\{1...k\\} $$

Then the total number of possible permutations would be $\lambda^k$.

$$ \prod_{i=1}^k |L_i| = \lambda^k $$

If we want on average 1 solution to exist among these $\lambda^k$ permutations, we need the total number of permutations $\lambda^k$ to be at least $n$, and thus each list's length $\lambda$ must be at least $n^{\frac{1}{k}}$, i.e. the $k$-th root of $n$.

$$ \lambda^k \ge n $$
$$ \lambda \ge n^{\frac{1}{k}} $$

This brings the expected number of solutions among $\\{L_1, L_2, ..., L_k\\}$ to at least 1:

$$
\begin{align}
E \left[| e_i \in L_i \quad \forall i \in \\{1...k\\} | : \sum_{i=1}^k e_i \equiv e' \mod n \right] &= \frac{\lambda^k}{n} \\\\
& \\\\
&\ge \frac{n}{n} \\\\
&\ge 1 \\\\
\end{align}
$$

As for actually finding the solution... The output of the hash function $H_{\text{sig}}$ is not predictable, so Carol cannot simply compute the solution in an analytic way. But there are ways for her to search more efficiently.

## Search Strategy

If we do a naive sequential search of the lists $\\{L_1, L_2, ..., L_k\\}$ to find a solution $e_1 + e_2 + ... + e_k \equiv e' \mod n$, the computational work needed find that solution remains roughly the same (gargantuan) regardless of how many lists we have. At best, searching only two lists of length $\lambda = n^{\frac{1}{2}}$, we're talking a complexity of $O(\sqrt{n})$, which for secp256k1 is about $\sqrt{n} \approx 2^{128}$ computations. By the time we find the solution, the sun will have exploded, heat death of the universe yadda yadda - you know the rest.

We're assuming $H_{\text{sig}}$ is cryptographically secure, so can't rely on hash collisions, preimage attacks or other cheat-codes like that.

So what's a cypherpunk to do?

A classic trick of algorithmic efficiency is to break down a complex task into smaller and simpler ones.

It is evidently too difficult to find a solution when hashes are all evenly distributed among $\mathbb{Z}\_n$. If $n$ is very large, the number of combinations we'd need to check would be absurd.

It would be easier if we only had to look for solutions distributed among a smaller range than $\mathbb{Z}\_n$. Because the lower-bound of the list length $\lambda$ is determined by the size of the range we're searching within (i.e. $\mathbb{Z}\_n$), we can make it easier to find a solution if we can find a clever way to reduce the size of that range.

Let's explore a particular example of Wagner's Algorithm where $k = 8$ (eight lists) and we want to find hashes $\\{e_A, e_B, e_C, ..., e_H\\}$ from each list $\\{L_A, L_B, L_C, ..., L_H\\}$ such that they all sum to $0$ when taken mod $n$.

Why sum to $0$ instead of $e'$? This makes Wagner's algorithm much easier to execute, and we can do so without loss of generality: **One list $L_H$ is modified by subtracting $e'$ from each random hash in $L_H$.** This results in the correct set of solution hashes summing to $e'$.

$$ e_A + e_B + e_C + ... + (e_H - e') \equiv 0 \mod n $$
$$ e_A + e_B + e_C + ... + e_H \equiv e' \mod n $$

We will build a _binary tree,_ and break the problem into smaller chunks at each distinct _height_ $h$ of the tree by _merging lists together_ while preserving important properties in child lists, and maintaining pointers back to the hashes in the original lists.

<img style="color: white" src="/images/wagner/list-tree.svg">

<!-- TODO redo diagram -->

After building the final root node list $\mathcal{L}$, we should expect to find at least one solution, and we can follow the pointers back up the tree to find the original hashes $\\{e_A, e_B, e_C, ..., e_H\\}$ which created that solution.

### Merging The Leaves

Perhaps we could _merge_ two leaf lists $(L_A, L_B)$ into list $L_{AB}$ at height $h = 1$ while maintaining the same list length, but with elements distributed across a _smaller domain_ using some yet-to-be-defined operation $\bowtie_h$.

$$ L_{AB} = L_A \bowtie_h L_B $$

When merging two parent lists $(L_A, L_B)$ into a child list $L_{AB}$, we want to capture two important properties in the child list:

1. Elements in the child list should be distributed across a significantly smaller range of possible values than the elements in the parent lists.
2. Elements in the child list should be the sum of two elements from the parent lists. Each child list element should maintain pointers to the two elements in the parent lists which created them.

Our approach to merging will be to iterate through every combination of candidate elements $(\hat{e}\_A, \hat{e}\_B)$ from both lists, and ***test to see if their sum falls within a certain range around zero,*** wrapping modulo $n$. At the height $h = 1$, the range will be a certain size, and at $h = 2$ we will shrink the range to further reduce the necessary domain.

How big should that range be?

Let's parameterize the _filter range_ $\mathcal{R}\_h$ for height $h$ as some interval $[a_h, b_h]$ wrapping around zero modulo $n$.

$$
\mathcal{R}\_h = \\{a_h ... b_h\\} \mod n
$$

We don't know what that interval is yet, but we can deduce what it should be.

Assume the two leaf lists $(L_A, L_B)$ each have the same length $\lambda$. We want to expect the child list $L_{AB}$ to also have length $\lambda$ so that when we apply this operation for future children of $L_{AB}$, we still only need to search approximately $\lambda^2$ possibilities each time.

$$ |L_A| = |L_B| = \lambda $$
$$ L_{AB} = L_A \bowtie_1 L_B $$
$$ E[|L_{AB}|] = \lambda $$

Since both parent lists have length $\lambda$, we have $\lambda^2$ combinations between them. To maintain approximately the same length in the child list $L_{AB}$ we need the probability of the sum of two randomly sampled elements $(\hat{e}\_A, \hat{e}\_B)$ falling into the range $\mathcal{R}\_h$ to be exactly $\frac{1}{\lambda}$.

$$ \hat{e}\_A \leftarrow L_A \quad \quad \hat{e}\_B \leftarrow L_B $$
$$ Pr\left[ \hat{e}\_A + \hat{e}\_B \in \mathcal{R}\_1 \mod n \right] = \frac{1}{\lambda} $$

If we independently roll this probability once for each unique pair in lists $(L_A, L_B)$, we would have rolled it exactly $\lambda^2$ times. Due to [Linearity of Expectation](https://brilliant.org/wiki/linearity-of-expectation/), we should expect about $\frac{\lambda^2}{\lambda} = \lambda$ pairs from the parent lists to filter down into the child list. This gives us exactly what we want: The child list will contain about $\lambda$ elements.

$$
\begin{align}
E[|L_{AB}|] &= \frac{|L_A| \cdot |L_B|}{\lambda} \\\\
            &= \frac{\lambda^2}{\lambda} \\\\
            &= \lambda \\\\
\end{align}
$$

We already know that the probability of two elements $(\hat{e}\_A, \hat{e}\_B)$ randomly sampled from $\mathbb{Z}\_n$ summing to a particular number modulo $n$ is $\frac{1}{n}$. But what if, instead of summing to a single number, we ask whether $\hat{e}\_A + \hat{e}\_B \mod n$ ***falls into a range*** of size $|\mathcal{R}\_h|$?

Intuitively it should make sense that the probability then becomes $\frac{|\mathcal{R}\_h|}{n}$, since we have $|\mathcal{R}\_h|$ chances instead of $1$ chance for the random roll of the $n$-sided die to land where we want it to.

We can use this relationship to compute how large the initial _filter range_ $\mathcal{R}\_1$ needs to be in terms of $n$ and $\lambda$.

$$ \hat{e}\_A \leftarrow L_A \quad \quad \hat{e}\_B \leftarrow L_B $$
$$ Pr\left[ \hat{e}\_A + \hat{e}\_B \in \mathcal{R}\_1 \mod n \right] = \frac{|\mathcal{R}\_1|}{n} = \frac{1}{\lambda} $$
$$ |\mathcal{R}\_1| = \frac{n}{\lambda} $$

Booyah! A filter range of size $\frac{n}{\lambda}$ at height $h = 1$ will result in our desired filter probability $\frac{1}{\lambda}$, and thus our desired expected child list length $E[|L_{AB}|] = \lambda$.

For a range of size $\frac{n}{\lambda}$ around $0$, we should set

$$a_1 = -\frac{n}{2 \lambda} \quad \quad b_1 = \frac{n}{2 \lambda} - 1 $$

The range $\\{a_1 ... b_1\\}$ will thus have size $1 + b_1 - a_1 = \frac{n}{\lambda}$.

$$
\begin{align}
|\\{a_1 ... b_1\\}| &= 1 + b_1 - a_1 \\\\
&= 1 + (\frac{n}{2 \lambda} - 1) - (-\frac{n}{2 \lambda}) \\\\
&= \frac{n}{2 \lambda} - (-\frac{n}{2 \lambda}) \\\\
&= \frac{n}{2 \lambda} + \frac{n}{2 \lambda} \\\\
&= \frac{2n}{2 \lambda} \\\\
&= \frac{n}{\lambda} \\\\
\end{align}
$$

To rephrase more succinctly: If we make $\lambda^2$ random rolls of an $n$-sided die (i.e. $\lambda^2$ random sums modulo $n$), we should expect around $\lambda^2 \cdot \frac{n}{\lambda} \div n$ of those rolls to land in the range $\mathcal{R}\_1$, thus ending up in the child list $L_{AB}$.

$$
\begin{align}
E[|L_{AB}|] &= \overbrace{\lambda^2}^{\text{Combinations of $L_A$ and $L_B$}} \cdot
\overbrace{\frac{n}{\lambda}}^{\text{Size of range $\mathcal{R}\_1$}} \div
\overbrace{n}^{\text{Domain size}} \\\\
&= \frac{\lambda^2 n}{\lambda n} \\\\
&= \lambda \\\\
\end{align}
$$

The $\lambda$ elements in the merged child list $L_{AB}$ have an important distinctive property: ***They are now distributed randomly throughout $\mathcal{R}\_1$, instead of throughout $\mathbb{Z}\_n$.*** This range has size $\frac{n}{\lambda}$ - much smaller than $\mathbb{Z}\_n$.

Furthermore, if we add together any two elements sampled from $\mathcal{R}\_1$, their sum will fall within the range $\\{2 a_1 ... 2 b_1\\}$: a range which is predictable and easy to work with.

## Merging the Children

What about for other heights?

$$ L_{ABCD} = L_{AB} \bowtie_2 L_{CD} $$

When we merge the lists $(L_{AB}, L_{CD})$, we will be working with lists of the same expected length $\lambda$, but with elements distributed among a much smaller domain: $\mathcal{R}\_1$. This allows us to further reduce the filter range $\mathcal{R}\_2$ for height $h = 2$, and for other heights as well.

In general, if we want to expect $\lambda$ elements in each merged list, we want each each filter range $\mathcal{R}\_h$ be about $\frac{1}{\lambda}$ times the size of the previous range $\mathcal{R}\_{h-1}$.

This gives us a generalized formula for the $\bowtie_h$ operator.

$$ a_h := - \frac{n}{2 \lambda^h} \quad \quad b_h := \frac{n}{2 \lambda^h} - 1 $$
$$ \mathcal{R}\_h := \\{a_h ... b_h\\} \mod n $$
$$ L_A \bowtie_h L_B := \\{\ (\hat{e}\_A + \hat{e}\_B \mod n) \in \mathcal{R}\_h : \hat{e}\_A \in L_A, \hat{e}\_B \in L_B \ \\} $$

By repeating this procedure, merging lists in a tree-like pattern, we can gradually reduce the domain among which elements in each merged list are distributed.

|Height|Filter Range Size|
|:----:|:----------:|
|$h = 1$|$\|\mathcal{R}\_1\| = \frac{n}{\lambda}$|
|$h = 2$|$\|\mathcal{R}\_2\| = \frac{n}{\lambda^2}$|
|$h = 3$|$\|\mathcal{R}\_3\| = \frac{n}{\lambda^3}$|
|$h = 4$|$\|\mathcal{R}\_4\| = \frac{n}{\lambda^4}$|
|...|...|

Remember as well that for every pair of elements $(\hat{e}\_A, \hat{e}\_B)$ whose sum $\hat{e}\_{AB}$ falls into the filter range, we must maintain two pointers from $\hat{e}\_{AB}$ back to its parent elements $(\hat{e}\_A, \hat{e}\_B)$. This is required for Carol to be able to find the original candidate hashes which were summed to produce the final output solution. If $\hat{e}\_{AB} + \hat{e}\_{CD} \equiv e' \mod n$, then all ancestor elements $\\{\hat{e}\_A, \hat{e}\_B, \hat{e}\_C, \hat{e}\_D\\}$ which were summed to form $\hat{e}\_{AB}$ and $\hat{e}\_{CD}$ will also themselves sum to $e' \mod n$.

If a merge operation ever outputs an empty list, this is a failure condition and it means we need to retrace our steps, starting over with new randomly generated leaf lists. If we merge an empty list $L'$ with a non-empty list $L$, the output $L' \bowtie_h L$ will always be empty, since there are no pairs of elements possible between $L'$ and $L$.

## Finding the Solution

Remember our goal is not just to shrink the domain but to find a tangible solution. Thankfully, as we cinch the domain of elements closer around zero, we become exponentially more likely to find solutions. By merging lists, we are reducing the number of lists - thus reducing the number of permutations we have to check - but also we are increasing the probability that any set of elements $\\{\hat{e}\_i\\}$ from lists of a given height will sum to zero mod $n$.

We will ultimately need to perform a different operation $\bowtie$ to create the final root list $\mathcal{L}$. This operation will not involve a filter range. We instead perform a set intersection operation to see if the penultimate lists $L_{ABCD}$ and $L_{EFGH}$ share any elements which sum to zero mod $n$.

The obvious way to do this is to define the operation $L_1 \bowtie L_2$ directly (but less efficiently) by iterating through every combination of the operand lists $L_1$ and $L_2$, looking for sums of zero.

$$ L_1 \bowtie L_2 := \\{\ (\hat{e}\_1 + \hat{e}\_2 \equiv 0 \mod n) : \hat{e}\_i \in L_i \ \\} $$

More efficiently, we could perform $L_1 \bowtie L_2$ as an intersection of the lists $L_1$ and $-L_2$, where $-L_2$ indicates each element in the list $L_2$ is negated mod $n$. This allows us to use faster algorithms like a hash-intersection, with time complexity $O(|L_1| + |L_2|)$.

Consider the following lists:

$$ L_1 = \\{1, 5, 8\\} \quad \quad L_2 = \\{3, 2, 6\\} $$
$$ -L_2 = \\{7, 8, 4\\} $$
$$ \mathcal{L} = L_1 \bowtie L_2 $$

If $n = 10$, we want $\mathcal{L}$ to contain only elements created by summing to zero mod $10$. This would obviously be $8$ from $L_1$ and $2$ from $L_2$, because $8 + 2 \equiv 0 \mod 10$.

Returning to our $k = 8$ example, we could describe the whole algorithm's operations as follows.

$$ L_{AB} = L_A \bowtie_1 L_B \quad \quad
   L_{CD} = L_C \bowtie_1 L_D \quad \quad
   L_{EF} = L_E \bowtie_1 L_F \quad \quad
   L_{GH} = L_G \bowtie_1 L_H $$
$$ L_{ABCD} = L_{AB} \bowtie_2 L_{CD} \quad \quad
   L_{EFGH} = L_{EF} \bowtie_2 L_{GH} $$
$$ \mathcal{L} = L_{ABCD} \bowtie L_{EFGH} $$

For efficiency, we don't actually want to evaluate the whole tree top-to-bottom like this, because doing so would require that we keep unnecessary lists in memory during the procedure, which might be expensive if those lists are large, or if there are lots of lists. It would be better if we only load the lists into memory (or generate them) when needed.

Thanks to the tree structure of the algorithm, we can evaluate the merging operations in a deferred sequence to reduce memory requirements. We could discard the elements of parent lists if they are no longer referenced by the child lists they are merged into.

For our $k = 8$ example, the merging operations would be computed in this sequence:

1. $L_{AB} = L_A \bowtie_1 L_B$
2. $L_{CD} = L_C \bowtie_1 L_D$
3. $L_{ABCD} = L_{AB} \bowtie_2 L_{CD}$
4. $L_{EF} = L_E \bowtie_1 L_F$
5. $L_{GH} = L_G \bowtie_1 L_H$
6. $L_{EFGH} = L_{EF} \bowtie_2 L_{GH}$
7. $\mathcal{L} = L_{ABCD} \bowtie L_{EFGH}$

Leaf lists like $L_A$ and $L_G$ would only be generated once needed. Once a list is no longer needed, we can discard it, keeping only references to elements which were passed down to merged child lists.

This way, we don't have to store so much data in memory at once. Instead we only have to store a maximum of 4 lists at a time in this example: two in storage and two in working memory (to perform merge operations). For larger values of $k$ we would need more storage, but still only two lists need to exist in working memory at a time.

## List Length

We still have yet to fully understand how to choose our list length $\lambda$, so let's flesh that out.

When we build the root list $\mathcal{L} = L_{ABCD} \bowtie L_{EFGH}$, want both penultimate parent lists $(L_{ABCD}, L_{EFGH})$ to contain elements distributed among a range whose size is around $\lambda^2$. This way, with $\lambda^2$ permutations (on average) between $|L_1| \cdot |L_2|$, we can expect about $\frac{\lambda^2}{\lambda^2} = 1$ solutions (on average) when joining $L_{ABCD} \bowtie L_{EFGH}$ to make the root list.

The height of the penultimate lists will be $\log_2(k) - 1$, i.e. the last height before the root node. For $k = 8$, that is height $h = 2$.

$$
\begin{align}
\log_2(k) - 1 &= \log_2(8) - 1 \\\\
&= 3 - 1  \\\\
&= 2 \\\\
\end{align}
$$

This makes sense for our $k = 8$ example:

<img style="color: white" src="/images/wagner/list-tree.svg">

Thus, we want $|\mathcal{R}\_2| = \lambda^2$. But wait, didn't we already define the size of any given filter range? We did!

$$ a_h := - \frac{n}{2 \lambda^h} \quad \quad b_h := \frac{n}{2 \lambda^h} - 1 $$
$$ \mathcal{R}\_h := \\{a_h ... b_h\\} \mod n $$
$$ |\mathcal{R}\_h| = \frac{n}{\lambda^h} $$

And we can make use of that to compute what $\lambda$ should be!

$$
\begin{align}
|\mathcal{R}\_2| = \lambda^2 &= \frac{n}{\lambda^2} \\\\
\lambda^4 &= n \\\\
\lambda &= n^{\frac{1}{4}} \\\\
\end{align}
$$

In general, we can choose the list length $\lambda$ for number of lists $k$ modulo $n$, since we will always want the size of the penultimate range $\mathcal{R}\_{\log_2(k)-1}$ to be $\lambda^2$.

$$
\begin{align}
|\mathcal{R}\_{\log_2(k)-1}| = \lambda^2 &= \frac{n}{\lambda^{\log_2(k)-1}} \\\\
\lambda^2 \cdot \lambda^{\log_2(k) - 1} &= n \\\\
\lambda^{2 + \log_2(k) - 1} &= n \\\\
\lambda^{1 + \log_2(k)} &= n \\\\
\lambda &= n^{\frac{1}{1 + \log_2(k)}} \\\\
\end{align}
$$

In english, $\lambda$ should be the $1+\log_2(k)$-th root of $n$. This ensures all the probabilities and expectations we've set up will work out as we planned, and we should hopefully get a solution out once all the lists have been merged.

## Full Description

Above I've tried to walk through the steps of Wagner's Algorithm in detail, justifying each step in an attempt to make it seem more approachable.

In this section, I'll provide a bare description of the algorithm itself applied to InsecureMuSig, and omit the full reasoning behind each operation.

1. Fix the modulus $n$ and the desired sum $e'$.

2. Choose $k$, which describes how many lists we want to search, and how many concurrent signing sessions Carol will need to open with Alice and Bob.

3. Compute the list length $\lambda$.

$$ \lambda = n^{\frac{1}{1 + \log_2(k)}} $$

4. Define the list-generation procedure for lists $\\{L_1, L_2, ..., L_{k-1}\\}$, by sampling $\lambda$ randomized inputs per list.

$$ \forall i \in \\{1 ... k-1\\} \quad \forall j \in \\{1 ... \lambda\\} $$
$$ \hat{X}\_{i, j} \leftarrow \mathbb{S}\_n $$
$$
\begin{align}
\hat{e}\_{i, j} &= H_{\text{sig}}(\hat{X}\_{i, j}\ \|\|\ D\ \|\|\ m_i) \\\\
L_i &= \\{\hat{e}\_{i, 1}, \hat{e}\_{i, 2}, ..., \hat{e}\_{i, \lambda}\\} \\\\
\end{align}
$$

For the last leaf list $L_k$, subtract $e'$ from each of its elements.

$$ \forall j \in \\{1 ... \lambda\\} $$
$$ \hat{X}\_{k, j} \leftarrow \mathbb{S}\_n $$
$$
\begin{align}
\hat{e}\_{k, j} &= H_{\text{sig}}(\hat{X}\_{k, j}\ \|\|\ D\ \|\|\ m_k) - e' \mod n \\\\
L_k &= \\{\hat{e}\_{k, 1}, \hat{e}\_{k, 2}, ..., \hat{e}\_{k, \lambda}\\} \\\\
\end{align}
$$

For better memory efficiency, these lists should only be generated once they are needed. Each hash $\hat{e}\_{i, j}$ must contain a pointer to the curve point $\hat{X}\_{i, j}$ which was used to create it.

5. Define the merge operation $\bowtie_h$ for a given height $h$. This operator merges two lists into a new list at height $h$ by summing each combination of two elements, one from each list, modulo $n$ and including the sum in its output list if the sum falls within an inclusive range $\mathcal{R}\_h$, wrapping modulo $n$.

$$ a_h := - \frac{n}{2 \lambda^h} \quad \quad b_h := \frac{n}{2 \lambda^h} - 1 $$
$$ \mathcal{R}\_h := \\{a_h ... b_h\\} \mod n $$
$$ L_1 \bowtie_h L_2 := \\{\ (\hat{e}\_1 + \hat{e}\_2 \mod n) \in \mathcal{R}\_h : \hat{e}\_i \in L_i \ \\} $$

Every element $\hat{e}\_{ij} = \hat{e}\_i + \hat{e}\_j \mod n$ in the output list $L_{ij} = L_i \bowtie_h L_j$ must contain two pointers to the parent elements $(\hat{e}\_i, \hat{e}\_j)$ which were summed to create $\hat{e}\_{ij}$.

6. Define the join operation $\bowtie$ which will be used to construct the final root list $\mathcal{L}$ at the maximum tree height $h = \log_2(k)$. This operator returns a list composed solely of zeros which also have pointers to the parent elements $(\hat{e}\_i, \hat{e}\_j)$ which were summed to create them.

$$ L_1 \bowtie L_2 := \\{\ (\hat{e}\_1 + \hat{e}\_2 = 0 \mod n) : \hat{e}\_i \in L_i \ \\} $$

7. Begin merging lists.

- Start by generating the first two leaf lists $L_1$ and $L_2$, and merge them as $L_{12} = L_1 \bowtie_1 L_2$ at height $h = 1$.
- Generate lists $L_3$ and $L_4$. Merge them as $L_{34} = L_3 \bowtie_1 L_4$.
- Merge these two lists $L_{1234} = L_{12} \bowtie_2 L_{34}$ at height $h = 2$.
- Generate new lists $L_5$ and $L_6$.

Continue in this fashion, proceeding to the next height whenever possible, generating new leaf lists and merging them as required, until we have the two penultimate lists at height $h = \log_2(k) - 1$.

If a merge operation ever results in an empty list, discard this branch of the tree and start over with freshly generated leaf lists.

8. Join the penultimate lists $L_i$ and $L_j$ with the join operator $\bowtie$.

$$ \mathcal{L} = L_i \bowtie L_j $$

If $\mathcal{L}$ is empty, start over again with freshly generated leaf lists.

9. If $\mathcal{L}$ contains at least one element, follow its pointers back up the tree to the hashes in the leaf lists. The result will be a set of hashes $\\{e_1, e_2, ..., \hat{e}\_k\\}$ such that $e_1 + e_2 + ... + \hat{e}\_k = 0$.

10. Follow the pointers from the leaf elements to find the curve points $\\{X_1, X_2, ... X_k\\}$ which were hashed to construct each element. Since the last leaf element $\hat{e}\_k$ was constructed by subtracting $e'$ from the actual challenge, this means the set of nonce points $\\{X_1, X_2, ... X_k\\}$ will result in signature challenges which sum to $e' \mod n$.

$$ e' = H_{\text{sig}}(R'\ \|\|\ D\ \|\|\ m') $$
$$ e_i = H_{\text{sig}}(X_i\ \|\|\ D\ \|\|\ m_i) \quad \forall i \in \\{1...k\\} $$
$$ \hat{e}\_k = e_k - e' $$
$$
\begin{align}
e_1 + e_2 + ... + \hat{e}\_k &\equiv 0 \mod n \\\\
e_1 + e_2 + ... + e_k - e' &\equiv 0 \mod n \\\\
e_1 + e_2 + ... + e_k &\equiv e' \mod n \\\\
\end{align}
$$

11. Carol can now provide rogue nonces to Alice and Bob so that $\\{X_1, X_2, ... X_k\\}$ are used as the aggregate nonces in each of the $k$ signing sessions, as discussed before.

## Performance

Let's analyze the computational complexity of Wagner's Algorithm.

- At each list-merging operation ($L_1 \bowtie_h L_2$), we must perform $\lambda^2$ simple addition operations.
- At the root node at height $\log_2(k)$, we perform a join operation $\bowtie$ which uses $2\lambda$ computations. These $2 \lambda$ operations are insignificant next to the rest of the computations though, so we can safely ignore them.
- We must perform $\frac{k}{2}$ merging operations at height $h = 1$, then $\frac{k}{4}$ merging operations at height $h = 2$, then $\frac{k}{8}$ operations at $h = 3$, and so on.
- This means we perform $\frac{k}{2} + \frac{k}{4} + \frac{k}{8} + ... + \frac{k}{2^{\log_2(k)-1}}$ merges, for a total of $\lambda^2 \left( \frac{k}{2} + \frac{k}{4} + \frac{k}{8} + ... + \frac{k}{2^{\log_2(k)-1}} \right)$ simple addition operations.

The sequence $\frac{k}{2} + \frac{k}{4} + \frac{k}{8} + ... + \frac{k}{2^{\log_2(k)-1}}$ can be rewritten as the sum of a finite geometric series:

$$ \sum_{i=1}^{\log_2(k)-1} \frac{k}{2^i} $$
$$ \sum_{i=1}^{\log_2(k)-1} \frac{k}{2} \left( \frac{1}{2} \right) ^{i-1} $$

[The sum of a finite geometric series starting at $a$ with ratio $r$ over $n$ iterations is](https://www.khanacademy.org/math/algebra2/x2ec2f6f830c9fb89:poly-factor/x2ec2f6f830c9fb89:geo-series/v/deriving-formula-for-sum-of-finite-geometric-series) $a\left( \frac{1-r^n}{1-r} \right)$. Therefore:

$$
\begin{align}
\sum_{i=1}^{\log_2(k)-1} \frac{k}{2} \left( \frac{1}{2} \right) ^{i-1} &=
   \frac{k}{2} \left( \frac{1 - \left( \frac{1}{2} \right)^{\log_2(k)-1}}{1 - \frac{1}{2}} \right) \\\\
&= \frac{k}{2} \left( \frac{1 - \left( \frac{1}{2} \right)^{\log_2(k)-1}}{\frac{1}{2}} \right) \\\\
&= \frac{k}{2} \left( 2 \left( 1 - \left( \frac{1}{2} \right)^{\log_2(k)-1} \right) \right) \\\\
&= k \left( 1 - \left( \frac{1}{2} \right)^{\log_2(k)-1} \right) \\\\
\end{align}
$$

Because $\left( \frac{1}{2} \right)^x = \frac{1}{2^x} = 2^{-x}$:

$$
\begin{align}
&= k \left( 1 - 2^{1-\log_2(k)} \right) \\\\
&= k \left( 1 - \frac{2}{2^{\log_2(k)}} \right) \\\\
&= k \left( 1 - \frac{2}{k} \right) \\\\
&= k - 2 \\\\
\end{align}
$$

A quick sanity check and our formula seems to work:

$$ k = 32 \quad \quad \log_2(k) = 5 $$
$$
\begin{align}
\sum_{i=1}^{\log_2(k)-1} \frac{k}{2^i} &= \sum_{i=1}^{5-1} \frac{32}{2^i} \\\\
&= \sum_{i=1}^{4} \frac{32}{2^i} \\\\
&= \frac{32}{2} + \frac{32}{4} + \frac{32}{8} + \frac{32}{16} \\\\
&= 16 + 8 + 4 + 2 \\\\
&= 30 \\\\
&= k - 2 \\\\
\end{align}
$$

Thus in total, we perform $\lambda^2 (k - 2)$ simple operations, which make up the bulk of the computational work in the algorithm.

### Optimizations

There's an easy optimization which boosts the speed of Wagner's Algorithm by at least one order of magnitude.

The bulk of the work occurs when adding together every combination of elements $(\hat{e}\_1, \hat{e}\_2)$ between two lists $(L_1, L_2)$ of length $\lambda$, and filtering the sums based on a range $\\{a_h ... b_h\\}$ modulo $n$. The merging operation as I've described it above would look something like this in Python.

```python
def merge(L1, L2):
  sums = []
  a, b = filter_range(height)
  for e1 in L1:
    for e2 in L2:
      z = (e1 + e2) % n
      if z >= a or z <= b:
        sums.append(z)
  return sums
```

The complexity thereof is $O(\lambda^2)$, because as written, it appears we have to test every possible combination of elements, but this needn't be so.

Remember that $L_1$ and $L_2$ are simple collections of numbers. We can restructure them however we want to improve efficiency and save work. There exist all manners of data structures for doing this.

One option would be to _sort the list_ $L_2$ prior to iterating through $L_1$. For every $\hat{e}\_1$ we draw from $L_1$, we now have the benefit of working with a sorted $L_2$.

Observe how for any given $\hat{e}\_1$, there is only a specific range of values which $\hat{e}\_2$ can be, such that $\hat{e}\_1 + \hat{e}\_2 \mod n \in \\{a_h ... b_h\\}$. Namely:

$$
\begin{align}
\hat{e}\_2 \in \\{a_h - \hat{e}\_1 ... b_h - \hat{e}\_1\\} \mod n \\\\
\end{align}
$$

Any values in $L_2$ outside the range $\\{a_h - \hat{e}\_1 ... b_h - \hat{e}\_1\\} \mod n$ need not be checked at all, because we know for certain that they will never sum with $\hat{e}\_1$ to a value in $\\{a_h ... b_h\\}$.

If $L_2$ is sorted, we can use a binary search to quickly ($O(\log_2(\lambda))$ complexity) find the location in $L_2$ where elements close to $a_h - \hat{e}\_1 \mod n$ would be sorted. We then iterate through those elements in $L_2$, adding them to the new merged child list $L_{12}$ until we reach an element larger than $b_h - \hat{e}\_1 \mod n$, at which point we can halt our search of $L_2$, and continue to the next element in $L_1$.

As an example, consider a case where:

$$ n = 32 $$
$$ a_h = -4 \equiv 28 \mod n $$
$$ b_h = 3 $$

We are merging two lists like so:

$$
\begin{align}
L_1 &= \\{5, 8, 19, 30\\} \\\\
L_2 &= \\{6, 9, 10, 21\\} \\\\
\end{align}
$$

- First, we loop through $L_1$ and encounter the element $\hat{e}\_1 = 5$.
  - Compute the minimum viable value for $\hat{e}\_2$ as $a_h - \hat{e}\_1 = -4 - 5 \equiv 23 \mod 32$.
  - Since $L_2$ is sorted, we can binary search it to quickly find where we could expect to find $23$ if it existed in $L_2$. It would be at the very end of $L_2$ though, so we wrap around to the beginning of $L_2$ and begin our search there at $\hat{e}\_2 = 6$.
  - $5 + 6 = 11$, which does not fall into the range $\\{28 ... 3\\} \mod 32$. We can now discontinue our search for a partner sum for $5$. This checks out, because indeed there is *no number* $\hat{e}\_2 \in \\{7...22\\}$ which would sum with $5$ such that $5 + \hat{e}\_2 \in \\{28 ... 3\\} \mod 32$.
- Continuing our loop through $L_1$, we encounter the element $\hat{e}\_1 = 8$.
  - Compute the minimum viable value for $\hat{e}\_2$ as $a_h - \hat{e}\_1 = -4 - 8 \equiv 20 \mod 32$.
  - Binary search $L_2$ to find where $20$ would sort into $L_2$. We find the index for the next highest value in $L_2$: $\hat{e}\_2 = 21$.
  - Beginning our search here, we find that $8 + 21 = 29$ which _does_ fall within $\\{28...3\\} \mod 32$. We add $29$ to the output list $L_{12}$ and continue looping forward through $L_2$.
  - We hit the end of $L_2$, but once again we wrap around to the beginning of $L_2$. We encounter the element $\hat{e}\_2 = 6$.
  - $8 + 6 = 14$ does not fall within the filter range. We discontinue the loop here and move on to the next element of $L_1$. Again this checks out, because no $\hat{e}\_2 \in \\{7...19\\}$ can provide $8 + \hat{e}\_2 \in \\{28 ... 3\\} \mod 32$.

In Python, this might look something like so:

```python
from bisect import bisect_left

def fast_merge(L1, L2):
  sums = []
  a, b = filter_range(height)
  L2 = sorted(L2)

  for e1 in L1:
    min_index = bisect_left(L2, (a - e1) % n)
    index = min_index
    while index < min_index + len(L2):
      e2 = L2[index % len(L2)]
      z = (e1 + e2) % n
      if z >= a or z <= b:
        sums.append(Lineage(z, e1, e2))
      else:
        break # no more useful elements to be found.
      index += 1

  return sums
```

This new merge operation has significantly lower complexity.

- It requires one sorting operation per merge, which can be done in $O(\lambda \log_2(\lambda))$ time with an algorithm such as heapsort, quicksort or merge-sort.
- Once $L_2$ has been sorted, we loop through $L_1$ for a total of $\lambda$ iterations.
- On each iteration, we perform a binary search of $L_2$ in $O(\log_2(\lambda))$ time. We then add an average of 1 element to the output list $L_{12}$ (since we expect $L_{12}$ to have $\lambda$ elements), and also perform one extra check which tells us when we run out of useful elements in $L_2$.

In total, our new merge operation algorithm requires

$$
\begin{align}
\lambda \log_2(\lambda) + \lambda (\log_2(\lambda) + 2) &= \lambda \log_2(\lambda) + \lambda \log_2(\lambda) + 2 \lambda \\\\
&= 2 \lambda \log_2(\lambda) + 2 \lambda \\\\
&= 2 \lambda ( \log_2(\lambda) + 1 ) \\\\
\end{align}
$$

computations. It runs in $O(2 \lambda ( \log_2(\lambda) + 1 ))$ time.

This is a big improvement over the $O(\lambda^2)$ complexity for the naive sequential algorithm. For lists of small size, there is barely a difference, but the larger $\lambda$ becomes, the greater the efficiency savings. For all $\lambda > 8$, the binary-searching algorithm takes the cake.

<img src="/images/wagner/merge-complexity-graph.png">

To put this into perspective, merging two lists of length $\lambda = 2048$ we'd be doing about **91 times more work** with the sequential merge algorithm.

Since we are performing $k - 2$ merges in total, the whole algorithm requires $(k - 2)(2\lambda (\log_2(\lambda) + 1))$ operations.

### Choosing $k$

If we fix $n$, note that the more lists we have - i.e. the higher $k$ is - the fewer elements we need in each list, because $\lambda = n^{\frac{1}{1 + \log_2(k)}}$. For instance, with secp256k1's $n \approx 2^{256}$, then with $k = 8$, we need $n^{\frac{1}{4}} \approx 2^{64}$ hashes per list. With 128 lists ($k = 128$) we need only $n^{\frac{1}{8}} \approx 2^{32}$ hashes per list to be able to find a solution with Wagner's Algorithm.

Does fewer elements per list result in fewer computations overall? Is there some ideal number of lists which optimizes the amount of computation required to find a solution? In our case, we can set $k$ to whatever we want within reason - as long as Carol can effectively manage $k$ concurrent signing sessions with Alice and Bob.

The total work we need to do is $(k - 2)(2 \lambda (\log_2(\lambda) + 1))$. If you wanted to be a fancy-pants, you could take the derivative of this expression with respect to $k$, and find out exactly how many lists would be most efficient for any given value of $n$.

But however nerdy I may be, I am also adverse to pointless effort. It would be much easier to simply guess and check every plausible value of $k$ for a given $n$. Since we only want values of $k$ which are powers of two, such a test should be very simple and fast.

```python
from math import log2, inf

# secp256k1 curve order
n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

min_computations = inf
best_k = 1

for log_k in range(2, 32):
  k = 2 ** log_k
  lamda = n ** (1 / (1 + log_k))
  computations = round((k - 2) * (2 * lamda * (log2(lamda) + 1)))

  change = computations - min_computations
  print(
    "k =% 8d; computations required:% 30d; change: %+.2f%%" %
    (k, computations, 100*change/min_computations)
  )

  if computations < min_computations:
    min_computations = computations
    best_k = k
  else:
    break

print()
print("Best is k = %d = 2^%d" % (best_k, log2(best_k)))
```

```
k =       4; computations required: 16831834955285952201643524096; change: +nan%
k =       8; computations required:       14388460377493450260480; change: -100.00%
k =      16; computations required:           3780631184960625152; change: -99.97%
k =      32; computations required:             18291434784828656; change: -99.52%
k =      64; computations required:               475747350059814; change: -97.40%
k =     128; computations required:                35716948033536; change: -92.49%
k =     256; computations required:                 5463841149033; change: -84.70%
k =     512; computations required:                 1379906617598; change: -74.74%
k =    1024; computations required:                  502792114295; change: -63.56%
k =    2048; computations required:                  241469572845; change: -51.97%
k =    4096; computations required:                  143536403739; change: -40.56%
k =    8192; computations required:                  100948092745; change: -29.67%
k =   16384; computations required:                   81255644943; change: -19.51%
k =   32768; computations required:                   73009987584; change: -10.15%
k =   65536; computations required:                   71840273971; change: -1.60%
k =  131072; computations required:                   76265276072; change: +6.16%

Best is k = 65536 = 2^16
```

Looks like for secp256k1, the best case for computation time of Wagner's Algorithm is $k = 2^{16}$ for a total of $65536$ lists. Notice that beyond a point we start to see diminishing returns as we further double $k$.

Realistically, Carol may want to set $k$ somewhere between $1024$ and $65536$. Below $1024$ lists, Carol would lose out on orders of magnitude of efficiency savings. Above $65536$ lists, it would become impractical for Carol to execute so many concurrent signing sessions with Alice and Bob, and she wouldn't even be gaining any more computational efficiency savings by taking the risk.

## Normal Distributions

There is one odd detail of Wagner's Algorithm which still mystifies me.

If we sample two random elements $(\hat{e}\_{AB}, \hat{e}\_{CD})$ from lists $(L_{AB}, L_{CD})$ at height $h = 2$ and add them together modulo $n$, those sums will form a [_normal distribution_](https://en.wikipedia.org/wiki/Normal_distribution) (AKA a bell curve) among a range which is _double the size_ of $\mathcal{R}\_1$, and centered on $-1$.

This is because the filter range $\mathcal{R}\_1$ is less than half the size of $n$, so when we add two elements from $\mathcal{R}\_1$ together, their sum could be at most $2 b_1$, and at minimum $2 a_1$.

$$ a_1 = -\frac{n}{2 \lambda} \quad b_1 = \frac{n}{2 \lambda} - 1 $$
$$ \mathcal{R}\_1 = \\{a_1 ... b_1\\} $$
$$ \hat{e}\_{AB} \leftarrow L_{AB} \quad \hat{e}\_{CD} \leftarrow L_{CD} $$
$$ \hat{e}\_{AB} + \hat{e}\_{CD} \in \\{2 a_1 ... 2 b_1 \\} $$

Thus, for any pair $(\hat{e}\_{AB}, \hat{e}\_{CD})$ randomly sampled from $(L_{AB}, L_{CD})$, the distribution of their sum will not be a perfectly random $n$-sided die as we had at $h = 1$. With each sum $\hat{e}\_{AB} + \hat{e}\_{CD} \mod n$ we are rolling a _weighted_ probability, where sums closer to $n - 1$ are more likely to occur, since there are more pairs of numbers in $\mathcal{R}\_1$ which sum to values numbers to $n - 1$.

To better understand this, imagine a smaller-scale hypothetical example where $\mathcal{R} = \\{-5 ... 4\\}$. If we sample two random values from $\mathcal{R}$ and sum them, we will get a normal distribution. Provided each value in $\mathcal{R}$ is equally likely to be sampled, we can arrange two copies of $\mathcal{R}$ in a grid and visually see which sums are most common.

|+|-5|-4|-3|-2|-1|0|1|2|3|4|
|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
|-5|-10|-9|-8|-7|-6|-5|-4|-3|-2|-1|
|-4|-9|-8|-7|-6|-5|-4|-3|-2|-1|0|
|-3|-8|-7|-6|-5|-4|-3|-2|-1|0|1|
|-2|-7|-6|-5|-4|-3|-2|-1|0|1|2|
|-1|-6|-5|-4|-3|-2|-1|0|1|2|3|
| 0|-5|-4|-3|-2|-1|0|1|2|3|4|
| 1|-4|-3|-2|-1|0|1|2|3|4|5|
| 2|-3|-2|-1|0|1|2|3|4|5|6|
| 3|-2|-1|0|1|2|3|4|5|6|7|
| 4|-1|0|1|2|3|4|5|6|7|8|

<img src="/images/wagner/normal-distribution.png">

As you can see, $-1$ is the most common sum. The same will also be true of our lists of hashes. The sum of two elements $(\hat{e}\_{AB}, \hat{e}\_{CD})$ randomly sampled from $\mathcal{R}\_1$ will also tend to be clustered more densely around $-1$, since we defined the range $[a_1, b_1]$ to be centered at $-1$.

Notably this does change the probability math when computing how to define our next filter range $\mathcal{R}\_2$. We wanted to define the interval $[a_2, b_2]$ such that the probability of $\hat{e}\_{AB} + \hat{e}\_{CD} \mod n$ falling into $[a_2, b_2]$ is exactly $\frac{1}{\lambda}$.

Strangely however, Wagner's original paper makes no mention of this normal distribution. Wagner only illustrates the generalized form of his algorithm for $k = 4$, where this distribution never occurs, because $h$ never rises above $1$.

> We can also apply the tree algorithm to the group $(\mathbb{Z} / m \mathbb{Z}, +)$ where $m$ is arbitrary. Let $[a, b] := \\{x \in \mathbb{Z} / m \mathbb{Z} : a \le x \le b\\}$ denote the interval of elements between a and b (wrapping modulo m), and define the join operation $L_1 \bowtie_{[a,b]} L_2$ to represent the solutions to $x_1 + x_2 \in [a, b]$ with $x_i \in L_i$. Then we may solve a 4-sum problem over $\mathbb{Z} / m \mathbb{Z}$ by computing $(L_1 \bowtie_{[a,b]} L_2) \bowtie (L_3 \bowtie_{[a,b]} L_4)$ where $[a, b] = [−m/2^{\ell+1}, m/2^{\ell+1} − 1]$ and $\ell = \frac{1}{3} \log m$. In general, one can adapt the $k$-tree algorithm to work in $(\mathbb{Z} / m \mathbb{Z}, +)$ by replacing each $\bowtie_{\ell}$ operator with $\bowtie_{[−m/2^{\ell+1}, m/2^{\ell+1} − 1]}$, and this will let us solve $k$-sum problems modulo $m$ about as quickly as we can for xor.

In his paper, Wagner focused on solving what he dubbed _the $k$-sum problem:_ finding $k$ numbers from $k$ randomly generated lists which sum to zero. However he was clearly more focused on finding binary numbers which XOR to zero, rather than on additive groups of integers modulo $n$ (or $m$, as Wagner used in the above excerpt). It's possible he never considered this consequence of the generalization of his algorithm, or perhaps he knew but realized it was inconsequential and so omitted it from his paper.

Peculiarly, Wagner's Algorithm still seems to work for large values of $k > 4$, so the normal distribution doesn't appear to have a significant effect on the probabilities involved. I spent some time trying to work out the exact probabilities at $h > 1$, but once I realized the change was negligible, I abandoned that line of investigation.

## Implementation

To prove to myself that this absurd-seeming procedure actually works, I wrote up a pure Python implementation of Wagner's Algorithm. [Click here to view the code on Github](https://github.com/conduition/wagner).

You can install and use it with `pip install wagner`.

```python
import random
import hashlib
import wagner


def hashfunc(r, n, index):
  r_bytes = r.to_bytes((int.bit_length(n) + 7) // 8, 'big')
  preimage = r_bytes + index.to_bytes(16, 'big')
  h = hashlib.sha1(preimage).digest()
  return int.from_bytes(h, 'big') % n


def generator(n, index):
  r = random.randrange(0, n)
  return wagner.Lineage(hashfunc(r, n, index), r)


if __name__ == "__main__":
  n = 2 ** 128
  preimages = wagner.solve(n, 888, generator=generator)
  print(sum(hashfunc(r, n, index) for index, r in enumerate(preimages)) % n) # -> 888
```

My code demonstrates that although the attack is plausible, it is still very hard to pull off. Not to disparage my performance optimizations, but the procedure is quite slow for large values of $n$. The practical limit to compute a solution in a reasonable amount of time, at least on my current machine, is $n <= 2^{128}$ - much smaller than secp256k1's $n \approx 2^{256}$.

Beyond this, the procedure is too slow to execute a real-world attack. After opening her $k$ signing sessions, Carol cannot wait too long to compute the points $\\{X_1, X_2, ..., X_k\\}$. She needs to compute those points relatively quickly so she can determine which rogue nonces to supply to Alice and Bob. If Carol takes too long, Alice and Bob may have given up on the signing sessions, or even realized what Carol is up to.

However, simply because _my_ code does not compute solutions fast enough doesn't mean the attack is infeasible. There exist many much stronger computers out there, and I have barely scratched the surface of the possible optimizations one can make to Wagner's Algorithm. Not to mention I wrote my implementation in one of the slowest programming languages in town, and made no attempts whatsoever at parallelization. With enough rented cloud computing power, a faster language like C or Rust, and a cleverly optimized implementation, it would certainly be plausible to execute this attack.

## Conclusion

Thankfully, the whole attack has been made obsolete against the real MuSig, due to the nonce commitment round which was introduced in the updated MuSig protocol. Without the option to choose rogue nonces, Carol cannot control the challenges.

However, as [Blockstream's Jonas Nick writes](https://medium.com/blockstream/insecure-shortcuts-in-musig-2ad0d38a97da), Wagner's Attack is definitely still applicable to MuSig in some edgecases though. It pays for devs to really understand how this attack works, so that hopefully we can avoid reintroducing the same vulnerability in when creating new protocols or when optimizing existing systems.

The subtle math behind the attack is fascinating. It goes to show that however experienced one might be, the true test of a cryptosystem occurs when it is exposed to a critical and observant community. It is _absolutely essential_ for experts to attack each other's systems. There's simply no way for any one person (or even a group of people) to collectively hold in their mind all the myriad ways their system could be attacked.

In cryptography, a solid proof is like a well-forged sword... but rigorous peer review is the grindstone, and time is the foot which effects the sharpening.

<details>
  <summary>Sources</summary>

- [_On the Security of Two-Round Multi-Signatures_ - Drijvers et al](https://eprint.iacr.org/2018/417)
- [_A Generalized Birthday Problem_ - David Wagner](https://link.springer.com/content/pdf/10.1007/3-540-45708-9_19.pdf)
- [_Insecure Shortcuts in MuSig_ - Blockstream](https://medium.com/blockstream/insecure-shortcuts-in-musig-2ad0d38a97da)
- https://bitcoin.stackexchange.com/questions/91534/musig-signature-interactivity
- [_Birthday Attack_ - Wikipedia](https://en.wikipedia.org/wiki/Birthday_attack)

</details>
