---
title: Resharing Shamir Secret Shares to Change the Threshold
date: 2023-09-06
mathjax: true
category: cryptography
---

In my last article on [Shamir Secret Sharing](/cryptography/shamir/), I outlined the basics of Shamir Secret Sharing (SSS) and described how polynomial interpolation works. Then I described an _issuance_ protocol which adds new shareholders or recovers lost shares using multi-party computation practices. If you're not already familiar with Shamir Secret Sharing, I highly recommend reading that article first.

This article will focus on a protocol called _secret resharing,_ which I first heard about in [this thesis by Mehrdad Nojoumian](https://uwspace.uwaterloo.ca/bitstream/handle/10012/6858/nojoumian_mehrdad.pdf?sequence=1#subsection.4.3.1).

Resharing can be used to recompute new secret shares, optionally with a new threshold. In a Shamir secret sharing group with threshold $t$, resharing allows a group of $t$ or more shareholders to cycle their shares in such a way that old shares from before the resharing event and new shares from after it are not compatible with one another. This might sound undesirable, but there are many cases where a group of shareholders may want to invalidate someone else's share.

For example, what if one share is accidentally exposed? If one share is public, the group's threshold has essentially decreased from $t$ to $t - 1$, beause that exposed share can now be assumed to be public knowledge. The bearer of the exposed share no longer has any weight in the group.

The group as a whole may wish to restore the security of their shares by revoke the exposed share. By regenerating their shares, the group ensures the exposed share cannot be be used, _as long as the rest of the group securely erases their old shares as well._

Resharing also allows shareholders to change the threshold of their shares from $t$ to any new threshold $t'$. Shares created from the resharing protocol have the new threshold $t'$ needed to recover the original shared secret.

As an added bonus, the set of participants can be changed during a resharing session: The set of shareholders _before_ resharing can be different from the set of participants _after_ resharing. Any number of old shareholders can be removed and any number of new shareholders can be added.

We want our protocol to work in an operating environment where some of our peers may be malicious. The protocol must be _verifiable,_ so that adversarial shareholders cannot collude to corrupt the new shares, or learn anything about the group's secret. This is called _verifiable_ secret resharing, or VSR for short.

## Mission

A set of $t$ or more shareholders may wish to change the threshold of their group's shares from $t$ to some new threshold $t'$ by regenerating their shares. Any set of $t - 1$ or fewer shares from before the resharing execution must not reveal any information about the new shares produced by resharing.

If $t' = t$, then the resharing protocol should still work, but instead has the intended effect of simply rendering old shares unusable without changing the threshold.

The set of shareholders may also be changing. Some shareholder may be removed, and others introduced into the group.

Here follows a resharing protocol with verifiable commitments which enables a set of $t$ or more shareholders to compute updated shares. Shareholders who are offline at the time must be able to receive asynchronous messages, otherwise their old shares won't be compatible with the new shares.

A detailed explanation of VSR is given in [this paper by Wong, Wing, and Wang](https://apps.dtic.mil/sti/pdfs/ADA461227.pdf).

## Parameters

Yippee! Let's _let_ all the things.

- Let $n$ be the total number of shareholders in the group.
- Let $t$ be the old threshold.
- Let $t'$ be the desired new threshold.
- Let $\mathbb{Z}\_q$ be the finite field of integers mod some prime number $q$.
- Let $f(x)$ be the old secret polynomial of degree $t - 1$, with coefficients $\\{s_0, s_1, ..., s_{t-1}\\}$ in $\mathbb{Z}\_q$.
- Let $f'(x)$ be the new secret polynomial of degree $t' - 1$, with coefficients $\\{s_0', s_1', ..., s_{t-1}'\\}$ in $\mathbb{Z}\_q$.
- Let $G$ be an additive group generator (e.g. an elliptic curve base point) of order $q$.
- Let each $i \in \\{1...n\\}$ be an index in $\mathbb{Z}\_q$ representing a share.
- Let $z_i$ be the original evaluation of the secret share polynomial for share $i$, such that $z_i = f(i)$.
- Let $z_i'$ be the new evaluation of the secret share polynomial for share $i$, such that $z_i' = f'(i)$.
- Let $S$ be the set of at least $t$ share indexes whose bearers are online and participating in the threshold change protocol.
- Let $I(P) \rightarrow p(x)$ be an interpolation algorithm which takes in a set of points $P$ and outputs a unique polynomial $p(x)$ which interpolates all points in $P$.
- Let $\\{\phi_0, \phi_1, ..., \phi_{t-1}\\}$ be the original public coefficients of the secret polynomial $f(x)$, such that

$$ f(x) \cdot G = \sum_{k = 0}^{t-1} \phi_k x^k $$

- Let $\gamma_i^X$ be the Lagrange coefficients for a set of inputs $X$, used to evaluate a polynomial at $0$.

$$
\begin{align}
\gamma_i^X &= \prod_{\substack{j \in X \\\\ j \ne i}} \frac{0 - j}{i - j} \\\\
           &= \prod_{\substack{j \in X \\\\ j \ne i}} \frac{j}{j - i} \\\\
\end{align}
$$

...such that $\sum_{i \in X} \gamma^X_i p(i) = p(0)$ for any polynomial $p(x)$ of degree at most $|X|-1$.

# Strategy

Our goal is to construct a protocol which gives each shareholder $i$ the means to verifiably compute $f'(i)$, where $f'(x)$ is a new randomly generated degree $t'-1$ polynomial, which shares a constant term with the old joint share polynomial $f(x)$, such that $f'(0) = f(0) = s_0$. Once participants have shares generated by $f'(x)$, the threshold is changed without changing the secret, because one needs only $t'$ evaluations to interpolate the degree $t' - 1$ polynomial $f'(x)$, and thus learn the original secret $f'(0) = s_0$.

Let's denote the new coefficients of this new polynomial $\\{s_0', s_1', ..., s_{t'-1}'\\}$. Since the evaluation $f'(0)$ must be the same as $f(0)$, we can easily conclude the constant terms $s_0' = s_0$ are the same. What about the other coefficients?

Naturally, no malicious subset of fewer than $t$ shareholders must be able to learn or influence anything about these new coefficients. Thus, the new coefficients $\\{s_1', s_2', ..., s_{t'-1}'\\}$ must be jointly constructed. Every shareholder in $S$ must contribute a random value to every coefficient. This ensures a cabal of $t - 1$ malicious shareholders cannot bias $f'(x)$ unfairly - As long as at least one party contributes honest random values, the new coefficients will also be random.

One way to do this would be to get each shareholder $i$ to generate $t' - 1$ random values $\\{a_{(i, 1)}, a_{(i, 2)}, ..., a_{(i, t'-1)}\\}$ (one for each of the new coefficients). We treat each $\\{a_{(i, k)}\\}\_{i \in S}$ as a set of $t$ points $P_k = \\{(i, a_{(i, k)})\\}\_{i \in S}$. Note how each shareholder in $S$ contributes one point to each set $P_k$ - one for every coefficient in $\\{s_1', s_2', ..., s_{t'-1}'\\}$.

Consider the _coefficient polynomial_ $c_k(x)$ of degree at most $t - 1$ which interpolates all $t$ points in $P_k$. The constant term $c_k(0)$ will be uniformly random. Any attacker who knows $t-1$ or fewer evaluations of $c_k(x)$ (i.e. who knows $t-1$ values of $a_{(i, k)}$) will be unable to interpolate $c_k(0)$.

We treat each $c_k(0)$ as the $k$-th coefficient of $f'(x)$ for $k \in \\{1...t'-1\\}$. This defines $f'(x)$ as a degree $t' - 1$ polynomial with jointly-chosen random coefficients.

$$ P_k = \\{(i, a_{(i, k)})\\}\_{i \in S} $$
$$ I(P_k) \rightarrow c_k(x) $$
$$
\begin{align}
s_k' &= c_k(0) \\\\
     &= \sum_{i \in S} \gamma^S_i a_{(i, k)} \\\\
f'(x) &= \sum_{k = 0}^{t' - 1} s_k' x^k \\\\
      &= s_0 + \sum_{k = 1}^{t' - 1} s_k' x^k \\\\
      &= s_0 + \sum_{k = 1}^{t' - 1} x^k \overbrace{\sum_{i \in S} \gamma^S_i a_{(i, k)}}^{\text{coefficients}} \\\\
\end{align}
$$

This seems a woefully roundabout way of constructing a random polynomial, but the reason why we approached $f'(x)$ this way will make sense once each shareholder tries to compute her new share.

## Multi-Party Interpolation

We have a definition for $f'(x)$ which gives us a polynomial with our desired properties, but how can we ensure each shareholder $i$ can compute their own $f'(i)$ trustlessly? It is not immediately clear how to do this.

Recall how we defined $f'(x)$ above. We'll take that definition and expand it, playing some algebraic trickery to find how shareholders can compute their new share $f'(x)$ without learning or using any secret information which should belong to other shareholders.

$$
\begin{align}
s_k' &= \sum_{i \in S} \gamma^S_i a_{(i, k)} \\\\
f'(x) &= s_0 + \sum_{k = 1}^{t' - 1} s_k' x^k \\\\
      &= s_0 + \sum_{k = 1}^{t' - 1} x^k \sum_{i \in S} \gamma^S_i a_{(i, k)} \\\\
      &= s_0 + \sum_{k = 1}^{t' - 1} \sum_{i \in S} \gamma^S_i a_{(i, k)} x^k \\\\
      &= s_0 + \sum_{i \in S} \sum_{k = 1}^{t' - 1} \gamma^S_i a_{(i, k)} x^k \\\\
      &= s_0 + \sum_{i \in S} \gamma^S_i \sum_{k = 1}^{t' - 1} a_{(i, k)} x^k \\\\
\end{align}
$$

Individual shareholders don't know $s_0$, so we should try to substitute something else in its place. We can use a Lagrange interpolation polynomial, interpolating the $t$ shares $\\{z_i\\}\_{i \in S}$, in place of $s_0$. This allows us to factor out the sum and Lagrange coefficients.

$$
\begin{align}
s_0 &= \sum_{i \in S} \gamma^S_i z_i \\\\
f'(x) &= s_0 + \sum_{i \in S} \gamma^S_i \sum_{k = 1}^{t' - 1} a_{(i, k)} x^k \\\\
      &= \sum_{i \in S} \gamma^S_i z_i + \sum_{i \in S} \gamma^S_i \sum_{k = 1}^{t' - 1} a_{(i, k)} x^k \\\\
      &= \sum_{i \in S} \gamma^S_i \left( z_i + \sum_{k = 1}^{t'-1} a_{(i, k)} x^k \right) \\\\
\end{align}
$$

Remember that $\gamma^S_i$ is an interpolating Lagrange coefficient, so that $\sum_{i \in S} \gamma_i^S p(i) = p(0)$ for any polynomial $p(x)$ with degree at most $t-1$. _That expression beside the Lagrange coefficient can also be thought of as a polynomial with parameter $i$ and input variable $x$._

$$
\begin{align}
f'(x) &= \sum_{i \in S} \gamma^S_i \overbrace{\left( z_i + \sum_{k = 1}^{t'-1} a_{(i, k)} x^k \right)}^{\text{this is a polynomial function}} \\\\
      &= \sum_{i \in S} \gamma^S_i ( \overbrace{z_i + a_{(i, 1)} x + a_{(i, 2)} x^2 + ... + a_{(i, t'-1)} x^{t'-1}}^{\text{this is a polynomial function}} ) \\\\
\end{align}
$$

This expression for $f'(x)$ shows us a surprising (but mind-warping) fact: Any new share $f'(x)$ can be thought of as the constant term of a hypothetical degree $t-1$ polynomial, which is itself constructed by interpolating evaluations of a set of $t$ _distinct polynomials_ on the same input $x$.

Let's clean up this definition and denote those _resharing polynomials_ as $\\{g_j(x)\\}\_{j \in S}$.

$$ g_j(x) = z_j + \sum_{k = 1}^{t' - 1} a_{(j, k)} x^k $$

***Notice how shareholder $j$ has access to all the information needed to evaluate $g_j(x)$ on any input $x$.***

A new share $z_i'$ can be computed by interpolating these $t$ polynomials' evaluations at input $i$.

$$ z_i' = f'(i) = \sum_{j \in S} \gamma^S_j \cdot g_j(i) $$

Thus, for shareholder $i$ to learn her updated share, she needs to receive $\\{g_j(i)\\}\_{j \in S}$, i.e. one evaluation of $g_j(i)$ from every other shareholder $j \in S$.

Of course, this all hinges on the assumption that every $\\{g_j(i)\\}\_{j \in S}$ is a polynomial at which $g_j(0) = z_j$, which is not guaranteed if we do not trust shareholders to submit honest evaluations. Thus, we must also require each shareholder $i$ to commit to their resharing polynomial $g_i(x)$ by submitting the public coefficients of $g_i(x)$. This _commitment_ can be compared by other shareholders to make sure everyone is behaving consistently, and then used to verify evaluations by computing $g_i(x) \cdot G$.

$$ A_{(i, k)} = a_{(i, k)} G $$
$$ C_i = \\{A_{(i, 1)}, A_{(i, 2)}, ..., A_{(i, t'-1)}\\} $$

We'll see further down how these commitments are used. I think I've spent enough paragraphs on motivation at this point, so let's dive into the specific protocol.

# The Protocol

In this section, I'll simply describe the resharing protocol step-by-step.

Assume every online shareholder can positively identify each other and can communicate with one-another over secure and authenticated channels.

Any offline shareholders not in $S$ must be able to receive messages asynchronously from the shareholders in $S$, such as through encrypted email or message queues. If an offline shareholder misses any messages, they may be unable to verify or construct their new share. Alternatively, one might assume all shareholders to be online and available.

Every shareholder is assumed to have access to a consistent view of $\\{\phi_0, \phi_1, ..., \phi_{t-1}\\}$ representing the public coefficients of $f(x)$, which can be used to compute any $f(x) \cdot G$.

$$ f(x) \cdot G = \sum_{k=0}^{t-1} \phi_k x^k $$

## Resharing

1. Each shareholder $i \in S$ generates $t' - 1$ random coefficients $\\{a_{(i, 1)}, a_{(i, 2)}, ..., a_{(i, t' - 1)}\\}$. These coefficients define a degree $t' - 1$ polynomial $g_i(x)$, whose constant term is the existing share $z_i$.

$$
\begin{align}
g_i(x) &= z_i + \sum_{k = 1}^{t' - 1} a_{(i, k)} x^k \\\\
\end{align}
$$

2. Each online shareholder $i \in S$ computes a commitment $C_i$ to the coefficients of $g_i(x)$.

$$ A_{(i, k)} = a_{(i, k)} G  $$
$$ C_i = \\{A_{(i, 1)}, A_{(i, 2)}, ..., A_{(i, t' - 1)}\\} $$

This commitment, along with the original public polynomial coefficients $\\{\phi_0, \phi_1, ..., \phi_{t-1}\\}$, allows a bearer to compute $g_i(x) \cdot G$ for any value of $x$, but not its discrete log $g_i(x)$.

$$
\begin{align}
g_i(x) \cdot G &= \sum_{k = 0}^{t-1} \phi_k i^k + \sum_{k=1}^{t'-1} A_{(i, k)} x^k \\\\
               &= f(i) \cdot G + \left(\sum_{k=1}^{t'-1} a_{(i, k)} x^k \right) G \\\\
               &= \left( z_i + \sum_{k=1}^{t'-1} a_{(i, k)} x^k \right) G \\\\
               &= g_i(x) \cdot G \\\\
\end{align}
$$

3. Each online shareholder $i \in S$ publishes their commitment $C_i$ to all other shareholders (including offline ones).

4. All online shareholders should ensure they hold the same set of commitments $C_i$ before continuing. Some shareholders may attempt denial-of-service attacks by submitting inconsistent commitments. This would cause the resharing protocol to fail unattributably, although without exposing any private data.

5. Once a shareholder $i$ receives all commitments $\\{C_j\\}\_{j \in S}$, he evaluates $g_i(j)$ for every other shareholder $j \in \\{1 ... n\\}$ (including offline shareholders), and sends the evaluation to shareholder $j$.

6. Once shareholder $i$ receives the evaluation $g_j(i)$ from another shareholder $j$, he can verify the evaluation using $C_j$ and the original public coefficients $\\{\phi_0, \phi_1, ..., \phi_{t-1}\\}$.

$$
\begin{align}
g_j(i) \cdot G &= \sum_{k = 0}^{t-1} \phi_k j^k + \sum_{k = 1}^{t' - 1} A_{(j, k)} i^k \\\\
&= f(j) \cdot G + \left( \sum_{k = 1}^{t' - 1} a_{(j, k)} i^k \right) G \\\\
&= \left( z_j + \sum_{k = 1}^{t' - 1} a_{(j, k)} i^k \right) G \\\\
&= g_j(i) \cdot G \\\\
\end{align}
$$

7. Once shareholder $i$ receives all $\\{g_j(i)\\}\_{j \in S}$, a new share $z_i'$ can then be computed.

$$ z_i' = \sum_{j \in S} \gamma^S_j g_j(i) $$

8. The shareholder can now compute new public coefficients $\\{\phi_0', \phi_1', ..., \phi_{t'-1}'\\}$ for the joint polynomial.

$$ \phi_k' = \sum_{j \in S} \gamma_j^S A_{(j, k)} $$

- $\phi_0' = \phi_0$ remains unchanged, because the secret $s_0$ itself remains unchanged.
- If $t' < t$, we can let $\phi_k' = 0$ where $k \ge t'$, because $A_{(j, k)}$ will be undefined.

<details>
  <summary>Why can we compute the new joint public coefficients this way?</summary>

Recall we defined $f'(x)$ as a degree $t' - 1$ polynomial with coefficients $\\{s_0', s_1', ..., s_{t'-1}\\}$.

We defined each coefficient $s_k'$ as the constant term of a polynomial $c_k(x)$, which passes through the points $\\{(j,\ a_{(j, k)})\\}\_{j \in S}$.

$$ P_k = \\{(j,\ a_{(j, k)})\\}\_{j \in S} $$
$$ I(P_k) \rightarrow c_k(x) $$
$$ s_k' = c_k(0) = \sum_{j \in S} \gamma^S_j a_{(j, k)} $$

The public version of these coefficients $\\{\phi_0', \phi_1', ..., \phi_{t'-1}'\\}$ can be computed as $s_k' G$.

$$
\begin{align}
\phi_k' = s_k' G &= \left( \sum_{j \in S} \gamma^S_j a_{(j, k)} \right) G \\\\
                 &=  \sum_{j \in S} \gamma^S_j A_{(j, k)} \\\\
\end{align}
$$

</details>

9. Every shareholder $i$ can overwrite their old share $z_i$ with their new share $z_i'$, and discard $g_i(x)$.

In doing this, we have swapped out our old degree $t-1$ polynomial $f(x)$ for a completely new degree $t' - 1$ polynomial $f'(x)$. The only feature in common between the two polynomials is their constant term $s_0$.

The new shares $\\{z_1', z_2', ..., z_n'\\}$ are evaluations of $f'(x)$, and thus have a recovery threshold of $t'$ instead of $t$, yet still recover the same secret.

## Recovery

At recovery time, the shareholders now need a subset $R$ of at least $t'$ shares to recover the master secret $s_0 = f(0) = f(0)$.

$$
\begin{align}
f(0) &= \sum_{i \in R} \gamma_i^R z_i' \\\\
&= \sum_{i \in R} \gamma_i^R \left( \sum_{j \in S} \gamma_j^S g_j(i) \right) \\\\
&= \sum_{i \in R} \sum_{j \in S} \gamma_i^R \gamma_j^S g_j(i) \\\\
&= \sum_{j \in S} \sum_{i \in R} \gamma_i^R \gamma_j^S g_j(i) \\\\
&= \sum_{j \in S} \gamma_j^S \left( \sum_{i \in R} \gamma_i^R g_j(i) \right) \\\\
&= \sum_{j \in S} \gamma_j^S \cdot g_j(0) \\\\
&= \sum_{j \in S} \gamma_j^S \cdot f(j) \\\\
&= f(0)
\end{align}$$

## Gotchas

The resharing procedure has its problems.

- Shares generated by resharing are not forwards or backwards compatible. After a resharing, shareholders in a group may become fragmented if some shareholders did not attend the resharing, or missed their asynchronous messages from the resharing.
  - Implementations which allow asynchronous resharing need to plan for this contingency, giving shareholders a way to prove their old share is valid but needs to be updated. They should support [a share issuance protocol](/cryptography/shamir/) so that shareholders can regroup by issuing valid updated shares for the fragmented shareholders who missed the memo.
- There is no way to verify a shareholder deleted their old shares after a resharing event. Selfish shareholders can freely cache old shares. If a threshold increase occurs, it is impossible to know for sure whether all shareholders updated their shares. If some subset of $t$ shareholders maintain their old shares, the threshold has not really increased.
  - As a corollary, we can see that decreasing the threshold is easier than increasing it, as decreasing the threshold does not run into any incentive traps. It is natural for a selfish shareholder to prefer a share which carries more weight among the group.

## Use Cases

### Replacing shareholders

Perhaps a shareholder in the group is longer behaving. Perhaps they have stopped responding, and the whereabouts of their share is unknown. Perhaps the group no longer trusts this shareholder. The group can reshare the secret and exclude the misbehaving shareholder, perhaps reconfiguring the arrangement of the shares and sending some resharing evaluations to a replacement shareholder.

### Revoking exposed shares

If one shareholder has accidentally exposed their share, resharing could be useful to revoke it by generating a new set of shares that are not backwards compatible with the exposed share.

### Changing the threshold

As discussed, resharing is a relatively straightforward way to change the recovery threshold of a shared secret, and it is highly flexible. Unlike other methods, resharing allows choosing an arbitrary new threshold $t'$, whereas some threshold-modification protocols only work when $t' > t$ or vice-versa.

### Defending against mobile adversaries

Since shares are not backwards or forwards compatible through resharing events, we can view resharing as a sort of _share-cycling_ procedure.

Hacking people is hard work. Consider an attacker who can steal some shares from one shareholder at a time, but must do so over a protracted duration, say weeks or months, breaking into each target one-by-one and stealing their share, until they have $t$ or more shares and can recover the secret $s_0$.

If shareholders proactively reshare their secret with new polynomials once every day, or once a week, it dramatically reduces the window of opportunity for this attacker. The attacker must now break into at least $t$ shareholders' machines on the same day, or within the same week.

## Reasoning

Consider the set of resharing polynomials $\\{g_i(x)\\}\_{i \in S}$ each of degree $t' - 1$.

$$ g_i(x) = z_i + \sum_{k = 1}^{t' - 1} a_{(i, k)} x^k $$

If each of the $t$ shareholders in $S$ distribute an evaluation of their resharing polynomials to every other shareholder in the group, then only a subset of $t'$ of those evaluations are needed to completely reconstruct every polynomial $\\{g_i(x)\\}\_{i \in S}$. This would allow one to reconstruct all $\\{g_i(0)\\}\_{i \in S} = \\{z_i\\}\_{i \in S}$. The resulting set of $t$ shares can then be used to reconstruct $f(0) = s_0$.

However, this would be inefficient if shareholders had to store those $t$ evaluations as their new share. We want shareholders to be able to _update_ their shares from $z_i$ to some new share $z_i'$ of the same size, without storing extra redundant data for every threshold change, in such a way that their shares are still fully valid under canonical Shamir secret sharing protocols.

Instead, we want a simple share representable as $z_i' = f'(i)$, so that all a shareholder must do to update their share is overwrite their old share $z_i \in \mathbb{Z}\_q$ with a new share $z_i' \in \mathbb{Z}\_q$. We also want to be able to concisely update the joint public polynomial's coefficients $\\{\phi_0, \phi_1, ..., \phi_{t-1}\\}$, so that we can easily verify shares (and resharing polynomial evaluations) in the future. This is where most of the complexity in the resharing protocol lives.

## Conclusion

Having only recently discovered the wealth of mathematical literature on threshold secret sharing, I feel rather overwhelmed at the incredible scope of designs that clever people have concocted. Prior, having only known the basic Shamir Secret Sharing scheme, I had no idea it was possible to change shareholders, thresholds, or secrets so easily. Can't wait to see what comes next.
