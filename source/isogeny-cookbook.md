---
title: Isogeny Cryptography Cookbook for Beginners
date: 2026-05-14
mathjax: true
category: cryptography
description: My collection of facts, proofs, and results from the world of isogeny-based crypto.
---

# Isogeny Cryptography Cookbook for Beginners

[My previous article on isogenies](/cryptography/isogenies-intro/) was a light sampling of the world of isogeny cryptography. This one is the full nine-course meal.

This article is a collection of facts, proofs, notes, and tidbits I have gathered together from the world of isogeny-based cryptography. I have tried to cite sources where possible, which are typically scholarly articles, lecture notes, or textbooks. My goal is to provide an approachable learning resource for others like myself who may lack a formal mathematics background but are interested in learning isogeny cryptography. I have tried to define all mathematical terms, notation, and techniques which aren't taught in an average high-school.

I will be focusing on the mathematics needed to understand the signature schemes SQIsign and PRISM, and the parameter sets they come packaged with. The motivation for this narrow focus was explained in [my previous article](/cryptography/isogenies-intro/) - I see these schemes as the current optimal candidates for inclusion into Bitcoin to replace the structure of classical secp256k1-based signatures. Accordingly I will be mostly ignoring the world of oriented isogenies and class group actions which gives rise to schemes like CSIDH and CSI-FiSh. Perhaps eventually I will expand the collection of notes but for now it is long-winded enough as is.

Let's get cracking.

## Notation

Some basic math notations will make this article much easier to write succinctly:

| Notation | Meaning |
|:-:|-|
| $\mathbb{R}$ | The [real numbers](https://en.wikipedia.org/wiki/Real_number) |
| $\mathbb{Q}$ | The [rational numbers](https://en.wikipedia.org/wiki/Rational_number) |
| $\mathbb{Z}$ | The [integers](https://en.wikipedia.org/wiki/Integer) |
| $\mathbb{Z}\_p$ | The integers modulo $p$ |
|$a \in S$| The element $a$ _in_ the set $S$ |
|$a \notin S$| The element $a$ _is not in_ the set $S$ |
| $a \approx b$ | $a$ is _approximately equal_ to $b$ |
| $a \mod p$ | The _residue_ (remainder) of $a$ after dividing by $p$ ([explanation](https://en.wikipedia.org/wiki/Modular_arithmetic)) |
| $\|S\|$ | The _cardinality_ (number of elements) of a set $S$. |
| $H \cup G$ | The _union_ of sets $H$ and $G$: The set of all elements contained in _either_ $G$ or $H$. |
| $H \cap G$ | The _intersection_ of sets $H$ and $G$: The set of all elements contained in _both_ $G$ or $H$. |
| $H \subset G$ | The set $H$ is a _strict subset_ of $G$: $H$ contains some elements of $G$ but not all. |
| $H \subseteq G$ | The set $H$ is a _subset_ of $G$: $H$ contains some elements of $G$ (possibly all). |
| $G \setminus H$ | The set $G$ _without its subset_ $H$. The resulting set contains no elements of $H$. |
| $\lfloor \frac{q}{n} \rfloor$ | The _floor_ of $\frac{q}{n}$ (round down after dividing). |

## Terminology

| Phrase | Meaning |
|:-:|-|
| The _order_ of a finite field | The number of elements in the finite field |

## High-Level

Isogeny cryptography is a web woven from many threads of mathematics. This cookbook will document the prerequisite knowledge one subject at a time, hopefully to the point of fully convincing the reader how (and why) certain constructions behave the way they do, after which we'll proceed to the next subject and do the same, until we have everything we need to build an isogeny cryptosystem.

The non-exhaustive list of relevant subjects we will cover includes:

| Subject | Draft Status |
|:-:|:-:|
| [Finite fields](#Finite-Fields) | Done ✅ |
| [Extension fields](#Extension-Fields) | Done ✅ |
| [Elliptic Curves](#Elliptic-Curves) | Done ✅ |
| [Isogenies](#Isogenies) | WIP 🚧 |
| [Torsion Groups](#Torsion-Groups)  | TODO |
| [Quaternion Algebras](#Quaternion-Algebras) | TODO |
| [Endomorphism Rings](#Endomorphism-Rings) | TODO |
| [SQIsign](#SQIsign) | TODO |

Once we have all of these tools under our belt, we can implement secure signature schemes.

## Finite Fields

Finite fields, also called Galois Fields after [their creator](https://en.wikipedia.org/wiki/%C3%89variste_Galois), can be thought of as a computer-friendly finite set of numbers with addition, subtraction, multiplication, and division.

A finite field of _order_ (size) $p$ is typically written as $\mathbb{F}\_p$. Any finite field must follow the same basic rules as the real numbers $\mathbb{R}$. Namely:

- There exists an _additive identity_ $0$ such that for any field element $a$ we have $a + 0 = a$.
- There exists a _multiplicative identity_ $1$ such that for any field element $a$ we have $a * 1 = a$.
- Every field element $a$ has an _additive inverse_ $-a$ such that $a + (-a) = 0$
- Every field element $a$ has a _multiplicative inverse_ $a^{-1}$ such that $a \cdot  a^{-1} = 1$
- Addition is:
    - _associative_: $(a + b) + c = a + (b + c)$
    - _commutative_: $a + b = b + a$
- Multiplication is:
    - _associative_: $(a \cdot b) \cdot c = a \cdot (b \cdot c)$
    - _commutative_: $a \cdot b = b \cdot a$
    - _distributive over addition:_ $a \cdot (b + c) = a \cdot b + a \cdot c$

These rules should all seem pretty obvious - like, that's how basic-ass algebra works right?

Well yes, but not all number systems follow these rules, and when we get to the section on quaternions we'll see an example of a non-commutative algebra system. We should be explicit about the minimum requirements that a number system needs to satisfy to be a finite field. In most cases this is not really something to worry about: Once you have a finite field, you can work with it much like you can work with the real numbers. There are some interesting exceptions worth mentioning though, which we'll get to.

### Construction

Finite fields can have any _order_ (size) $q$ which is a power of a prime number $p$, often written as $q = p^k$ where $p$ is a prime and $k$ is a positive integer. Note that $p = 2$ is a prime, so we can have a finite field which is a size of a power of two. Fields of size $2^k$ are used often in coding theory (e.g. [Reed-Solomon codes](https://en.wikipedia.org/wiki/Reed%E2%80%93Solomon_error_correction)) to maximize space efficiency in error-correcting codes.

For cryptographic use cases, we typically need $p$ to be some large prime number (hundreds of bits long), and set $k = 1$, so we end up with a _prime-order_ finite field $\mathbb{F}\_p$. Finite fields of prime order $p$ are typically built using the set of integers mod $p$, written as $\mathbb{Z}\_p$. This is basically the integers from $0$ up to and including $p - 1$, with arithmetic performed [modulo](https://en.wikipedia.org/wiki/Modular_arithmetic) $p$.

### Arithmetic

In this way, addition, subtraction, multiplication, and exponentiation operations in the field all follow from regular integer arithmetic rules, e.g. $5 \cdot 3 = 15$. If working in $\mathbb{Z}\_{13}$, then $5 \cdot 3 \equiv 2 \mod 13$, with the three-lined equals sign meaning [_congruent_](https://en.wikipedia.org/wiki/Modular_arithmetic#Congruence), or in plain english: 15 reduced modulo 13 is 2. This way we get _associativity_ and _commutativity_ for free.

The additive and multiplicative identities are $0$ and $1$ respectively, which are always in the field. The additive inverse of $a \in \mathbb{Z}\_p$ is given by subtracting modulo $p$: $-a \equiv p - a \mod p$, so we satisfy the inverse rule $a + (p - a) \equiv 0 \mod p$.

Multiplying by $-1$ has the same effect in a finite field as it does in $\mathbb R$: negation. Since $-1 \equiv p - 1$, then for any other field element $x \in \mathbb F_p$, we have:

$$ x (p-1) \equiv xp - x \equiv p - x \equiv -x $$

### Multiplicative Inverse

The multiplicative inverse requires more careful thought. Given any integer $a \in \mathbb{Z}\_p$ we need some other integer $a^{-1} \in \mathbb{Z}\_p$ such that $a \cdot a^{-1} \equiv 1 \mod p$. To solve this, we introduce [Fermat's little theorem](https://artofproblemsolving.com/wiki/index.php?title=Fermat%27s_Little_Theorem): _If $p$ is prime and $a$ is not a multiple of $p$, then_

$$ a^{p - 1} \equiv 1 \mod p $$

<details>
  <summary>Proof</summary>
  <div id="fermats-little-theorem"></div>

Here is my favorite proof of Fermat's little theorem. It requires no extra machinery but is a little more verbose.

Let $p$ be a prime number, and let $S$ be the set of integers from $1$ to $p - 1$:

$$
S = \\{1, 2, 3, ... p - 1\\}
$$

By definition, every $i \in S$ is distinct and less than $p$.

Pick an integer $a \in \mathbb{Z}$ which is not a multiple of $p$, and multiply each element of $S$ by $a$.

$$
a \cdot S = \\{ a, 2a, 3a, ... (p-1)a \\}
$$

Recall that sets are unordered, so two sets are equivalent if they contain the same elements.

I claim the set $a \cdot S$ is a _permutation_ of $S$ (same elements different order) which are equivalent when we reduce $a \cdot S$ modulo $p$.

$$ a \cdot S \equiv S \mod p $$

All elements of both sets are reduced modulo $p$, and both sets have $p - 1$ elements ($\|S\| = \|a \cdot S\| = p - 1$). Thus we can prove this claim by showing

1. $a \cdot S \pmod p$ does not contain zero, and
2. $a \cdot S \pmod p$ does not contain duplicate elements.

If (1) is true, then $a \cdot S \pmod p$ must contain only elements in the range $1$ to $p - 1$. Statement (2) proves both sets contain the same $p - 1$ elements $\\{1, 2, 3, ... p - 1\\}$.

To prove (1), we recall that $0 \notin S$, so if $a \cdot S \pmod p$ contains zero, it must be because $a \cdot S$ contains a multiple of $p$ which reduces to zero when divided by $p$. This is not possible because we assumed that $a$ is not a multiple of $p$, so for any positive $i < p$, the product $a \cdot i$ is also not a multiple of $p$. This follows from the prime factorizations of $a$ and $i$, neither of which can contain $p$.

To prove (2), we assume the opposite and find a contradiction. For $a \cdot S \pmod p$ to contain a duplicate non-zero element, then there must exist two distinct elements $i \neq j$ in $S$ such that

$$ ai \equiv aj \mod p $$

However, this admits a contradiction. We can factor $a$ out of the equation, since it is not a multiple of $p$. If $a$ were a multiple of $p$, it would be congruent to zero modulo $p$, and we'd just end up with $0 \cdot i \equiv 0 \cdot j \mod p$ which is always true. After canceling $a$ we get:

$$ i \equiv j \mod p $$

This contradicts our definition of $i \neq j$ and $i, j \in S$, which is impossible since $1 \le i, j < p$. Thus we know $ai \not \equiv aj \mod p$ for every distinct $i, j \in S$, and so we have proven statement (2).

Consequentially, we know

$$ a \cdot S \equiv S \mod p $$

Finally we move on to extracting Fermat's little theorem from this.

The cumulative product of all elements of $S$ must then be equal to the product of all elements in $a \cdot S \pmod p$. We know this because both sets contain the same numbers, and integer multiplication is commutative (order of operations is irrelevant).

$$
\begin{align}
\prod_{i \in a \cdot S} i & \equiv \prod_{i \in S} i \mod p \\\\
\prod_{i \in S} ai & \equiv \prod_{i \in S} i \mod p \\\\
a \cdot 2a \cdot 3a \cdot ... \cdot (p-1)a & \equiv 1 \cdot 2 \cdot 3 \cdot ... \cdot (p - 1)  \mod p \\\\
\end{align}
$$

Factor out $a$ from the left hand side:

$$
a^{p - 1} \cdot 1 \cdot 2 \cdot 3 \cdot ... \cdot (p-1) \equiv 1 \cdot 2 \cdot 3 \cdot ... \cdot (p - 1) \mod p
$$

Now cancel out each of the factors from $1, 2, 3, ... p - 1$ from $S$ (which we can do since none of them are multiples of $p$), and we end up with Fermat's little theorem:

$$ a^{p - 1} \equiv 1 \mod p $$

</details>

By factoring out an $a$, we find the multiplicative inverse we've been looking for:

$$
\begin{align}
a^{p - 2} \cdot a &\equiv 1 \mod p \\\\
a^{-1} \cdot a &\equiv 1 \mod p \\\\
\end{align}
$$

Thus, the multiplicative inverse of any $a \in \mathbb{Z}\_p$ is simply $a^{-1} \equiv a^{p - 2} \mod p$.

Since $p$ is typically quite large, there are [faster ways to find this number than by naive exponentiation](https://en.wikipedia.org/wiki/Finite_field_arithmetic#Multiplicative_inverse), but this gives an intuitive approach which can be proven with only elementary background in modular arithmetic.

We can use multiplicative inverses to define what _division_ means inside our finite field $\mathbb{F}\_p$. When we write $a / b = \frac{a}{b}$, we really mean $a \cdot b^{-1}$. However for convenience and intuition we typically write with division notation.

There is one trivial exception: zero has no multiplicative inverse, since $0 \cdot a = 0$ by definition. This corresponds to the fact that dividing by zero is undefined on the integers.

### Squares (Quadratic Residues)

Another common operation we can define inside $\mathbb{F}\_p$ is taking square roots. We define $\sqrt{a}$ to be the unique element $x$ such that $x^2 = a$. In more formal language, $a$ is the _quadratic residue_ of $x$ modulo $p$.

*For the remainder of the article, I will eschew the formal term "quadratic residue" in favor of the shorter and more intuitive term "square". Pedants may lament such a simplification, but this choice makes this article easier to write, and to read.*

To figure out how to compute $x = \sqrt{a}$, we need some foundations first.

Not every element in $\mathbb{Z}\_p$ is a perfect square. This is because for any positive integer $z \in \mathbb{Z}\_p$, its square $z^2$ is equivalent to the square of its _additive inverse_ $(-z)^2$ when reduced modulo $p$.

$$
\begin{align}
z^2 &\equiv (-z)^2 \mod p \\\\
    &\equiv (p - z)^2 \mod p \\\\
    &\equiv (p - z)(p - z) \mod p \\\\
    &\equiv p^2 - 2zp + z^2 \mod p \\\\
    &\equiv z^2 \mod p \\\\
\end{align}
$$

In more plain language, every equation $a \equiv x^2 \mod p$ _has two solutions_ in $x$: one is $z$ and the other is $p - z$. This is the maximum number of solutions possible, because of _Lagrange's Theorem of Number Theory:_ In any field - finite or otherwise - a polynomial of degree $d$ has _at most_ $d$ roots.

<details>
  <div id="lagrange-theorem"></div>
  <summary>Proof</summary>

Here follows a proof of Lagrange's theorem.

Let $f_d(x)$ denote any polynomial of degree $d$.

We know any linear polynomial $f_1(x) = ax + b$ has exactly one root which we will call $r_1$.

$$ a r_1 + b = 0$$
$$ a r_1 = -b $$
$$ r_1 = \frac{-b}{a} $$

For any $f_d(x)$ with degree $d > 1$, we can write the polynomial as

$$ f_d(x) = (x - r_d) \cdot f_{d-1}(x) $$

where $f_{d-1}(x)$ is some degree $d-1$ polynomial and $r_d$ is a root of $f_d(x)$. We show how to count the number of roots of $f_d(x)$.

For an input $a$ to be a root of $f_d(x)$, we need $f_d(a) = 0$. For this, we need $a = r_d$, or else $a$ is a root of $f_{d-1}(x)$. Recursively descending into $f_{d-1}(x) = (x - r_{d-1}) \cdot f_{d-2}(x)$, we repeat like this until we arrive at $f_1(x)$ whose only root is $r_1$. Thus for $a$ to be a root of $f_d(x)$, it must be in the set $\\{r_1, r_2, r_3, ... r_d\\}$ which clearly has at most $d$ unique members.

</details>

If $p$ is odd, then $p - 1$ is even, and we can find exactly $\frac{(p - 1)}{2}$ distinct unordered tuples $(z, p - z)$ of positive integers in $\mathbb{Z}\_p$ such that $z^2 \equiv (p - z)^2 \equiv a \mod p$. There is no $z = p - z$ possible since this would imply $2z = p$, but $p$ is odd, a contradiction.

Thus we have exactly $\frac{p - 1}{2}$ squares in $\mathbb{Z}\_p$.

<details>
<summary>Example in $\mathbb{Z}_7$</summary>

| $\quad z \quad$ | $\quad z^2 \quad$ | $z^2 \pmod 7$ |
|:-:|:-:|:-:|
|0|0|0|
|1|1|1|
|2|4|4|
|3|9|2|
|4|16|2|
|5|25|4|
|6|36|1|

Notice how every perfect square repeats twice in the table. This is true in general for other fields bigger than $\mathbb{Z}\_2$. The exception is the trivial square $0$, which only appears once in any such table.

Also note how only half of the nonzero elements of $\mathbb{Z}\_7$ appear in the third column.
</details>

We know $a^{\frac{p - 1}{2}} \equiv \pm 1 \mod p$ because of Fermat's little theorem:

$$
\begin{align}
a^{p - 1} &\equiv 1 \mod p \\\\
a^{\frac{p - 1}{2}} &\equiv \sqrt{1} \mod p \\\\
\end{align}
$$

It is clear that $\sqrt{1} = 1$ in any field, but as shown already the other square root of $1$ must be $p-1$, so

$$ a^{\frac{p - 1}{2}} \equiv \sqrt{1} \equiv \pm 1 \mod p $$

Turns out this quantity $a^{\frac{p - 1}{2}}$ computes a special value called the [Legendre Symbol](https://en.wikipedia.org/wiki/Legendre_symbol) of $a$ with respect to $p$. It lets us test for squareness in $\mathbb{Z}\_p$ according to [Euler's Criterion](https://en.wikipedia.org/wiki/Euler%27s_criterion):

$$
\begin{align}
a^{\frac{p - 1}{2}} \equiv 1 \mod p \quad & \longleftrightarrow \quad a \text{ is a square mod } p \\\\
a^{\frac{p - 1}{2}} \equiv -1 \mod p \quad & \longleftrightarrow \quad a \text{ is NOT a square mod } p \\\\
\end{align}
$$

<details>
  <summary>Proof</summary>
  <div id="eulers-criterion"></div>

For a non-zero element $a$ to be a square in $\mathbb{Z}\_p$, there must exist $z \in \mathbb{Z}\_p$ such that

$$
a \equiv z^2 \mod p
$$

Exponentiate both sides by $\frac{p-1}{2}$.

$$
\begin{align}
a^{\frac{p - 1}{2}} & \equiv \left( z^2 \right)^{\frac{p - 1}{2}} \mod p  \\\\
                    & \equiv z^{p - 1} \mod p  \\\\
\end{align}
$$


But call up our old pal Fermat again and we get:

$$
a^{\frac{p - 1}{2}} \equiv z^{p - 1} \equiv 1 \mod p
$$

Thus, if $a$ is a square, then $a^{\frac{p - 1}{2}} \equiv 1 \mod p$. However, what if $a$ is _not_ a square?

By Lagrange's Theorem ([proven earlier](#lagrange-theorem)), we know the polynomial $f(x) = x^{\frac{p - 1}{2}} - 1 \mod p$ has at most $\frac{p - 1}{2}$ roots, and these we can find explicitly by simply generating $\frac{p - 1}{2}$ squares $Q = \left\\{ 1^2, 2^2, 3^2, ... \left(\frac{p-1}{2}\right)^2 \right\\} \mod p$. Any other $x \in \mathbb{Z}\_p$, $x \not \in Q$ _cannot_ be a root of $f(x)$ and thus is not a square.

This proves $a^{\frac{p - 1}{2}} \not \equiv 1 \mod p$ for a non-square $a$.

Given that we know $\left(a^{\frac{p-1}{2}}\right)^2 = a^{p-1} = 1$, the only other possibility is $a^{\frac{p - 1}{2}} \equiv -1 \mod p$.

</details>

As for actually finding $\sqrt{a}$, [there are general algorithms for any prime modulus](https://en.wikipedia.org/wiki/Tonelli%E2%80%93Shanks_algorithm), but typically for cryptographic use cases, we opt for a simple assumption that $p \equiv 3 \mod 4$, then $p+1$ is divisible by $4$, which enables us to efficiently compute $\sqrt{a}$ as

$$ \sqrt{a} \equiv \pm a^{\frac{p+1}{4}} \mod p$$

<details>
  <summary>Proof</summary>

By squaring this value, we recover $a$.

$$ \left( \pm a^{\frac{p+1}{4}} \right)^2 \equiv a^{\frac{p+1}{2}} \equiv a \cdot a^{\frac{p-1}{2}} \mod p $$

Recall that if $a$ is a square, we have $a^{\frac{p-1}{2}} \equiv 1 \mod p$. Thus:

$$ a \cdot a^{\frac{p-1}{2}} \equiv a \mod p $$

</details>

<details>
  <summary>Sources</summary>
  <ul>
    <li><a href="https://en.wikipedia.org/wiki/Finite_field">Finite Fields - Wikipedia</a></li>
    <li><a href="https://en.wikipedia.org/wiki/Quadratic_residue">Quadratic Residues - Wikipedia</a></li>
    <li><a href="https://people.computing.clemson.edu/~westall/851/rs-code.pdf">Clemson University lecture notes</a></li>
    <li><a href="https://www.geeksforgeeks.org/engineering-mathematics/fermat-little-theorem/">Fermat's little theorem</a></li>
  </ul>
</details>

### Review

We learned how a prime-order finite field $\mathbb{F}\_p$ is typically constructed, by using the integers mod $p$.

$$ \mathbb{F}\_p = \mathbb{Z}\_p $$

We have efficient algorithms for common arithmetic operations in $\mathbb{F}\_p$:

- addition/subtraction
- multiplication/division
- exponentiation
- square roots (If we choose $p \equiv 3 \mod 4$)

Prime-order finite fields form the bedrock of almost all modern cryptography, besides just isogenies. But in the domain of isogenies, we need more flexibility.

## Extension Fields

As it turns out, we will need an _extension_ of our base field $\mathbb{F}\_p$ to properly define and compute isogenies for our later cryptosystems. The reasons for this are complex - Basically having an extension field makes security much easier to achieve and prove.

To understand extensions, let's first talk about fields more generally.

### Field Extensions and Closures

We say a polynomial is _defined over_ a field $F$ if every coefficient in that polynomial is part of $F$.

We say a field $F$ is _algebraically closed_ if every polynomial of degree-1 or higher defined over $F$ has at least one root in $F$.

For example, any quadratic polynomial $f(x) = ax^2 + bx + c$ defined over the complex numbers $\mathbb{C}$ always has two roots in $\mathbb{C}$ [as per the fundamental theorem of algebra](https://en.wikipedia.org/wiki/Fundamental_theorem_of_algebra). You can find them with the good old quadratic formula $x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$. The fundamental theorem applies generally to any polynomial, even those of higher degrees - though we don't have formulas to find all roots in general. As such, we say the field of complex numbers $\mathbb{C}$ is _algebraically closed:_ Every polynomial in $\mathbb{C}$ _has roots which are also in_ $\mathbb C$.

I should point out that any field $F$ which isn't _algebraically closed_ can be _algebraically extended_. This is because if there are polynomimals in $F$ which have no roots in $F$, then we can just _make up_ a new field which includes some defined roots for that polynomial. For example, in the field of rational numbers $\mathbb{Q}$, there is no root for the polynomial $f(x) = x^2 - 2$. No problem, we can just make up a new number and write it as $\sqrt{2}$ and add it to the field. We have _extended_ $\mathbb{Q}$ to support an _irrational_ number and we write the resulting _field extension_ as $\mathbb{Q}(\sqrt{2})$ (think of $\mathbb{Q}$ being _adjoined with_ $\sqrt{2}$). In $\mathbb{Q}(\sqrt{2})$, field elements look like $a + b \sqrt{2}$, where $a, b \in \mathbb{Q}$.

But $\mathbb{Q}(\sqrt 2)$ is not _algebraically closed_ because I can still construct polynomials which have no roots in $\mathbb{Q}(\sqrt 2)$. Examples include $f(x) = x^2 + 1$ (for which we need to define $\sqrt{-1}$) or $g(x) = x^2 - 3$ (for which we need $\sqrt 3$).

If a field $F$ is _not_ algebraically closed, then there exists some _extension_ field $\overline{F}$ which _is_ algebraically closed. We write $\overline F$ to denote this field, called the _algebraic closure_ of $F$.

### Finite Field Extensions

These same properties apply to finite fields, which we can also extend in similar ways.

Say we pick a prime $p$ and construct our base field $\mathbb F_p = \mathbb Z_p$ using the integers mod $p$, as in the previous section. A field element $r \in \mathbb{F}\_p$ is just an integer $r \in \mathbb Z_p$. But there are some polynomials in $\mathbb F_p$ which have no roots, such as $f(x) = x^2 + 1$ in $\mathbb Z_{19}$. This follows from the facts proved in the previous section, namely that in $\mathbb Z_p$ for odd $p$, there always exist $\frac{p - 1}{2}$ squares and $\frac{p - 1}{2}$ non-squares. For every _non-square_ $r \in \mathbb Z_p$, we can define a polynomial $f(x) = x^2 - r$ which has no roots in $\mathbb Z_p$.

To extend $\mathbb F_p$, we pick a non-square $r \in \mathbb Z_p$, and define $i$ such that $i^2 = r$. We then construct a _quadratic extension field_ $\mathbb F_{p^2} = \mathbb Z_p(i)$, whose elements are represented as $\alpha + \beta i$ with $\alpha, \beta \in \mathbb F_p$. You might think of an element $x \in \mathbb F_{p^2}$ being stored as a tuple $x = (\alpha, \beta)$.

We can find roots in $\mathbb F_{p^2}$ for any degree 2 polynomial $f(x) = ax^2 + bx + c$ using the quadratic formula $x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$ which works just as well in a finite field as it does in the real numbers. Whatever $b^2 - 4ac$ evaluates to, we can always represent $\sqrt{b^2 - 4ac}$ in $\mathbb F_{p^2}$ by using $i$ as a _basis._

<details>
  <summary>Proof</summary>

Here follows a three-step proof that we can always represent the square root of a non-square element $s \in \mathbb Z_p(i)$ using some imaginary basis $i \not \in \mathbb Z_p$.

Let $r, s \in \mathbb Z_p$ be non-square. Let $i^2 = r$ be an imaginary square root of $r$.

1. Notice that

$$
\begin{align}
\sqrt{s} &= \sqrt{s \cdot r \cdot r^{-1}} \\\\
         &= \sqrt{r} \cdot \sqrt{s \cdot r^{-1}} \\\\
         &= i \sqrt{s \cdot r^{-1}} \\\\
\end{align}
$$

Thus if $s \cdot r^{-1}$ is a square, we can compute $\sqrt{s \cdot r^{-1}} \in \mathbb Z_p$, and represent $\sqrt{s} = i \sqrt{s \cdot r^{-1}}$.

2. The inverse of a non-square is _also_ a non-square, because the inverse of any element $r \in \mathbb Z_p$ always has the same Legendre symbol.

$$
\begin{align}
\left( r^{-1} \right)^{\frac{p-1}{2}} &\equiv \left( r^{\frac{p-1}{2}} \right)^{-1} \mod p \\\\
                                  &\equiv \left( 1 \right)^{-1} \equiv 1 \mod p \quad \text{if $r$ is a square} \\\\
                                  &\equiv \left( -1 \right)^{-1} \equiv -1 \mod p \quad \text{if $r$ is a non-square} \\\\
\end{align}
$$

Then by [earlier proofs in the previous section](#eulers-criterion), if $r$ is a non-square, then $r^{-1}$ is also.

3. The Legendre symbol of a product $rs \in \mathbb F_p$ is the product of the factors' Legendre symbols. This follows neatly from the distributivity of exponentiation over multiplication in the field.

$$ \left( rs \right)^{\frac{p-1}{2}} \equiv r^{\frac{p-1}{2}} \cdot s^{\frac{p-1}{2}} \mod p $$

In particular, the product of two non-squares $rs \pmod p$ always has a Legendre symbol of $1$, because the Legendre symbols of $r$ and $s$ are always $r^{\frac{p - 1}{2}} \equiv s^{\frac{p-1}{2}} \equiv -1 \mod p$. Therefore:

$$
\begin{align}
\left( rs \right)^{\frac{p-1}{2}} &\equiv r^{\frac{p-1}{2}} \cdot s^{\frac{p-1}{2}} \mod p \\\\
                              &\equiv (-1)(-1) \mod p \\\\
                              &\equiv 1 \mod p \\\\
\end{align}
$$

Therefore, the product $rs \pmod p$ is always a square.

This proves $\sqrt{s \cdot r^{-1}}$ is defined in $\mathbb Z_p$, and we can represent $\sqrt{s}$ as $i \sqrt{s \cdot r^{-1}}$.

</details>


<details>
  <summary>Example</summary>

In this example, we find the roots of a quadratic (degree-2) polynomial over the extension field $\mathbb F_{p^2}$. These roots do not exist in $\mathbb F_p$.

- $p = 19$
- $r = -1 \equiv p - 1$
- $f(x) = 17x^2 + 3x + 10$

First we plug into the quadratic formula $a = 17$, $b = 3$, $c = 10$:

$$ x \equiv \frac{-b \pm \sqrt{b^2 - 4ac}}{2a} \mod p $$
$$ x \equiv \frac{-3 \pm \sqrt{3^2 - 4 \cdot 17 \cdot 10}}{2 \cdot 17} \mod p $$
$$ x \equiv \frac{16 \pm \sqrt{13}}{15} \mod p $$

$13$ is _not_ a square in $\mathbb Z_p$. But we can represent it using $i$ as a basis:

$$
\begin{align}
\sqrt{13} &\equiv i \sqrt{13 \cdot r^{-1}} \mod p \\\\
          &\equiv i \sqrt{13 \cdot (-1)^{-1}} \mod p \\\\
          &\equiv i \sqrt{13 \cdot (-1)} \mod p \\\\
          &\equiv i \sqrt{p-13} \mod p \\\\
          &\equiv i \sqrt{6} \mod p \\\\
          &\equiv 5i \mod p \\\\
\end{align}
$$

To verify, simply check $(5i)^2 = 25 i^2 = -25 \equiv 13 \mod p $

Substituting this, we get the roots of $f(x)$:

$$ x \equiv \frac{16 \pm 5i}{15} \mod p $$
$$ x \equiv \frac{16}{15} \pm \frac{5i}{15} \mod p $$
$$ x \equiv 15 \pm 13i \mod p $$

Thus we get the roots $x = 15 + 13i$ or $x = 15 - 13i \equiv 15 + 6i \mod p$.

$$
\begin{align}
f(15 + 13i) &\equiv 17(15 + 13i)^2 + 3(15+13i) + 10 \mod p \\\\
            &\equiv 17(18 + 10i) + 3(15+13i) + 10 \mod p \\\\
            &\equiv (2 + 18i) + (7+i) + 10 \mod p \\\\
            &\equiv 0 \mod p \\\\
\end{align}
$$
$$
\begin{align}
f(15 + 6i) &\equiv 17(15 + 6i)^2 + 3(15+6i) + 10 \mod p \\\\
           &\equiv 17(18 + 9i) + 3(15+6i) + 10 \mod p \\\\
           &\equiv (2 + i) + (7+18i) + 10 \mod p \\\\
           &\equiv 0 \mod p \\\\
\end{align}
$$

</details>

### Defining i

To make the field multiplication and division simpler, it would be convenient if $i$ could always be defined as $i^2 \equiv -1 \mod p$. Then $(\alpha + \beta i)(\alpha' + \beta' i)$ simplifies to

$$ \alpha \alpha' + (\alpha \beta' + \alpha' \beta) i + \beta \beta' i^2 $$
$$ \alpha \alpha' + (\alpha \beta' + \alpha' \beta) i - \beta \beta' $$

...saving us one field multiplication.

For $i := \sqrt{-1} \mod p$ to be useful for building an extension field, we need $i \not \in \mathbb Z_p$, so we need for $-1$ to be a _non-square_ modulo $p$. Fortunately, this always happens if $p \equiv 3 \mod 4$.

<details>
  <summary>Proof</summary>

Recall $(-1)^{\frac{p-1}{2}} \equiv -1 \mod p$ if and only if $-1$ is a non-square.

If $p \equiv 3 \mod 4$, then $\frac{p - 1}{2} \equiv \frac{3 - 1}{2} \equiv 1 \mod 4$ is always an odd number.

Because $(-1)^n = (-1)^{(n \mod 2)}$, this implies $(-1)^{\frac{p-1}{2}} = (-1)^1 = -1$, and so $-1$ is always a non-square.

</details>

This gives us _even more reason_ to pick $p \equiv 3 \mod 4$, besides the fact shown earlier that offers a convenient square root formula in $\mathbb Z_p$.

### Arithmetic

Arithmetic on $\mathbb F_{p^2}$ is mostly straightforward. Addition subtraction and multiplication all work like the complex numbers.

Let $(\alpha + \beta i) \in \mathbb F_{p^2}$ and $(\alpha' + \beta' i) \in \mathbb F_{p^2}$.

- Addition: $(\alpha + \beta i) + (\alpha + \beta i) = (\alpha + \alpha') + (\beta + \beta')i$
- Subtraction: $(\alpha + \beta i) - (\alpha + \beta i) = (\alpha - \alpha') + (\beta - \beta')i$
- Multiplication: $(\alpha + \beta i)(\alpha' + \beta' i) = (\alpha \alpha' - \beta \beta) + (\alpha \beta' + \alpha' \beta) i$ (assuming $i^2 = -1$)

Multiplicative inversion again requires some work to define correctly, but thankfully we can use our definition of $i^2 = -1$ to inherit the basic rules of inversion for complex numbers. We find:

$$ (\alpha + \beta i)^{-1} = \frac{\alpha}{\alpha^2 + \beta^2} - i \left( \frac{\beta}{\alpha^2 + \beta^2} \right) $$

<details>
  <summary>Proof</summary>

We will find a formula for $\frac{1}{\alpha + \beta i}$ using the _complex conjugate_ $\alpha - \beta i$.

$$
\begin{align}
\frac{1}{\alpha + \beta i} &= \frac{\alpha - \beta i }{(\alpha + \beta i)(\alpha - \beta i)} \\\\
                           &= \frac{\alpha - \beta i }{\alpha^2 + \alpha \beta i - \alpha \beta i - \beta^2 i^2} \\\\
                           &= \frac{\alpha - \beta i }{\alpha^2 - \beta^2 i^2} \\\\
                           &= \frac{\alpha - \beta i }{\alpha^2 + \beta^2} \\\\
                           &= \frac{\alpha}{\alpha^2 + \beta^2} - i \left( \frac{\beta}{\alpha^2 + \beta^2} \right) \\\\
\end{align}
$$

[More info on the inverses of complex numbers](https://www.123calculus.com/en/complex-number-inverse-page-1-45-160.html).

</details>

<sub>During an actual computation, for efficiency we would compute $n = (\alpha^2 + \beta^2)^{-1} \in \mathbb F_p$ first, and then find $(\alpha + \beta i)^{-1} = \alpha n + (\beta n) i \in \mathbb F_{p^2}$.</sub>

Finding square roots is more difficult, so let's put that off for now and learn a bit more about extension fields in general.

### Higher Degree Extensions

The complex-number-esque technique works specifically for extending $\mathbb F_p$ to $\mathbb F_{p^2}$, but other techniques are needed to extend further. In general, we can produce any finite field of size $\mathbb F_{p^k}$ by representing elements of the field as polynomials modulo some irreducible (i.e. _prime_) polynomial of degree $k$, with coefficients in $\mathbb F_p$. More details [here](https://en.wikipedia.org/wiki/Finite_field#Non-prime_fields) and [here](https://kconrad.math.uconn.edu/blurbs/galoistheory/finitefields.pdf) and [here](https://building-babylon.net/2024/05/19/construction-of-the-finite-fields/).

There is the notion of the _degree_ of an extension field relative to some other field. For finite fields, a base field $\mathbb F_q$ (where $q = p^k$ for a prime $p$) can be _extended_ to any degree-$n$ extension $\mathbb F_{q^n}$. The degree of an extension can be thought of as the _dimensionality_ of the extension over its base field. Imagine the extension field as a vector space, in which the base field is embedded, and elements of the extension field are expressed with vectors of elements in the base field. The maximum dimensionality of those vectors is the _degree_ of the extension field.

The degree of a field extension $K$ over its base field $F$ is often written as:

$$ [K : F] $$

For instance, the finite field $\mathbb F_{p^2}$ which we just constructed is an extension of $\mathbb F_p$ with _degree 2,_ because $\mathbb F_{p^2}$ is a kind of 2-dimensional vector space that embeds $\mathbb F_p$ inside it.

$$ [\mathbb F_{p^2} : \mathbb F_p] = 2 $$

We _could_ also construct an even bigger extension field $\mathbb F_{p^6}$ of size $\left(p^2\right)^3 = p^6$, using $\mathbb F_{p^2}$ as a base field. The degree of this extension would be $[\mathbb F_{p^6} : \mathbb F_{p^2}] = 3$, because $p^6 = \left(p^2 \right)^3$.

However, for our purposes we don't need to worry about actually _constructing_ higher-degree extensions of $\mathbb F_p$ beyond $\mathbb F_{p^2}$. Our construction for $\mathbb F_{p^2}$ is very efficient, and we cover all the bases we need for later higher-level mathematics.

<sub>Interestingly, the complex-number approach to building $\mathbb F_{p^2}$ is computationally identical to the field of polynomials with coefficients in $\mathbb F_p$ modulo the irreducible polynomial $x^2 + 1$, written as $\mathbb{F}\_p[x] / (x^2 + 1)$.</sub>

<details>
  <summary>Demonstration</summary>

Consider two field elements $(\alpha + \beta i) \in \mathbb F_{p^2}$ and $(\alpha' + \beta' i) \in \mathbb F_{p^2}$.

Replace $i$ with $x$ and you have polynomial expressions of degree 1.

Addition and subtraction are obviously the same for $\mathbb F_{p^2}$ as for degree-1 polynomials: Just add or subtract like coefficients.

For multiplication, we will show how the expansion of a product in $\mathbb F_{p^2}$ is equivalent to $\mathbb F_p[x] / (x^2 + 1)$.

$$
\begin{align}
&(\alpha + \beta i)(\alpha' + \beta' i) \quad & \quad (\alpha + \beta x)(\alpha' + \beta' x) \\\\
&\alpha \alpha' + (\alpha \beta' + \alpha' \beta)i + \beta \beta' i^2 \quad & \quad \alpha \alpha' + (\alpha \beta' + \alpha' \beta)x + \beta \beta' x^2 \\\\
\end{align}
$$

Using our definition of $i^2 = -1$ in $\mathbb F_{p^2}$, we can simplify the left expression to $\alpha \alpha' + (\alpha \beta' + \alpha' \beta) i - \beta \beta'$.

Notice for the right-hand expression, we do something computationally equivalent when we find the remainder polynomial $r(x)$ after dividing by $x^2 + 1$.

$$ \alpha \alpha' + (\alpha \beta' + \alpha' \beta)x + \beta \beta' x^2  = p(x) (x^2 + 1) + r(x) $$
$$ p(x) = \beta \beta' \quad \quad r(x) = (\alpha \beta' + \alpha' \beta)x + \alpha \alpha' - \beta \beta' $$

You can find $r(x)$ using [polynomial long division](https://engineering.purdue.edu/kak/compsec/NewLectures/Lecture6.pdf) or other methods, but computationally it is much faster to substitute $x^2 = -1$, and it has the same result.

To verify:

$$
\begin{align}
p(x)(x^2 + 1) + r(x) &= (\beta \beta')(x^2 + 1) + (\alpha \beta' + \alpha' \beta)x + \alpha \alpha' - \beta \beta' \\\\
&= \beta \beta' x^2 + \beta \beta' + (\alpha \beta' + \alpha' \beta)x + \alpha \alpha' - \beta \beta' \\\\
&= \beta \beta' x^2 + (\alpha \beta' + \alpha' \beta)x + \alpha \alpha' \\\\
\end{align}
$$

...which is the same expression we started with.

I'll leave it as an exercise to the reader to prove that multiplicative inversion and square roots are also computationally equivalent.

</details>

That said, $\mathbb F_{p^2}$ is _not_ algebraically closed. In fact, it's impossible for _any_ finite field to be algebraically closed.

<details>
  <summary>Proof</summary>

Given a finite field $\mathbb F_{p^k}$, we can always construct a non-constant polynomial with no roots in $\mathbb F_{p^k}$.

$$
f(x) = \prod_{z \in \mathbb F_{p^k}} (x - z) + 1
$$

This polynomial clearly has no roots in $\mathbb F_{p^k}$ because it evaluates to $1$ for any $z \in \mathbb F_{p^k}$.

</details>

We could keep extending $\mathbb F_{p^2}$ to get $\mathbb F_{p^4}$, or $\mathbb F_{p^6}$, or even $\mathbb F_{p^{12}}$ which contains all three. However, we'll never reach an algebraically closed finite field, and we don't really need to. Isogeny and elliptic curve math literature often discusses the algebraic closure $\overline{\mathbb F}\_p$, and for some time this confused me, because as shown above, it is impossible to have an algebraically closed finite field. Turns out, we never actually need to construct $\overline{\mathbb F}\_p$ in cryptographic software, and it's only used as a tool for proofs and analysis. More on that later.

### Characteristic

The _characteristic_ of a field $F$, sometimes written $\mathrm{char}(F)$, but usually just written as $p$, is defined as _the smallest number of times you can add $1$ (the multiplicative identity) to itself before arriving back at $0$ (the additive identity)._

$$ p \cdot 1 = \overbrace{1 + 1 + ... + 1}^{p \text{ times}} = 0 $$
$$ \mathrm{char}(F) = p $$

By consequence, this means multiplication by $p$ must be an _annihilator_ for any element $n \in F$.

$$
\begin{align}
n \cdot p &= n \cdot p \cdot 1 \\\\
          &= n \cdot 0 \\\\
          &= 0 \\\\
\end{align}
$$

In the base field $\mathbb F_p = \mathbb Z_p$, the notion of characteristic has been unimportant, perhaps even redundant, which is why I failed to mention it until now. In modular arithmetic, multiplying any number by a modulus $p$ will naturally reduce to zero. So the characteristic is just the modulus $p$, which is also always the size of the finite field built using $\mathbb Z_p$.

But in the extension field $\mathbb F_{p^2}$ (and in any higher degree extensions) it now becomes important to distinguish between the field's _order_ (size), and its _characteristic._

$$ \overbrace{|\mathbb F_{p^2}| = p^2}^{\text{order}} \quad \quad \overbrace{\mathrm{char}(\mathbb F_{p^2}) = p}^{\text{characteristic}} $$

### General Properties

In general, for any field $\mathbb F_q$ of _order_ $|F_q| = q = p^k$ where the _characteristic_ $p$ is prime, we have the following rules:

#### Order Exponent Identity

In $\mathbb F_q$, exponentiation by $q$ is an identity map.

Let $x \in \mathbb F_q$.

$$ x^q = x $$

<details>
  <summary>Proof</summary>

Let $\mathbb F_q$ be a finite field of order $q$. Since $\mathbb F_q$ is finite, any nonzero element $x \in \mathbb F_q$ must be a generator of some cyclic multiplicative subgroup $H = \\{1, x, x^2, ... x^{n-1}\\}$ of order $n$ with all $x^i$ distinct. By cyclic, I mean that $x^n = 1$: After multiplying $x$ by itself enough times, you _must_ eventually get back to $1$.

There are $q - 1$ nonzero elements in $\mathbb F_q$. By [Lagrange's theorem for Group Theory](https://en.wikipedia.org/wiki/Lagrange%27s_theorem_(group_theory)), the order $n$ of a multiplicative subgroup _must evenly divide the number of nonzero elements $q - 1$ in $\mathbb F_q$._

$$ q - 1 \equiv 0 \mod n $$

<details>
  <summary>Proof</summary>

Here is a proof of Lagrange's Theorem, not generally, but phrased in the context of finite fields.

Let $H$ be a multiplicative subgroup of order $n$ in a finite field $\mathbb F_q$ with generator $x$.

$$ H = \\{1, x, x^2, ... x^{n-1}\\} $$

First notice that $H$ cannot contain zero because zero does not have a multiplicative inverse. Thus $n \le q - 1$ because $\mathbb F_q$ has $q - 1$ nonzero elements.

If $n = q - 1$, then $n$ divides $q - 1$ and we're done. Otherwise we assume $n < q - 1$.

Let $a_1 \in \mathbb F_q \setminus H$ be a nonzero finite field element which is *not* in $H$. Multiply each element of $H$ by $a_1$ to produce a new set (not a group).

$$ a_1 H = \\{ a_1,\ a_1 x,\ a_1 x^2,\ ...\ a_1\ x^{n-1} \\} $$

This new set $a_1 H$ and the original subgroup $H$ are disjoint - They share no common elements.

$$ a_1 H \cap H = \\{\ \\} $$

If a common element $a_1 x^i \in \left( a_1 H \cap H \right)$ did exist, then we would have for some $i, j \in \mathbb Z_n$:

$$
\begin{align}
a_1 x^i &= x^j \\\\
a_1 &= x^j x^{-i} \\\\
    &= x^{(j - i \mod n)} \\\\
\end{align}
$$

$a_1 = x^{(j - i \mod n)}$ must be part of $H$, which we assumed not to be the case when we picked $a_1$: a contradiction. Thus we are left to conclude that if $a_1 \not \in H$, then $a_1 x^i \not \in H$.

If $|a_1 H| + |H| = 2n = q - 1$, then we are done and $n$ divides $q-1$.

Otherwise we continue by finding another set $a_2 H$, where $a_2 \not \in H$ and also $a_2 \not \in a_1 H$. This new set $a_2 H$ is likewise disjoint from the prior two sets $H$ and $a_1 H$ by a similar argument.

If an element $a_2 x^i = x^j$ existed in $H$, we get a contradiction where

$$ a_2 = x^{(j - i \mod n)} \in H $$

If an element $a_2 x^i = a_1 x^j$ existed in $a_1 H$, we get a contradiction where

$$ a_2 = a_1 x^{(j - i \mod n)} \in a_1 H $$

We can continue this procedure with $a_3$, $a_4$, and so on. Each time we introduce a new set of $n$ previously-unseen elements to our collection. Eventually we will run out of unused elements in $\mathbb F_q$, with the final set $a_{\frac{q-1}{n}} H$.

Now we can prove that $n$ divides $q - 1$ by contradiction.

Suppose $n$ does not divide $q - 1$. Then after constructing $m := \lfloor \frac{q-1}{n} \rfloor$ sets $\\{H, a_1 H, a_2 H, ... a_m H\\}$, we would be left with some nonzero element $e \in \mathbb F_q$ which is in none of these sets. But, by our earlier argument, we could then produce the set $eH = \\{e, ex, ex^2, ... e x^{n-1}\\}$ containing $n$ previously unseen elements which must clearly be members of $\mathbb F_q$. We would then have a total of $m + 1$ disjoint sets of $n$ distinct elements, all in $\mathbb F_q$. But $n(m + 1) > q - 1$ exceeds the number of nonzero elements in $\mathbb F_q$, which is impossible.

We can only conclude $n$ divides $q - 1$, and that our set-construction procedure _partitions_ the nonzero elements of $\mathbb F_q$ into exactly $\frac{q-1}{n}$ sets of size $n$.


Sources

- https://en.wikipedia.org/wiki/Lagrange%27s_theorem_(group_theory)
- https://crypto.stanford.edu/pbc/notes/group/lagrange.html
- https://advancedmath.org/Math/GroupTheory/LagrangesTheorem.pdf

</details>

Since $q - 1$ is always multiple of $n$, and since $x^n = 1$, we arrive at a generalized form of Fermat's Little Theorem for any finite field.

$$ x^{q-1} = 1 $$

This holds for any choice of $x$ and any group order $n$, since $n$ always divides $q - 1$, and $x^{mn} = x^n = 1$ for any integer $m$.

Which leads us to conclude:

$$ x^q = x $$

</details>

#### Freshman's Dream

Let $x, y \in \mathbb F_q$ and $p = \mathrm{char}(\mathbb F_q)$.

$$ (x + y)^p = x^p + y^p $$

<details>
  <summary>Proof</summary>

Here follows a proof that the Freshman's Dream identity holds in any field $\mathbb F_q$ with characteristic $p$.

The expansion of $(x+y)^p$ will have $p+1$ terms.

$$
\begin{align}
(x + y)^p &= \overbrace{(x + y)(x + y)...(x + y)}^{p \text{ copies }} \\\\
          &= x^p + a_1\ x^{p-1} y + a_2\ x^{p-2} y^2 + ... + a_{p-1}\ x y^{p-1} + y^p \\\\
          &= x^p + y^p + \sum_{c=1}^{p-1} a_c \ x^{p-c} y^c
\end{align}
$$

Because $xp = 0$ for any $x \in \mathbb F_q$, it suffices to prove that every coefficient $\\{a_1, a_2, ... a_{p-1}\\}$ has a factor of $p$, and thus are all zero in $\mathbb F_q$.

To this end we defer to the [Binomial theorem](https://en.wikipedia.org/wiki/Binomial_theorem), which states:

> The $n$-th power of a binomial $(x+y)^n$ expands to:
>
> $$ (x+y)^n = \sum_{c = 0}^n \left( \frac{n!}{c!(n - c)!} \cdot x^{n-c} y^c \right) $$
>
> ...where the $n!$ operator denotes the factorial $n! = n(n-1)(n-2)...(2)(1)$

<details>
  <summary>Proof</summary>

Here I provide a combinatorial proof of the binomial theorem for the curious.

Observe that when expanding $(x + y)^n = \overbrace{(x + y)(x + y)...(x + y)}^{n \text{ copies }}$, we have $n$ binary choices to make: Do we multiply $x$, or do we multiply $y$? In total we have $2^n$ different possible _combinations._

For each choice, if we select $c$ copies of $x$, we thereby select $n - c$ copies of $y$. We call each set of choices a _combination_ and the resulting expanded product of that combination is $x^c y^{n - c}$.

Notice the number of possible combinations which result in multiplying $c$ copies of $x$ is exactly the coefficient of the term $x^c y^{n - c}$ in the binomial expansion.

With this in mind, we'd like to find how to compute these coefficients in the expansion. Using our combinatorial analogy, this problem directly corresponds to the following question: _How many ways are there to choose $c$ elements from a set $S$ which has $n$ members?_

Take an iterative approach. We start with $n$ members in $S$ to pick from. After the first choice, we are left with $n - 1$ options. This repeats until we have picked $c$ members with $n-c$ members left unselected. In total we have $n(n-1)(n-2)...(n - c + 1)$ different ways of picking these $c$ elements.

However, among these different selections, it is possible we picked the same elements in a different order. For our purposes (binomial expansion), we don't care about the ordering. To discount ordering, we must ask: _How many ways can we order a set of $c$ elements?_

We pick the first element from $c$ options, then the second from $c - 1$ options, and so on, until we have picked $c-1$ elements and are left with the last remaining element in our shuffling. This corresponds to $c(c-1)(c-2)...(2)(1) = c!$ distinct orderings.

To review, we have $n(n-1)(n-2)...(n - c + 1)$ different ordered ways of selecting $c$ elements from a set of $n$ members, and we have $c!$ distinct ordering-classes among those selections.

To count the number of distinct sets (unordered) of $c$ elements from $S$ we divide the number of ordered selections by the number of possible orderings.

$$ \frac{n(n-1)(n-2)...(n - c + 1)}{c!} $$

Multiply the numerator and denominator by $(n - c)!$ to recover the binomial coefficient:

$$ {n \choose c} = \frac{n!}{c!(n-c)!} $$

Therefore, for the $c$-th term of the binomial expansion, its coefficient $a_c$ is $\frac{n!}{c!(n-c)!}$.

</details>

From this, we can see that the coefficients in our binomial expansion correspond to

$$ a_c = \frac{p!}{c!(p - c)!} $$

In the cases where $c = 0$ or $c = p$, then we have the denominator $c!(p - c)! = p!$, and so $a_c = 1$. This corresponds to the fact that the first and last term of the expansion are exactly $x^p$ and $y^p$ respectively.

For all other cases, we can partially reduce the fraction to see its factorization.

$$
\begin{align}
a_c &= \frac{p!}{c!(p - c)!} \\\\
\\\\
    &= \frac{p(p-1)(p-2)...(2)(1)}{c! \cdot (p - c) (p - c - 1) ... (2) (1)} \\\\
\\\\
    &= \frac{p(p-1)(p-2)...(p - c + 2)(p - c + 1)}{c!} \\\\
\end{align}
$$

At this point we see $p$ cannot be reduced out of the fraction. Therefore all $a_c$ must have a factor of $p$ when $0 < c < p$, and so $a_c = 0$ in $\mathbb F_q$. Thus:

$$
\begin{align}
(x + y)^p &= x^p + y^p + \xcancel{\sum_{c=1}^{p-1} a_c \ x^{p-c} y^c} \\\\
          &= x^p + y^p  \\\\
\end{align}
$$

This completes our proof.

</details>

#### Frobenius Endomorphism

The Freshman's Dream property of $\mathbb F_q$ leads us to inquire closer at the properties of a special function which we call the _Frobenius Endomorphism_ $\pi(x)$.

$$ \pi(x) = x^p $$

We denote the $n$-th iteration of $\pi(x)$ by $\pi^n(x)$.

$$ \pi^n(x) = \overbrace{\pi(\pi(...\pi}^{n \text{ times}}(x))) = x^{p^n} $$

If $p = q = |\mathbb F_q|$, then $\pi$ is almost completely uninteresting because it is the identity function. See the _order exponent identity_ proven above, where $x^p = x^q = x$.

However, for an extension field where $q = p^k$ for $k > 1$, then Frobenius is actually very interesting.

From the properties of exponentiation by $p$, we end up with the following properties of $\pi(x)$:

1. $\pi$ is a field [homomorphism](https://en.wikipedia.org/wiki/Ring_homomorphism) on any elements $x, y \in \mathbb F_q$:

$$
\begin{align}
\left( \pi(x) \right)^n &= (x^p)^n \\\\
&= (x^n)^p \\\\
&= \pi(x^n) \\\\
\end{align}
$$
$$
\begin{align}
\pi(x) \cdot \pi(y) &= x^p \cdot y^p \\\\
&= (xy)^p \\\\
&= \pi(xy) \\\\
\end{align}
$$
$$
\begin{align}
\pi(x) + \pi(y) &= x^p + y^p \\\\
&= (x + y)^p \\\\
&= \pi(x+y) \\\\
\end{align}
$$
$$ \pi(1) = 1^p = 1 $$
$$ \pi(0) = 0^p = 0 $$

2. For any element $x \in \mathbb F_q$ where $q = p^k$, $\pi$ generates a cyclic group with order $k$, assuming $\mathbb F_q$ is the _minimal subfield<sup>\*</sup>_ of $x$:

$$ \pi(\pi(x)) = \left( x^p \right)^p = x^{p^2} $$
$$ \pi^n(x) = x^{p^n} $$
$$ \pi^k(x) = x^{p^k} = x^q = x $$

<sub>\* By "minimal subfield", we mean $x$ must not be in any subfield $\mathbb F_{p^j} \subset \mathbb F_q$. If so, this property applies to the subfield $\mathbb F_{p^j}$ instead.</sub>

Note this property implies $\pi$ fixes all elements $v \in \mathbb F_p$ (Recall $\mathbb F_p$ is the base subfield of $\mathbb F_q$):

$$ \pi(v) = v^p = v $$


### Squares (Quadratic Residues)

We now have everything we need to compute square roots in $\mathbb F_{p^2}$.

How do we tell if an element $u = \alpha + \beta i \in \mathbb F_{p^2}$ is a square? We can use a variant of the same Euler's Criterion technique shown before for $\mathbb F_p$, by raising $u$ to the power of $\frac{p^2 - 1}{2}$.

$$
u^{\frac{p^2-1}{2}} = (\alpha + \beta i)^{\frac{p^2 - 1}{2}} =
\begin{cases}
\ 1 &\text{ if $u$ is a square in $\mathbb F_{p^2}$ } \\\\
 -1 &\text{ otherwise }
\end{cases}
$$

This computes a sort of generalized Legendre symbol for any element of $\mathbb F_{p^2}$. This value is sometimes called the _character_ of an element, and in some texts like Silverman's Arithmetic of Elliptic Curves, is written as a function $\chi(u) = \pm 1$.

<details>
  <summary>Proof</summary>

Let $\mathbb F_q$ be a finite field with $q$ elements.

Here's a proof that $u^{\frac{q-1}{2}} = 1$ for any $u \in \mathbb F_q$ if and only if $u$ is a square in $\mathbb F_q$. We'll follow an almost-identical argument as we used to [prove Euler's Criterion](#eulers-criterion) for the base field.

First, recall the [order exponent identity](#Order-Exponent-Identity) in any finite field $\mathbb F_q$ (AKA generalized Fermat's little theorem):

$$ x^q = x $$
$$ x^{q - 1} = 1 $$

We know if $u$ is a square in $\mathbb F_q$, there must exist $z \in \mathbb F_q$ such that

$$ u = z^2 $$

We exponentiate both sides by $\frac{q - 1}{2}$, and we are left with

$$
\begin{align}
u^{\frac{q - 1}{2}} &= \left( z^2 \right)^{\frac{q-1}{2}} \\\\
&= z^{q - 1} \\\\
&= 1 \\\\
\end{align}
$$

Thus, if $u$ is a square, then $u^{\frac{p - 1}{2}} = 1$. However, what if $u$ is _not_ a square?

By Lagrange's Theorem ([proven earlier](#lagrange-theorem)), we know the polynomial $f(x) = x^{\frac{q - 1}{2}} - 1$ has at most $\frac{q - 1}{2}$ roots, and these we can find explicitly by simply generating $\frac{q - 1}{2}$ squares $Q = \left\\{ 1^2, 2^2, 3^2, ... \left(\frac{q-1}{2}\right)^2 \right\\}$. Any other $x \in \mathbb F_q$, $x \not \in Q$ _cannot_ be a root of $f(x)$ and thus is not a square.

This proves $u^{\frac{q - 1}{2}} \neq 1$ when $u$ is non-square.

Given that we know $\left(u^{\frac{q-1}{2}}\right)^2 = u^{q-1} = 1$, the only other possibility is $u^{\frac{q - 1}{2}} = -1$.

</details>

Given a square $\alpha + \beta i \in \mathbb F_{p^2}$ we can find a square root $x + yi$ which is also in $\mathbb F_{p^2}$.

We can reuse the formulas for complex numbers:

$$ (x + yi)^2 = \alpha + \beta i $$
$$ \Downarrow $$
$$ x = \pm \sqrt{\frac{1}{2} \left( \alpha \pm \sqrt{\alpha^2 + \beta^2} \right)} \quad \quad y = \frac{\beta}{2x} $$

From this, we derive more efficient formulas for $x$ and $y$ which are specific to finite fields.

$$ \text{Let } v := \frac{1}{2}\left( \alpha + \sqrt{\alpha^2 + \beta^2} \right) \pmod p $$

$$
x \equiv
\begin{cases}
\ \sqrt v \mod p                   &\text{ if $v$ is a square } \\\\
\\\\
\ \frac{\beta}{2 \sqrt{-v}} \mod p &\text{ otherwise } \\\\
\end{cases}
$$

$$ y \equiv \frac{\beta}{2x} \mod p $$
$$ \Downarrow $$
$$
y \equiv
\begin{cases}
\ \frac{\beta}{2 \sqrt v} \mod p                   &\text{ if $v$ is a square } \\\\
\\\\
\ \sqrt{-v} \mod p &\text{ otherwise } \\\\
\end{cases}
$$

<details>
  <summary>Derivation</summary>

Here follows a derivation of the above formulas for squares in $\mathbb F_{p^2}$. Strap in.

Let $\alpha + \beta i$ be the square of $x + yi \in \mathbb F_{p^2}$.

$$ \alpha + \beta i = (x + y i)^2 $$

We want to find formulas for the real & imaginary coefficients $x$ and $y$ of the square root element $x + yi$. Start by expanding:

$$
\begin{align}
\alpha + \beta i &= x^2 + 2xyi + y^2 i^2  \\\\
&= \underbrace{x^2 - y^2}\_{\alpha} + \underbrace{2xy}\_{\beta}i  \\\\
\end{align}
$$

Since all terms in this equation are fully expanded, we know the real coefficient must be $\alpha = x^2 - y^2$, and the imaginary coefficient must be $\beta = 2xy$. We have two equations with two unknowns - We can now solve this as a system of equations.

$$
\text{solve for $x$ and $y$}
\begin{cases}
\ \alpha \equiv x^2 - y^2 & \mod p \\\\
\ \beta \equiv 2xy & \mod p \\\\
\end{cases}
$$

We could solve this by brute force using substitution and invoking the quadratic formula, but there's a more elementary way.

Let $\gamma = x^2 + y^2 \pmod p$ be the _field norm_ of $x + yi \in \mathbb F_{p^2}$. This is related to the use of the word _norm_ in complex arithmetic, which you could think of as the _distance of a complex number from $0$,_ or perhaps its _absolute value._

Notice what happens if we square $\gamma = x^2 + y^2$ and compare against the square of $\alpha = x^2 - y^2$.

$$ \alpha^2 \equiv x^4 + y^4 - 2 x^2 y^2 \mod p$$
$$ \gamma^2 \equiv x^4 + y^4 + 2 x^2 y^2 \mod p$$

The difference between these squares is itself the square of $\beta = 2xy$.

$$
\begin{align}
\gamma^2 - \alpha^2 &\equiv 4 x^2 y^2 \mod p \\\\
&\equiv (2xy)^2 \mod p \\\\
&\equiv \beta^2 \mod p \\\\
\end{align}
$$

This gives us a relationship between the field norm of $x + yi$ and the field norm of $\alpha + \beta i$.

$$
\begin{align}
\gamma^2 - \alpha^2 &\equiv \beta^2 \mod p \\\\
\gamma^2 &\equiv  \alpha^2 + \beta^2 \mod p \\\\
\gamma &\equiv \pm \sqrt{\alpha^2 + \beta^2} \mod p \\\\
\end{align}
$$

Intuitively, this makes sense if we analogize to complex numbers. Multiplying two complex numbers also multiplies their norms. So squaring $x + yi$ would also square its norm $\gamma$.

For convenience, let $\delta := \alpha^2 + \beta^2 \pmod p$ be the field norm of $\alpha + \beta i$.

$$ \gamma \equiv \pm \sqrt{\delta} \mod p $$

Let's discard the variable $\gamma$, substituting in our original definition $\gamma = x^2 + y^2$. We can easily find an expression for $y^2$ in terms of $x^2$.

$$
\begin{align}
x^2 + y^2 &\equiv \pm \sqrt{\delta} \mod p \\\\
y^2 &\equiv - x^2 \pm \sqrt{\delta} \mod p \\\\
\end{align}
$$

If we substitute this into one of our earlier constraints from the system of equations, then we find almost exactly what we need: a formula for $x^2$.

$$
\begin{align}
x^2 - y^2 &\equiv \alpha \mod p \\\\
x^2 &\equiv \alpha + y^2 \mod p \\\\
x^2 &\equiv \alpha \pm \sqrt{\delta} - x^2 \mod p \\\\
2x^2 &\equiv \alpha \pm \sqrt{\delta}  \mod p \\\\
x^2 &\equiv \frac{1}{2}\left( \alpha \pm \sqrt{\delta} \right)  \mod p \\\\
\end{align}
$$

More concretely:

$$
x^2 = \text{ one of }
\begin{cases}
\ \frac{1}{2}\left( \alpha + \sqrt{\delta} \right) \\\\
\ \frac{1}{2}\left( \alpha - \sqrt{\delta} \right) \\\\
\end{cases}
$$

Once we have $x \equiv \pm \sqrt{x^2} \mod p$, we can easily compute $y$ using the other constraint from the system of equations.

$$
\begin{align}
2xy &\equiv \beta \mod p \\\\
y &\equiv \frac{\beta}{2x} \mod p \\\\
\end{align}
$$

However, before we can definitively calculate $y$, there is ambiguity around which signs to use for the $\pm$ square roots. If we tidy this up we will find a more exact formula for $x$, and thus for $y$ as well.

The inner root $\pm \sqrt \delta = \pm \sqrt{\alpha^2 + \beta^2}$ should be addressed first. We must assume $\delta$ is a square in $\mathbb F_p$ for this formula to work - indeed this is precisely how we can test for squareness of any element $\alpha + \beta i \in \mathbb F_{p^2}$. But which inner square root should we use: $+ \sqrt{\delta}$ or $- \sqrt{\delta}$? Will both produce a correct $x \in \mathbb F_p$ when plugged into our formula? Will either?

Recall the Legendre symbol of any nonzero $r \in \mathbb F_p$ is $r^{\frac{p-1}{2}} \equiv 1 \mod p$ if and only if $r$ is a square in $\mathbb F_p$, and otherwise $r^{\frac{p-1}{2}} \equiv -1 \mod p$ when $r$ is a non-square.

The Legendre symbol of a product $rs \in \mathbb F_p$ is the product of the factors' Legendre symbols. This follows neatly from the distributivity of exponentiation over multiplication in $\mathbb F_p$.

$$ \left( rs \right)^{\frac{p-1}{2}} \equiv r^{\frac{p-1}{2}} \cdot s^{\frac{p-1}{2}} \mod p $$

In other words:
- If $r$ and $s$ are both squares, then their product $rs$ **is also a square.**
  - Corresponds to $1 \cdot 1 = 1$
- If $r$ is a square but $s$ is not, then their product $rs$ **is not a square.**
  - Corresponds to $1 \cdot (-1) = -1$
- If neither $r$ nor $s$ are squares, then their product $rs$ **is a square.**
  - Corresponds to $(-1) \cdot (-1) = 1$

We can use these properties to deduce facts about the squareness of field elements. For instance, let us take our two candidates for $x^2$ - one using $+ \sqrt{\delta}$, one using $- \sqrt{\delta}$) - and we multiply them together.

$$ \left( \frac{1}{2}\left( \alpha + \sqrt{\delta} \right) \right) \cdot \left(\frac{1}{2}\left( \alpha - \sqrt{\delta} \right) \right) $$

Simplify using the difference of squares identity $(a+b)(a-b) = a^2 - b^2$:

$$ \frac{1}{4}\left( \alpha + \sqrt{\delta} \right) \left( \alpha - \sqrt{\delta} \right) $$
$$ \frac{1}{4}\left( \alpha^2 - \left(\sqrt{\delta}\right)^2 \right) $$
$$ \frac{1}{4}\left( \alpha^2 - \delta \right) $$

Substitute $\delta = \alpha^2 + \beta^2$:

$$ \frac{1}{4}\left( \alpha^2 - \alpha^2 - \beta^2 \right) $$
$$ \frac{-\beta^2}{4} $$

Notice that the simplified product $\frac{-\beta^2}{4}$ _is a non-square,_ because it can be factored into a non-square ($-1$) times a square $\left(\frac{\beta^2}{4}\right)$.

$$ \frac{-\beta^2}{4} \equiv (-1) \cdot \left( \frac{\beta}{2} \right)^2 \mod p $$

Therefore, **one and only one of the original factors which produced this number _must be a square._** We define this square to be the canonical $x^2$.

$$
x^2 =
\begin{cases}
\ \frac{1}{2}\left( \alpha + \sqrt{\delta} \right) & \text{ if a square}\\\\
\ \frac{1}{2}\left( \alpha - \sqrt{\delta} \right) & \text{ otherwise}\\\\
\end{cases}
$$

Computationally, it would suck to have to compute both these possible values for $x^2$. Thankfully, we can reformulate the second case in terms of $\alpha + \sqrt{\delta}$ by reorganizing our earlier result, and we find a compact expression for $x = \pm \sqrt{\frac{1}{2}\left( \alpha - \sqrt{\delta} \right)}$ which we can use in the case when $\frac{1}{2}\left( \alpha + \sqrt{\delta} \right)$ is not a square.

$$
\begin{align}
\left( \frac{1}{2}\left( \alpha + \sqrt{\delta} \right) \right) \cdot \left(\frac{1}{2}\left( \alpha - \sqrt{\delta} \right) \right) &\equiv \frac{-\beta^2}{4} \mod p \\\\
\frac{1}{2}\left( \alpha - \sqrt{\delta} \right) &\equiv \frac{-\beta^2}{4} \left( \frac{1}{2}\left( \alpha + \sqrt{\delta} \right) \right)^{-1} \mod p \\\\
\sqrt{\frac{1}{2}\left( \alpha - \sqrt{\delta} \right)} &\equiv \sqrt{\frac{-\beta^2}{4} \left( \frac{1}{2}\left( \alpha + \sqrt{\delta} \right) \right)^{-1}} \mod p \\\\
x &\equiv \pm \frac{\beta}{2} \sqrt{-\left( \frac{1}{2} \left( \alpha + \sqrt{\delta} \right) \right)^{-1}} \mod p \\\\
\end{align}
$$

We use the identity $\sqrt{-a^{-1}} = \left( \sqrt{-a} \right)^{-1}$, due to the commutativity of radicals and exponents.

$$
\begin{align}
x &\equiv \pm \frac{\beta}{2} \left(\sqrt{- \frac{1}{2} \left( \alpha + \sqrt{\delta} \right) }\right)^{-1} \\\\
\end{align}
$$

This leads to an efficient formula for $x$.

Let $v := \frac{1}{2}\left( \alpha + \sqrt{\alpha^2 + \beta^2} \right)$. Then:

$$
x \equiv
\begin{cases}
\ \sqrt v \mod p                   &\text{ if $v$ is a square } \\\\
\\\\
\ \frac{\beta}{2 \sqrt{-v}} \mod p &\text{ otherwise } \\\\
\end{cases}
$$

For $y = \frac{\beta}{2x}$ we have:

$$
y \equiv
\begin{cases}
\ \frac{\beta}{2 \sqrt v} \mod p &\text{ if $v$ is a square } \\\\
\\\\
\ \sqrt{-v} \mod p &\text{ otherwise } \\\\
\end{cases}
$$

Sources

- https://eprint.iacr.org/2020/1497.pdf
- https://eprint.iacr.org/2012/685.pdf

</details>

From these formulas, we inherit a second natural test for squareness in $\mathbb F_{p^2}$: Simply check if $\alpha^2 + \beta^2$ is a square in $\mathbb F_p$. If so, we know $\alpha + \beta i$ must be a square in $\mathbb F_{p^2}$.

This turns out to be more computationally efficient than checking the Legendre symbol $(\alpha + \beta i)^{\frac{q - 1}{2}} = \pm 1$, because we can do all the arithmetic in the base field $\mathbb F_p$ instead of in $\mathbb F_{p^2}$.

### Sources

- https://matherama.com/Tutorials/Chapter%2004%20-%20Complex%20Numbers%20Basics/04%20-%20Square%20root%20of%20a%20complex%20number/
- https://en.wikipedia.org/wiki/Frobenius_endomorphism
- https://e.math.cornell.edu/people/belk/numbertheory/FiniteFields.pdf
- https://www.imo.universite-paris-saclay.fr/~pierre-loic.meliot/algebra/finite_fields.pdf
- https://math.mit.edu/classes/18.783/2017/LectureNotes4.pdf

### Review

We've learned how to concretely construct the finite extension field $\mathbb F_{p^2}$ which gives us complex-number-like arithmetic on a base field $\mathbb F_p$. We've seen how we can test for and then find square roots in $\mathbb F_{p^2}$ efficiently.

We've proven a number of properties of finite fields in general, including facts about an interesting function called the Frobenius endomorphism, $\pi(x) = x^p$ which has homomorphic properties, and the important difference between a field's _order_ and its _characteristic._

This rounds up the necessary background notes on finite fields, and we can now move on to...



## Elliptic Curves

An elliptic curve used for cryptography is typically a cubic equation which implicitly defines a smooth _non-singular<sup>\*</sup>_ curve, such as an elliptic curve $E$ in short Weierstrass form:

$$ E : y^2 = x^3 + ax + b $$

\*Here "non-singular" means the curve has no cusps (sharp points) or self-intersections. Given coefficients $a$ and $b$ from the curve's short Weierstrass form, we can check this property holds algebraically by confirming that $4a^3 + 27b^2 \neq 0$. [Source](https://mathworld.wolfram.com/EllipticDiscriminant.html). (TODO Proof)

As an example, here is what the secp256k1 curve $y^2 = x^3 + 7$ looks like when graphed over the real numbers:

<img width="100%" style="max-width: 500px;" src="/images/isogenies/secp-curve.png">

Note that an elliptic curve can be _defined_ over any field, including the real numbers $\mathbb R$, the complex numbers $\mathbb C$, or - most relevantly for this article - a finite field $\mathbb F_q$. When we say a curve $E: y^2 = x^3 + ax + b$ is _defined over_ the field $F$, we mean the Weierstrass coefficients $a$ and $b$ are in $F$, and we write this as $E/F$.

Given an elliptic curve $E/F$, a _point_ on $E$ is a pair of numbers $(x, y)$ which satisfy the curve equation of $E$. Note $x$ and $y$ _do not necessarily have to be in the same field $F$ over which the curve $E$ is defined!_ Sometimes we want to refer to the set of points which satisfy $E$'s equation in some larger or smaller field $K$.

You'll often see the notation $E(K)$, spoken as "$E$ join $K$", which denotes the set of all $(x, y)$ pairs in $K$ which satisfy $E/F$, with field arithmetic performed in the larger of the two fields: $K$ or $F$. This set is also often referred to as the set of _"$K$-rational points"_ on $E$. In general, isogenists often say a point is _$K$-rational_ if both $x, y \in K$ and the point $(x, y)$ satisfies some elliptic curve equation - The exact curve and the field it's defined over are often (unfortunately) implied by context.

For reasons you will see soon, any such set of $K$-rational points $E(K)$ also includes a special _point at infinity,_ written simply as $0$ because it will play the role of zero for algebraic purposes later. In the mathematical literature, many authors often write the infinity point as $\mathcal O$, or $0_E$ to denote the infinity point for a specific curve $E$. Do not be confused: They are all referring to the same concept.

$$ E(K) = \\{ (x, y) \in K : y^2 = x^3 + ax + b \\} \cup \\{ 0 \\} $$

The earlier graph of the secp256k1 curve $E: y^2 = x^3 + 7$ is a visualization of the set $E(\mathbb R)$: the set of $\mathbb R$-rational points on the secp256k1 curve. However, in cryptography we typically define curves over a finite field and consider points rational over that field - This way we do not get floating point precision errors, and we can more effectively reason about security. Check out [this interactive tool to play around with elliptic curves over finite fields](https://andrea.corbellini.name/ecc/interactive/modk-add.html).

When we have some finite field $F$, we can define an elliptic curve $E$ over that field by allowing the curve parameters $a$ and $b$ to take values in $F$. This is written as $E/F$ as explained earlier. Any pair $x, y \in F$ which correctly solves the curve equation of $E/F$ is designated a "point" in the curve, and a member of the set of $F$-rational points: $(x, y) \in E(F)$.

We often write points with upper case letters like $P$ or $Q$. This is a notational shortcut to avoid having to write out the full point.

$$ P = (x, y) $$

For isogeny cryptography, we're interested in points which are _rational_ (i.e: they correctly satisfy the curve equation) in some low-degree extension field $\mathbb F_{p^k}$ for a _large prime_ $p$ and a small degree $k$. We need $p$ to be large so that the field order $|\mathbb F_{p^k}| = p^k$ is large enough to provide adequate security against brute-force attacks. For computational efficiency, we ideally want curve points which are rational in (at most) the smallest non-trivial extension field $\mathbb F_{p^2}$, because there we have efficient arithmetic algorithms as described in the prior section.

Note the set of $\mathbb F_{p^2}$-rational curve points $E(\mathbb F_{p^2})$ also includes all curve points which are rational over the base field $\mathbb F_p$, for which we also have very efficient arithmetic.

$$ E(\mathbb F_p) \subset E(\mathbb F_{p^2}) $$

### Curve Structure

Elliptic curves have a useful common structure. For any point $(x, y)$ in a field $F$ which satisfies the curve $E: y^2 = x^3 + ax + b$, we know the point $(x, -y)$ must also be on the curve, because $\left(-y \right)^2 = y^2$ in any field. There are some cases where $-y = y$, namely when $y = 0$. This means for any valid $x$ coordinate, we have at most two valid $y$ coordinates, and if you know the $x$ coordinate you can calculate both $y$ coordinates by finding the two square roots of $x^3 + ax + b$.

Furthermore, we can efficiently distinguish between the two possible $y$ coordinates by testing for divisibility by two (i.e. even or odd).

<details>
  <summary>Proof</summary>

Here is a proof that we can always distinguish between $y$ and $-y$ if $y \in \mathbb F_{p^2}$ for a large prime $p$.

By "distinguish", I mean: Given an unlabeled unordered pair $y, -y \in \mathbb F_{p^2}$ and a single bit of information, determine uniquely which value $y$ or $-y$ the bit is referencing.

First, notice that for any even non-zero $v \in \mathbb F_p$, then $-v \equiv p-v \mod p$ must be odd. This is because any prime $p > 2$ is odd, and subtracting an even number from an odd number always gives another odd number. Likewise if $v \in \mathbb F_p$ is odd, then $-v \equiv p - v$ must be even, because subtracting two odd numbers always gives an even number.

In other words, negation modulo $p$ flips the _parity_ of any non-zero $v \in \mathbb F_p$.

If $y \in \mathbb F_{p^2}$, then we have:

$$
\begin{align}
y &= \alpha + \beta i \\\\
-y &= -\alpha - \beta i \\\\
   &= (p - \alpha) + (p - \beta) i \\\\
\end{align}
$$

...where $\alpha, \beta \in \mathbb F_p$.

Then for any $\alpha > 0$, we know $p - \alpha$ must have opposite parity, and likewise for $\beta$ and $p - \beta$. Thus to distinguish between $y = \alpha + \beta i$ and $-y = (p - \alpha) + (p - \beta) i$, we can inspect the parity of $\alpha$ and $\beta$ sequentially.

Given a single bit of parity information $b \in \\{0, 1\\}$ (0 meaning "even" or 1 meaning "odd"), we check:

- If $\alpha > 0$ and $\alpha \equiv b \mod 2$, then $y$ must be the intended value.
- If $\alpha > 0$ and $\alpha \not \equiv b \mod 2$, then $-y$ must be the intended value.
- If $\alpha = 0$ then check $\beta$ instead.
  - If $\beta > 0$ and $\beta \equiv b \mod 2$, then $y$ must be the intended value.
  - If $\beta > 0$ and $\beta \not \equiv b \mod 2$, then $-y$ must be the intended value.
  - If $\beta = 0$, then $y = -y = 0$ and both values are the same.

There are other ways to distinguish between $y$ and $-y$, but this provides a simple and computationally efficient method.

</details>

Perhaps now you may understand why we spent so much time and effort talking about squares and taking square roots in finite fields. Squares are a fundamental part of elliptic curve cryptography in general, because we often represent elliptic curve points by compressing the $y$ coordinate.

Given there are at most two possible $y$ coordinates for a given $x$ coordinate, we can represent a point on an elliptic curve with $(x, b)$ where $b \in \\{0, 1\\}$ is a parity bit to help distinguish the correct $y$ coordinate between the two candidates $y$ and $-y$. At other times, we are able to elide the parity bit $b$ altogether, and perform arithmetic using only the $x$ coordinate with the sign/parity of the $y$ coordinate being implied by convention, or else completely discarded.

To do this we must first find $y$ and $-y$ using only $x$. Given a curve $y^2 = x^3 + ax + b$, this means we must find the two square roots: $y = \pm \sqrt{x^3 + ax + b}$. Only then can the parity bit $b$ have any utility. Thanks to our earlier work understanding squares in finite fields, we already have all the tools we need to compute this.

### Point Counting

Because not all elements in $\mathbb F_{p^2}$ are squares, not all values of $x$ map to valid coordinates on a curve $y^2 = x^3 + ax + b$. Actually, counting the number of points on an elliptic curve over any finite field is a challenging problem.

There are efficient algorithms to do this in general, such as Schoof's Algorithm:

- https://math.mit.edu/classes/18.783/2022/LectureNotes8.pdf
- https://en.wikipedia.org/wiki/Schoof%27s_algorithm
- https://en.wikipedia.org/wiki/Schoof%E2%80%93Elkies%E2%80%93Atkin_algorithm

However, for our purposes, I will skip over the details of how these algorithms work, as we will find soon a much more succinct and efficient way to compute the order of a certain special subtype of elliptic curve (Montgomery curves).

### Visualizing Elliptic Curves

I found [this impressive set of slides](https://stevejtrettel.site/talks/visualizing-elliptic-curves/slides.pdf) by Steve Trettel which show some very unique and interesting visualizations of elliptic curves over various types of fields. Visual learners should certainly take a peek.

### Point Arithmetic

Elliptic curves are mathematically and cryptographically interesting because we can create [_abelian groups_](https://en.wikipedia.org/wiki/Abelian_group) on top of them.

An abelian group is just a set of mathematical objects where we have some defined _commutative group operation_ between elements of the group. For instance, the set of integers $\mathbb Z$ can be turned into an abelian group using their addition or multiplication operations. We'd write the multiplicative group of integers as $\mathbb Z^\*$, which is abelian. This applies to many other common number groups like $\mathbb R$, $\mathbb Q$, $\mathbb C$, and also any finite field $\mathbb F_q$, and so on. But an abelian group doesn't have to consist purely of numbers and numerical operations.

Anyone can define an abelian group in a bespoke and arbitrary way provided the abelian group laws hold. For instance, you could define an "addition" operation on the set of all paint colors, by mixing paints together. Mixing paint is commutative: It doesn't matter which paint you start with. Red + green + yellow is the same as yellow + red + green, etc. The set of paint colors is now an abelian group under the _color-mixing_ group operation.

The abelian group operation in an elliptic curve is _point addition,_ and it is most easily defined in a geometric sense. Here is a little infographic I modified from Wikipedia which shows the basic rules of elliptic curve groups, with diagrams showing curves graphed over $\mathbb R$, with $x$ on the X-axis and $y$ on the Y-axis. Recall the _infinity point_ is written as $0$, and you should think of it as the hypothetical point reached by extending a vertical line to infinity.

<img src="/images/isogenies/ec-addition.svg">

In English:

1. Three _colinear_ points on the curve sum to infinity (AKA zero).
2. When a line intersects the curve tangentially, rule 1 applies with the tangent point counted twice.
3. Any two points connected by a vertical line sum to infinity.
4. Rule 3 applies to [inflection points](https://en.wikipedia.org/wiki/Inflection_point).

Rules 1 and 3 are the most salient. They tell us, rather obliquely, how to compute the sum of two points on a curve.

Since $P + Q + R = 0$ from rule 1, we know $P + Q = -R$. What does $-R$ even mean though?

Rule 3 tells us $P + Q + 0 = 0$ when $P$ and $Q$ have opposite $y$ coordinates. This implies $P + 0 = 0 - Q$: Negation of a point $Q$ means negating the $y$ coordinate of $Q$, i.e. flipping about the X-axis.

So taken together, these two rules tell us how to compute a sum of points $P+Q = R$: We first find $-R$ by drawing a line between $P$ and $Q$, and then find the third curve point intersected by that line. We then flip the $y$ coordinate of $-R$ to find its negation, $R$, which is the sum $P + Q$ we wanted.

<img style="max-width: 400px; border-radius: 10px;" src="/images/isogenies/ec-addition-example.png">

TODO: Fix the point notation to match the prior examples.

<sub><a href="https://www.embeddedrelated.com/showarticle/1590.php">Image Source</a></sub>

You might wonder how we know such a third line intersection point always exists on the curve. Indeed, sometimes we only have two intersection points, as seen in the graph of rule 2 where the intersection point $Q$ is a _tangent_ point of the curve.

Rules 2 tells us how to handle these cases. Rule 2 says that if a line only has two intersections, one of them being through a tangent point, then the tangent point $Q$ is said to be summed twice. This corresponds to the geometric fact that the intersection point $Q$ has a [_multiplicity_](https://onlinelibrary.wiley.com/doi/full/10.1155/2023/6346685) of 2.

Think of _multiplicity_ as the number of intersections contained in a single point. If one were to disturb the curves slightly, one could split an intersection of multiplicity 2 into two intersections of multiplicity 1.

Therefore, when adding a point $Q$ to itself $Q + Q$ - often called _point doubling_ - we draw a line tangent to the curve which intersects $Q$. We find the other intersection on $P$, and invert it to get the sum $Q + Q = -P$.

In even more special cases, there are places where we can draw a line which intersects the curve only once. These are called _inflection points,_ which in geometric terms are _convex_ places on the curve: A line drawn tangent to such a point would intersect the curve nowhere else. More precisely, inflection points on an elliptic curve are said to have _multiplicity_ 3, because a slight disturbance to the line could produce three intersections. Rule 4 clarifies rule 3 for the corner-case of inflection points, by defining the negation of an inflection point to be itself.

Could there be a fourth intersection point, or even more? No, and we know this because of [Bezout's theorem](https://en.wikipedia.org/wiki/B%C3%A9zout%27s_theorem), which proves that two distinct algebraic curves of degrees $d_1$ and $d_2$ can intersect in at most $d_1 \cdot d_2$ points. Since a line has degree $1$ and an elliptic curve has degree $3$, the two can intersect in at most $3$ points.

<details>
  <summary>Proof</summary>

Here follows a highly specific proof that elliptic curves and straight lines may intersect in at most 3 locations. [Bezout's theorem](https://en.wikipedia.org/wiki/B%C3%A9zout%27s_theorem) proves this more generally for any algebraic curves, but this proof is easier to follow without any algebraic geometry background.

An algebraic curve is the set of all $(x, y)$ points on the Cartesian plane for which some bivariate (two variable) polynomial $f(x, y)$ returns zero.

Let polynomials $f(x, y)$ and $g(x, y)$ define two such algebraic curves.

$$ f(x, y) = x^3 + ax + b - y^2 $$
$$ g(x, y) = cx + d - y $$

Notice $f(x, y)$ describes an elliptic curve $y^2 = x^3 + ax + b$, and $g(x, y)$ describes a line $y = cx + d$.

The intersections of those curves are the set of points $(x, y)$ where $f(x, y) = g(x, y) = 0$. This gives us a system of two equations with two unknowns.

$$
\text{Solve for $x$ and $y$ }
\begin{cases}
0 = x^3 + ax + b - y^2 \\\\
0 = cx + d - y \\\\
\end{cases}
$$

We can find an expression for $y$ in terms of $x$:

$$
\begin{align}
0 &= cx + d - y \\\\
y &= cx + d \\\\
\end{align}
$$

...and substitute that back into the first equation:

$$
\begin{align}
0 &= x^3 + ax + b - y^2 \\\\
  &= x^3 + ax + b - (cx + d)^2 \\\\
  &= x^3 + ax + b - (c^2 x^2 + 2cdx + d^2) \\\\
  &= x^3 - c^2 x^2 + (a - 2cd)x + b - d^2 \\\\
\end{align}
$$

Solving this equation for $x$ will give us the solutions for $f(x, y) = g(x, y) = 0$. We could do this by using the [cubic formula](https://math.vanderbilt.edu/schectex/courses/cubic/), but we don't really need to.

As per Lagrange's Theorem for Number Theory, which [we proved earlier](#lagrange-theorem), a degree-3 polynomial has at most 3 roots, and so this technique yields at most 3 possible solutions for $x$. Using the equation $y = cx + d$ we can then derive one corresponding $y$ for each value of $x$. In total, this yields at most three solutions.

If the field over which $f$ and $g$ are defined is _algebraically closed,_ then this technique always gives _at least_ one solution for $(x, y)$.

There is an edgecase to consider. If $g(x, y)$ describes a vertical line $g(x, y) = x - v$ (the vertical line at $x = v$), then the above technique cannot be applied. In this case, the intersections are given by the system of equations:

$$
\text{Solve for $x$ and $y$ }
\begin{cases}
0 = x^3 + ax + b - y^2 \\\\
0 = x - v \\\\
\end{cases}
$$

...which can be solved by substituting $x = v$ and solving for $y = \pm \sqrt{v^3 + av + b}$, giving at most two solutions: $(x, y)$ and $(x, -y)$.

</details>

### Adding Points in Any Field

Drawing pretty pictures over the real numbers is all well and good, but how can we compute point addition with finite field arithmetic?

The geometric definitions of the elliptic curve group operation still apply in the world of finite fields, even in extension fields like $\mathbb F_{p^2}$. This is not immediately obvious, but if we take a look at what the geometric definition means algebraically, we'll see the necessary computations are all completely defined and unambiguous regardless of which field we use, finite or otherwise.

Given two points $P = (x_P, y_P)$ and $Q = (x_Q, y_Q)$ on a curve $E: y^2 = x^3 + ax + b$, we want to find their sum $P+Q$, and handle the edgecases where $P = Q$ or $P + Q = -Q$ or $P + Q = -P$.

First we naturally must check if $P = -Q$, by checking if $x_P = x_Q$ and $y_P = -y_Q$. If so, we have defined $Q + (-Q) = 0$, so the sum is the infinity point $0$ and we are done.

Otherwise, does $P = Q$? Then find the tangent slope $m$ of $P = Q$ as follows:

$$ m = \frac{3 x_P^2 + a}{2 y_P} $$

This formula can be found by using some calculus to take the first derivative of $\sqrt{x^3 + ax + b}$.

<details>
  <summary>Proof</summary>

To find the tangent slope of a point $(x, y)$ in the curve $y^2 = x^3 + ax + b$, we take the derivative of the expression $\sqrt{x^3 + ax + b}$ with respect to $x$.

For any function $f(x)$ we denote its first-order derivative as $f'(x) = \frac{d(f(x))}{dx}$.

To find the derivative of $\sqrt{x^3 + ax + b}$, we define $f(x) = \sqrt{x} = x^{\frac{1}{2}}$ and $g(x) = x^3 + ax + b$. Thus we can express in terms of $f$ and $g$:

$$ f(g(x)) = \sqrt{x^3 + ax + b} $$

The [chain rule of calculus](https://en.wikipedia.org/wiki/Chain_rule) states:

$$ (f \circ g)'(x) = f'(g(x)) \cdot g'(x) $$

We must now find the derivatives of $g$ and $f$ separately.

$f(x) = \sqrt x$ can be differentiated using a single application of the [_power rule_ of calculus](https://en.wikipedia.org/wiki/Power_rule), which states the derivative of $x^n$ is

$$ \frac{d(x^n)}{dx} = n x^{n - 1} $$

For square roots, this means:

$$
\begin{align}
f'(x) &= \frac{d \left( x^{\frac{1}{2}} \right)}{dx} \\\\
&= \frac{1}{2} \cdot x^{-\frac{1}{2}} \\\\
&= \frac{1}{2 x^\frac{1}{2}} \\\\
&= \frac{1}{2 \sqrt x} \\\\
\end{align}
$$

$g(x) = x^3 + ax + b$ can be differentiated by [summing the derivatives](https://en.wikipedia.org/wiki/Differentiation_rules#Differentiation_is_linear) of the polynomial terms $x^3$, $ax$, and $b$.

- $\frac{d (x^3)}{dx} = 3 x^2$, as per the power rule.
- $\frac{d (ax)}{dx} = 1 \cdot a x^0 = a$, as per the power rule and constant factor rule.
- $\frac{db}{dx} = 0$ because the derivative of a constant is always zero.

...giving us:

$$ g'(x) = 3 x^2 + a $$

And as a reminder, we previously found

$$ f'(x) = \frac{1}{2 \sqrt x} $$

Now we can compute the derivative $(f \circ g)'(x)$:

$$
\begin{align}
(f \circ g)'(x) &= f'(g(x)) \cdot g'(x) \\\\
&= \frac{1}{2 \sqrt{g(x)}} \cdot \left( 3 x^2 + a \right) \\\\
&= \frac{3 x^2 + a}{2 \sqrt{g(x)}} \\\\
\end{align}
$$

If we leave calculus and return back to the world of elliptic curves, we recall that $y^2 = g(x) = x^3 + ax + b$, so we can substitute $y$ to get our formula for the tangent slope at $(x, y)$:

$$ \frac{d \left( \sqrt{x^3 + ax + b} \right)}{dx} = \frac{3 x^2 + a}{2 y} $$

</details>

Alternatively, if $P \neq Q$, then we find the slope of the line between the two points as:

$$ m = \frac{y_P - y_Q}{x_P - x_Q} $$

...or equivalently:

$$ m = \frac{y_Q - y_P}{x_Q - x_P} $$

To find a point $R = (x_R, y_R)$ which lies on the line passing through $P$ and $Q$, we compute the $x_R$ and $y_R$ coordinates using a couple of simple formulas:

$$ x_R = m^2 - x_P - x_Q $$
$$ y_R = m(x_R - x_P) + y_P $$

Since $P + Q + R = 0$ (rule 1), the sum point should be $P + Q = -R = (x_R, -y_R)$, and we are done.

<details>
  <summary>Proof</summary>

We need to find a curve point $R = (x_R, y_R) \in E$ on the line passing through points $P = (x_P, y_P) \in E$ and $Q = (x_Q, y_Q) \in E$, which has slope $m = \frac{y_P - y_Q}{x_P - x_Q} = \frac{y_Q - y_P}{x_Q - x_P}$.

Remember, the point $R$ is actually the _additive inverse_ of the sum $P+Q = -R$ that we ultimately want to compute.

Given these constraints, we have the following system of equations:

$$
\text{Solve for $x_R$ and $y_R$ }
\begin{cases}
m = \frac{y_R - y_P}{x_R - x_P}  \\\\
y_R^2 = x_R^3 + a x_R + b  \\\\
\end{cases}
$$

Rearrange the first equation to find an expression for $y_R$ in terms of $x_R$:

$$
\begin{align}
m &= \frac{y_R - y_P}{x_R - x_P}  \\\\
m(x_R - x_P) &= y_R - y_P \\\\
m(x_R - x_P) + y_P &= y_R \\\\
\end{align}
$$

Substitute into the other equation:

$$
\begin{align}
y_R^2 &= x_R^3 + a x_R + b \\\\
(m(x_R - x_P) + y_P)^2 &= x_R^3 + a x_R + b \\\\
\end{align}
$$

We could use brute force to fully expand and solve this cubic equation using the [cubic formula](https://math.vanderbilt.edu/schectex/courses/cubic/), but there is a much less verbose shortcut.

If we partly expand $(m(x_R - x_P) + y_P)^2$ focusing on the $x_R^2$ term, we will see that the leading coefficient for the $x_R^2$ term will be $m^2$.

$$ (m(x_R - x_P) + y_P)^2 $$
$$ m^2(x_R - x_P)^2 + ... $$
$$ m^2(x_R^2 - 2 x_R x_P + x_P^2) + ... $$
$$ m^2 x_R^2 + ... $$

If we rearrange our earlier cubic equation into standard form, we'll see the coefficient of the $x_R^2$ term is $-m^2$:

$$
\begin{align}
m^2 x_R^2 + ... &= x_R^3 + a x_R + b \\\\
0 &= x_R^3 - m^2 x_R^2 - ... + a x_R + b \\\\
\end{align}
$$

Now look at this as a polynomial $g(x)$:

$$
\begin{align}
g(x) &= x^3 + ax + b - (m(x - x_P) + y_P)^2 \\\\
     &= x^3 - m^2 x^2 - ... + a x + b \\\\
\end{align}
$$

We know it has a root at $g(x_P) = 0$, because the point $P = (x_P, y_P)$ is on the curve.

$$ (m(x_P - x_P) + y_P)^2 = y_P^2 = x_P^3 + ax_P + b $$

If $Q = P$, then $x_Q = x_P$, and so $g(x_Q) = 0$ is also a root, obviously.

If $Q \neq P$, then $g(x)$ has a second _distinct root_ at $g(x_Q) = 0$, because the point $Q = (x_Q, y_Q)$ is on the same line and is also on the curve.

Recall if $Q \neq P$, we defined $m = \frac{y_P - y_Q}{x_P - x_Q} = \frac{y_Q - y_P}{x_Q - x_P}$.

$$
\begin{align}
(m(x_Q - x_P) + y_P)^2 &= \left(\frac{y_Q - y_P}{x_Q - x_P} \left( x_Q - x_P \right) + y_P \right)^2 \\\\
&= (y_Q - y_P + y_P)^2 \\\\
&= y_Q^2 \\\\
&= x_Q^3 + a x_Q + b
\end{align}
$$

The fact that $g(x)$ has two roots at $x_P$ and $x_Q$ implies that it must factor into

$$ g(x) = (x - x_P)(x - x_Q)(x - x_R) $$

...where $x_R$ is a third root. If we expand this factored form of $g(x)$ and find the coefficient of the $x^2$ term:

$$
\begin{align}
g(x) &= (x - x_P)(x - x_Q)(x - x_R) \\\\
     &= x^3 - x_P x^2 - x_Q x^2 - x_R x^2 + ...  \\\\
     &= x^3 - (x_P + x_Q + x_R) x^2 + ...  \\\\
\end{align}
$$

Taken with our previous formula for $g(x)$ in standard form which had the term $-m^2 x^2$, this implies:

$$ x_P + x_Q + x_R = m^2 $$

We can use this to finally give us our formula for $x_R$:

$$ x_R = m^2 - x_P - x_Q $$

Once we have $x_R$, we can plug this into our line equation to find $y_R$:

$$ y_R = m(x_R - x_P) + y_P $$

</details>

As you can see, these _addition and doubling_ formulas require only simple arithmetic which can be computed in any field, finite or otherwise. We will want to revise the formulas slightly when we switch to using Montgomery form curves later, but know these formulas can be applied generally to any elliptic curve over any field with characteristic $p > 3$ (which includes the later Montgomery curves as well).

### Supersingular Curves

Not all elliptic curves are created equal. Some are more useful than others for our cryptographic purposes. Turns out, we specifically want to work with _supersingular_ elliptic curves. Let's examine what this means, and why it is a useful property.

Let $E$ be an elliptic curve defined over the finite field $\mathbb F_{p^2}$, and let $E(\mathbb{F}\_{p^2})$ denote the set of all points on $E$ which are in $\mathbb{F}\_{p^2}$ including the point at infinity $0_E$. This is sometimes called the set of $\mathbb{F}\_{p^2}$-rational points.

There are [many equivalent ways](https://en.wikipedia.org/wiki/Supersingular_elliptic_curve) to define what _supersingular_ means mathematically, but the simplest to understand is to check the the curve's _cardinality_ (size) over $\mathbb F_{p^2}$, denoted $|E(\mathbb{F}\_{p^2})|$.

$$ |E(\mathbb{F}\_{p^2})| \equiv 1 \mod p \quad \leftrightarrow \quad E \text{ is supersingular } $$

In more plain terms: The number of nonzero points on the curve is divisible by the finite field characteristic $p$. _The remainder of 1 is there because of the point at infinity $0_E$._

<details>
  <summary>Generalization to $\mathbb F_q$</summary>

More generally, for any arbitrary finite field $\mathbb F_{q}$ with characteristic $\mathrm{char}(\mathbb F_q) = p$, this can be expressed as:

$$ q + 1 - |E(\mathbb F_q)| \equiv 0 \mod p $$

Or equivalently:

$$ |E(\mathbb F_q)| - q \equiv 1 \mod p $$

In the literature, you may see different varieties of this statement.

Often the value $q + 1 - |E(\mathbb F_q)|$ is short-handed as the "trace of Frobenius" or the "trace of the $q$-th power Frobenius" (Source: [Silverman][silverman], Chapter V, Remark 2.6).

You may see this property written as $p \mid \mathrm{tr}(\pi)$ ($p$ divides the trace of Frobenius). These are all the same statement. We may discard the $q$ term when $q = p^k$, because $q \equiv p^k \equiv 0 \mod p$.

</details>

If we don't already know it, we can compute the cardinality of the curve $|E(\mathbb{F}\_{p^2})|$ using something like [Schoof's algorithm](https://handwiki.org/wiki/Schoof%27s_algorithm).

If checking for supersingularity is all we care about, a faster method is by checking if the curve's [Hasse Invariant](https://math.stackexchange.com/questions/2159585/hasse-invariant-of-an-elliptic-curve) is zero.

<details>
  <summary>Hasse Invariant Explanation</summary>

Let $E: y^2 = x^3 + ax + b$ be an elliptic curve defined over a finite field $\mathbb F_q$ with characteristic $\mathrm{char}(\mathbb F_q) = p$.

The Hasse Invariant of $E$ is the coefficient of the $x^{p-1}$ term in the following expanded polynomial:

$$
\begin{equation}
(x^3 + ax + b)^{\frac{p-1}{2}}
\end{equation}
$$

To find this coefficient, we could use the [multinomial theorem](https://en.wikipedia.org/wiki/Multinomial_theorem), but since this polynomial has at most 3 terms, it suffices to use the more elementary [trinomial expansion](https://en.wikipedia.org/wiki/Trinomial_expansion), which states generally for any trinomial power $(a + b + c)^n$:

$$ (a + b + c)^n = \sum_{i + j + k = n} \left( \frac{n!}{i! \cdot j! \cdot k!} \cdot a^i \cdot b^j \cdot c^k \right) $$

Note the counters $i$, $j$, and $k$ iterate over all possible triples of integers up to and including $n$ which sum to $n$.

TODO: Proof

For our polynomial $(x^3 + ax + b)^{\frac{p-1}{2}}$, we set $n = \frac{p-1}{2}$ and therefore have:

$$ (x^3 + ax + b)^n = \sum_{i + j + k = n} \left( \frac{n!}{i! \cdot j! \cdot k!} \cdot x^{3i} \cdot (ax)^j \cdot b^k \right) $$

We are interested only in the coefficient on $x^{p-1}$ of this expansion, so let's find it. For each term of the sum, we can find the degree of $x$ in that term by expanding the product of $x^{3i}$ and $(ax)^j$:

$$ x^{3i} \cdot (ax)^j = x^{3i + j} \cdot a^j $$

This tells us we need to be looking at any terms in the sum where $3i + j = p - 1$, and so restricts $k$ to $k = n - i - j$.

For any such term, the coefficient will be

$$ \frac{n!}{i! \cdot j! \cdot k!} \cdot a^j \cdot b^{n - i - j} $$

...and so their sum will be:
<!--
$$ \sum_{3i + j = p - 1} \left( \frac{n! \cdot a^j \cdot b^{n - i - j}}{i! \cdot j! \cdot (n - i - j)!}  \right) $$
$$ \sum_{3i + j = p - 1} \left( \frac{n! \cdot a^j \cdot b^n \cdot b^{-i} \cdot b^{-j}}{i! \cdot j! \cdot (n - i - j)!}  \right) $$
$$ \sum_{3i + j = p - 1} \left( \frac{n! \cdot a^j \cdot b^n}{i! \cdot j! \cdot (n - i - j)! \cdot b^i \cdot b^j}  \right) $$
$$ b^n \cdot n! \cdot  \sum_{3i + j = p - 1} \left( \frac{a^j}{i! \cdot j! \cdot (n - i - j)! \cdot b^i \cdot b^j}  \right) $$
 -->
TODO


</details>


We can go faster still if we're willing to accept a negligible chance of a false-positive, by using a Monte Carlo algorithm: Sample a random point $Q \in E/\mathbb{F}\_{p^2}$ and return true if $(p + 1)Q = 0_E$ OR $(p - 1)Q = 0_E$. If this test returns false, it guarantees that $E$ is _not supersingular._ If this test returns true, there is only a $\frac{8p}{(p - 1)^2} \approx \frac{8}{p}$ chance of a false positive result where $E$ is not supersingular. (TODO proof)

Since $p$ is typically quite large ($p > 2^{248}$), one pass is generally sufficient for cryptographic purposes. If not, we can repeat this Monte Carlo test with $t$ distinct points to achieve an error rate of about $\left(\frac{8}{p}\right)^t$.

[There are lots of ways to check supersingularity.](https://arxiv.org/abs/1107.1140) In many cases we can skip this check though, because as we'll see later, we can usually infer supersingularity from context.

### j-invariants

Another important property of an elliptic curve is its $j$-invariant. Given an elliptic curve in short Weierstrass form $E: y^2 = x^3 + ax + b$, we can compute its $j$-invariant $j(E)$ as:

$$
\begin{align}
j(E) &= \frac{2^8 \cdot 3^3 \cdot a^3}{2^2 a^3 + 3^3 b^2} \\\\
     &= 1728 \cdot \frac{4 a^3}{4 a^3 + 27 b^2} \\\\
\end{align}
$$

Or if given a curve in Montgomery form $E: B y^2 = x^3 + A x^2 + x$, we can compute the $j$-invariant like this:

$$ j(E) = \frac{256(A^2 - 3)^3}{A^2 - 4} $$

The $j$-invariant will be important later for grouping related curves together into classes.

## Isogenies

An isogeny is a function that takes an input point from one elliptic curve and maps it onto a different elliptic curve.

Isogenies are typically denoted with greek letters $\varphi$ or $\phi$ (phi, pronounced "f-eye") or $\psi$ (psi, pronounced "s-eye"). We might write an isogeny $\varphi$ like this:

$$ \varphi : E_1 \rightarrow E_2 $$

...indicating it maps points from an elliptic curve $E_1$ onto points of another elliptic curve $E_2$. We can express the evaluation of the isogeny $\varphi$ using function notation, passing a point $P$ into it:

$$ P \in E_1 $$
$$ \varphi(P) \in E_2 $$

A key property of an isogeny is that it must preserve the structure of the domain (input) curve's abelian group after mapping onto the codomain (output) curve. In other words, it is a [_homomorphism_](https://en.wikipedia.org/wiki/Homomorphism) between two curves.

Specifically, given $P, Q \in E_1$:

$$ \varphi(P) + \varphi(Q) = \varphi(P + Q) $$

Isogenies must also preserve the infinity point, mapping the infinity point of the domain (input curve) to the infinity point of the codomain (output curve).

Isogenies are great to work with for cryptography, because they can be computed in polynomial time, and as we'll see later can be efficiently represented with a very small amount of data - this will be crucial for constructing compact signature schemes.

### Affine Form

Let's see an example. Let $E_1$ and $E_2$ be elliptic curves defined over $\mathbb{F}\_{p^2}$. Let $\varphi : E_1 \rightarrow E_2$ be an isogeny from $E_1$ to $E_2$.

We can think of $\varphi$ as a set of rational polynomials acting on the $(x, y)$ curve point coordinates:

$$ \varphi((x, y)) = \left(\frac{g_1(x)}{h_1(x)}, y \frac{g_2(x)}{h_2(x)} \right) $$

Where:
- $g_1$, $h_1$, $g_2$, $h_2$ are polynomials defined over $\mathbb{F}\_{p^2}$
- $g_1$ and $h_1$ are coprime
- $g_2$ and $h_2$ are coprime
- $h_1$ and $h_2$ have the same roots

Maybe you can see how if $h_1(x) = 0$ (or equivalently $h_2(x) = 0$), then $\varphi$ outputs the point at infinity, $0_{E_2}$.

The _degree_ of an isogeny $\varphi$, denoted $\deg(\varphi)$ is simply:

$$ \deg(\varphi) = \max(\deg(g_1), \deg(h_1)) $$

### Kernel Form

However, the explicit/affine representation is typically not used for isogenies in practice. We'd have to store four polynomials which might each have very large degree. Computing the isogeny would be a chore.

More commonly, isogenies are represented by their kernel. The kernel of an isogeny $\varphi: E_1 \rightarrow E_2$ is denoted $\ker(\varphi)$, which is the set of points which $\varphi$ maps to $0_{E_2}$.

$$ \ker(\varphi) = \\{ P \in E_1 : \varphi(P) = 0_{E_2} \\} $$

A magical fact: Any isogeny can be _almost_ uniquely identified by its kernel.

> Why "almost"?

### Isomorphisms

Well basically every elliptic curve is part of a distinct _isomorphism class._ Isomorphisms are just degree-1 isogenies: A linear change of coordinates.

This is kind of like how every integer $d \in \mathbb{Z}$ is part of some _residue class_ if you reduce it modulo some other integer.

### Automorphisms
TODO

### Endomorphisms
TODO

### Frobenius Morphism
TODO

### Point Multiplication
TODO
- Degree of $[n]$ is $n^2$.

### Separability
TODO
- Cyclic isogenies

### Duals
TODO

### Velu's Formula
TODO

### The Isogeny Graph
TODO


## Torsion Groups
TODO


## Quaternion Algebras
TODO


## Endomorphism Rings
TODO

## SQIsign

SQIsign is a [3rd-round finalist of the NIST PQC standardization competition](https://groups.google.com/a/list.nist.gov/g/pqc-forum/c/LXoTAe5AN78/) (Also see [this report](https://csrc.nist.gov/pubs/ir/8610/final)). It is a cryptographic signature scheme based on all the isogeny math we have learned up to this point, and its security rests on the assumption that the supersingular isogeny problem (and equivalently, the endomorphism ring problem) is hard.

To build SQIsign from scratch, we start with a _base finite field_ $\mathbb F_p$. For efficient field arithmetic we assume $p \equiv 3 \mod 4$ and $p > 3$. Some examples of such primes chosen by the SQIsign team:

| Security Level (bits) | Prime $p$ |
|-|-|
| 128 bits (NIST-I) | $5 \cdot 2^{248} - 1$ |
| 192 bits (NIST-III) | $65 \cdot 2^{376} - 1$ |
| 256 bits (NIST-V) | $27 \cdot 2^{500} - 1$ |

Unlike in traditional ECC, we don't stop there. We need an [_extension field_](#Extension-Fields) $\mathbb F_{p^2}$ which we build on top of the base field $\mathbb F_p$ as described in an earlier section.

TODO


## TODO sources

- https://sites.math.washington.edu/~smith/Teaching/504/504.pdf
- https://mathworld.wolfram.com/EllipticDiscriminant.html
- https://web.math.princeton.edu/~jl5270/talks/bezoutsTheorem.pdf
- https://ocw.mit.edu/courses/18-783-elliptic-curves-spring-2021/597144daafd05ed68ba5145a505148cc_MIT18_783S21_notes2.pdf
- https://andrea.corbellini.name/2015/05/17/elliptic-curve-cryptography-a-gentle-introduction/#algebraic-addition
- https://eprint.iacr.org/2017/212.pdf
- https://eprint.iacr.org/2009/213.pdf
- https://eprint.iacr.org/2017/293.pdf
- https://eprint.iacr.org/2017/1198.pdf
- https://eprint.iacr.org/2022/880.pdf
- https://math.stackexchange.com/questions/3189147/divisor-on-elliptic-curve
- https://arxiv.org/pdf/1310.7789
- https://arxiv.org/pdf/2410.06123
- Adaptor sigs:
  - https://eprint.iacr.org/2024/561.pdf
  - https://eprint.iacr.org/2021/150.pdf


## Sources

- https://www.pdmi.ras.ru/~lowdimma/BSD/Silverman-Arithmetic_of_EC.pdf ([alternative link][silverman])
- https://sqisign.org/spec/sqisign-20250707.pdf
- https://troll.iis.sinica.edu.tw/ecc24/slides/1-02-intro-isog.pdf

[silverman]: https://www.semanticscholar.org/paper/The-arithmetic-of-elliptic-curves-Silverman/7d62cc6267a4c9f513b45a874fdcd7d6582c0cdb
