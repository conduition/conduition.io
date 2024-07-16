---
title: Multi-Party Submarine Swaps
date: 2024-07-12
mathjax: true
category: scriptless
description: Scaling submarine swaps into a cooperative multi-party protocol for better efficiency.
---

[Submarine swaps](https://docs.lightning.engineering/the-lightning-network/multihop-payments/understanding-submarine-swaps) allow lightning users to trustlessly swap between on-chain UTXOs and lightning balances. They're basically atomic swaps for the lightning network, and they're incredibly useful for Lightning node operators to balance their channels, among other things.

As submarine swaps become increasingly important and more commonly used, it might be a good opportunity to see how we might better scale submarine swaps in an environment where more peers and providers are available to conduct swaps.

## Review

A traditional submarine swap is a 2-party atomic swap using two hash-time lock contracts (HTLCs): one on-chain on Bitcoin, and one off-chain on Lightning.

Say we have Alice, who wants to sell on-chain bitcoin in exchange for a lightning payment, and Bob, who wishes to buy Alice's on-chain funds with his off-chain lightning balance.

First Alice generates a random secret $s$ which only she knows.

Alice and Bob construct a 2-of-2 escrow address which gives Bob full spending power if he learns $s$, expressed using a hash-lock condition. Control of the funds returns to Alice after a certain blockheight $B$ is reached.

Example with descriptors:

```rust
tr(
  musig(<alice_pubkey>, <bob_pubkey>),
  {
    and(sha256(<hash>), pk(<bob_pubkey>)),
    and(after(<B>), pk(<alice_pubkey>))
  }
)
```

Alice deposits her coins into the 2-of-2 escrow contract, confident she can reclaim them at blockheight $B$, and that Bob cannot yet claim the coins because only Alice knows $s$.

Alice gives Bob a lightning invoice for the same amount of coins, using $\text{SHA256}(s)$ as the payment hash for the invoice. Bob can pay this invoice by offering Alice a lightning HTLC timelocked to at most $B - \Delta$ where $\Delta$ is some reasonable block delay. If Alice claims Bob's lightning HTLC (on or off-chain), then Bob learns Alice's preimage secret $s$, which he could then use to sweep Alice's on-chain coins. If Alice sneakily claims Bob's lightning HTLC at the last possible block $B - \Delta$, Bob will have $\Delta$ blocks to see $s$ on-chain and use it to sweep Alice's on-chain HTLC.

And voila! Bob and Alice have swapped on-chain and off-chain coins with one-another, and neither has any opportunity to cheat. To improve privacy and efficiency, Alice and Bob can cooperate once Bob pays the lightning invoice, by using [MuSig](/cryptography/musig/) to co-sign a transaction which surrenders the escrowed coins to Bob.

## Efficiency

Some submarine swap providers such as [LightningLabs' Loop](https://lightning.engineering/loop/) batch their on-chain transactions. When sweeping on-chain coins they receive, they do so in batched transactions to better consolidate large amounts of coins in fewer UTXOs. When funding submarine swap escrow contract addresses, they do so in batched transactions as well, with each output funding a distinct submarine swap contract.

There is still an efficiency bottleneck here though, because of the topology of the submarine swap protocol itself. We have many small nodes (users) all interacting only with a single submarine swap provider, such as Loop or Boltz. Users are not aware of each other's transactions at all, and so each submarine swap is a completely self-contained contract between a single user and a single swap provider. This creates waste.

Every single on-chain to off-chain submarine swap requires a separate funding transaction by users, since users are generally not aware of each other and so cannot batch their funding transactions together. Furthermore, each submarine swap creates its own independent funding output, and so even if funding transactions _are_ batched (as they would be in the case of Loop's off-chain to on-chain protocol), we still have $n$ distinct funded HTLC addresses, which must be resolved with $n$ additional transactions.

## Scaling

We can improve efficiency by scaling submarine swaps up from a single-taker protocol to an $n$-taker protocol. Instead of assuming a single maker and a single taker per swap, we will now assume a single maker **and $n$ takers** who are capable of authenticated communication, either P2P or through a proxy (e.g. the maker). These parties will all work together to execute a trustless atomic swap by aggregating their $n$ submarine swap contracts into a single funding UTXO.

This increases complexity and fragility of the protocol, but also improves on-chain efficiency dramatically. Let's see how it works.

## On-Chain -> Off-Chain takers

We'll first examine the case of on-chain to off-chain swaps by $n$ takers. In this scenario, we have two sides of the transaction:

- **The Takers:** A group of $n$ parties who want to swap smaller on-chain UTXOs in exchange for off-chain lightning channel balances.
- **The Maker:** An individual or business who wants to exchange their LN balance for on-chain coins.

Instead of funding $n$ distinct on-chain escrow addresses as with a traditional submarine swap, the takers coordinate to fund a single escrow contract, from which coins are paid out in a single transaction - either directly to the maker if the contract goes smoothly, or refunded back to the takers if something goes wrong.

1. The maker creates $n$ random secret preimages $\\{s_1, s_2, ... s_n\\}$ (one for every taker).

2. Takers and maker collaborate to create an $n$-of-$n$ taproot hashlock address which pays to the maker if they can reveal $\\{s_1, s_2, ... s_n\\}$.

Here is an example 3-of-3 hashlock expressed with descriptors:

```rust
tr(
  musig(
    <taker1_pubkey>,
    <taker2_pubkey>,
    <taker3_pubkey>,
    <maker_pubkey>
  ),
  and(
    hash160(<hash1>),
    hash160(<hash2>),
    hash160(<hash3>),
    pk(<maker_pubkey>)
  )
)
```

Using taproot, we can hide what could become a very large hashlock script off-chain if everyone cooperates, by using the 4-of-4 internal key to handle the cooperative spending path. We use `hash160` instead of `sha256` to save block space, while preserving the option to use Lightning HTLCs (which use plain `sha256`) with the same preimage secrets.

3. Takers construct a _funding transaction_ which spends the takers' UTXOs, paying into the multisig address (with possible change outputs). The takers **do not** sign the funding transaction yet.
4. The takers construct a _timeout transaction_ which returns their money. The timeout transaction distributes the _funding transaction_ output back to the takers. An absolute locktime of blockheight $B$ must be enforced on the _timeout transaction._
5. The takers and maker cooperatively sign the _timeout transaction._ The maker is OK with this, due to the timelock.
6. The maker sets up $n$ lightning HTLC offers which pay each of the $n$ takers their respective amounts for the swap. The lightning HTLC paying to taker $i$ uses payment hash $\text{SHA256}(s_i)$. Takers may use distinct amounts. Takers cannot _claim_ these HTLC offers yet, because the maker alone knows the preimages $\\{s_1, s_2, ... s_n\\}$ for each HTLC. The absolute timelock on each of these lightning HTLCs must be at least $B + \Delta$, where $\Delta$ is a reasonable block delay.
7. Once all takers have received their lightning HTLC offers, the takers cooperatively sign and publish the _funding transaction._
8. Everyone waits for the funding transaction to be mined.

The maker now has three choices.

### 1: Forceful (On-Chain)

The maker can use the preimages $\\{s_1, s_2, ... s_n\\}$ to claim the funding output via the $n$-of-$n$ hashlock spending path. Such a _claim transaction_ would reveal all preimages to the takers, who can use each preimage to claim their own individual lightning HTLC offered by the maker.

If the maker waits to sneak in their _claim transaction_ at the last possible moment, this will, at worst, give the takers $\Delta$ blocks to claim the lightning HTLCs offered by the maker.

### 2: Cooperative (Off-Chain)

The maker can give each of the preimages $\\{s_1, s_2, ... s_n\\}$ to each of the takers (one per taker). The takers can use these preimages to claim the lightning HTLCs offered by the maker. In exchange, the takers should cooperate with the maker to sign a transaction which releases the funding UTXO to the maker.

If any takers run away with their preimage without giving a signature to the maker in return, the maker still has the option to claim the funding output forcefully on-chain.

Note that it would be irrational for the maker to only give out _some_ of the preimages, and not others, as each preimage is effectively a right to claim some off-chain coins from the maker. If the maker wishes to be fully compensated on-chain, they must eventually reveal all preimages, or else none of them.

### 3: Timeout

The maker can choose not to reveal any of the preimages. The takers will thus be unable to claim the maker's lightning HTLC offers. Once blockheight $B$ is reached, any of the takers can publish the _timeout transaction_ to give all takers their money back. After $\Delta$ more blocks, the maker's lightning HTLC offers expire.

### Performance

If we had instead used $n$ traditional submarine swaps, the minimum on-chain footprint would have been:

- $n$ distinct funding transactions with at least one input and one output each
- $n$ distinct inputs to claim the funding UTXOs (possibly batched into a single TX)

In the optimal case, our batched approach reduces the on-chain footprint of these $n$ swaps to:

- One funding transaction with at least $n$ inputs, and at least one output (probably more, due to change outputs)
- One input to claim the funding UTXO (possibly batched with other funding UTXO claims)

It's worth noting that if $n$ is large, and some takers are uncooperative, the maker may need to publish a large number of RMD160 hashes and a large script in an on-chain witness, to forcefully claim the funding output. This might affect performance analysis and choice of $n$.

## Off-Chain -> On-Chain takers

Now let's see how this same approach works in reverse.

In this scenario, we have:

- **The Takers:** Multiple smaller parties who want to spend their off-chain lightning channel balances to receive small on-chain UTXOs.
- **The Maker:** An individual or business who wants to exchange their large on-chain UTXOs for off-chain lightning channel balance.

Instead of funding $n$ distinct on-chain escrow addresses as with a traditional submarine swap, the maker funds a single escrow contract, from which coins are paid out in a single transaction - either directly to the takers if the contract goes smoothly, or refunded back to the maker if something goes wrong.

1. The maker creates $n$ random secret preimages $\\{s_1, s_2, ... s_n\\}$ (one for every taker).
2. Takers and maker collaborate to create a $1$-of-$n$ taproot hashlock address.

Here is an example hashlock address with 3 takers expressed with descriptors:

```rust
taker_joint_pubkey = musig(
  <taker1_pubkey>,
  <taker2_pubkey>,
  <taker3_pubkey>
);

tr(
  musig(
    <taker1_pubkey>,
    <taker2_pubkey>,
    <taker3_pubkey>,
    <maker_pubkey>
  ),
  {
    {
      and(
        hash160(<hash1>),
        pk(taker_joint_pubkey)
      ),
      and(
        hash160(<hash2>),
        pk(taker_joint_pubkey)
      )
    },
    and(
      hash160(<hash3>),
      pk(taker_joint_pubkey)
    )
  }
)
```

Note how in this script, the takers are the joint recipients of 3 distinct hashlock spending branches, where _any one_ of the three preimages for `<hash1>`, `<hash2>` or `<hash3>` can be used by the takers to claim the coins.

3. The maker constructs a _funding transaction_ which spends the maker's UTXOs, paying into the HTLC address (with possible change outputs). The maker **does not** sign the funding transaction yet.
4. The maker constructs a _timeout transaction_ which returns their money. The timeout transaction spends the _funding transaction_ with an absolute locktime of blockheight $B$.
5. The takers and maker cooperatively sign the _timeout transaction._ The takers are OK with this, because of the timelock.
6. The takers cooperate to construct $n$ _claim transactions,_ which each split the funding UTXO among the takers using a different taproot hashlock spending branch. The takers cooperatively sign all $n$ _claim transactions,_ none of which may be published until one of the secrets $\\{s_1, s_2, ... s_n\\}$ is known. The takers are each OK with signing this, because it doesn't spend any of their own money. Each taker $i$ must have a fully signed claim transaction for their respective hash, $\text{RMD160}(\text{SHA256}(s_i))$, so that if taker $i$ learns $s_i$, they will be able to publish that claim transaction.
7. The maker signs and publishes the _funding transaction._
8. Everyone waits for the funding transaction to be mined.
9. The takers set up $n$ lightning HTLC offers which pay the maker their respective amounts for the swap using the payment hash $\text{SHA256}(s_i)$ for each taker $i$. Takers may use distinct amounts. The timelock on each of these HTLCs must be at most $B - \Delta$, where $\Delta$ is a reasonable block delay. ***The maker must wait until all HTLCs are active to settle any of them.***
10. The maker can use their preimage secrets $\\{s_1, s_2, ... s_n\\}$ to settle any or all of the lightning HTLCs offered by the takers. This reveals at least one preimage $s_i$ to at least one of the takers. Note that a rational maker should claim _all_ or _none_ of the takers' HTLCs, because exposing even a single $s_i$ will let the takers split the funding UTXO using one of their claim transactions.

Each taker now has two choices:

### 1: Forceful (On-Chain)

Any taker $i$ who learns preimage $s_i$ can use it to publish a _claim transaction_ (signed earlier by all takers). This atomic transaction distributes the maker's funds fairly among the takers.

If the maker waits to reveal all preimages $\\{s_1, s_2, ... s_n\\}$ at the last possible moment by resolving the lightning HTLCs (offered by the takers) on-chain, this will, at worst, give the takers $\Delta$ blocks to publish and mine a _claim transaction._

### 2: Cooperative (Off-Chain)

Once the maker has claimed all lightning HTLCs, and the preimages $\\{s_1, s_2, ... s_n\\}$ are revealed, the maker can cooperate with the takers to sign a new version of the claim transaction using the 4-of-4 internal musig key. This lets us hide the hashlock spending paths in the taproot commitment, improving privacy and on-chain efficiency.

If anyone fails to sign this new transaction, a taker can always fall back to publishing a forceful _claim transaction,_ as long as they do so before blockheight $B$, when the _timeout transaction_ becomes valid.

### Timeout

If, instead of revealing preimages, the maker simply does nothing, then the takers' lightning HTLC offers will expire at block height $B - \Delta$, returning their money. Later, at block height $B$, the maker can use the timeout transaction to sweep the whole funding UTXO back in one piece.

If the takers become unresponsive after the maker publishes the _funding transaction,_ then the maker simply waits until blockheight $B$ and publishes the timeout transaction.

### Performance

If we had instead used $n$ traditional submarine swaps, the minimum on-chain footprint would have been:

- $n$ distinct escrow-funding outputs (possibly batched together in one funding TX)
- $n$ distinct transactions to claim the funding UTXOs, with at least one input and one output each (batching unlikely)

In the optimal case, our batched approach reduces the on-chain footprint of these $n$ swaps to:

- One escrow-funding output (possibly batched in a larger meta-funding TX)
- One claim transaction to split the funding UTXO, with one input and $n$ outputs

In the case where some takers or the maker are uncooperative, the takers will need to use one of the hashlock branches to claim the on-chain funds.

## Less Griefing Plz

Although scaling submarine swaps up to multiple parties is clearly possible, the concrete efficiency gains are debatable, because they largely depend on all parties in the procedure cooperating. This is especially true for the on-chain to off-chain takers scenario, where even a single unresponsive taker can force the market maker to burn extra fees publishing a bunch of seemingly unnecessary hashes and preimages.

The same griefing risks exist for traditional submarine swaps, but are more pronounced in a multi-party setting because one bad apple can make the whole swap more expensive for everyone.

To discourage griefing by takers, a maker might implement a combination of techniques:

- Fees. The maker can either add fees onto the invoiced amount which takers must pay (in the case of off-chain to on-chain takers), or reduce the value of the HTLC the maker offers to takers (in the case of on-chain to off-chain takers). This incentivizes makers to offer swapping services and makes some griefing attacks more expensive.
- A deposit system. A maker may force takers to offer up an HTLC for a small percentage of their requested swap amount as a deposit, using a Lightning HOLD invoice. If the taker is cooperative during the swap, the maker can release the deposit back to the taker by canceling the invoice. If the taker misbehaves, the maker can settle the invoice, taking the deposit as punishment. This deposit is not trustless - the maker can take it unilaterally, and so a modicum of trust, accountability, or reputation is needed.
- Anonymous usage tokens. A taker could purchase ecash tokens in bulk from a maker, which can later be redeemed anonymously in exchange for the right to participate in a multi-party submarine swap with that maker.
- Fidelity bonds. These would allow anonymous makers or takers to prove they are committed to transacting honestly by sacrificing some number of bitcoins to earn a persistent maker/taker identity.

## Future Work

- Point-time lock contracts (PTLCs) on Lightning would enable significantly more private and efficient on-chain resolution of multi-party submarine swaps in either direction. What would a PTLC-powered multi-party submarine swap look like? How much more efficient would it be, exactly?
- Is it possible to perform $n$-to-$m$ submarine swaps, with $n$ on-chain UTXO sellers and $m$ buyers paying with Lightning?
