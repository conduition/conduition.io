---
title: Issuing New Shamir Secret Shares Using Multi-Party Computation
date: 2023-09-04
mathjax: true
category: cryptography
---

Shamir's Secret Sharing (SSS) is a well known tool in the cryptography community. It is used in protocols like [SLIP39](https://github.com/satoshilabs/slips/blob/master/slip-0039.md) and [FROST](https://eprint.iacr.org/2020/852). SSS is popular because of its property of [information-theoretic security](https://en.wikipedia.org/wiki/Information-theoretic_security) (it is secure even against adversaries who have infinite computational power).

SSS is a powerful cryptographic tool, but it struggles in terms of flexibility. If a share is lost, it is not easy to issue new ones. Adding new shares is possible if enough shares are brought together to recover the original secret, but what if shareholders do not wish to reveal their shares to each other yet? What if they _never_ want to reveal their secret shares, as would be the case with a threshold multisignature protocol such as [FROST](https://eprint.iacr.org/2020/852)?

What if the shareholders distrust each other, or the dealer? How can they be sure their shares, or the shares of others, are valid?

In this article, I'll cover the basics of how Shamir's Secret Sharing works. I'll demonstrate how to extend it with verifiable properties so that the dealer and shareholders need not trust one another. Finally I'll describe a procedure which can be used to trustlessly issue new shares _without_ recovering the full original secret. All the while, shareholders don't need to trust each other or the dealer, and learn nothing about the new share they issued.

## Notation

Just so we're all on the same page:

| Notation | Meaning |
|:--------:|---------|
|$x \in S$| $x$ is a member of set $S$. |
|$\mathbb{Z}\_{q}$| The set of integers mod $q$. |
|$x \leftarrow S$ | Sampling $x$ randomly from the set $S$. |
| $a\ \|\|\ b$ | A deterministic concatenation of $a$ and $b$. |

# Polynomials

The basis of Shamir's Secret Sharing lies in the fundamental theorem of algebra, specifically in the mechanics of polynomials, so we should do some review of this domain before we dive into SSS.

## Review

- A polynomial expression is any expression of variables* that involves only addition/subtraction, multiplication/division, and positive-integer exponentiation.
  - Usually single-variable polynomials denote the variable as $x$.
- The _degree_ of a polynomial is the highest power of the variable used in the expression (with a non-zero coefficient).
- The _coefficients_ of a polynomial are the multipliers alongside each power of the variable when it is in [standard form](https://www.cuemath.com/algebra/standard-form-polynomial/).
- The _roots_ of a polynomial expression are the values of $x$ which cause the expression to evaluate to zero.
  - Sometimes the roots of a polynomial are _complex,_ meaning they involve numbers which make use of the imaginary number $i = \sqrt{-1}$. Don't worry, we won't be dealing with complex numbers today!
- A _polynomial function_ is a function which can be computed by simply evaluating a polynomial on an input $x$.

\* <sub>Note that today I'll be writing exclusively about _univariate_ (single-variable) polynomials, where the variable is denoted $x$.</sub>

For example, $f(x) = 3x^3 + 9x - 5$ is a polynomial function with degree $3$ (AKA a _cubic_ polynomial). Its coefficients are $3$ for the cubic ($x^3$) term, $9$ for the linear ($x$) term, and $5$ for the constant ($x^0$) term.

Polynomials aren't only written in standard form though. They could be written in factored form, such as $f(x) = x(x - 10)(x + 4)$, or a mix of the two, like $f(x) = (x - 1)(x^2 + 10x - 3)$. As long as only the addition/subtraction multiplication/division and natural number exponentiation operations are used on the variable $x$, it is still called a polynomial.

By contrast, a function like $f(x) = 2^x$ is _not_ a polynomial because it takes the base $2$ to the power of $x$. Such a function doesn't behave according to the laws of polynomials.

Almost everyone will have at least some experience handling polynomials, as most high school math classes deal extensively in linear (degree $1$) polynomials such as $5x + 4$, and quadratic (degree $2$) polynomials such as $x^2 - 6x - 3$. Students are taught how to factor them, expand them, find their roots, graph them, and many other things, but only in university level mathematics would you be taught how powerful these tools are for cryptography.

## Interpolation

The [Fundamental Theorem of Algebra](https://en.wikipedia.org/wiki/Fundamental_theorem_of_algebra) states:

> Every non-zero, single-variable, degree $n$ polynomial with complex coefficients has exactly $n$ complex roots.

In other words: If a polynomial has degree $n$, then there are exactly $n$ different values of $x$ which make it evaluate to zero (if we include complex numbers). If you think about the shapes that these functions take on the [Cartesian Plane](https://en.wikipedia.org/wiki/Cartesian_coordinate_system), this makes sense.

<img src="/images/shamir/polynomial-graphs-by-degree.jpeg">

This theorem has a helpful consequence.

Say we have a set of $n$ points $\\{(x_1, y_1), (x_2, y_2), ..., (x_n, y_n)\\}$, where all $x$ values are distinct (i.e. $x_1 \ne x_2 \ne x_3 \ne ... \ne x_n$). Then there exists some _unique_ polynomial function $f(x)$ of degree at most $n - 1$ which passes through all $n$ points, such that $f(x_i) = y_i$ for each $(x_i, y_i)$ point from $\\{1...n\\}$. A common way to phrase this is that $f(x)$ _interpolates_ the points $\\{(x_1, y_1), (x_2, y_2), ..., (x_n, y_n)\\}$.

<details>
  <summary>Uniqueness: Proof by contradiction</summary>

How do we know $f(x)$ is unique? We will assume it _isn't_ true. In exploring the consequences of that assumption, we will find a logical contradiction.

Assume there exists two non-zero polynomial functions $f(x)$ and $g(x)$ of degree at most $n - 1$ which pass through those $n$ points, such that $f(x) \ne g(x)$ for at least one input $x$ (indicating the polynomials are different), but also that $f(x_i) = g(x_i) = y_i$ for all $n$ points.

Since $f(x)$ and $g(x)$ each have degree at most $n - 1$, each has at most $n - 1$ _roots._

Consider the difference between the two polynomials $r(x) = f(x) - g(x)$. Since we assumed $f(x) \ne g(x)$, this implies $r(x) \ne 0$.

Since $f(x_i) = g(x_i)$ at all $\\{x_1, x_2, ..., x_n\\}$, it follows that $f(x_i) - g(x_i) = 0$ for all $\\{x_1, x_2, ..., x_n\\}$ as well. This implies the polynomial $r(x)$ has at least $n$ roots.

Recall $r(x)$ was defined as $r(x) = f(x) - g(x)$, so $r(x)$ can't have a higher degree than either $f(x)$ or $g(x)$, which we assumed have degree at most $n - 1$. Adding and subtracting polynomials merely adds or subtracts their coefficients without introducing higher-degree terms. Thus $r(x)$ must have at most degree $n - 1$.

This is a contradiction. On one hand, $r(x)$ must have $n$ roots. On the other hand, it must have degree at most $n - 1$, which - due to the Fundamental Theorem of Algebra - means it must have $n - 1$ roots.

This contradiction is proof that $r(x)$ must be equal to the zero polynomial (i.e. $r(x) = 0$). This is the only logically consistent way for $r(x)$ to have $n$ roots while also having degree at most $n - 1$.

</details>

The very special and helpful property of interpolating polynomials is: **To interpolate a polynomial $f(x)$ of degree $t - 1$, we need _at least_ $t$ evaluations of $f(x)$** (i.e. points that $f(x)$ passes through).

Said differently, if we create $n$ evaluations of $f(x)$, such as $(1, f(1)), (2, f(2)), ..., (n, f(n))$, then only $t$ of those evaluations are needed to reconstitute $f(x)$ and thus evaluate it at any input. With any fewer than $t$ evaluations, we would gain no new information about $f(x)$ itself, because there exists an _infinite number_ of degree $t - 1$ polynomials which pass through those same $t - 1$ or fewer points.

Perhaps by now you might be starting to see why [polynomial interpolation](https://en.wikipedia.org/wiki/Polynomial_interpolation) is at the heart of Shamir's Secret Sharing.

## Demonstration

This concept is easier to understand visually with linear polynomials. Picture two points $P_1$ and $P_2$ on the Cartesian plane.

<img src="/images/shamir/two-points.png">

Any two points are sufficient to uniquely describe a line between them. Remember that a line on the Cartesian plane is just a degree-1 (AKA _linear_) polynomial. Only one unique line (polynomial) passes through (interpolates) the two points.

In this case, the polynomial happens to be $f(x) = -2x + 9$.

<img src="/images/shamir/two-points-with-line.png">

If we are given additional points $P_3$ and $P_4$ located along the same line, this doesn't change the polynomial function which interpolates all four points.

<img src="/images/shamir/more-points-with-line.png">

However, if we are given only _one_ evaluation, say $P_1$ where $f(2) = 5$, we gain no information about $f(x)$ because there are infinite other _linear_ polynomials (lines) which pass through the same point.

<img src="/images/shamir/one-point-with-many-lines.png">

This concept generalizes to higher-degree polynomials! Given the same two points $P_1$ and $P_2$, there are infinite degree-2 (AKA _quadratic_) polynomials which pass through those points.

<img src="/images/shamir/two-points-with-many-quadratics.png">

But add a third point and suddenly we can find only one quadratic polynomial which interpolates them.

<img src="/images/shamir/three-points-with-quadratic.png">

> but how would we actually _do_ the interpolation?

There are many ways to skin this cat. Given $n$ data points, the polynomial we interpolate from them would be the same. As long as our method works and works quickly, the mechanics aren't crucial to know at this point. Many interpolation methods exist:

- Lagrange Interpolation (the most commonly known)
- Newton Interpolation
- Inverting the Vandermonde Matrix (uses linear algebra)

For the time being, assume we have some black box interpolation algorithm $I(P) \rightarrow f$ which takes in some set of $n$ points called $P$, and spits out a polynomial $f(x)$ which has degree at most $n - 1$. I'll discuss how $I(P)$ works a bit later. By now you're probably dying to know how this all applies to Shamir's Secret Sharing.

# Shamir's Scheme

This wouldn't be a math article if we don't start by defining some parameters.

- Let $\mathbb{F}\_q$ be a [Finite Field](https://en.wikipedia.org/wiki/Finite_field) containing $q$ elements, where $q$ is some large prime number.
  - If you're not familiar with Finite Fields, just consider it as a special group of numbers, such that addition, subtraction, multiplication, and division all work normally as they do within the real numbers, except there are a finite quantity of $q$ possible discrete numbers that can be used.
  - Usually, this is the set of integers modulo a prime number $q$, AKA $\mathbb{Z}\_q$.
- Let $s_0$ be a secret such that $s_0 \in \mathbb{F}\_q$. Our goal is to break $s_0$ into shares so we can distribute them.
  - Usually $s_0$ is just some large random number randomly sampled from $\mathbb{F}\_q$, such as a private key.
- Let $n$ be the total number of shares we want to issue.
- Let $t$ be the minimum number of shares required to reconstruct $s_0$, such that $t \le n$.


## Distribution

Shamir's Secret Sharing scheme starts with a trusted\* dealer who knows $s_0$ and wants to distribute it evenly as $n$ shares, such that any subset of at least $t$ shares can be recombined to recover $s_0$. For example, the trusted dealer might be backing up a signing key or encryption key across physically distributed locations, or with trusted representatives such as staff, attorneys, family, and close friends.

\* <sub>There are [other schemes which allow mutually distrustful parties to generate shares of a common but yet-unknown secret](https://link.springer.com/content/pdf/10.1007/3-540-46766-1_9.pdf), but that is out of scope for today.</sub>

1. The dealer samples $t - 1$ random values $\\{s_1, s_2, ..., s_{t-1}\\}$ from $\mathbb{F}\_q$.

2. The dealer treats $\\{s_0, s_1, s_2, ... s_{t-1}\\}$ as _the coefficients of a degree $t - 1$ polynomial function_ $f(x)$.

$$
\begin{align}
f(x) &= s_0 + s_1 x + s_2 x^2 + ... + s_{t-1}x^{t-1} \\\\
     &= \sum_{i=0}^{t-1} s_i x^i
\end{align}
$$

3. The dealer assigns each share a unique _index_ $i \in \mathbb{F}\_q$, labeling each share $i$. They could be randomly selected, but usually indexes are just the ascending natural numbers, so we'd have $\\{1, 2, ..., n\\}$. The indexes _must not be zero_ and _must not have repetitions._

4. The dealer evaluates $z_i = f(i)$ at each of the $n$ different indexes.

$$
\begin{align}
z_1 &= f(1) \\\\
z_2 &= f(2) \\\\
&... \\\\
z_n &= f(n) \\\\
\end{align}
$$

5. The dealer distributes shares as tuples of $(i, z_i)$. $z_i$ is the private data within each share which must be kept secret.

## Recovery

At recovery time, the original secret $s_0$ is assumed to no longer be available - Perhaps it was lost in a boating accident, or left encrypted with an unknown password. Perhaps the original dealer was hit by a bus and her representatives are now charged with handling her affairs. Perhaps the dealer is no longer willing to cooperate. Regardless, the shareholders must recover $s_0$ independently, using only their shares.

Let $R$ be the set of $t$ or more share indexes which are participating in the recovery. We assume that at least $t$ shares are available. Some shareholders might not be online or might also have been hit by aforementioned bus. Some shares may have been physically destroyed, such as in house fires or boating accidents. As long as $t$ shares are still available, $f(x)$ and $s_0$ can be reconstructed.

Each of the shares in $R$ is given to some trusted\* _recoverer_ whose duty is to reconstitute the original secret $s_0$ given $t$ or more shares. The recoverer might be one of the shareholders, or an independent entity.

\* <sub>Care is needed here. If the recoverer is malicious, they might use $s_0$ themselves for some nefarious purpose. SSS doesn't specify what to do once $s_0$ is recovered - It is quite limited in that capacity. Canonically, SSS is solely a secret backup and recovery tool. What comes after is up to the implementation.</sub>


1. The recoverer is given a set of $t$ or more shares $\\{(i, z_i)\\}\_{i \in R}$. Shares must have unique indexes.

2. The recoverer treats the shares as the evaluations produced by some degree $t - 1$ polynomial function $f(x)$ over $\mathbb{F}\_q$, such that $f(i) = z_i$ for all $i \in R$.

3. The recoverer uses a polynomial interpolation algorithm $I(\\{(i, z_i)\\}\_{i \in R})$ to interpolate the polynomial $f(x)$.

4. The recoverer evaluates $f(0)$. This outputs $s_0$, because:

$$
\begin{align}
f(x) &= s_0 + s_1 x + s_2 x^2 + ... + s_{n-1} x^{n-1} \\\\
f(0) &= s_0 + s_1 (0) + s_2 (0^2) + ... + s_{n-1} (0^{n-1}) \\\\
     &= s_0 \\\\
\end{align}
$$

## Gotchas

SSS seems simple, but it is an easy protocol to screw up in practice.

- [It is very important that the non-constant coefficients of $f(x)$ are totally random](https://bitcointalk.org/index.php?topic=2199659.0), otherwise the information-theoretic security of SSS is lost.
- When distributing shares, it is crucial [that the dealer _does not_ distribute a share evaluated at index zero](https://blog.trailofbits.com/2021/12/21/disclosing-shamirs-secret-sharing-vulnerabilities-and-announcing-zkdocs/), because since $f(0) = s_0$, they would be giving away the secret $s_0$.
- Shareholders must be trusted not to use phony shares when recovering. If one shareholder submits a phony or faulty share, they could change the secret which is recovered to something unusable, and nobody would be able to tell which shareholder screwed up.
- There must be a trusted recoverer machine and a trusted dealer machine who will both know $s_0$. If either is compromised, $s_0$ will naturally be exposed.
- The dealer and the recoverer must use the same finite field $\mathbb{F}\_q$, which could result in incompatibilities if this field is non-standard.

But still, the power of SSS is undeniable, especially as a primitive when combined with other tools.

Before we demonstrate how shareholders can trustlessly issue new shares, I want to take a moment to learn about how $f(x)$ can be interpolated. If you're already familiar with polynomial interpolation, [click here to skip ahead](#Issuing-a-New-Share).

# Interpolation

In my opinion, the most intuitive interpolation method is [Lagrange Interpolation](https://en.wikipedia.org/wiki/Lagrange_polynomial). First discovered in 1779 by Edward Waring, this method is named after the scientist Joseph-Louis Lagrange who made the method famous.

The Lagrange method takes a step-by-step approach to achieve a polynomial with all of our desired qualities. Given $t$ points $\\{(x_1, y_1) ... (x_t, y_t)\\}$ with distinct $x$-coordinates, we should be able to find a polynomial function $f(x)$ which:

1. [x] interpolates all $t$ points ($f(x_i) = y_i$)
2. [x] has degree at most $t - 1$

Where to begin? We can make use of the Fundamental Theorem of Algebra once more: **A degree $t-1$ polynomial will have $t-1$ roots** - i.e. it outputs zero at $t-1$ different inputs.

Since we are given $t$ points, we can define a degree $t-1$ polynomial $p_i(z)$ which outputs zero at all $t-1$ inputs $\\{x_1, ..., x_{i-1}, x_{i+1}, ..., x_t\\}$, specifically excluding the input $x_i$ where it outputs... _something_ which is not zero.

$$
\begin{align}
p_i(z) &= (z - x_1)...(z - x_{i-1})(z - x_{i+1})...(z - x_t) \\\\
       &= \prod_{\substack{j=1 \\\\ j \ne i}}^t (z - x_j) \\\\
\end{align}
$$

This is the simplest polynomial we could define with roots at $\\{x_1, ..., x_{i-1}, x_{i+1}, ..., x_t\\}$. If we plug in any $x_j \ne x_i$, then $p_i(x_j) = 0$.

Seems weird to do this, but $p_i(x)$ now has a handy property: Out of all the $x$-coordinates we care about, it only has a non-zero output specifically at $x_i$. That output can be predicted in advance and scaled however we'd like it.

Specifically, we can scale $p_i(z)$ by multiplying by $y_i$ and dividing by $p_i(x_i)$. This scales the output to $y_i$ when we input $z = x_i$.

Let's define this operation as a new polynomial function $l_i(z)$.

$$
\begin{align}
l_i(z) &= p_i(z) \frac{y_i}{p_i(x_i)} \\\\
       &= y_i \frac{p_i(z)}{p_i(x_i)} \\\\
\end{align}
$$

As a result, $l_i(x)$ outputs our desired $y_i$ value at input $x_i$, or it outputs zero at all other $x_j \ne x_i$.

$$
\begin{align}
l_i(x_i) &= y_i \frac{p_i(x_i)}{p_i(x_i)}  \\\\
         &= y_i \\\\
\end{align}
$$
$$
\begin{align}
l_i(x_j) &= y_i \frac{p_i(x_j)}{p_i(x_i)}  \\\\
         &= y_i \frac{0}{p_i(x_i)} \\\\
         &= 0 \\\\
\end{align}
$$

We can expand $p_i(z)$ and regroup factors to make everything more readable.

$$
\begin{align}
l_i(z) &= y_i \frac{(z - x_1)...(z - x_{i-1})(z - x_{i+1})...(z - x_t)}{(x_i - x_1)...(x_i - x_{i-1})(x_i - x_{i+1})...(x_i - x_t)} \\\\
       &= y_i \left( \frac{z - x_1}{x_i - x_1} \right) ... \left( \frac{z - x_{i-1}}{x_i - x_{i-1}} \right) \left( \frac{z - x_{i+1}}{x_i - x_{i+1}} \right) ... \left( \frac{z - x_t}{x_i - x_t} \right)\\\\
       &= y_i \prod_{\substack{j=1 \\\\ j \ne i}}^t \frac{z - x_j}{x_i - x_j} \\\\
\end{align}
$$

Imagine if we repeat this for all $i \in \\{1...t\\}$, and we find $\\{l_1, l_2, ..., l_t\\}$. Since each $l_i$ passes through the point $(x_i, y_i)$ but outputs zero at all $x_j \ne x_i$, then the sum of all $\\{l_1, l_2, ..., l_t\\}$ would be a new polynomial which interpolates _all_ the points $\\{(x_1, y_1) ... (x_t, y_t)\\}$.

$$
\begin{align}
f(z) &= l_1(z) + l_2(z) + ... + l_t(z) \\\\
     &= \sum_{i=1}^t l_i(z) \\\\
\end{align}
$$
$$
\begin{align}
f(x_i) &= l_1(x_i) + ... + l_i(x_i) + ... + l_t(x_i) \\\\
       &= 0 + ... + y_i + ... + 0 \\\\
       &= y_i \\\\
\end{align}
$$

More commonly, this is written in the mathematical literature in terms of a _basis polynomial_ $L_i(z)$ which outputs $1$ at $x_i$ and zero at $x_j \ne x_i$. Then the output of $L_i(z)$ is scaled by a factor of $y_i$. The textbook definition of a Lagrange Interpolation Polynomial is usually written as

$$
\begin{align}
L_i(z) &= \left( \frac{z - x_1}{x_i - x_1} \right) ... \left( \frac{z - x_{i-1}}{x_i - x_{i-1}} \right) \left( \frac{z - x_{i+1}}{x_i - x_{i+1}} \right) ... \left( \frac{z - x_t}{x_i - x_t} \right) \\\\
       &= \prod_{\substack{j=1 \\\\ j \ne i}}^t \frac{z - x_j}{x_i - x_j} \\\\
\end{align}
$$
$$
\begin{align}
f(z) &= y_1 L_1(z) + y_2 L_2(z) + ... + y_t L_t(z)  \\\\
     &= \sum_{i=1}^t y_i L_i(z) \\\\
\end{align}
$$

Notice how $L_i(z)$ only needs $\\{x_1, x_2, ... x_t\\}$ in order to be evaluated - its definition doesn't require any of the $y$-coordinate values, so $L_i(z)$ can be computed on any input $z$ by anyone who knows $\\{x_1, x_2, ..., x_t\\}$, whether or not they know the corresponding evaluation outputs $\\{y_1, y_2, ..., y_t\\}$.

A common way that modern academic papers will represent the basis polynomials $L_i(x) is by calling them _Lagrange Coefficients_ defined for some constant $c$. They will usually be given some greek symbol such as $\lambda_i$ (_lambda_), with the subscript $i$ representing the $x$ value in the $(x, y)$ point which is being interpolated by that specific basis polynomial.

$$
\begin{align}
\lambda_i &= \left( \frac{c - x_1}{x_i - x_1} \right) ... \left( \frac{c - x_{i-1}}{x_i - x_{i-1}} \right) \left( \frac{c - x_{i+1}}{x_i - x_{i+1}} \right) ... \left( \frac{c - x_t}{x_i - x_t} \right) \\\\
       &= \prod_{\substack{j=1 \\\\ j \ne i}}^t \frac{c - x_j}{x_i - x_j} \\\\
\end{align}
$$
$$
\begin{align}
f(z) &= y_1 \lambda_1 + y_2 \lambda_2 + ... + y_t \lambda_t  \\\\
     &= \sum_{i=1}^t y_i \lambda_i \\\\
\end{align}
$$


## Example

Here we explore three basis polynomials for the $x$-coordinates $\\{1, 2, 3\\}$.

$$
\begin{align}
L_1(z) &= \left( \frac{z-2}{1-2} \right) \left( \frac{z-3}{1-3} \right) \\\\
       &= \frac{1}{2}(z-2)(z-3) \\\\
\end{align}
$$
$$
\begin{align}
L_2(z) &= \left( \frac{z-1}{2-1} \right) \left( \frac{z-3}{2-3} \right) \\\\
       &= - (z-1)(z-3) \\\\
\end{align}
$$
$$
\begin{align}
L_3(z) &= \left( \frac{z-1}{3-1} \right) \left( \frac{z-2}{3-2} \right) \\\\
       &= \frac{1}{2} (z-1)(z-2) \\\\
\end{align}
$$

<img src="/images/shamir/basis-polynomials.png">

Let's say we are given the $y$-coordinates $\\{5, 2, 2\\}$, so the array of points we want to interpolate would be $\\{(1, 5), (2, 2), (3, 2)\\}$.

We can compute our interpolated polynomial on any input $z$ by evaluating $f(z) = 5 L_1(z) + 2 L_2(z) + 2 L_3(z)$.

<img src="/images/shamir/lagrange-polynomial.png">

This straightforward method is at the heart of numerous clever algorithms, including Shamir's Secret Sharing.

There are other improvements we could make to speed this procedure up and increase accuracy for floating point arithmetic - [Read about the Barycentric Form of Lagrange Polynomials](https://en.wikipedia.org/wiki/Lagrange_polynomial#Barycentric_form) for more.

But for our purposes this is sufficient background knowledge to proceed to the next section. What I really want you, dear reader, to remember, is how the _basis polynomials_ $L_i(z)$ are constructed. In particular:

- We can give any polynomial a root at any constant $c$ by multiplying a polynomial by $(x - c)$.
- When we add two polynomials $f(x)$ and $g(x)$ together, the _roots_ of either function take the value of its counterpart instead. If $f(c) = 0$, then $f(c) + g(c)$ is the same as $g(c)$.

We will make use of these properties in the next section.

# Trustless Sharing

Not so well-known as Shamir's scheme is [Feldman's Verifiable Secret Sharing (VSS) scheme](https://www.cs.umd.edu/~gasarch/TOPICS/secretsharing/feldmanVSS.pdf). This variant of Shamir's scheme allows participants who distrust each other or the dealer to verify shares are evaluations for a given secret. This turns out to be a very useful property for trustless protocols like multisig.

For Feldman's VSS, we must introduce a _group generator_ $G$. For this article, I'll be using an elliptic curve generator point $G$ with order $q$, so our finite field $\mathbb{F}\_q$ will be set to the integers mod $q$, i.e. $\mathbb{Z}\_q$. [Check out these elliptic curve cryptography resources](/cryptography/ecc-resources/) to learn more about how elliptic curves work.

In principle, this works for any kind of discrete-log group, including multiplicative groups of integers modulo any prime number $q$, but the notation is easier to understand using an additive group like an elliptic curve.

## Distribution

For Feldman's VSS extension, the dealing phase of SSS is modified as follows.

1. After computing the coefficients $\\{s_1, s_2, ..., s_{t-1}\\}$, the dealer computes a set $C$ of commitments to the secret $s_0$ and every other coefficient $s_i$, such that

$$ \phi_i = s_i G $$
$$ C = \\{\phi_0, \phi_1, \phi_2, ..., \phi_{t-1}\\} $$

Notice that $s_0$ is the discrete logarithm (secret key) of $\phi_0$. In a way we could think of $\phi_0$ as the _public key_ for $s_0$, which might prove useful to the verifying shareholders, depending on the context of the implementation.

2. While distributing the shares, the dealer broadcasts $C$ to all shareholders, in such a way that shareholders can be sure they all received the same commitment $C$ from the dealer. If no secure broadcasting message system is available, the shareholders must compare with one-another independently to verify they all hold the same values of $C$.

3. Each shareholder can verify their share $z_i$ is valid under $C$ by testing that $z_i G = \sum_{j=0}^{t-1} i^j \phi_j$. This works because $\\{\phi_0,  \phi_1, ..., \phi_{t-1}\\}$ act like public equivalents of the secret coefficients $\\{s_0, s_1, ..., s_{t-1}\\}$ which define the dealer's polynomial $f(x)$.

$$
\begin{align}
z_i G &= \sum_{j=0}^{t-1} \phi_j i^j \\\\
      &= \phi_0 + \phi_1 i + \phi_2 i^2 + ... + \phi_{t-1} i^{t-1} \\\\
      &= s_0 G + s_1 i G + s_2 i^2 G + ... + s_{t-1} i^{t-1} G \\\\
      &= (s_0 + s_1 i + s_2 i^2 + ... + s_{t-1} i^{t-1}) G \\\\
      &= \left( \sum_{j=0}^{t-1} s_j i^j \right) G \\\\
      &= f(i) \cdot G \\\\
\end{align}
$$

Knowing $C = \\{\phi_0, \phi_1, ..., \phi_{t-1}\\}$ doesn't give the shareholders any secret information about $f(x)$, assuming $\phi_j \div G$ is not computable (i.e. assuming the elliptic curve discrete log problem is hard). But $C$ does give shareholders the ability to verify shares are valid for a particular polynomial commitment $C$.

This way, shareholders don't need to trust the dealer to distribute shares fairly. Perhaps the dealer might be unfair, or faulty. This gives shareholders a way to confirm with each other that they all hold shares of a secret, and that with at least $t$ shares they can recover the secret key of $\phi_0$.

## Recovery

This verification can also be done at recovery time by the recoverer. The recovery process can be modified as follows:

1. When receiving shares, each share is sent as $(i, z_i, C_i)$ where $C_i$ is the original commitment $C$ as known to the bearer of share $i$.

2. Each share $(i, z_i)$ is verified against $C_i$ during recovery. All reported commitments must be the same ($C_i = C_j$ holds for any $i$ and $j$).

Any minority of shareholders who submit mismatching commitments or invalid shares can be detected. If all shareholders in $R$ behave, then and only then can recovery succeed.

## Shares as Keys

If we treat each share $z_i$ as a secret key, then knowledge of $C$ gives each shareholder the ability to compute the "public-key" $Z_i = z_i G$ of any other share $z_i$.

$$
\begin{align}
Z_i = z_i G &= \sum_{j=0}^{t-1} \phi_j i^j \\\\
            &= f(i) \cdot G \\\\
\end{align}
$$

This gives each shareholder a way to prove they own a given share without revealing it: Just sign a message with the secret key $z_i$. Anyone who knows $C$ and $i$ can verify the message by computing the public key $Z_i$ and verifying signatures against it. Similarly, any $Z_i$ could be used as an encryption key to exchange messages which only specific shareholders can read.

# Issuing a New Share

Suppose a dealer has issued $n$ Shamir shares and has disappeared, or has deleted the secret $s_0$ and the coefficients $\\{s_1, s_2, ..., s_{t-1}\\}$. In such a situation, the only way to recover the secret is with $t$ or more shares.

Suppose that a quorum of shareholders possessing at least $t$ shares wish to issue a new share (or recover an existing one) at index $\ell$, and distribute it to a new (or existing) shareholder. There are many reasons this might be needed:

- A existing share was lost in a boating accident.
- A existing shareholder was hit by a bus and nobody can find her share.
- A new shareholder is to be inducted into the group.

The naive method would be to bring those $t$ shares together on a trusted recovery machine, and interpolate the original polynomial $f(x)$ constructed by the dealer. The recoverer could evaluate $z_{\ell} = f(\ell)$ on any index $\ell$ at which the new share should be issued. That share could then be transmitted (securely) to the new shareholder as $(\ell, z_{\ell})$. Effectively, this is like performing the recovery stage followed by a half-way execution of the dealing stage under Shamir's original scheme.

However this comes with a major drawback: There must be a trusted recoverer who reconstructs the full polynomial $f(x)$ in-the-clear in order to issue a new share. This implies reconstructing $s_0$ as well. The new share $(\ell, z_{\ell})$ could be exposed: first in the very process of its computation, and again when it is forwarded to the new shareholder.

Ideally, shareholders should be able to issue new shares without reconstructing $s_0$ on a single, potentially vulnerable machine, using some interactive multi-party computation, in a way that only the recipient of the new share can learn it.

### Disclaimer

**Don't implement this in a production environment!**

Although I believe I have effectively proven the security of this protocol below, there may be some loophole which would allow a malicious shareholder to learn more about $f(x)$ or the secret $s_0$. I would much appreciate extra review on this concept and feedback about whether its security reduces to other proven schemes.

## The Mission

There is a set of $t$ shareholders who want to issue a new share, or recover an existing one, at index $\ell$, but none of them want to expose their $z_i$ secret shares to one-another yet. Similarly, the new shareholder is also timid, and would prefer if _only they_ learn the new share $z_{\ell}$ and nobody else.

Let $S$ represent the set of share indexes which are participating in the issuance protocol.

Each bearer of share $i$ knows $z_i = f(i)$. Each shareholder knows their own index $i$. To construct a new share at index $\ell$, shareholders in $S$ wish to give an evaluation of $f(\ell)$ to shareholder $\ell$ without learning $f(\ell)$ themselves.

## Assumptions

For simplicity I may write as though each share at index $i \in S$ is held by one shareholder - a person or a machine - but the same protocol works if some shareholders hold multiple shares.

It is crucial that each shareholder of $S$ can communicate with one-another over a secure and identifiable channel. Shareholders of $S$ can also all communicate securely with the new shareholder at index $\ell$.

## Strategy

In this section I'll describe the strategy we'll use to attack this problem at a high level, and hopefully motivate the concept.

Consider a _blinding polynomial_ $\beta(x)$ (that symbol is a _beta_) of degree $t - 1$, constructed by random sampling from $\mathbb{F}\_q$. This polynomial $\beta(x)$ outputs apparently random nonsense at all inputs, except input $\ell$ at which it outputs zero.

Now consider the _issue polynomial_ $\zeta(x)$ (that symbol is a _zeta_) for $\ell$, which is the sum of the original share-creation polynomial $f(x)$ and the blinding polynomial $\beta(x)$.

$$ \zeta(x) = f(x) + \beta(x) $$

$\zeta(x)$ inherits the the interesting property from the blinding polynomial $\beta(x)$ where it outputs random nonsense at every input except $\ell$. Since $\beta(\ell) = 0$ and $f(\ell)$ is just the desired share $z_{\ell}$, it follows that $\zeta(\ell)$ also outputs the desired new share $z_{\ell}$, but $\zeta(x)$ at any other input $x$ is meaningless nonsense - it is _blinded_ at all other inputs.

$$
\begin{align}
\zeta(\ell) &= f(\ell) + \beta(\ell) \\\\
            &= f(\ell) + 0 \\\\
            &= z_{\ell} \\\\
\end{align}
$$
$$ \zeta(x) : x \ne \ell =\ ? $$

Our strategy will be for participants in $S$ to jointly evaluate the issuance polynomial $\zeta(x)$ at $t$ different inputs, and then pass those evaluations to the new shareholder for index $\ell$. The new shareholder can interpolate $\zeta(x)$ and compute $\zeta(\ell) = z_{\ell}$ to get their share of the secret. Since $\zeta(x)$'s output is otherwise random, no additional information is learned by interpolating the $\zeta(x)$ polynomial - that is, unless someone can somehow interpolate $\beta(x)$ and subtract it from $\zeta(x)$.

Participants in $S$ must not learn $t$ or more evaluations of $\zeta(x)$ - otherwise they would also learn $z_{\ell}$. They must each contribute to the evaluations, otherwise the ritual might be rigged by some subgroup of malicious shareholders.

The question then becomes: _How can the issuers in $S$ construct and evaluate $\zeta(x)$ fairly and without exposing secret data to each other?_

## Multi-Party Computation

All shareholders in $S$ must work together to build $\beta(x)$. If $\beta(x)$ is constructed by a single shareholder or by a cabal of corrupted shareholders, they could collude with the new shareholder to learn $f(x)$ and run off with the secret $s_0$.

We can use multi-party computation practices to construct a joint polynomial which all shareholders in $S$ contribute to.

Each shareholder $i \in S$ constructs a random degree $t - 2$ polynomial, and multiplies it by $(x - \ell)$ to produce a degree $t - 1$ polynomial which has a root at $\ell$. This polynomial is then denoted $b_i(x)$ - the _partial blinding polynomial_ for share $i$. We will then define the joint blinding polynomial $\beta(x)$ as the sum of all partial blinding polynomials $b_i(x)$ for all $i \in S$.

$$ \beta(x) = \sum_{i \in S}b_i(x) $$

This ensures that the joint blinding polynomial $\beta(x)$ will be random as long as at least one shareholder is honest. Imagine all shareholders pouring a bit of paint into a central glass. Even if $t - 1$ shareholders were to pour water into the cup, as long as at least one shareholder pours a real paint, the color of the resulting mixture will not be fully transparent.

## Procedure

<sub>Beware: The procedure I describe in this section is _unverifiable_ for old and new shareholders alike. Shareholders must trust each other not to attempt denial-of-service or griefing attacks by issuing faulty contributions to the multi-party computation. I'll discuss how to make this fully trustless in the next section.</sub>

1. Shareholder $i$ samples $t - 1$ random coefficients $\\{u_{(i, 0)}, u_{(i, 1)}, ..., u_{(i, t-2)}\\}$ and uses them to construct their partial blinding polynomial $b_i(x)$ as follows.

$$ u_{(i, j)} \leftarrow \mathbb{F}\_q $$
$$
\begin{align}
b_i(x) &= (x - \ell)(u_{(i, 0)} + u_{(i, 1)} x + u_{(i, 2)} x^2 + ... + u_{(i, t-2)} x^{t-2}) \\\\
       &= (x - \ell) \sum_{j = 0}^{t-2} u_{(i, j)} x^j \\\\
\end{align}
$$

2. Shareholder $i$ computes $b_i(j)$ for every other share $j \in S$, and distributes each to the bearer of share $j$.

3. Each bearer of share $i \in S$ waits to receive all $\\{b_j(i)\\}\_{j \in S}$ - the evaluations of other $b_j(x)$ polynomials on his index $i$.

4. Once in possession of all $\\{b_j(i)\\}\_{j \in S}$, the shareholder can compute $\beta(i)$ by summing all $b_j(i)$.

$$ \beta(i) = \sum_{j \in S}b_j(i) $$

5. Remember how we defined $\zeta(x) = f(x) + \beta(x)$? The bearer of share $i$ sums $z_i$ and $\beta(i)$ to yield $\zeta(i)$. This is because the share $z_i$ is just the evaluation of $f(i)$, as mentioned earlier.

$$
\begin{align}
\zeta(i) &= z_i + \beta(i) \\\\
         &= f(i) + \sum_{j \in S}b_j(i) \\\\
\end{align}
$$

6. Each shareholder $i$ sends the evaluation $(i,\ \zeta(i))$ to the new shareholder of index $\ell$, for a total of $t$ points $P = \\{(i,\ \zeta(i))\\}\_{i \in S}$.

7. The new shareholder runs the interpolation algorithm $I(P)$ to yield the degree $t - 1$ polynomial $\zeta(x)$, which they can compute at $\zeta(\ell)$ to learn their new share $z_{\ell}$.

$$ P = \\{(i,\ \zeta(i))\\}\_{i \in S} $$
$$ I(P) \rightarrow \zeta(x) $$
$$
\begin{align}
z_{\ell} &= \zeta(\ell) \\\\
         &= f(\ell) + \beta(\ell) \\\\
         &= f(\ell) + \sum_{i \in S}b_i(\ell) \\\\
         &= f(\ell) + \sum_{i \in S} \left( (\ell - \ell) \sum_{j = 0}^{t-2} u_{(i, j)} \ell^j \right) \\\\
         &= f(\ell) \\\\
\end{align}
$$

$z_{\ell}$ is just as valid a share as any other. Its bearer is on equal footing with the rest of the shareholding group. They can save $(\ell, z_{\ell})$ and conclude the issuance session by broadcasting a confirmation to the shareholders in $S$.

At this point, each shareholder $i$ can safely discard $b_i(x)$ and its coefficients $\\{u_{(i, 0)}, u_{(i, 1)}, ..., u_{(i, t-2)}\\}$ to ensure they don't fall into the wrong hands.

Caution! $\ell$ could be any index, but it must be agreed upon ahead of time by the whole issuer quorum $S$, as $\zeta(x) = f(x)$ only holds for $x = \ell$. For all other inputs, $\zeta(x)$ spits out nonsense.

Practically, $\ell$ should be chosen as an index whose share $z_{\ell}$ is certain not to be available to anyone, otherwise the issuers might duplicate someone else's existing share. Maybe Steve didn't get hit by a bus - maybe he just turned his phone off for a vacation. Upon his return, he'll be pretty upset that we gave his share to someone else. The group would need to find some way to revoke the duplicate shares (a topic for another day).

## Verifiable Procedure

The above protocol works in the sense that shareholder $\ell$ will get the correct share $z_{\ell}$, but it lacks verification protocols to defend against griefing and denial-of-service attacks. Let's amend the above protocol with some verification steps, inspired by [Feldman's VSS scheme](#Trustless-Sharing).

Assume for additional safety that the secret-sharing dealer used VSS, and so the public coefficients $\\{\phi_0, \phi_1, ..., \phi_{t-1}\\}$ of $f(x)$ are known to all shareholders, such that $\phi_i = s_i G$ as in Feldman's VSS. I'll also assume that each shareholder can reliably identify who holds which shares, so that a shareholder who does not hold share $i$ cannot pose as its bearer.

1. Once shareholder $i$ has sampled coefficients $\\{u_{(i, 0)}, u_{(i, 1)}, ..., u_{(i, t-2)}\\}$ for their partial blinding polynomial $b_i(x)$, they compute public commitments for those coefficients $\\{U_{(i, 0)}, U_{(i, 1)}, ..., U_{(i, t-2)}\\}$.

$$ u_{(i, j)} \leftarrow \mathbb{F}\_q $$
$$ U_{(i, j)} = u_{(i, j)} G $$
$$ B_i = \\{U_{(i, 0)}, U_{(i, 1)}, ..., U_{(i, t-2)}\\} $$

2. _Before_ evaluating any $b_i(x)$, shareholder $i$ broadcasts their _blinding commitment_ $B_i$ to all other shareholders $j \in S$. In turn, they receive blinding commitments $\\{B_j\\}\_{j \in S}$.

Any commitment $B_i$ can be used to compute a public version of the _partial blinding polynomial_ $b_i(x)$, i.e. to compute $b_i(x) \cdot G$ on any input $x$.

$$
\begin{align}
b_i(x) \cdot G &= (x - \ell) \left( U_{(i, 0)} + x U_{(i, 1)} + x^2 U_{(i, 2)} + ... + x^{t-2} U_{(i, t-2)} \right) \\\\
                 &= (x - \ell) \sum_{j = 0}^{t-2} x^j U_{(i, j)} \\\\
                 &= (x - \ell) \sum_{j = 0}^{t-2} x^j u_{(i, j)} G \\\\
                 &= \left( (x - \ell) \sum_{j = 0}^{t-2} u_{(i, j)} x^j \right) G \\\\
                 &= b_i(x) \cdot G \\\\
\end{align}
$$

A shareholder possessing _all_ $\\{B_i\\}\_{i \in S}$ can compute the public coefficients $\\{\theta_0, \theta_1, ..., \theta_{t-2}\\}$ (those symbols are called _theta_) of the _joint blinding polynomial_ $\beta(x)$.

$$ \theta_j = \sum_{i \in S} U_{(i, j)} $$
$$
\begin{align}
\beta(x) \cdot G &= \sum_{i \in S} b_i(x) \cdot G \\\\
                 &= \sum_{i \in S} (x - \ell) \sum_{j = 0}^{t-2} x^j u_{(i, j)} G \\\\
                 &= (x - \ell) \sum_{i \in S} \sum_{j = 0}^{t-2} x^j U_{(i, j)} \\\\
                 &= (x - \ell) \sum_{j = 0}^{t-2} x^j \sum_{i \in S} U_{(i, j)} \\\\
                 &= (x - \ell) \sum_{j = 0}^{t-2} x^j \theta_j \\\\
\end{align}
$$

With this, one can compute $\beta(x) \cdot G$ on any input $x$.

$$
\begin{align}
\beta(x) \cdot G &= (x - \ell)(\theta_0 + x \theta_1 + x^2 \theta_2 + ... + x^{t-2} \theta_{t-2}) \\\\
                 &= (x - \ell) \sum_{j = 0}^{t-2} x^j \theta_j \\\\
\end{align}
$$

It's important that every $B_i$ is _broadcast_ over some consistent medium to all other shareholders in $S$ in such a way that everyone can be sure they hold the same commitments. If such a broadcast medium isn't available, shareholders must verify with one-another that they all received the same $B_j$ for every $j \in S$. If someone sent around inconsistent commitments, it would cause the whole issuance process to fail later.

3. Once all\* other shareholders' commitments $\\{B_j\\}\_{j \in S}$ are in hand and are universally agreed upon, only _then_ does shareholder $i$ compute $b_i(j)$ for all $j \in S$ and send each evaluation to shareholder $j$.

$$
\begin{align}
b_i(x) &= (x - \ell)(u_{(i, 0)} + u_{(i, 1)} x + u_{(i, 2)} x^2 + ... + u_{(i, t-2)} x^{t-2}) \\\\
       &= (x - \ell) \sum_{j = 0}^{t-2} u_{(i, j)} x^j \\\\
\end{align}
$$

\* <sub>For better efficiency, it is okay for shareholder $i$ to optimistically send out blinding polynomial evaluations _before_ receiving all commitments, as long as she only sends out a maximum of $t - 2$ evaluations. The last evaluation should only be transmitted once she has all $\\{B_j\\}\_{j \in S}$. [This section of the security proof explains why](#Rogue-Blinding-Evaluations). </sub>

4. Upon receiving the partial blinding polynomial evaluation $b_j(i)$ from another shareholder $j$, she verifies that the evaluation matches the commitment $B_j$.

$$ B_j = \\{U_{(j, 0)}, U_{(j, 1)}, ..., U_{(j, t-2)}\\} $$
$$ b_j(i) \cdot G = (i - \ell) \sum_{k = 0}^{t-2} x^k U_{(j, k)} $$

5. Shareholders aggregate their partial blinding polynomial evaluations to compute $\zeta(i)$ as described in the previous section.

$$
\begin{align}
\zeta(i) &= z_i + \sum_{j \in S}b_j(i) \\\\
         &= f(i) + \beta(i) \\\\
\end{align}
$$

6. Each shareholder $i$ sends to the new inductee shareholder $\ell$ the following data:

- The public coefficients of the share polynomial $f(x)$: $C = \\{\phi_0, \phi_1, ..., \phi_{t-1}\\}$.
- The public coefficients of blinding polynomial $\beta(x)$: $B = \\{\theta_0, \theta_1, ..., \theta_{t-1}\\}$
- The new share index $\ell$.
- The evaluation of the issuance polynomial $(i,\ \zeta(i))$.

7. The new shareholder $\ell$ _verifies all the things._

- Ensure that the sets of public coefficients $B$ and $C$ for the joint polynomials, as well as the new index $\ell$ given by every shareholder in $S$ are all consistent. If not, someone might be trying to play funny games.
- (optional) If a-priori knowledge of the public point $\phi_0 = s_0 G$ is available or verifiable, now would be a good time to check that it matches $C$.
- Verify each evaluation $(i,\ \zeta(i))$ is authentic for the given commitments $B$ and $C$.

$$
\begin{align}
\zeta(i) \cdot G &= (\phi_0 + i \phi_1 + i^2 \phi_2 + ... + i^{t-1} \phi_{t-1}) + \\\\
&\quad  (i - \ell)(\theta_0 + i \theta_1 + i^2 \theta_2 + ... + i^{t-2} \theta^{t-2}) \\\\
                 &= \sum_{j = 0}^{t-1} i^j \phi_j + (i - \ell) \sum_{j = 0}^{t-2} i^j \theta_j \\\\
                 &= f(i) \cdot G + \beta(i) \cdot G \\\\
\end{align}
$$

If these checks pass, the new shareholder $\ell$ is confident that $\zeta(\ell) = f(\ell)$ yielding their share $z_{\ell}$ of the secret polynomial $f(x)$. Remember the whole point of this was to give shareholder $\ell$ a share that would let them help to recover $f(x)$, and hence the secret $s_0$, which is the constant coefficient of $f(x)$.

8. Once the new shareholder has $t$ valid evaluations of $\zeta(\ell)$, they can use the points $\\{(i,\ \zeta(i))\\}\_{i \in S}$ to perform polynomial interpolation to recover the full degree $t - 1$ polynomial $\zeta(x)$.

$$ P = \\{(i,\ \zeta(i))\\}\_{i \in S} $$
$$ I(P) \rightarrow \zeta(x) $$
$$
\begin{align}
\zeta(\ell) &= f(\ell) + \beta(\ell) \\\\
            &= f(\ell) + 0 \\\\
            &= z_{\ell} \\\\
\end{align}
$$

## Security Proof

I'm now going to take a stab at proving the security of this protocol. Of course, all this assumes the discrete logarithm problem is hard, and $M$ cannot simply compute $s_0 = \phi_0 \div G$.

Consider a situation in which a dishonest cabal of malicious shareholders $M$, which is some subset of $S$, attempts to learn some information from the share issuance process which they could use to deduce more information about $f(x)$ or the secret $s_0$. The issuance protocol is secure if $M$ learns nothing which they did not already know about $f(x)$ or $s_0$ before participating in an execution of the issuance protocol.

Shamir's Secret Sharing is perfectly secure against $t - 1$ malicious shareholders, so as long as $M$ consists of fewer than $t$ shareholders, they do not yet know any information about $f(x)$ before executing the share issuance protocol.

### Honest Inductee

Consider when $M$ is one share short of a full takeover. Here, $M$ is composed of $t - 1$ existing malicious shareholders in $S$. The new shareholder $\ell$ and at least one shareholder $h \in S$ remain honest.

The only new information which $M$ learns during the issuance process is the partial blinding polynomial evaluations $b_h(j)$, which are sent by the bearer of share $h$ to each malicious shareholder $j$ in the cabal $M$. This allows $M$ to collectively interpolate any $b_h(x)$ using those evaluations, plus the implicit point $(\ell, 0)$.

$$ I(\\{(j,\ b_h(j))\\}\_{j \in M}, (\ell, 0)) \rightarrow b_h(x) $$

But this is of no use to $M$, because $b_h(x)$ will be totally random if shareholder $h$ is honest, and is thus unrelated to $f(x)$ or $s_0$. This gives $M$ no additional information.

Since the new shareholder $\ell$ is honest, $M$ does not learn $\zeta(x)$ or any evaluations thereof.

### Malicious Inductee

Consider an alternative situation in which the new shareholder $\ell$ is colluding with $M$, where $M$ is now composed of $t - 2$ shareholders in $S$. There remain two honest shareholders $(h, g) \in S$. This case is more subtle, so let's take stock of every piece of information that $M$ learns in the process, and the relationships between what $M$ does not learn.

First, $M$ receives the evaluations of the partial blinding polynomials $b_h(j)$ and $b_g(j)$ for all $j \in M$, which are random. $M$ does _not_ receive evaluations $\\{b_h(h),\ b_h(g),\ b_g(h),\ b_g(g)\\}$. To learn these, $M$ would need to interpolate the partial blinding polynomials $b_h(x)$ and $b_g(x)$. This would require $M$ learning at least $t - 1$ evaluations of each polynomial to supplement the presumed point $(\ell, 0)$. As stated, $M$ receives only $t - 2$ evaluations of each: $\\{b_h(j)\\}\_{j \in M}$, and $\\{b_g(j)\\}\_{j \in M}$.

$M$ does learn the blinding polynomial evaluations on the indexes $j \in M$. This allows them to define relationships between the four unknowns using Lagrange interpolation polynomials. I'll emphasize the values which $M$ does not know.

$$ \lambda_i = \left( \frac{h - g}{i - g} \right) \left( \frac{h - \ell}{i - \ell} \right) \left( \prod_{\substack{j \in M \\\\ j \ne i}} \frac{h - j}{i - j} \right) $$
$$ \overbrace{b_h(h)}^{\text{unknown}} = \sum_{j \in M} \lambda_j b_h(j) + \lambda_g \overbrace{b_h(g)}^{\text{unknown}} $$

$$ \gamma_i = \left( \frac{g - h}{i - h} \right) \left( \frac{g - \ell}{i - \ell} \right) \left( \prod_{\substack{j \in M \\\\ j \ne i}} \frac{g - j}{i - j} \right) $$
$$ \overbrace{b_g(g)}^{\text{unknown}} = \sum_{j \in M} \gamma_j b_g(j) + \gamma_h \overbrace{b_g(h)}^{\text{unknown}} $$

<sub>$\lambda_i$ and $\gamma_i$ are Lagrange Coefficients, defined to interpolate the evaluations of $b_h(x)$ and $b_g(x)$ which are availalbe to $M$.</sub>

$M$ also learns the two issuance polynomial evaluations, since they are sent to the new and malicious shareholder $\ell$.

$$
\begin{align}
\zeta(h) &= z_h + \beta(h)  \\\\
           &= z_h + \sum_{i \in S} b_i(h)  \\\\
\end{align}
$$
$$
\begin{align}
\zeta(g) &= z_g + \beta(g)  \\\\
           &= z_g + \sum_{i \in S} b_i(g)  \\\\
\end{align}
$$

Let's extract the values which are unknown to $M$ from the summation notation, for better readability.

$$ \zeta(h) = \sum_{j \in M} b_j(h) + \overbrace{z_h + b_h(h) + b_g(h)}^{\text{unknown}} $$
$$ \zeta(g) = \sum_{j \in M} b_j(g) + \overbrace{z_g + b_h(g) + b_g(g)}^{\text{unknown}} $$

Using these evaluations, $M$ can learn the new share $z_{\ell} = \zeta(\ell) = f(\ell)$, which is related to the shares $\\{z_i\\}\_{i \in S}$ through a Lagrange interpolation polynomial.

$$ \varphi_i = \prod_{\substack{j \in S \\\\ j \ne i}} \frac{\ell - j}{i - j} $$
$$
\begin{align}
z_{\ell} &= f(\ell) \\\\
         &= \sum_{i \in S} \varphi_i \cdot f(i) \\\\
         &= \sum_{i \in S} \varphi_i z_i \\\\
\end{align}
$$

<sub>$\varphi_i$ is a set of Lagrange coefficients defined to interpolate each share index in $S$.</sub>

Grouping once more to see values known to $M$ and those unknown to $M$:

$$
z_{\ell} = \sum_{j \in M} \varphi_j z_j + \varphi_h \overbrace{z_h}^{\text{unknown}} + \varphi_g \overbrace{z_g}^{\text{unknown}}
$$

In summary, $M$ now has a system of _five_ equations:

$$ \overbrace{b_h(h)}^{\text{unknown}} = \sum_{j \in M} \lambda_j b_h(j) + \lambda_g \overbrace{b_h(g)}^{\text{unknown}} $$
$$ \overbrace{b_g(g)}^{\text{unknown}} = \sum_{j \in M} \gamma_j b_g(j) + \gamma_h \overbrace{b_g(h)}^{\text{unknown}} $$
$$ \zeta(h) = \sum_{j \in M} b_j(h) + \overbrace{z_h + b_h(h) + b_g(h)}^{\text{unknown}} $$
$$ \zeta(g) = \sum_{j \in M} b_j(g) + \overbrace{z_g + b_h(g) + b_g(g)}^{\text{unknown}} $$
$$ z_{\ell} = \sum_{j \in M} \varphi_j \cdot z_j + \varphi_h \cdot \overbrace{z_h}^{\text{unknown}} + \varphi_g \cdot \overbrace{z_g}^{\text{unknown}} $$

...with six unknowns:

- $b_h(h)$
- $b_h(g)$
- $b_g(h)$
- $b_g(g)$
- $z_h$
- $z_g$


This is an [undetermined system of equations](https://en.wikipedia.org/wiki/Underdetermined_system): It has infinite solutions (technically not infinite solutions, since we're working in the finite field $\mathbb{F}\_q$, but any solution is equally likely). If $M$ could learn any one of those unknowns, they would be able to solve the system of equations and unravel the secret-sharing scheme, but as long as at least two shareholders in $S$ are honest and keep those values secret, it will be impossible for a malicious subgroup to solve for any secrets.

### Trickery

Can $M$ fool honest shareholders $h$ or $g$ into revealing one of these hidden values?

Aside from verification commitments, the only inputs which either honest shareholder accepts from $M$ that are used in secret computations are the evaluations of the partial blinding polynomials.

$$ \\{b_j(h)\\}\_{j \in M} \quad \quad \\{b_j(g)\\}\_{j \in M} $$

These potentially malicious inputs are summed with honest partial blinding evaluations from the two honest shareholders to compute the evaluations $\zeta(h)$ and $\zeta(g)$.

$$ \zeta(h) = \overbrace{\sum_{j \in M} b_j(h)}^{\text{malicious}} + z_h + b_h(h) + b_g(h) $$
$$ \zeta(g) = \overbrace{\sum_{j \in M} b_j(g)}^{\text{malicious}} + z_g + b_h(g) + b_g(g) $$

Since all shareholders in $M$ are acting in concert, and since all $b_j(x)$ evaluations will be aggregated anyway, let's simplify and define the evil inputs $e_1$ and $e_2$ such that

$$ \zeta(h) = \overbrace{e_1}^{\text{malicious}} + z_h + b_h(h) + b_g(h) $$
$$ \zeta(g) = \overbrace{e_2}^{\text{malicious}} + z_g + b_h(g) + b_g(g) $$

$M$ will be given $\zeta(h)$ and $\zeta(g)$ by the honest shareholders. $M$ can attempt to choose some evil values of $e_1$ and $e_2$ which reveal information about the unknowns, but this is not possible as $z_h + b_h(h) + b_g(h)$ and $z_g + b_h(g) + b_g(g)$ are honestly random. No matter what value of $e_1$ or $e_2$ is chosen by $M$, both evaluations $\zeta(h)$ and $\zeta(g)$ given to $M$ will appear to be randomly chosen.

### Rogue Blinding Evaluations

The blinding polynomial commitments $\\{B_j\\}\_{j \in S}$ are an essential part of this scheme, at least in cases where we're considering an actively colluding set of shareholders. Commitments must all be received before a shareholder transmits all of his partial blinding polynomial evaluations.

Under certain conditions, a malicious cabal $M$ of $t - 1$ shareholders can execute a _griefing attack_, influencing the issuance polynomial evaluation $\zeta(h)$ of the one honest shareholder $h$ to make him expose his share to the new shareholder $\ell$. Although shareholder $\ell$ is not part of $M$ by definition and so $M$ learns nothing from this attack, this would still hurt the honest shareholder $h$ and compromise the security of the scheme.

Shareholder $h$ will evaluate the issuance polynomial as

$$
\begin{align}
\zeta(h) &= z_h + \sum_{j \in S} b_j(h) \\\\
         &= \overbrace{\sum_{j \in M} b_j(h)}^{\text{malicious}} + z_h + b_h(h) \\\\
         &= \overbrace{e}^{\text{malicious}} + z_h + b_h(h) \\\\
\end{align}
$$

If verifiable commitments $B_i = \\{U_{(i, 0), U_{(i, 1)}, ..., U_{(i, t - 2)}}\\}$ are not used, or if shareholder $h$ doesn't wait for all blinding polynomial commitments before sending $b_h(j)$ to shareholders $j \in M$, then $M$ could wait until they receive all $t - 1$ blinding polynomial evaluations from shareholder $h$. They can then interpolate $b_h(x)$ and collectively compute a rogue set of evaluations $e$ which they would submit to shareholder $h$.

$$ e = \sum_{j \in M} b_j(h) = - b_h(h) $$

This fools shareholder $h$ into computing $\zeta(h) = z_h$ which would expose the honest shareholder's share $z_h$ to the new shareholder $\ell$.

$$
\begin{align}
\zeta(h) &= \overbrace{e}^{\text{malicious}} + z_h + b_h(h) \\\\
         &= -b_h(h) + z_h + b_h(h) \\\\
         &= z_h \\\\
\end{align}
$$

The new shareholder $\ell$ who receives this evaluation might use $\\{\phi_0, \phi_1, ..., \phi_{t-1}\\}$ to passively observe that $\zeta(h) \cdot G = f(h) \cdot G$. Shareholder $\ell$ has found herself in possession of a duplicate share $z_h$ instead of the new share she intended to learn, $z_{\ell}$.

$M$ cannot fully control the output of $\zeta(h)$ because they do not know $z_h$. They could not, for example, cause the new share $\zeta(\ell)$ to evaluate to a number they already know. Even if they could, shareholder $\ell$ would catch such shenanigans when they verify the evaluations $\\{(i,\ \zeta(i))\\}\_{i \in S}$.

Note that for efficiency reasons, it would be entirely safe for shareholder $h$ to prematurely transmit $t - 2$ evaluations of $b_h(x)$, but hold back the last evaluation in reserve until he receives all $\\{B_j\\}\_{j \in M}$. This is because $M$ needs at least $t$ evaluations of $b_h(x)$ to interpolate it and compute a rogue value of $e = - b_h(h)$. The cabal $M$ already knows one implicit evaluation, $b_h(\ell) = 0$. Knowing an additional $t - 2$ evaluations of $b_h(x)$ does not give $M$ enough information to interpolate $b_h(x)$, and so they cannot compute $e = - b_h(h)$.

## Security Intuition

Recall we defined $\zeta(x)$ as the sum of $f(x) + \beta(x)$. The blinding polynomial $\beta(x)$ acts as a shield, jointly built by every shareholder in $S$. This prevents the issuance polynomial $\zeta(x)$ from leaking information about the underlying secret polynomial $f(x)$ to the new shareholder $\ell$ who recovers it, _except_ for the specific prearranged index $\ell$ at which $\zeta(\ell) = f(\ell)$.

Thanks to $\beta(x)$, the coefficients of $\zeta(x)$ are all a mix of the secret coefficients $\\{s_0, s_1, ..., s_{t-1}\\}$ chosen by the dealer, and the random coefficients $\\{u_{(i, 0)}, u_{(i, 1)}, u_{(i, t - 2)}\\}$ sampled uniformly by _every_ shareholder $i$.

Notice that as long as _at least one_ participant sampled her $u_{(i, j)}$ coefficients honestly, then the joint blinding polynomial $\beta(x)$ will also have totally unpredictable coefficients.

Unfortunately for the malicious inductee, every coefficient in $\zeta(x)$ is thus scrambled by some random offset. The inductee cannot distinguish between coefficients of $\zeta(x)$ given by a real issuance session, and a random set of coefficients, except that they can use $\\{\phi_0, \phi_1, ..., \phi_{t-1}\\}$ to verify $\zeta(\ell) \cdot G = f(\ell) \cdot G$.

Otherwise, the malicious inductee could have generated the coefficients of $\zeta(x)$ randomly on their own and they would end up with the same distribution of coefficients.

### Degrees of Freedom

It is important that the blinding polynomial $\beta(x)$ has degree $t - 1$, and is configured so that every one of its $t$ coefficients appears randomly sampled.

If $\beta(x)$ had degree $t$ or higher then so would $\zeta(x)$. The new shareholder would need to be given at least $t + 1$ evaluations of $\zeta(x)$ to interpolate their new share $z_{\ell} = \zeta(\ell)$, which is impossible if only $t$ shares are available. This breaks usability of the protocol.

On the other hand, $\beta(x)$ also can't be a polynomial of degree $t - 2$ or less without compromising security. If the degree of $\beta(x)$ was $t - 2$ or lower, a cabal of $t-2$ shareholders in $S$ could interpolate $\beta(x)$ given $t-2$ evaluations of the partial blinding polynomials from the 2 honest shareholders, plus the implicit point $(\ell, 0)$.

If the new shareholder $\ell$ also colludes for a total of $t - 1$ dishonest parties, then the cabal can compute $f(x) = \zeta(x) - \beta(x)$ and find the secret $s_0 = f(0)$. This breaks our security model, so $\beta(x)$ must have at exactly degree $t - 1$.

### Blinding Polynomial Secrecy

It is crucial that the full blinding polynomial $\beta(x)$ must not be learned, especially by the new shareholder $\ell$. Shareholders should discard their partial blinding polynomial $b_i(x)$ as soon as it is no longer needed. The blinding polynomials must be completely randomly generated, not derived through any deterministic mechanism.

If $\beta(x)$ can be discovered, predicted, or derived by the new shareholder, then the new shareholder can compute $f(x) = \zeta(x) - \beta(x)$ to recover the original secret polynomial, and learn the secret $s_0$.

The joint blinding polynomial coefficients $\\{\vartheta_0, \vartheta_1, ..., \vartheta_1\\}$ must not be reused for multiple issuance sessions. If the same joint blinding coefficients are used to construct two different issuance polynomials, $\zeta(x)$ and $\zeta'(x)$, at distinct indexes $\ell$ and $\ell'$ respectively, then the two shareholders who interpolated $\zeta(x)$ and $\zeta'(x)$ could collude to recover $f(x)$.

<details>
  <summary>Here's how.</summary>

If two distinct issuance polynomials $\zeta(x)$ and $\zeta'(x)$ use the same blinding coefficients, two colluding shareholders can solve a system of equations to compute $f(x)$.

Let $\\{\vartheta_0, \vartheta_1, ..., \vartheta_{t-2}\\}$ represent the jointly chosen random coefficients of $\beta(x)$, such that

$$ \vartheta_j = \sum_{i \in S} u_{(i, j)} $$
$$ \vartheta_j G = \theta_j $$
$$ \beta(x) = (x - \ell) \sum_{j = 0}^{t-2} \vartheta_j x^j $$

For brevity, let's define $w(x)$ as the reused part of the blinding polynomial.

$$ w(x) = \sum_{j = 0}^{t-2} \vartheta_j x^j $$
$$ \beta(x) = (x - \ell) \cdot w(x) $$
$$ \beta'(x) = (x - \ell') \cdot w(x) $$

Phrase $w(x)$ in terms of $f(x)$.

$$
\begin{align}
\zeta(x) &= f(x) + \beta(x) \\\\
\zeta(x) &= f(x) + (x - \ell) \cdot w(x) \\\\
\zeta(x) - f(x) &= (x - \ell) \cdot w(x) \\\\
\frac{\zeta(x) - f(x)}{x - \ell} &= w(x) \\\\
\end{align}
$$

This will work out similarly for the alternate issuance polynomial.

$$
\begin{align}
\zeta'(x) &= f(x) + (x - \ell') \cdot w(x) \\\\
w(x) &= \frac{\zeta'(x) - f(x)}{x - \ell'} \\\\
\end{align}
$$

Set both sides equal.

$$
\begin{align}
\frac{\zeta(x) - f(x)}{x - \ell} &= \frac{\zeta'(x) - f(x)}{x - \ell'} \\\\
\end{align}
$$

Together the colluding shareholders know $\zeta(x)$ and $\zeta'(x)$, as well as $\ell$ and $\ell'$, so they can solve for $f(x)$.

$$
\begin{align}
\frac{\zeta(x) - f(x)}{x - \ell} &= \frac{\zeta'(x) - f(x)}{x - \ell'} \\\\
\left( \zeta(x) - f(x) \right)(x - \ell') &= \left( \zeta'(x) - f(x) \right)(x - \ell) \\\\
\zeta(x) \cdot (x - \ell') - f(x) \cdot (x - \ell') &= \zeta'(x) \cdot (x - \ell) - f(x) \cdot (x - \ell) \\\\
f(x) \cdot (x - \ell) - f(x) \cdot (x - \ell') &= \zeta'(x) \cdot (x - \ell) - \zeta(x) \cdot (x - \ell') \\\\
f(x) \cdot ((x - \ell) - (x - \ell')) &= \zeta'(x) \cdot (x - \ell) - \zeta(x) \cdot (x - \ell') \\\\
f(x) \cdot (x - \ell - x + \ell') &= \zeta'(x) \cdot (x - \ell) - \zeta(x) \cdot (x - \ell') \\\\
f(x) \cdot (\ell' - \ell) &= \zeta'(x) \cdot (x - \ell) - \zeta(x) \cdot (x - \ell') \\\\
f(x) &= \frac{\zeta'(x) \cdot (x - \ell) - \zeta(x) \cdot (x - \ell')}{\ell' - \ell} \\\\
\end{align}
$$

</details>

### Index Verification

The shareholders in $S$ must ensure that all $i \in S$ are distinct from one another and from $\ell$. Duplicate share indexes would cause divide-by-zero errors when interpolating $I(P)$ and possibly lead to unexpected vulnerabilities.

It is also important that each shareholder can positively identify which agents holds which shares when communicating. Agents who misrepresent their share indexes could fool honest shareholders into computing erroneous data.

For example, if a potential new shareholder asks to be issued a share at index $q$, shareholders must not allow this. Jointly computing $f(q)$ could result in computing $f(0)$ if working in the field of integers (if $\mathbb{F}\_q = \mathbb{Z}\_q$), because $q \mod q \equiv 0$.

Shareholders who hold multiple shares may equivocate by reporting different share indexes to different peers during the setup phase. If shareholder $i$ also controls share $j$ legitimately, they could tell other shareholders that they are using either index and give their peers different views of $S$. Both peers could verify $i$ and $j$ are legitimate indexes for this shareholder, despite the inconsistency. Shareholders should thus also verify that all parties agree on the set of indexes $S$ involved in the share recovery procedure. This is left as an exercise to the implementation.

## Use Cases

### Recovery

Share recovery is probably the most realistic use case for this algorithm. If shareholders maintain a record of who has which share, then they can safely recover lost shares. Records of share ownership are crucial here, so that a phony recovery attempt does not give a malicious shareholder access to new shares they shouldn't have. For example, Bob might have share $i$, and claims he forgot his share. He might report his share index as $\ell$ instead in an attempt to learn someone else's share (or learn a completely new share). The other shareholders must be able to verify if $\ell$ is his original share index, to tell if Bob is misbehaving.

As an example, say an employee's laptop is wiped with a Shamir share share on it. The other staff on their team who - assuming they have at least $t$ shares between them - could interactively assist the employee in recovering the lost share without exposing any shares to anyone who shouldn't have them. This is safe only if the other staff can verify which share the victim had before it was lost.

Users of [SLIP39](https://github.com/satoshilabs/slips/blob/master/slip-0039.md) might find this procedure interesting, as it would allow a user to recover lost SLIP39 shares without having to physically bring the shares together. Yet, I doubt the security of this concept in practice, given the highly sensitive nature of a Bitcoin hardware wallet. To perform interactive share recovery with multi-party computations, the threshold of shares would need to be plugged into separate internet-connected computers, which defeats the purpose of a hardware wallet in the first place.

Interactive share recovery (and all the verification steps) would need to be implemented in hardware wallet firmware, and then all $t$ shareholders would need to have a compatible hardware wallet. This is probably much more effort than it is worth. Instead, a user could merely bring a set of $t$ shares physically together and reconstitute the full $f(x)$ polynomial on the hardware wallet.

### Repairable Multisignature

In the case of multisignature, the share recovery protocol would allow signers in polynomial-based threshold signing systems like [FROST](https://eprint.iacr.org/2020/852) to recover the long-lived signing shares of signers who experienced some hardware fault or forgot the encryption password for their signing key.

They could also enroll new signers into their group, provided they can mitigate the risk that a new signer might actually be an old signer in a fake mustache.

### Repairable Escrow

One could create a redundant 2-of-3 multisignature escrow service in which the user acts as the dealer of shares of a threshold private key. One share (the _escrow_ share) is given to the escrow agent, and two are given to the user. The user can store one of their shares (the _cold_ share) on paper or a USB drive, somewhere safe and offline. The other share (the _hot_ share) can be an online, active-use signing key, used to collaborate with the escrow agent to sign certificates, Bitcoin transactions, emails, etc.

- The escrow agent acts as a remote second factor, verifying the user with some secondary authentication method like a hardware token, or biometrics.
- If the user loses one of their shares but retains the other share, the escrow agent can collaborate with the user to recover the lost share trustlessly, thereby returning the user to his original fully functioning state. Other threshold multisignature schemes would require a key migration to fully recover both of the user's shares.
- If the escrow agent disappears, the user can independently recover their share with the hot and cold shares, and give the recovered escrow share to a new escrow agent. Colluding escrow agents would be powerless, because they each have the same share.

## Alternative Approaches

### Sampling Evaluations

One could also design the partial blinding polynomials $b_i(x)$ by sampling random _evaluations_ in $\mathbb{F}\_q$ instead of sampling random coefficients.

A shareholder $i$ would sample $t - 1$ random evaluations $y_j \leftarrow \mathbb{F}\_q : \\{y_j\\}\_{j \in S : j \ne i}$, one for each index in $S$ except for their own.

They would append the fixed point $(\ell, 0)$ for a total of $t$ points, and interpolate the resulting degree $t - 1$ polynomial $b_i(x)$.

$$ I(\\{(j, y_j)\\}\_{j \in S : j \ne i}, (\ell, 0)) \rightarrow b_i(x) $$

The evaluations $\\{(j, b_i(j))\\}\_{j \in S : j \ne i} = \\{(j, y_j)\\}\_{j \in S : j \ne i}$ would be sent to all other shareholders $j \in S$. Shareholder $i$ would receive all $\\{b_j(i)\\}\_{j \in S : j \ne i}$, and then compute $\zeta(i) = z_i + \sum_{j \in S} b_j(i)$ as normal from there, computing $b_i(i)$ on her own.

This alternative approach is a helpful demonstration that however $b_i(x)$ may be constructed, one evaluation of $b_i(x)$ is not truly random, but a function of the other $t - 1$ random evaluations, plus the assumed evaluation $b_i(\ell) = 0$. At first this seems concerning, but as described above, a colluding subgroup would need at least $t - 1$ shareholders who know $b_i(j)$ to interpolate the full $b_i(x)$ polynomial, and shareholder $\ell$ (who receives $\zeta(i)$) must also participate to make use of this knowledge to learn $f(x)$.

### NSG Enrollment

[This paper by Stinson and Wei](https://arxiv.org/pdf/1609.01240.pdf) describes a similar approach to issue or recover Shamir shares, in section 2. Unfortunately I only read about this method once I had already finished the majority of this article.

Both methods are very similar and share similar security proofs. Stinson and Wei's approach might be slightly more efficient in terms of computations, but they also did not describe a verification process to avoid denial-of-service and griefing attacks.

## Conclusion

Other interesting extensions to Shamir's Secret Sharing include [changing the threshold](/cryptography/shamir-resharing/), removing a shareholder, or modifying the shared secret in a verifiable fashion.

I might spend a bit of time to write a demo implementation of this algorithm in Python or Rust in the near future if there is sufficient interest.

I have seen [some recent interest](https://gist.github.com/nickfarrow/64c2e65191cde6a1a47bbd4572bf8cf8) on the concept of [hardware-backed FROST signing tools](https://frostsnap.com/). Having the ability to recover such a device without the need to migrate keys would be a huge win.

<details>
  <summary>Sources</summary>

- [_A Practical Scheme for Non-Interactive Verifiable Secret Sharing_ - Paul Feldman](https://www.cs.umd.edu/~gasarch/TOPICS/secretsharing/feldmanVSS.pdf)
- [_SLIP39 Specification_ - SatoshiLabs](https://github.com/satoshilabs/slips/blob/master/slip-0039.md)
- [_FROST: Flexible Round-Optimized Schnorr Threshold Signatures_ - Komlo & Goldberg](https://eprint.iacr.org/2020/852)
- [_Combinatorial Repairability for Threshold Schemes_ - Stinson & Wei](https://arxiv.org/pdf/1609.01240.pdf)
- [_Fundamental Theorem of Algebra_ - Wikipedia](https://en.wikipedia.org/wiki/Fundamental_theorem_of_algebra)
- [_Lagrange Polynomials_ - Wikipedia](https://en.wikipedia.org/wiki/Lagrange_polynomial)

</details>
