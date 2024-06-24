---
title: Off-Chain Ticketing for Discreet Log Contracts
date: 2024-01-04
mathjax: true
category: scriptless
---

<small>This post is an updated and ever-green duplicate of [my original email to the dlc-dev mailing list](https://mailmanlists.org/pipermail/dlc-dev/2023-November/000182.html) in November 2023. Also see [this post I made on DelvingBitcoin](https://delvingbitcoin.org/t/off-chain-dlc-ticketing-systems/214/3).
</small>

I'm going to assume readers are already familiar with a bunch of Bitcoin technologies. The protocol I'm proposing here builds on the following:

- [The Bitcoin Lightning Network](https://lightning.network)
- [Discreet Log Contracts (DLCs)](https://www.dlc.wiki/)
- Public Key Aggregation using techniques like [MuSig](/cryptography/musig/)
- [Adaptor Signatures](/scriptless/adaptorsigs/)

## Problem

A bunch of players want to participate in a DLC together. With a traditional DLC, all players would deposit their buy-in money on-chain into a multisignature contract, and pre-sign a bunch of Contract-Execution Transactions (CETs) which pay them each different amounts depending on an outcome which some Oracle(s) will sign. Once the Oracle signature is published, the correct CET can be unlocked and published, paying out the winner(s).

This works great for small numbers of players betting with large amounts of money. One of the first publicly known demonstrations of a DLC was a [2-person bet on the results of the 2020 USA presidential election](https://www.coindesk.com/tech/2020/09/15/discreet-log-contracts-are-bringing-private-scriptless-smart-contracts-to-bitcoin/).

This approach becomes less practical if the DLC buy-in costs are small and the number of players is large, such as in lotteries, or communal betting pools. As the number of players increases, the cost of transacting on-chain increases. With smaller buy-in costs, players are giving up proportionally more of their money to on-chain mining fees.

On-chain DLCs simply are not scalable to large multi-player contracts.

## Solution

I created a protocol in which a single _Market-Maker_ with sufficient free capital can trustlessly front the overall value of the DLC, and charge players buy-in costs over the Bitcoin Lightning Network. If winning players cooperate, the winners' payouts can also be issued over the Lightning Network as well. The optimal case results in publishing three on-chain transactions which are indistinguishable from normal P2TR transactions. The on-chain footprint is the same regardless of how many players buy-in, or how many players are paid out at the end.

This concept was originally geared towards provably fair lotteries. [I made a more detailed blog post about that use-case here](https://conduition.io/scriptless/lottery/). At the end of that article, I briefly note how the strategy could be generalized beyond simple lotteries to arbitrary DLCs. Here I'll elaborate on how this methodology can be applied generally to _any_ DLC, not just a lottery.

## Concept

Let there be a set of $n$ players who have pubkeys $\\{P_1, P_2, ... P_n\\}$.

Let $\Delta$ be some block delay within which a transaction could reasonably be mined, e.g. 144 blocks.

The outcome of the DLC will be signed by an oracle who promises to sign one of a set of outcome messages $\\{m_1, m_2, ...\\}$ using nonce $R$. A message $m_i$ if signed would unlock the point $S_i = R + H(R, D, m_i) \cdot D$, where $D$ is the oracle's pubkey. Without loss of generality, we can also support multiple oracles.

Let's assume there is some _Market Maker_ with enough capital to cover the cost of the whole DLC up-front. Players will each buy _tickets_ for entry into the DLC, by paying the Market Maker off-chain via HTLCs or PTLCs over the Lightning Network, or even cross-chain using atomic swap techniques. A ticket is just a secret key or preimage which gives the player a chance - depending on the Oracle - to claim some of the on-chain capital committed by the Market Maker.

The Market Maker could be a contestant in the DLC himself, or he could be an independent bystander seeking to profit by leasing his on-chain capital to serve others.

## Example

Here's an example of a ticketed DLC with 3 players, Alice, Bob, and Carol, and a Market Maker who isn't participating in the DLC. We assume the oracle signs one of two possible messages, which dictates the outcome of the contract. If outcome $m_1$ is signed, then Alice and Bob divvy up the winnings taken from Carol. If outcome $m_2$ is signed, then Bob and Carol split the winnings taken from Alice in some other way.

\* <sub>I'm using PTLCs in this example, but a <a href="#HTLCs-instead-of-PTLCs">very similar approach can be used if only HTLCs are available.</a></sub>

<img src="/images/ticketed-dlc/contract.svg">

1. The Market Maker sets up (but does not sign) $\text{TX}\_{\text{init}}$, which deposits the DLC's entire value $\hat{v}$ into a 4-of-4 multisig address. Control of this contract is shared between the Market Maker and the three players, but the on-chain source of the funds is the responsibility of the Market Maker.

2. The Market Maker creates unsigned transactions to create a 3-stage contract.
    - Stage 1 begins with the outcome transactions $\text{TX}\_{\text{outcome } 1}$ and $\text{TX}\_{\text{outcome } 2}$ - one for every possible outcome. Each $\text{TX}\_{\text{outcome } i}$ spends $\text{TX}\_{\text{init}}$ to the control of a specific set of winners, depending on the outcome.
    - From $\text{TX}\_{\text{outcome } i}$, the Market Maker creates two mutually exclusive transactions:
      - $\text{TX}\_{\text{split } i}$, which splits the DLC value $\hat{v}$ into separate payouts for each winner. It has a relative timelock of $\Delta$ blocks.
      - $\text{TX}\_{\text{reclaim } i}$, which pays to the sole control of the Market Maker after a relative timelock of $2 \Delta$ blocks.
    - For each player (a 'winner') who receives money from the DLC outcome, we add an output to $\text{TX}\_{\text{split } i}$.
    - Each output in $\text{TX}\_{\text{split } i}$ pays to a 2-of-2 escrow contract jointly owned by a winning player and the Market Maker.
    - Spending from each output in $\text{TX}\_{\text{split } i}$, the Market Maker sets up two mutually exclusive transactions:
      - $\text{TX}\_{\text{win } i j}$, which pays to the sole control of player $j$ after a relative timelock of $\Delta$ blocks.
      - $\text{TX}\_{\text{reclaim } i j}$, which pays to the sole control of the Market Maker after a relative timelock of $2 \Delta$ blocks.

3. The Market Maker sends these unsigned transactions to the players, who reply with partial signatures. The players take no issue with signing, because the players haven't yet invested any money into the DLC; The Market Maker is frolicking about with their own capital at this stage.

4. The Market Maker creates adaptor signatures on each $\text{TX}\_{\text{outcome } i}$, locked with the point $S_i$ (the oracle's locking point for outcome $i$).

5. The Market Maker generates a set of secret tickets $\\{t_1, t_2, t_3\\}$ - one for each player. Each ticket has a public point $T_i = t_i \cdot G$, where $G$ is the secp256k1 base point.

6. The Market Maker creates adaptor signatures on each $\text{TX}\_{\text{win } i j}$ locked with the point $T_j$, so that the ticket for player $j$ is needed to decrypt $\text{TX}\_{\text{win } i j}$ (the TX which pays out to player $j$). He also creates a set of adaptor signatures on each $\text{TX}\_{\text{split } i}$ locked with each potential winner's ticket. E.g. if Alice and Bob are winners in outcome 1, then $\text{TX}\_{\text{outcome } 1}$ could be published using _either_ Alice _or_ Bob's ticket secrets.

7. The Market Maker sends the encrypted signatures on all $\text{TX}\_{\text{outcome } i}$, $\text{TX}\_{\text{split } i}$, and $\text{TX}\_{\text{win } i j}$ transactions to the players.

8. The players verify and ACK the adaptor signatures.

9. All players pay a small fee to the Market Maker through a separate Lightning invoice. This prevents player spam and incentivizes the Market Maker. See the [discussion section](#Discussion) for more info.

10. The Market Maker signs and publishes $\text{TX}\_{\text{init}}$.

11. Once $\text{TX}\_{\text{init}}$ is confirmed, each player $j$ has an incentive to learn the ticket secret $t_j$ that encrypts $\text{TX}\_{\text{win } i j}$. By learning $t_j$, the player can enforce $\text{TX}\_{\text{split } i}$ followed by $\text{TX}\_{\text{win } i j}$ on-chain to claim winnings from any DLC outcome which pays to them. The Market Maker can sell each ticket secret $t_j$ to player $j$ using an off-chain point-time-lock contract. The price of the earlier fee from step 9 can optionally be factored into the ticket price.

12. Once all tickets have been purchased, and the outcome signature $s_i$ is published by the oracle, then the Market Maker has several options to settle the on-chain contract with each winning player:

<ol style="list-style-type: lower-alpha; margin-left: 30px;">
  <li>
    <i>(forceful, on-chain)</i> If the Market Maker is not cooperative, a winning player simply waits for the relative locktimes on $\text{TX}\\_{\text{split } i}$ and $\text{TX}\\_{\text{winner } i j}$ to mature and broadcasts them each sequentially. They can only do this if they have their ticket secret $t_j$.
  </li>
  <br>
  <li>
    <i>(single winner cooperates, on-chain)</i> If a winner wishes to receive their DLC winnings on-chain, she can cooperate with the Market Maker to sign a version of $\text{TX}\\_{\text{winner } i j}$ which has no relative locktime, and broadcast it. The two could even arrange a <a href="https://bitcoinops.org/en/topics/coinswap/">CoinSwap</a>, where the winner is paid out from a completely unrelated UTXO, owned by the Market Maker.
  </li>
  <br>
  <li>
    <i>(single winner cooperates, off-chain)</i> Each winner can adaptor-sign a settlement transaction with no locktime which refunds an output of $\text{TX}\\_{\text{split } i}$ to the Market Maker, and then sell the adaptor secret key to the Market Maker for an off-chain payout - effectively selling the Market Maker the right to reclaim their own on-chain capital. Such a settlement TX would supersede $\text{TX}\\_{\text{winner } i j}$, which is locked until $\text{TX}\\_{\text{split } i}$ has at least $\Delta$ confirmations.
  </li>
  <br>
  <li>
    <i>(all winners cooperate, off-chain)</i> [OPTIMAL] If every DLC winner cooperates with the Market Maker in the above way, they can all agree that the whole output of $\text{TX}\\_{\text{outcome } i}$ belongs to the Market Maker now, and so jointly sign a new transaction refunding all of $\text{TX}\\_{\text{outcome } i}$ (the entire DLC value $\hat{v}$) straight to the Market Maker with no locktime. This would supersede $\text{TX}\\_{\text{split } i}$, reducing the on-chain footprint to constant-complexity regardless of how many winners were involved. If some winners want to receive payouts on-chain, they can follow the same process, except they sell their adaptor secrets to the Market Maker using on-chain (or cross-chain) PTLCs/HTLCs.
  </li>
</ol>

## Discussion

Assuming a player can learn $s_i$ (the discrete log of $S_i$) from the oracle, then they can decrypt and publish $\text{TX}\_{\text{outcome } i}$ independently without the Market Maker's cooperation. However, by itself this is not useful to the player, because the market maker will use $\text{TX}\_{\text{reclaim } i j}$ to return the money to himself after its relative locktime of $2 \Delta$ blocks matures.

If player $j$ knows their ticket $t_j$ as well as $s_i$, they can decrypt and publish $\text{TX}\_{\text{split } i}$ followed by $\text{TX}\_{\text{win } i j}$ to claim their winnings independently (under outcome $i$). This is what makes tickets valuable and worth purchasing.

Nothing forces players to buy a ticket. A player could feign interest but abstain from actually purchasing a ticket. Players who abstain in this way will force the Market Maker into assuming their position in the DLC, creating counterparty risk.

If the Market Maker is unwilling to expose themselves to any counterparty risk, they can use [HODL invoices](https://voltage.cloud/blog/lightning-network-faq/understanding-hold-invoices-on-the-lightning-network/) to accept fees and ticket payments, only revealing ticket secrets once all players have active PTLC/HTLC offers for their tickets. If a player paid the initial fee but did not buy a ticket, then the Market Maker can take the fee as payment for wasting their time and locking up their capital for no reason. <!-- (Is there a better system there? more investigation needed) -->

## Benefits

- No on-chain association between DLC contestants.
- Minimal on-chain footprint (one TXO in, one TXO back out) is achievable.
- Market maker is not trusted with custody of funds.
- Market maker can be incentivized by charging fees.
- If using PTLCs, the contract's happy path consists entirely of taproot key spending (great for fungibility).
- If using HTLCs, this protocol could be executed via LN today, no new BOLTs, opcodes, or sighash types required.

## Use Cases

- Lotteries
- Multi-player games (roulette, betting pools, poker)
- Crowd-funding

## HTLCs instead of PTLCs

To support classic Lightning HTLCs available today, we simply rephrase the protocol such that the ticket secret $t_j$ is a preimage, and $T_j = H(t_j)$. Instead of adaptor signatures on each $\text{TX}\_{\text{win } i j}$, we instead encumber the relevant output of $\text{TX}\_{\text{split } i}$ with an HTLC script or tapscript tree like this:

```
<market_maker && P_j> OR
<P_j && preimage(T_j) && delay(delta)> OR
<market_maker && delay(2*delta)>
```

Off-chain payouts to winners can likewise be trivially converted to HTLCs.
