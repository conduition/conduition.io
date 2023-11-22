---
title: A Provably Fair Off-Chain Lottery
date: 2023-11-19
mathjax: true
category: scriptless
---

## Intro

In this document, I'll describe a protocol for a provably fair Bitcoin lottery in which players can pay into the jackpot using Lightning. If everyone cooperates, the winner can even receive their prize using Lightning too. This enables large scale federated lotteries with very low barriers to entry, and highly flexible ticketing systems, where 1 satoshi paid into the jackpot is literally equivalent to one ticket in the lottery. Players maintain total anonymity from one-another.

The lottery's jackpot capital is backed on-chain by a _market maker._ The market maker is trusted, but verifiable: While the market maker _could_ choose to award the jackpot to the wrong player (collusion is possible), any other honest player can immediately recognize this misbehavior, and publish a non-interactive fraud proof to warn others.

The market maker can publish irrefutable proofs demonstrating they picked winners fairly, and can commit himself to a deadline, where he must award the jackpot by a given block height, or else be financially punished.

Given more advancements in [BitVM](https://bitvm.org), it could even be possible for the market maker to commit himself to honest winner selection, allowing players to financially punish the market maker for choosing a winner dishonestly.

## Prerequisite Knowledge

- [Elliptic curve math basics](/cryptography/ecc-resources)
- [Merkle trees][merkle tree]
- [MuSig][musig]
- [Adaptor signatures][adaptor signatures]
- [Point-time lock contracts][ptlc]
- [Hash-time lock contracts][htlc]

## How?

Paying a Lightning Network invoice is essentially an exchange of money for a secret. Exposing one secret can do a lot if we set things up carefully.

My approach will be to construct a scenario where a prospective _player_ - someone who wants to buy into the lottery - need only pay a Lightning invoice in exchange for the market maker revealing a secret, called a _ticket_. The buyer can verify that, upon receiving the ticket, she can always claim jackpot (if she also wins). If a player wins but cannot present a valid ticket, the jackpot is returned to the market maker.

The winner is chosen based on a value which nobody can predict, but everyone can (eventually) agree on: A verifiable hash of a Bitcoin block at a pre-defined block-height _in the future._ For additional randomness, the winner hash is salted with the various parameters of the lottery, such as public keys and tickets.

By consulting the Bitcoin blockchain, players can verify who the correct winner is, and whether they were paid. If the market maker misbehaved and awarded money to the wrong player, then honest players can publish an irrefutable fraud proof, proving the market maker acted dishonestly.

## Lottery Registration

The market maker has a long-lived static public key $D$ which is public-knowledge and known to everyone.

1. To initiate a lottery, the market maker generates a random nonce $r$, and publishes the public nonce $R = rG$, with which he will later sign the lottery outcome.

2. Alongside $R$ the market maker publishes lottery metadata, such as:
    - the settlement block height $h$ - the block whose hash will be used to compute the winner.
    - the locktime delta, $\Delta$, which is some block delay during which a transaction can confidently confirm, e.g. 144 blocks (~24 hours).
    - the price per ticket (or price range, if applicable).
    - minimum/maximum number of players.
    - assorted implementation-dependent context info about the lottery.

3. A player who wishes to join a lottery pays a small deposit using a lightning invoice.
    - The deposit covers the cost of on-chain transaction fees by the market maker, and prevents DoS attacks.
    - Its value will be factored into the cost of the ticket, and depends on various factors like the on-chain fee market conditions, the size of the jackpot, the price of the ticket, and the minimum number of players in the lottery.
    - It should be as small as possible, because paying the deposit does not assure the player they can participate in the lottery.

4. The set of players in a lottery are identified by their public keys $\\{P_1, P_2, ... P_n\\}$, where $n$ is the number of players.
    - Players' pubkeys should be ephemeral, used only once per lottery (for privacy).
    - Each player $P_i$ specifies some satoshi value $v_i$ which they want to pay into the lottery. Each satoshi paid is one chance of winning. More sats = more chance of winning.
    - Under this protocol, the set of players and their ticket values must be fixed before the lottery can officially begin.
    - Players' public key keys should be arranged in some canonical sorting order, such as lexicographical order, so that each player is assigned a unique integer index.

5. Each player $P_i$ generates a random salt $q_i$, which they provide to the market maker. The salt ensures a player's ticket value cannot be guessed and analyzed by outside observers.

6. The market maker generates a _fairness secret key_ $f$, and computes its public key $F = f G$. This will be used to derive a provably fair lottery winner later.

7. The market maker generates a random set of secret tickets, one for each player: $\\{t_1, t_2, ... t_n\\}$.
    - Each ticket secret $t_i$ has corresponding public ticket points $T_i = t_i G$.
    - Alternatively, if your lightning invoices use [HTLCs][htlc] instead of [PTLCs][ptlc], think of each secret ticket $t_i$ as a preimage, and the ticket $T_i$ as a hash $H(t_i)$.

8. The market maker publishes to all players in the lottery:
    - The set of public keys $\\{P_1, P_2, ... P_n\\}$
    - The public tickets $\\{T_1, T_2, ... T_n\\}$
    - The ticket prices $\\{v_1, v_2, ... v_n\\}$
    - All player salt values $\\{q_1, q_2, ... q_n\\}$
    - The fairness pubkey $F = f G$.

9. Players verify that the salt value, pubkey, and ticket price they requested were not changed by the market maker.

10. Everyone uses the ordered set of ticket prices to compute the *win-windows* $\\{W_1, W_2, ... W_n\\}$.
    - Win-windows are used for weighted winner selection (the more you pay, the better your chances of winning).
    - Each player's win-window $W_i$ is a tuple of two numbers, $(u_i, w_i)$, where $u_i$ is simply the sum of all preceding ticket values, i.e. $u_i = v_1 + v_2 + ... v_{i-1}$, and $w_i = u_i + v_i$.
    - In other words, a win-window describe an interval which is as wide as the value $v_i$ of the lottery ticket that the player $P_i$ intends to purchase. Win-windows do not overlap. Specifically, they describe the range $[u_i, w_i)$.
    - Win-windows must be committed to explicitly, to allow fair-winner verification without revealing the ticket prices of any other players.

11. The total jackpot value can be computed as the sum:

$$ \hat{v} = \sum_{i=1}^n v_i = v_1 + v_2 + ... v_n $$

12. Players and the market maker independently compute a special [merkle tree] unique to this lottery, which is used for post-lottery fraud proofs and audits. The structure of this merkle tree allows for independent verification of almost any facet of a lottery, while exposing only a minimum of information.

First they compute the *ticket node hashes* $\\{N_1, N_2, ... N_n\\}$.

- Each ticket node hash $N_i$ is the root of a special [merkle tree] built from player-specific parameters:
  - Pubkey $P_i$
  - Ticket $T_i$
  - Ticket price $v_i$
  - Win-window $W_i$
  - Salt $q_i$
- The ticket node hash supports membership checks for any one or more of these parameters, without revealing (or allowing guessing of) the remaining parameters.

<img src="/images/lottery/ticket-node-diagram.svg">

The salt $q_i$ is essential if ticket price privacy is important. Otherwise a verifier can simply guess all the possible combinations of $W_i = (u_i, w_i)$ until they find the correct $\ell_v$.

The ticket node hashes are combined to form the *ticket merkle tree root* $\widetilde{T}$.

- This is the root of a [merkle tree] committing to all the ticket node hashes $\\{N_1, N_2, ... N_n\\}$.
- Each ticket node hash $N_i$ is a leaf in the tree at index $i$.

<img src="/images/lottery/ticket-root-diagram.svg">

Using merkle tree membership proofs within $\widetilde{T}$, any player can succinctly and non-interactively prove various assertions, such as:

- The pubkey $P_i$ was a participant in this lottery.
- The ticket $T_i$ was issued for this lottery.
- A ticket with a given price $v_i$ was issued for this lottery.
- A ticket with win-window $W_i$ was issued for this lottery.

Any such statement can be proven independently, or in tandem with one-another. This will be crucial for proving misbehavior later.

13. Finally, parties can compute the *lottery root hash* $L$.
    - $L$ is the hash $H(\widetilde{T}, F, R, \hat{v}, h)$ where:
      - $F$ is the fairness pubkey.
      - $R$ is the nonce which will be used to sign a winner.
      - $h$ is the settlement block height.
    - $L$ will be unique for any given lottery.

14. All parties compute a set of $n$ _outcome points,_ $\\{S_1, S_2, ... S_n\\}$, one for each possible winner:

$$ e_i = H(R, D, L, i) $$
$$ S_i = R + e_i D $$

- Each $S_i$ represents a public key which the market maker promises to unlock _if_ player $i$ wins this lottery, by revealing its discrete log $s_i = r + e_i d$. Only the market maker has the power to do this.
- The idea is similar to [Discreet Log Contracts][dlc]. It discourages equivocation: If the market maker signs two different players as the winners with the same nonce $R$ and key $D$, he reveals his long-lived secret key $d$, which discredits the market maker completely.
- Every outcome point $S_i$ will be used in concert with the ticket $T_i$ to guard the outcome where player $P_i$ wins the lottery.

15. All parties compute their joint pubkey, $P$ using [MuSig's key aggregation algorithm][musig] on $\\{D, P_1, P_2, ... P_n\\}$. This creates a multisignature pubkey which is jointly controlled by all players and the market maker.

At this point, all participants have what they need to start signing transactions for the on-chain lottery contract.

## Lottery Signing

1. The market maker creates the *lottery init transaction* $\text{TX}\_{\text{init}}$ which pays the whole jackpot value (fronted by the market maker) to a Taproot address of $P$, tweaked with the lottery root hash $L$.
    - Specifically, $\text{TX}\_{\text{init}}$ pays $\hat{v}$ satoshis to the tweaked pubkey $P' = P + H(P, L) \cdot G$. This output is called the _jackpot output._
    - The tweak with $L$ allows the participants to later prove that this jackpot output was associated with a particular lottery.

2. The market maker constructs a set of mutually exclusive transactions which spend from the jackpot output. There are different spending paths for every possible outcome.
    - A set of $n$ *outcome transactions,* $\\{\text{TX}\_{o1}, \text{TX}\_{o2}, ... \text{TX}\_{on}\\}$.
      - Each outcome transaction $\text{TX}\_{oi}$ spends the full balance of the jackpot output, paying to a 2-of-2 multisig address, owned by the market maker and a player $P_i$.
      - Each must have an absolute locktime of at most height $h$.
    - A set of $n$ *reclaim transactions,* $\\{\text{TX}\_{r1}, \text{TX}\_{r2}, ... \text{TX}\_{rn}\\}$.
      - One of these transactions will be used if a player registers, but fails to pay for a winning ticket. Unpurchased tickets will be treated as being owned by the market maker. If a player $P_i$ wins the lottery but can't claim their prize because they didn't buy their ticket secret $t_i$, then the market maker will use $\text{TX}\_{ri}$ to reclaim the jackpot.
      - Each must have a relative locktime of at least $2 \Delta$ blocks.
    - A set of $n$ *winner transactions,* $\\{\text{TX}\_{w1}, \text{TX}\_{w2}, ... \text{TX}\_{wn}\\}$.
      - One of these transactions will be used by an authentic winner to claim their jackpot on-chain using a ticket purchased from the market maker.

3. The market maker sends the following unsigned transactions each player $P_i$ in the lottery:
    - The init transaction $\text{TX}\_{\text{init}}$
    - All outcome transactions $\\{\text{TX}\_{o1}, \text{TX}\_{o2}, ... \text{TX}\_{on}\\}$
    - The reclaim transaction $\text{TX}\_{ri}$
    - The winner transaction $\text{TX}\_{wi}$

4. Every player verifies:
    - $\text{TX}\_{\text{init}}$:
      - [x] pays at least $\hat{v}$ satoshis to the correct taproot address $P'$, and
      - [x] has a locktime which is less than or equal to the current block height.
    - Every $\text{TX}\_{oi}$:
      - [x] spends the jackpot output from $\text{TX}\_{\text{init}}$,
      - [x] pays the entire balance to a 2-of-2 address owned by $P_i$ and the market maker's key $D$,
      - [x] has a reasonable fee rate, and
      - [x] has a locktime which is at most $h$.
    - $\text{TX}\_{ri}$:
      - [x] spends the output of $\text{TX}\_{oi}$, and
      - [x] has a relative locktime of at least $2 \Delta$.
    - $\text{TX}\_{wi}$:
      - [x] spends the output of $\text{TX}\_{oi}$,
      - [x] pays the entire balance to $P_i$, and
      - [x] has a relative locktime of at most $\Delta$.

If any of the above conditions fail, the player aborts.

5. In response, each player $P_i$ provides the market maker with a set of [MuSig][musig] partial signatures:
    - on all outcome transactions $\\{\text{TX}\_{o1}, \text{TX}\_{o2}, ... \text{TX}\_{on}\\}$
    - on their specific reclaim transaction $\text{TX}\_{ri}$
    - on their specific winner transaction $\text{TX}\_{wi}$

MuSig nonces can be pre-shared after the registration stage, for greater efficiency.

6. The market maker aggregates MuSig signatures on all transactions:
    - $\\{\text{TX}\_{o1},\text{TX}\_{o2}, ... \text{TX}\_{on}\\}$
    - $\\{\text{TX}\_{r1},\text{TX}\_{r2}, ... \text{TX}\_{rn}\\}$
    - $\\{\text{TX}\_{w1},\text{TX}\_{w2}, ... \text{TX}\_{wn}\\}$

...but he does NOT publish any transaction or its plaintext signature.

At this stage, the market maker is holding all the the signatures on all transactions. He _could_ broadcast $\text{TX}\_{\text{init}}$ and can unilaterally publish any $\text{TX}\_{oi}$ and wait to reclaim the funds using $\text{TX}\_{ri}$. He could also pay the jackpot out to any arbitrary player. However, the players would be fine with this, because the market maker would be toying around with his own money for no reason.

Here is a diagram of the structure of the pre-signed transactions now held by the market maker.

<img src="/images/lottery/tx-diagram.svg">

Let's see how he can convince players to start paying into the lottery.

## How to Make Tickets Valuable

1. The market maker uses an [_adaptor signature scheme_][adaptor signatures] to encrypt the final aggregated signatures on all of the _outcome_ and _winner_ transactions.
    - Each $\text{TX}\_{oi}$ signature is encrypted under the point $S_i$.
    - Each $\text{TX}\_{wi}$ signature is encrypted under the ticket point $T_i$.
      - If using [hash-locks][htlc] instead of [point-locks][ptlc], then the output of $\text{TX}\_{wi}$ must instead be encumbered by an [HTLC][htlc], which requires knowledge of the ticket preimage $t_i$.
    - The market maker computes a _fairness hint_ $z_i = s_i - f$.
    - This means:
      - If you have the adaptor-signed $\text{TX}\_{oi}$:
        - if you learn $s_i$, then:
          - you can use the hint $z_i$ to compute $f$, and
          - you can decrypt the signature and broadcast $\text{TX}\_{oi}$.
        - if someone publishes a valid $\text{TX}\_{oi}$, then you immediately learn $s_i$, and can use the hint $z_i$ to compute $f$.
      - If you have the adaptor-signed $\text{TX}\_{wi}$ and you learn the ticket $t_i$, then you can decrypt the signature and broadcast the transaction.
        - If using [hash-locks][htlc], you can claim the output of $\text{TX}\_{wi}$ once you learn the preimage $t_i$.

The core idea is, in order to claim the jackpot on-chain, a player needs to know their corresponding outcome secret $s_i$ _and_ the their ticket secret $t_i$. Knowing only one or the other is not financially beneficial to a player.

2. The market maker distributes all of these adaptor signatures and hints to every player.
    - It is important that every player receives a full set of all outcome transactions $\\{\text{TX}\_{o1}, \text{TX}\_{o2}, ... \text{TX}\_{on}\\}$, and their adaptor signatures, _not just the signature for their own preferred outcome transaction._ This is necessary for players to be able to build fraud proofs later.
    - Along with each adaptor signature on $\text{TX}\_{oi}$, the market maker sends the fairness hint $z_i$. The hint is essential because it enables players to learn $f$ from the decrypted adaptor signature, which is also crucial for fraud proofs.

3. Players verify the [adaptor signatures] given by the market maker, and abort if any are not vaild. A hint $z_i$ can be verified by confirming $z_i G = F - S_i$.

4. Once all players have confirmed their adaptor signatures are correct, the market maker can sign and publish $\text{TX}\_{\text{init}}$. The on-chain lottery contract is now live.

If a player stops cooperating at any time before the $\text{TX}\_{\text{init}}$ is published, the market maker can simply exclude them, take their deposit as a fee, and try again with the remaining players.

## Ticket Sales

At this stage, each player has valid adaptor signatures for every possible outcome transaction $\text{TX}\_{oi}$, locked by the outcome point $S_i$. They have a valid adaptor signature for their winner transaction $\text{TX}\_{wi}$ locked by the ticket point $T_i$, which pays the full jackpot from $\text{TX}\_{oi}$ to $P_i$. They have a set of hints $\\{z_1, z_2, ... z_n\\}$ which they can use to compute the fairness secret $f$ regardless of whichever outcome secret is revealed.

Each player also has verified that the money locked into the escrow contract by $\text{TX}\_{\text{init}}$ cannot be moved without their unanimous approval. The only way the jackpot output can be spent is through one of the pre-signed outcome transactions, which only the market maker can publish for now.

If the market maker decides to sign the player's index and publish $s_i = r + e_i d$, then the player can use $s_i$ to decrypt their outcome transaction $\text{TX}\_{oi}$. However, by itself, publishing $\text{TX}\_{oi}$ is useless to the player, because after $2 \Delta$ blocks, the money can be reclaimed by the market maker, using the reclaim transaction $\text{TX}\_{ri}$.

That is, unless the player can learn the ticket secret $t_i$. If she does, the player can decrypt $\text{TX}\_{wi}$, which, due to its relative timelock of only $\Delta$, can be published to claim the jackpot _before_ the market maker can use the reclaim transaction $\text{TX}\_{ri}$.

By publishing $\text{TX}\_{\text{init}}$, the market maker creates an incentive for players to learn their respective ticket secrets $\\{t_1, t_2, ... t_n\\}$. By learning her ticket secret, a player now stands to benefit, depending on which outcome transaction is published. From the time $\text{TX}\_{\text{init}}$ is mined up until block $h-1$, players can purchase tickets from the market maker by paying lightning invoices using [PTLCs][ptlc] (or [HTLCs][htlc]). They can also use on-chain PTLCs or HTLCs if desired.

Players should not buy tickets after height $h$, because the market maker already knows who the winner is once block $h$ is mined, and could be using this knowledge to rig the lottery.

### Counterparty Risk

Any tickets which have not been purchased by a player by block height $h$ are surrendered to the market maker. If a player wins the lottery and doesn't have their ticket, they can't claim the jackpot, and after a timeout it will be returned to the market maker.

By fronting the jackpot value himself, the market maker takes on counterparty risk. A player who puts down a deposit but doesn't pay for a ticket is effectively forcing the market maker to buy into the lottery, even though he may not wish to participate himself. For a market maker who runs many lotteries, this risk will balance out over time, especially since each player who forfeits their deposit is paying for it each time.

A market maker who does not wish to bear this risk or would prefer not to timelock their liquidity could use [HODL invoices][hodl invoices] to refund players' tickets and deposits automatically if not enough players buy in.

Future research could also seek out a robust protocol variant which allows the lottery to continue (with a smaller jackpot) even if some players refuse to purchase their tickets.

## Winner Choice

Once block $h$ is mined, ticket sales should stop and a winner must be chosen. How does the market maker choose the winner fairly, in a way that others can verify?

Remember our _fairness secret key_ $f$, and its public key $F = fG$? The market maker committed to the fairness key $F = f G$ as part of the lottery root hash $L = H(\widetilde{T}, F, R, \hat{v}, h)$. During registration and ticket sale phases, nobody knows the fairness secret key $f$ except for the market maker.

A naive design might use a hash of $L$ and $f$ to compute the winner, since $f$ is unknown to the players, and $L$ is a combination of randomized inputs from all players. $L$ was already committed to ahead of time, so the market maker can't change it. This seems promising, but it would not convince the players the outcome is honest. The market maker might be colluding with one of the players, choosing tickets or public keys maliciously to skew the outcome hash in favor of his chosen favorite.

The core problem is that _nobody,_ not even the market maker, should be able to predict the outcome in advance. However, _everyone_ (including passive observers) should be able to verify the outcome was fair. Does anyone know of a random number generator whose output everyone can agree on, but nobody can predict in advance?

### Block Hashes

The hashes of Bitcoin blocks are determined by miners, but miners cannot easily pick and choose block hashes without enormous physical energy expenditure. Most miners will publish the first block they can mine successfully. After the first `nbits` of leading zeros in the block hash, the remaining bits are effectively random, since they're the output of SHA256.

Because nobody can effectively predict block hashes more than one block in the future, we can use block hashes to salt the outcome which determines the winner of the lottery. Let $b$ be this locked-in block hash at height $h$.

The market maker should wait for block height $h$ to be mined, then wait for 2 or 3 extra confirmations just to be extra sure that there isn't a [blockchain reorg](https://learnmeabitcoin.com/technical/chain-reorganisation) which results in a change to $b$. Once the market maker is confident enough in the block $b$, he computes the winning satoshi index $w$ as:

$$ w = H(L, f, b) \mod \hat{v} $$

The distribution of $w$ will be slightly skewed if $\hat{v}$ is not a power of 2, but because $\hat{v}$ is so much smaller than the output of SHA256, this is negligible.

This diagram illustrates the various data points which go into selecting $w$.

<img src="/images/lottery/winner-choice-diagram.svg">

The only agent able to predict or influence $w$ would be a miner colluding with the market maker, who knows $f$ and has enough hashpower to rapidly produce a large enough selection of valid blocks at height $h$ to choose from. Such a miner might pick and publish a block whose hash results in a winning satoshi index $w$ landing inside their win-window. However, if such a miner exists, why would they bother using their obvious advantage in hashpower to rig lotteries, when they could be using that hashpower to mine more Bitcoin blocks to yield much greater profit?

The fairness secret $f$ is revealed when any outcome transaction $\text{TX}\_{oi}$ is published (or when $s_i$ is revealed). Revealing $f$ allows the correctness of the lottery outcome to be verified by all players, and also proves that the outcome was committed to in-advance by the market maker, but selected in an unpredictable fashion (assuming the market maker cannot influence the block hash $b$).

The actual winner's index $i$ can be found by simply iterating (or binary-searching) through the win-windows $\\{W_1, W_2, ... W_n\\}$ until a range is found which includes $w$. The index $i$ of that win-window is the winner index. The market maker signs this index and publishes the signature to all players to initiate on-chain settlement of the lottery contract.

$$ e_i = H(R, D, L, i) $$
$$ s_i = r + e_i d $$

## Settlement

The winning player $P_i$ who knows both $t_i$ and $s_i$ can prove to the market maker than the jackpot is rightfully theirs on-chain. After $\text{TX}\_{oi}$ is published, the player can offer the market maker a lightning invoice for $\hat{v}$ satoshis, in exchange for a signature on a new transaction, $\text{TX}\_{ri}'$ which is the same as $\text{TX}\_{ri}$ except with no relative locktime. This allows the jackpot to be withdrawn off-chain by the winner, while the market maker can reclaim the on-chain jackpot money before $\text{TX}\_{wi}$ matures.

Alternatively, if the player prefers to receive their jackpot with an on-chain transaction (or if the jackpot is too large for a lightning payment), then they can cooperate with the market maker to sign a new winner transaction $\text{TX}\_{wi}'$ with no locktime. Future research could also investigate the possibility of executing a cooperative [CoinSwap (AKA teleport transaction)][coinswap] to break the association between the market maker's jackpot output and the funds sent to the actual lottery winner.

If the market maker does not cooperate, the winner can simply wait for the relative locktime on the original $\text{TX}\_{wi}$ to mature, and publish it.

## Incentivizing an Unresponsive Market Maker

There is still one gap in the protocol: Handling a market maker who goes completely offline after everyone purchases their tickets.

The market maker is the only agent who can unlock the outcome transactions. If he goes dark once block $h$ is mined, then nobody can claim the jackpot (including the market maker himself). Assuming the market maker has already received payment for all tickets, he doesn't have incentive to complete the lottery protocol and publish an outcome signature. He earns no money by doing so.

To prove his intent to cooperate, the market maker can commit extra _collateral_ to the lottery, forcing himself to reveal one of the outcome secrets shortly after the settlement height $h$, or else forfeiting his collateral. The satoshi value of this collateral can vary, but to be a worthwhile incentive, it should be enough to put the market maker at a meaningful net loss if surrendered.

This *collateral output* should be added as a second output to $\text{TX}\_{\text{init}}$, paying to a multisig escrow contract address owned by all players and the market maker, similar to the jackpot output address.

_Except,_ unlike the jackpot output which is solely a multisig address, the collateral output address encodes a spending condition in a tapscript leaf which allows _anyone_ to take the collateral at block height $h + \Delta$ or higher. Alternatively, if appropriate for the fee market, the anyone-can-spend tapscript leaf could be replaced by a timelocked transaction which refunds to each player their respective ticket cost, or by a timelocked transaction paying to an address controlled jointly by all players, minus the market maker. The point is that after block $h + \Delta$, the market maker permanently loses control of this collateral.

From the collateral output, players sign an *acceptance transaction*, $\text{TX}\_{a}$. This transaction spends the collateral output, returning it to the market maker. The players expect the market maker to provide a set of $n$ adaptor signatures for $\text{TX}\_{a}$. The players only accept the collateral as valid if they can verify the adaptor signatures are encrypted under the points $\\{S_1, S_2, ... S_n\\}$. These adaptor signatures provide assurance that the market maker cannot reclaim his collateral output without exposing at least one of the outcome points. This incentivizes the market maker to reveal one of $\\{s_1, s_2, ... s_n\\}$ before block $h + \Delta$.

<img src="/images/lottery/collateral-commitment-diagram.svg">

The market maker _must not_ provide different encryptions of the same signature on $\text{TX}\_a$. Instead the players must sign the same transaction $n$ times, resulting in $n$ different aggregated signatures (i.e. $n$ distinct sets of [MuSig][musig] nonces are involved). If only one aggregated signature is used, then players would be able to use the related adaptor signatures to learn _all_ outcome secrets, and thus learn the market maker's long-lived secret key, once $\text{TX}\_{a}$ is published.

### Fees

As an alternative or auxillary inducement to publish an outcome, the market maker could charge a fee to the winner of the lottery, splitting the jackpot output at the winner transaction stage $\text{TX}\_{wi}$, with some pre-arranged fraction of the jackpot paid to the market maker.

## Succinct Fairness/Fraud Proof

This lottery protocol is not entirely trustless, as the market maker has the sole ability to determine which of the players receives the jackpot money. However, all the complexity described above is designed to assure players that, in the event of cheating by the market maker, they can construct an irrefutable proof that the market maker cheated. The market maker can similarly prove irrefutably that a lottery was executed honestly and fairly.

A succinct fairness/fraud proof consists of the following pieces of data:

- The settlement block height $h$
- The fairness secret key $f$
- The expected winner's index $i$
- The index of the actual winner $j$ (the one signed by the market maker)
  - If $j = i$, then the proof asserts fairness.
  - If $j \ne i$, the proof asserts fraud.
- The TXID of the published outcome transaction $\text{TX}\_{oj}$
- The expected winner's win-window $W_i$
- The actual winner's win-window $W_j$
- The actual winner's pubkey $P_j$
- The expected winner's ticket node hash $N_i$
- The actual winner's ticket node hash $N_j$
- The ticket merkle root hash $\widetilde{T}$
- A proof that the expected winner's win-window $W_i$ is a member of $N_i$
- A proof that the actual winner's win-window $W_j$ is a member of $N_j$
- A proof that both ticket node hashes $N_i$ and $N_j$ are members of the ticket merkle root $\widetilde{T}$
- The outcome signature pair $(R, s_j)$ attesting to player $j$ as the winner

### Verifying A Fairness/Fraud Proof

A verifier who already knows the market maker's signing key $D$ can:

- Verify the proof the win-window $W_i$ is a member of $N_i$
- Verify the proof the win-window $W_j$ is a member of $N_j$
- Verify the proof the ticket nodes $N_i$ and $N_j$ are members of $\widetilde{T}$
- Verify that $N_i$ and $N_j$ are indeed at their expected indexes $i$ and $j$ among the merkle tree leaves of $\widetilde{T}$
- Compute the fairness pubkey $F = f G$
- Look up the outcome transaction $\text{TX}\_{oj}$ on the blockchain to learn the jackpot output value $\hat{v}$.
- Compute the lottery root hash $L = H(\widetilde{T}, F, R, \hat{v}, h)$
- Verify the outcome signature $(R, s_j)$:
  - $e_j = H(R, D, L, j)$
  - $s_j G = R + e_j D$
- Look up the block hash $b$ of the block at height $h$
- Compute the winning satoshi index $w = H(L, f, b) \mod \hat{v}$
- Verify that $w$ is within in the win-window $W_i$
- Verify that $\text{TX}\_{oj}$ pays the jackpot to the [MuSig][musig] aggregated pubkey $D + P_j$

If any of the above verification steps fail, then the proof is invalid. Whether it was trying to assert fraud or fairness, its claim cannot proven true or false based on this proof.

If _all_ of the above verification steps pass, then the proof is authentic. It confirms:
- the market maker chose the player at index $j$ as the winner and awarded the jackpot to them.
- the player at index $i$ should have won this lottery

Whether the proof demonstrates fairness or fraud depends on whether $i = j$.
- If $i = j$, then the proof irrefutably demonstrates the market maker awarded the jackpot to the correct winner.
- If $i \ne j$, then the proof irrefutably demonstrates the market maker cheated by awarding the jackpot to the wrong winner.

Keep in mind that although a fairness proof demonstrates a lottery was conducted fairly, this proof cannot demonstrate that the players involved in the lottery were independent agents. The entire proof could be staged quite easily by the market maker to create the illusion of lottery volume. The lottery could have been the market maker buying tickets from himself, paying himself, playing around with his own money in a sandbox. It does not prove money actually changed hands.

## Privacy

Let's assume the best case scenario: The entire lottery went smoothly, a valid ticket-holding winner was chosen, and the jackpot was paid off-chain through a lightning invoice. We'll examine what can be seen or verified by passive observers. What does the lottery's audit trail look like?

If you don't know anything about a specific lottery and are just dragnet-scanning transactions on the blockchain, you won't be able to distinguish a successful lottery transaction from a normal payment transaction, except for the fact that taproot addresses are used.

You might be able to identify that a lottery occurred and its jackpot value, provided you can identify the UTXOs controlled by a market maker. But you won't be able to tell how many players there were, nor how much each player paid into the jackpot.

As the winner used a cooperative off-chain withdrawal, then you also won't be able to identify the ultimate destination of funds.

On-chain, all you see is:
  - $\text{TX}\_{\text{init}}$ which creates the jackpot at a taproot address, followed by
  - $\text{TX}\_{oi}$ which key-spends the jackpot to another taproot address, followed by
  - $\text{TX}\_{ri}'$ which key-spends the jackpot to _someone,_ possibly the market maker or possibly the winner.

In cases where a forceful resolution was required, you might be able to identify (based on the nSequence numbers in $\text{TX}\_{ri}$ or $\text{TX}\_{wi}$) whether the lottery was won by a valid ticketholder, or by the market maker himself. You might also be able to follow the money to see where the jackpot ends up on-chain.

If presented with a valid fairness/fraud proof, you will be able to see how much the correct winning player paid for their ticket, but you won't learn exactly how much the other players paid. You might gain a slight idea of how many players there were overall (by noting the depth of the merkle tree used for the ticket root hash $\widetilde{T}$), but that too can be obscured by using deeper and sparser merkle trees to construct $\widetilde{T}$.

## Generalizing for DLCs

This off-chain ticketing protocol could be generalized to work with any [Discreet Log Contract][dlc], not just random lotteries. A single untrusted market maker could provide on-chain capital for a DLC funded off-chain by many independent players. The market maker could even be one of the players themselves.

To generalize this principle to any DLC, the market maker sets up an $n$-of-$n$ multisig contract address, and creates a ticket for every player just like the lottery protocol. The players pre-sign a bunch of outcome transactions and payout transactions, and the market maker provides adaptor signatures locked by the DLC oracle's outcome points.

The market maker deposits the DLC capital into escrow. Each player pays for a ticket to the DLC, without which they would be unable to claim their share of the winnings (whatever the outcome might be).

The outcome and payout transactions can be constructed with timelocks such that if players cooperate with the market maker, they can receive their payouts privately off-chain, or via CoinSwap.

Throughout this process, the market maker would be *fully untrusted,* with trust only needed for the DLC oracle itself. All of it would be verifiable off-chain by the participants.

## Future Work

- To reduce counterparty risk, the market maker could require that all players buy tickets, utilizing lightning [HODL invoices][hodl invoices] to refund ticket payments in cases where not all players cooperate. The DLC or lottery could then proceed excluding the players who didn't pay their invoices.
- Market makers could use [CoinSwap][coinswap] to make on-chain withdrawals more private, breaking the link between the jackpot output and the actual prize payment.
- A market maker could set up a zero-knowledge lottery where players never learn each others' ticket prices. In such a setup, only the correct winner could prove fraud if the market maker misbehaves.
- Could the need for an initial deposit be removed? Could the deposit be used to buy some secret that contractually assures a player the right to participate in a lottery?
- The market maker who provides the capital could be fully decoupled from an oracle who signs bits of the latest block hash. This would turn the market maker into a fully untrusted entity who simply provides capital, while the actual outcome of the lottery would be decided by an blind oracle, who isn't privy to the details of every lottery.

More research is needed to solidify these ideas.

## Notation Reference

| Variable | Meaning |
|:------:|---------|
| $G$ | The secp256k1 curve generator point |
| $d$ | Market maker's secret key |
| $D = dG$ | Market maker's public key |
| $r$ | The market maker's secret signing nonce for a lottery |
| $R = r G$ | The market maker's public signing nonce for a lottery |
| $P_i$ | The pubkey for player index $i$ |
| $t_i$ | The ticket secret (or preimage) for player $i$ |
| $T_i = t_i G$ | The public ticket point (or hash) for player $i$ |
| $q_i$ | The ticket salt for player $i$ |
| $v_i$ | The price of the ticket for player $i$ |
| $W_i$ | The win-window for player $i$ |
| $\hat{v}$ | The total jackpot output value |
| $N_i$ | The ticket node hash for player $i$; A function of $(P_i, T_i, v_i, W_i, q_i)$ |
| $\widetilde{T}$ | The ticket root hash for all players; The merkle tree root of all $N_i$ |
| $L$ | The lottery root hash; Identifies the whole lottery and all players therein |
| $\Delta$ | A reasonable block delay to allow a transaction to confirm (e.g 144 blocks) |
| $\text{TX}\_{\text{init}}$ | The initialization transaction, which creates the escrowed jackpot output |
| $\text{TX}\_{oi}$ | The outcome transaction for the outcome where player $i$ wins, revealing $s_i$ in the process |
| $\text{TX}\_{ri}$ | The reclaim transaction for outcome $i$, in the case where player $i$ wins but didn't purchase their ticket |
| $\text{TX}\_{wi}$ | The winner transaction for outcome $i$, in the case where player $i$ wins and claims the jackpot |
| $b$ | The final block hash of the block at height $h$ |
| $w$ | The index of the winning satoshi; Used to select the winner among the win-windows |
| $s_i = r + e_i d$ | The outcome secret needed for player $i$ to win |
| $S_i = s_i G$ | The public outcome adaptor point for player $i$ |


[merkle tree]: https://en.wikipedia.org/wiki/Merkle_tree
[adaptor signatures]: /scriptless/adaptorsigs
[dlc]: https://bitcoinops.org/en/topics/discreet-log-contracts/
[musig]: /cryptography/musig
[coinswap]: https://bitcoinops.org/en/topics/coinswap/
[hodl invoices]: https://bitcoinops.org/en/topics/hold-invoices/
[ptlc]: https://bitcoinops.org/en/topics/ptlc/
[htlc]: https://bitcoinops.org/en/topics/htlc/
