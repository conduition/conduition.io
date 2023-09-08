---
title: I'm Honest, I Swear! - Credible Threats of Private Key Exposure
date: 2023-09-08
mathjax: true
category: scriptless
---

Smart contracts on Bitcoin are usually written with the assumption that all of the parties involved distrust one-another. Such contracts are written to have rigid enforceable execution paths. If one party deviates from the cooperative path, they must always do so to their own detriment. This creates an incentive for everyone to cooperate and behave honestly.

There are some cases where relaxing this requirement from _trustless_ to _trust-minimized_ can result in major benefits. For instance, [Discreet Log Contracts (DLCs)](https://suredbits.com/discreet-log-contracts-part-2-how-they-work-adaptor-version/) rely on trust-minimized _oracles_ - agents who are trusted to publish signatures attesting to real-world events.

DLCs are risky, because a malicious oracle could participate in wagers dishonestly and steal people's money. On the other hand, they offer a simple and elegant way to introduce real-world information into the Bitcoin blockchain. DLC users can enter into wagers on these events, or utilize the information to create contingent execution paths in more complex smart contracts. Trust can be dispersed by aggregating the signatures of multiple oracles.

Oracles sign their outcomes using long-lived signing keys, and publish those signatures on some public forum, website, or other broadcast medium. One of the notable features of the DLC oracle construction is that if an oracle signs two different outcomes for the same event, they expose their long-lived signing key, rendering it useless for future events.

But private keys are just random numbers. Any of us can generate millions of them per second and we'll never run out. What stops such an Oracle from just changing their signing key after cheating? There needs to be some _consequences_ to the exposure of that key.

This led me to thinking: **What methods exist to *materially demonstrate* that exposing a private key is against someone's interests?** After all, _behavior_ cannot be proven or predicted mathematically. _Incentives_ are the only reliable way to concretely influence the behavior of rational agents.

This idea expands beyond the scope of Discreet Log Contracts, but DLCs are a well-known case where commitment to a long-lived key is crucial, so I'll be using DLC oracles as a concrete example.

# Credible Threats

It is tough to commit to keeping a key secret.

Let's say there's an oracle who we'll call Oscar. Oscar wants to be a DLC signing oracle using his secret key $x$ and corresponding public key $X = xG$, but nobody trusts him because he's new, and hasn't signed any events yet. What can Oscar do to demonstrate his signing key is precious to him?

It comes down to this: Oscar must create a _credible threat_ to himself. If $x$ is revealed, Oscar must _lose_ something. Let's explore some ways he might do that.

## Informational Loss

Oscar could encrypt some sensitive data with the key $x$ and publish the ciphertext for all to see. Perhaps $x$ is the decryption key to his email inbox, or to his credit card information. Perhaps $x$ would decrypt Oscar's personal information, or expose his biometric data to the world. _Risky games you're playing there, Oscar._

If Oscar cheats and exposes his private key, observers could decrypt Oscar's sensitive data.

This approach is challenging for bystanders to verify. How would we know the ciphertext Oscar publishes is really what he claims it is, if we can't decrypt it? There would need to be some trusted intermediary in-between us and Oscar, vouching for the legitimacy of Oscar's ciphertext. Perhaps Oscar's credit card company, who knows his card number, could sign a statement confirming that yes, this ciphertext is indeed Oscar's credit card number, encrypted under $X$.

For the most part, this threat isn't practically credible, especially if no trusted 3rd party is available. It just kicks the can further down the road.

## Reputational Loss

This kind of loss is hard to quantify. Exposing one's long-lived signing key by intentionally misbehaving is obviously a public-relations no-no for Oscar if he plans on acting as a Discreet Log Contract oracle again in the future. In a way, the true _loss_ which Oscar stands to incur here is the _loss of future earnings_ which he could accrue as a popular oracle.

But nothing can stop Oscar from simply changing his online identity every time he cheats, and setting up shop as a new Oracle to attempt his scam all over again.

This is why a track-record of honest signatures is critical for DLC oracles. Nobody will trust Oscar because he has no reputation to lose, and everything to gain by cheating.

Oracles who have a proven track record of signing accurate events on-schedule will be more trustworthy and thus more popular. This reputation gives the Oracle something to lose - _notoriety_ - which will be thrown away if they cheat. They would have to restart from scratch if they wanted to execute such a scam again.

## Energy Loss

Anyone familiar with Bitcoin has doubtless pondered the elegant _proof-of-work_ algorithm which underlies Bitcoin's decentralized consensus mechanism.

A proof-of-work is a compact, self-evident demonstration of computational energy expenditure which is quick to verify but hard to fake. Every Bitcoin block includes one, in the form of a _nonce_ - a number included in the block, such that the block's SHA256 hash starts with at least some requisite number of zero bits. The more zero bits required, the greater the _difficulty_ of finding such a nonce. Since SHA256 hash outputs appear to be random and irreversible, miners who choose these nonces have no way of finding the correct one except by guessing and checking _many, many, many times,_ i.e. by expending energy.

This allows nodes on the Bitcoin network to determine which chain of blocks has the most _energy_ spent on it. All honest nodes defer to that chain as the final source of truth.

We can apply this same idea to _keys_ instead of _blocks,_ with the goal of making Oscar's private key a scarce resource which he will not want to casually surrender.

### Proof of Key-Scarcity

Consider Alice, who only trusts a public key from Oscar if the SHA256 hash of that key starts with some number of zero bits. Alice will not accept any other kinds of keys from Oscar. Before Oscar can transact with Alice at all, he will need to make an up-front time and energy investment to generate a key which Alice will accept. Since the output of SHA256 appears random, Oscar has no better way to find such a key than by guessing and checking (expending energy).

The state of the art secp256k1 cryptography libraries can generate a fresh public key quickly, but not _nearly_ as quickly as modern GPUs and ASICs can compute SHA256 hashes. The bottleneck which slows Oscar down will not be the SHA256 hash, but the elliptic curve base-point multiplication needed to compute public keys.

To put the difficulty levels into perspective, on my computer, I was able to generate a key whose hash had 17 leading zeros in under 10 minutes. Since the difficulty increase is exponential as we increase the number of leading zeros, I could expect to find a keyhash with 30 leading zero bits with roughly a month or two of computation time.

```
17 leading zero bits
  secret key: 346e6648e7ebff18b8e48d07457eddbba71b5afe2b67833f5be8a8a49335d984
  public key: ab7fa53c6a2548bb38137724d57825dca1c70b0e3812ad10889f9bae3b08ea5d
  hash: 0000404c101397514ec03c2a36913b17dfe6e6fae3e132893345821bf35db05c
```

Oscar might randomly pick public keys and hash them to speed his search up dramatically. But this would be pointless, because once Oscar finds such a public key, he won't know its secret key and won't be able to use it to sign anything.

If Oscar cheats Alice and exposes his public key, Alice can publish a compact proof of his cheating, so that others who follow the same protocol as her will not trust that key anymore. Oscar will need to generate a new key, requiring a new up-front energy investment, all while nobody will do business with him.

### Problems

Whether this protocol could actually work in practice is debatable.

- It requires an up-front energy investment which cannot be recouped by Oscar. This might create a perverse incentive for Oscar to recoup his energy expenditure losses by exploiting the trust placed in his hard-won key.
- Oscar can run an exit scam. If Oscar doesn't care about transacting on this protocol ever again, he can cheat and expose his key without any additional consequences (beyond reputational loss).
- If generating a valid key is not sufficiently hard, Oscar can generate lots of them quickly, and the proof-of-work becomes moot. On the other hand, if generating a valid key is _too_ hard, Oscar will never be able to transact with anyone. The difficulty must be _just right_ so that Oscar is disincentivized from misbehaving. Difficulty must be scaled to match with Oscar's energy resources, which might not be known. If Oscar is working for a nation state, he will naturally have access to far more computational power and hardware than a potato farmer with a dusty 10-year old PC.

Still, it is an interesting concept to think about, and perhaps there are some situations in which it may work. Perhaps in tandem with other credible threat commitments, a self-evident proof-of-work might give a little more credibility to a long-lived signing key.

## Financial Loss

This is the most obvious and robust form of commitment to a secret, deeply familiar to any users of the Lightning Network. Oscar will not be likely to misbehave if he stands to lose more money than he gains by cheating. There are several ways to go about enforcing financial loss.

### Multisig Escrow

Oscar can commit some on-chain bitcoins into a multi-signature escrow contract, allowing those funds to be claimed by his counterparties if his key $x$ is exposed. This convinces those counterparties that Oscar does not want to reveal $x$.

This approach sounds straightforward, but has a number of implications which make it complex and unwieldy in many scenarios.

- Oscar must deposit his funds into a multisignature contract with counterparties who must be trusted not to collude with Oscar.
  - These counterparties must either be trusted public intermediaries, or they must _be_ the exact same suspicious parties who wish to be convinced of Oscar's honesty. Anyone else might be colluding with Oscar, and an escrow contract with them would not convince anyone else.
  - Oscar might not be capable of funding multisig contracts with everyone whom he wishes to convince. He may lack the capital to invest. A DLC oracle specifically might be signing an event which could be subscribed to by hundreds or even thousands of people. Oscar may lack the time and resources to make on-chain escrow funding transactions to every individual party who wants to trust his attestation.
- The amount of Oscar's money in escrow must, at all times, be greater than the amount of money Oscar could stand to gain by cheating, otherwise Oscar could cheat and net the difference.

### Off-Chain Bounty

If Oscar's commitment doesn't need to last very long, one highly efficient approach would be for Oscar to create a [point-time lock contract (PTLC)](https://suredbits.com/payment-points-part-1/) to any suspicious party Alice over a Lightning Network route, which pays money to Alice if she learns Oscar's signing key $x$. As long as the amount of money in the PTLC is more than what Oscar would stand to gain by cheating Alice, then Alice can be confident Oscar isn't going to misbehave and expose $x$, because Alice can claim Oscar's PTLC if he does. If Oscar remains honest, Alice will not learn $x$ before the PTLC expires, and Oscar will get his money back.

This way, Oscar doesn't need to send any on-chain transactions to prove his trustworthiness, allowing him to potentially execute numerous commitments in this fashion. Provided Oscar has the capital to invest to prove his trustworthiness to every subscriber individually, PTLCs could be a very practical method of key commitment.

Unfortunately Oscar cannot maintain this commitment for a long time, because intermediary Lightning nodes will not want to keep their liquidity locked up in Oscar's PTLC.

### Public Timelock Bounty

What if all other options are exhausted?

- no publicly trusted intermediaries are available
- Oscar cannot practically deposit funds into escrow with everyone he wants to convince with his commitment
- his commitment needs to last for a very long time
- he needs to stake a _LOT_ of collateral

Oscar still has a fallback option. Oscar can commit funds into a timelocked, single-signature contract address. The address would commit to a Bitcoin script such as this one.

```
<locktime>
OP_CHECKLOCKTIMEVERIFY
OP_DROP
<pubkey>
OP_CHECKSIGVERIFY
```

The locktime would be some arbitrary block height or timestamp in the future. How far in the future? However long Oscar would like to convince people he will remain honest.

Any funds which Oscar sends to this address are staked until the locktime condition matures. At maturation, Oscar can reclaim the money or renew the bounty, but _only if his secret key remains secret._

If someone else learns his key before the timelock expires, he can be sure that someone will try to sweep the staked money by spending it with a high-fee the moment that the timelock matures. If Oscar tries to fight back by double-spending their transaction with an even higher fee, his opponent(s) can one-up him, submitting yet another transaction with even higher fees. This vicious cycle would repeat until the whole UTXO is effectively donated to the miners as a fee.

A timelock bounty is a simple and totally trustless way to create a credible threat of loss, without the need to maintain 1-on-1 communication with everyone Oscar is doing business with. It can be verified by anyone who can verify the bounty UTXO's existence.

Oscar could simply publish the transaction ID of the bounty deposit to convince anyone of exactly how much money he has committed not to expose $x$. This is especially important in one-way trust relationships like DLC oracles, where the oracle isn't aware of whom they need to convince.

However, timelocks also have a down side: If Oscar _does_ misbehave, none of the people he cheated will be compensated for their losses. If Oscar is not a rational actor, he may decide to cheat and expose his key, purely for the sake of griefing others. Depending how much he benefits from cheating, the net financial loss to Oscar might be insubstantial. Those who choose to trust his commitment must assume Oscar is rational.

Further, a subscriber to Oscar's key has no way to verify how much money Oscar could stand to gain by cheating. It might happen to be such that Oscar has 10 BTC staked as a bounty, but can simultaneously cheat in 20 different 1-BTC contracts. If each of those individual contracts' participants are unaware of each other, they might _individually_ believe that Oscar's commitment is worth more than he could gain by cheating, but this is not so if Oscar can cheat the whole group _concurrently._

## Conclusion

There is no single best way to achieve a key commitment. The best way to commit to a key is probably a mixture of all the above methods. The exact context is a huge factor.

Discreet Log Contract oracles, for example, could exploit this niche by offering an insurance service: A subscriber to their signature could pay the Oracle to open a PTLC to the subscriber contingent on knowing some secret $x$, which pays the subscriber if the oracle reveals $x$ (presumably by cheating). They might offer the same service on-chain, but with higher fees.

In concert with a public timelock bounty, a signing key with proof-of-work, and their reputation on the line, perhaps we can indeed _minimize_ the trust needed for Oracles.
