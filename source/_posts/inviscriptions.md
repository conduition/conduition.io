---
title: Inviscriptions - Undetectable Bitcoin Inscriptions
date: 2023-12-13
mathjax: true
category: bitcoin
---

[Bitcoin Ordinals & Inscriptions](https://docs.ordinals.com/introduction.html) are causing a rift in the Bitcoin community, between those who love them and those who hate them. Personally, I find them silly and anachronistic. But today, rather than attempting to argue one side or the other, I'd like to demonstrate why personal feelings, mine or yours, are irrelevant.

I would like to prove that inscriptions can be constructed in such a way that they are _uncensorable,_ their content being revealed only after having already been included in a block. I hope this will demonstrate to the well-meaning but unimaginative supporters of [Luke's "bugfix" crusade](https://github.com/bitcoin/bitcoin/pull/28408) that their efforts at enforcing "spam filtering" of inscription transactions are ultimately doomed.

## Inscriptions Review

[Inscriptions](https://docs.ordinals.com/inscriptions.html) are a relatively simple tool for those already familiar with the workings of Bitcoin transactions. At a high-level, they need only a few steps to execute:

1. Construct an `envelope` script fragment, which contains a series of arbitrary data pushes which will not be executed.

```
OP_FALSE
OP_IF
  <"ord">
  <1>
  <"text/plain;charset=utf-8">
  <0>
  <"Hello, world!">
OP_ENDIF
```

2. Create a script pubkey (a locking script) which includes the `envelope` fragment. Since the `envelope` is a no-op, it is never executed and can't have any effect on the script execution. For example:

```
OP_FALSE
OP_IF
  <"ord">
  <1>
  <"text/plain;charset=utf-8">
  <0>
  <"Hello, world!">
OP_ENDIF
<pubkey>
OP_CHECKSIG
```

3. Send some bitcoins to a taproot address which commits to the above script pubkey as one of its script leaves.

4. Spend those bitcoins, revealing this script (and thus the inscription data) in the process.

The bitcoins are reclaimed by the owner, minus fees, and the arbitrary data (the inscription) is recorded in the witness data of the block in which the TX is mined.

## Critique

I see this approach as pointless and inefficient for all its most common use cases.

If the goal is to communicate and transfer ownership of a unique digital asset (a Non-Fungible Token), then one should instead defer to some authority or Oracle which certifies the unique ownership of that asset. That entity can publish an [OpenTimestamped](https://opentimestamps.org/) signature attesting to the ownership, or publish a signed transaction which includes a commitment to the new owner (e.g. using a Taproot-style commitment hash).

If the purpose of the inscription is to create a provenance anchor in time (e.g. to prove something existed before a certain time), then [OpenTimestamps](https://opentimestamps.org/) is a fast and zero-cost alternative - far simpler and with near zero on-chain footprint.

If the goal is to distribute data uncensorably over a P2P network, [IPFS](https://ipfs.tech/) or [BitTorrent](https://en.wikipedia.org/wiki/BitTorrent) are much faster and more efficient means to do so.

Yet, in spite of my subjective opinions, [there have been over 47 million inscriptions made to date, storing over 13 gigabytes of data on the Bitcoin blockchain, costing the uploaders a cumulative 1908 BTC ($79 million USD as of 2023-12) in transaction fees.](https://ordiscan.com/) Jeez.

Okay, clearly people are very willing to throw away their money for no reason, and bitcoin miners are happy to pick it up. So what's next?

## Luke's "Fix"

[This PR](https://github.com/bitcoin/bitcoin/pull/28408) is, as far as I can tell, the spark which ignited the controversy.

The PR is quite a simple change. It works by detecting the particular format of the inscription `envelope` inside the witness script block, and counting the size of the inscribed data pushes (the stuff inside the unreachable `OP_IF` block). This byte count is tested against the 80 byte limit normally applied to `OP_RETURN` outputs, called the "max data-carrier limit". If the data-carrier limit is exceeded, Bitcoin core labels the transaction as 'non-standard', meaning it would not relay that transaction to other nodes, treating it as spam.

Notably this does not prevent the inscription transactions from being considered valid under consensus rules and mined in a block. Doing so would require a hard fork, and is not backwards compatible given that numerous inscription transactions have already been mined.

Instead, it is merely a soft-block to allow individual node operators to exclude transactions which they feel are not aligned with their vision for how Bitcoin transactions should be used. Any node operator today can modify their node to run such soft-blocking rules. For example, perhaps your node would exclude any transaction which pays to an OFAC sanctioned bitcoin address, or transactions which contain large multisig scripts.

Just like those other examples of soft-blocking though, this is a narrowly-focused fix. It addresses only the specific format of inscription which is currently popular.

# Inviscription

I would like to demonstrate another kind of inscription which _cannot_ be filtered using a simple analytical test. I hope this will prove Luke's PR is pointless, by showing that the underlying functionality which enables inscriptions can be made highly fungible with normal Bitcoin transactions.

**Theorem:** _One can hide arbitrary data in a Bitcoin transaction's witness, such that the true plaintext data is only revealed _after_ the transaction is mined._

**Consequences:** If my theorem is correct, it means that filtering, blocking, or otherwise censoring transactions based on the _kind_ of data they contain is an _unreachable goal._ Bitcoin nodes which process and relay transactions would be hard-pressed to distinguish between an inscription transaction and a normal Bitcoin transaction. Any attempt to do so would likely result in numerous false positives and false negatives.

## Script Ciphers

We define concept of a _Script Cipher._ A Script Cipher is a layer of encryption between arbitrary message data (e.g. an inscription), and valid Bitcoin script bytecode.

A Script Cipher has two methods:

1. `encode(bytes, translator) -> fragments`

The `encode` method converts a finite sequence of bytes into a set of Bitcoin script fragments. Each of the `fragments` looks like a genuine Bitcoin locking script. For example:

```
OP_DUP OP_HASH160 <hash> OP_EQUALVERIFY OP_CHECKSIG
```

Or

```
<2> <pubkey1> <pubkey2> <pubkey3> <3> <OP_CHECKMULTISIG>
```

Or

```
OP_SHA256 <hash> OP_EQUALVERIFY <pubkey> OP_CHECKSIG
```

The `translator` is a _succinct_ but randomized seed which describes the mapping between bytes and scripts. It might be a seed for a cryptographically secure RNG, for example, or a key to a cipher.

A Script Cipher should have a very large number of possible `translator`s, so in practice a `translator` should be thought of as a decryption key, and the `fragments` collectively act as a ciphertext.

2. `decode(fragments, translator) -> bytes`

The `decode` method decrypts the `fragments` back into the arbitrary data bytes. Note that it requires the `translator`. A key property of a Script Cipher is that without the `translator`, the `fragments` produced by its `encode` method cannot be distinguished from regular Bitcoin locking scripts.

### Script Cipher Existence Proof

I'll pause for a second to prove that Script Ciphers exist, by describing a very simple instance of a Script Cipher.

Let `translator` be a randomly generated symmetric encryption key for an authenticated encryption scheme.

For the encoding procedure:

- Encrypt `bytes` with `translator`. This produces a `ciphertext`.
- Break the `ciphertext` into a stack of fixed-length `chunks`, each 32 bytes long.
  - If needed, pad the last chunk until its length is also 32.
- For each `chunk`, construct a simple P2PKH script composed as follows:

```
OP_DUP OP_SHA256 <chunk> OP_EQUALVERIFY OP_CHECKSIG
```

This set of script pubkeys forms the `fragments` array.

To decode, simply extract & collect all `chunks` from the `fragments`, then concatenate and decrypt them with `translator`.

This is a rudimentary and inefficient Script Cipher, but is by no means the only way of achieving this kind of ciphered encoding. One could also combine other classes of locking script, such as hash-time locks, or even generate the locking script fragments dynamically based on the message content and `translator`.

### The Envelope Script

But before we can send any transactions, we must compose an `envelope` script which contains all of the above `fragments`, plus one extra locking script condition which will be used to actually claim the inscribed bitcoins.

Each of the `fragments` is included in the `envelope` as a mutually exclusive locking condition, forming a nested tree of `OP_IF` and `OP_ELSE` branches which might look something like this:

```
OP_IF
  /* fragment */
OP_ELSE
  OP_IF
    /* fragment */
  OP_ELSE
    OP_IF
      /* fragment */
    OP_ELSE
      ...
    OP_ENDIF
  OP_ENDIF
OP_ENDIF
```

Carrying on from the trivial example where `fragments` is an array of P2PKH conditions, an `envelope` containing 4 `fragments` (encoding $4 \cdot 32 = 128$ bytes of ciphertext) might look something like this.

```
OP_IF
  OP_DUP OP_SHA256 <pk_hash> OP_EQUALVERIFY OP_CHECKSIG
OP_ELSE
  OP_IF
    OP_DUP OP_SHA256 <chunk1> OP_EQUALVERIFY OP_CHECKSIG
  OP_ELSE
    OP_IF
      OP_DUP OP_SHA256 <chunk2> OP_EQUALVERIFY OP_CHECKSIG
    OP_ELSE
      OP_IF
        OP_DUP OP_SHA256 <chunk3> OP_EQUALVERIFY OP_CHECKSIG
      OP_ELSE
        OP_DUP OP_SHA256 <chunk4> OP_EQUALVERIFY OP_CHECKSIG
      OP_ENDIF
    OP_ENDIF
  OP_ENDIF
OP_ENDIF
```

`pk_hash` is the hash of an actual valid pubkey, for which the inscription recipient user has the secret key.

In the above example, I placed the locking condition paying to `pk_hash` in the first `OP_IF` branch. But in principle the `pk_hash` branch could be inserted anywhere among the other `fragments` if desired. Even if the `pk_hash` branch is nestled in between, though, the ciphertext chunks must maintain their order for decoding to be possible.

Since each of the `chunks` is a piece of ciphertext, they appear indistinguishable from SHA256 hashes, and so appear to be valid alternative spending conditions. But only one P2PKH branch of the script can actually be used at spending time.

In a more sensible (read: efficient) scenario, unused branches could be hidden in the leaves of a TapScript merkle tree, to gain a script size reduction. However, script size reduction is the opposite of what our user wants here. In this approach, we are intentionally abstaining from decomposing this script from `OP_IF` branches into TapScript leaves so that we can include all of our `chunks` in the witness script.

## On Chain

We will now go about publishing our inviscription on-chain.

The next steps are very similar to standard inscriptions, except an inviscription needs at least _three_ transactions:

1. The commit transaction
2. The ciphertext transaction
3. The translator transaction

### Commit Transaction

This is very similar to a regular inscription commit transaction. The `envelope` script pubkey is converted into a Pay-to-TapRoot address, and the user sends bitcoins to this address.

### Ciphertext Transaction

The ciphertext transaction claims the bitcoins from the `envelope` address. In the above example where the `pk_hash` locking condition is the very first branch, one would use the following witness stack to unlock the coins.

```
<signature> <pk> <1>
```

These - along with the `envelope` script itself - would be included in the witness data for one of the inputs to the ciphertext transaction.

Because each `chunk` of ciphertext is indistinguishable from random data, a node observing this transaction would have no way of telling whether the `chunks` encode an inviscription ciphertext, or if the chunks are actual pubkey hashes which _could_ be used for spending coins.

Only after the `translator` decryption key is revealed can the `chunks` fulfill their true purpose, which leads us to the next stage.

### Translator Transaction

The translator transaction must reveal the `translator`, and also point to the appropriate ciphertext transaction input which contains the `envelope` script. Using both of these, observers can look up and decrypt the `envelope`.

Revealing the `translator` could be done by, for example, including it in a fixed-format `OP_RETURN` output, or in a specifically formatted witness script in similar style to the ciphertext's own `envelope` script. Unlike the `envelope` though, the translator transaction's structure must not be intentionally obfuscated - quite the opposite, as its purpose is to enable on-chain discoverability of the plaintext data.

The pointer to the ciphertext transaction can either be explicit, or implicit (by convention).

1. **Implicit Example:** The translator transaction spends from an output of the ciphertext transaction. Alongside the `translator`, we also include the input index of the ciphertext transaction.
2. **Explicit Example:** The translator transaction explicitly points to the TXID and input index of the inviscription's ciphertext `envelope`.

Either way, once the `envelope` script is found, it can be decoded into `chunks`, e.g. by filtering out the `OP_IF` branch used to claim the coins from the commit transaction, and then decrypting the extracted ciphertext. This is just an example though - The Script Cipher is free to specify how exactly encoding and decoding of the `envelope` works under a given `translator`.

However, the translator transaction's structure should be recognizable and standardized, so that anyone scanning the mempool or blockchain can detect and decrypt the `envelope` once they see the translator transaction.

### Diagram

<img src="/images/inviscriptions/tx-diagram.svg">

## Detectability of the Translator TX

> But wait, if the translator transaction can be detected, couldn't it be censored?

Technically yes, but there is very little incentive to do so.

The idea of inviscription is to use the ciphertext transaction's fungibility properties to sneak it into a block under the radar of any mempool-level filtering/censorship, and only afterwards to publish the translator transaction, ousting it as an inviscription.

Bitcoin users opposed to inviscriptions _could_ try to filter/censor translator transactions, but by that time, _the damage is already done_ as far as block-space consumption and fee-market inflation. These are the primary motivators for the inscription filtering/censorship debate today. Thus, censoring translator transactions has no practical gain for the censoring parties beyond griefing the inscriber. This renders the practice far less appealing, and less likely to occur.

Take street art as an analogy. Inscriptions are like graffiti, except permanent. Currently, vandals are painting buildings in broad daylight: Their progress is easy to observe, and thus easy to interrupt if we wanted to.

However if we start to interrupt them too much, then the inscribers will just wait until dark, and paint in the shadows while we're asleep. We wake up and find their works were completed in secret, and by then, nobody can remove them. The damage is already done.

Furthermore, even if _one_ translator transaction can be identified and effectively excluded from the blockchain, the ciphertext is already on-chain, so censoring nodes would need to ensure that _no other translator transactions_ for that inviscription ever make it onto the chain _in perpetuity,_ which is no small feat.

And even then, the inscribing user can still publish their `translator` off-chain to reveal the inscription data, and prove they inscribed bitcoins with said data. It just won't be detectable by on-chain scanning alone.

## Fungibility of the Ciphertext TX

To be meaningfully resistant to censorship, the ciphertext transaction cannot be easily distinguishable from a regular TapRoot script-spend transaction. While this holds for small transactions, nobody who transacts normal financial payments actually wants to publish TapRoot transactions which waste kilobytes of witness space in redundant nested `OP_IF` trees, when they could use a much more efficient TapScript merkle tree instead.

> Could nodes simply censor any transaction which includes a large number of mutually exclusive `OP_IF`/`OP_ELSE` paths in a witness script?

Yes, but envelope formats can be generalized beyond `OP_IF` branches. Using similar approaches, one could embed the ciphertext almost anywhere.

- In the TapRoot control block
- In the pubkeys of an `OP_CHECKMULTISIG` script
- In the timestamps supplied to `OP_CHECKLOCKTIMEVERIFY` or `OP_CHECKSEQUENCEVERIFY`
- In pushdata blocks which are consumed, or dropped by `OP_DROP` or `OP_CHECKMULTISIGVERIFY`
- In op-codes themselves

One could even set up the `envelope` script such that the ciphertext data must be appended to the witness stack to unlock the output of the commit transaction. For example, consider this envelope script pubkey:

```
OP_HASH160 <chunk1_hash> OP_EQUALVERIFY
OP_HASH160 <chunk2_hash> OP_EQUALVERIFY
OP_HASH160 <chunk3_hash> OP_EQUALVERIFY
...
<pubkey> OP_CHECKSIG
```

This simple script could only be unlocked by providing `<sig> ... <chunk3> <chunk2> <chunk1>` in the witness stack, where each `chunk` is a 520-byte chunk of the ciphertext. The ciphertext could be extracted by simply reading the chunks from the witness.

This is far less efficient than pushing the chunks in the `envelope` script pubkey, but it also binds spending of the bitcoins to the knowledge of the chunks. It makes the ciphertext a giant preimage for a hash-lock spending condition, which by any argument is a valid way to encumber Bitcoins.

> Couldn't we filter transactions containing an input that has a very large witness stack? Those are probably inviscription ciphertext transactions.

Technically yes, but the inviscription ciphertext could be broken up across multiple inputs to lower the footprint of any single witness. A single ciphertext TX could be broken up into a set of multiple smaller and unrelated ciphertext transactions, their true cohesive purpose revealed only later by the translator transaction. Any arbitrarily low limit imposed on witness size or transaction size could be bypassed by breaking the inviscription ciphertext up into smaller pieces spread among more transactions.

## Conclusion

Besides the methods I've discussed here, there are probably countless other ways of obfuscating and revealing arbitrary data on the Bitcoin blockchain. They all invariably appear to be _vastly less efficient_ than what the [current inscriptions standard](https://docs.ordinals.com/inscriptions.html) uses, both in terms of computational workload and on-chain storage requirements. And ordinals themselves are infinitely less efficient than simply using [OpenTimestamps](https://opentimestamps.org/) to prove data provenance off-chain.

If [Luke's PR](https://github.com/bitcoin/bitcoin/pull/28408) is merged, the most popular Bitcoin node implementation will no longer relay inscription transactions. Inscription users frustrated by this artificially-imposed barrier will, if pressed, seek out alternative inscription methods to bypass it. Inventive users will find the barrier to be a two-foot fence: easily bypassed by sacrificing efficiency.

Instead of preempting foolish on-chain behavior, it is best to let foolish behavior run itself into the ground while the agents behind it waste their money. Numerous similar hype cycles have occurred in this industry, and they all end the same way: A slow fizzle out as everyone slowly but inevitably migrates to faster, more efficient, lower cost alternatives. I believe same will happen to inscriptions.

We Bitcoiners just need to keep a cool head, avoid rushing into rash action, and let nature take its course.

In the meantime, [join me on Github in my efforts to reduce the on-chain footprint](https://github.com/ordinals/ord/discussions/2879) of downstream apps and protocols which are causing this inscription debate in the first place.
