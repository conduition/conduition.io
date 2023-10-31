---
title: Announcing the MuSig2 Rust Crate
date: 2023-10-31
mathjax: true
category: code
---

I am proud to announce...

<p style="font-size: 130%">
  <a href="https://github.com/conduition/musig2">
     The first <b>publicly-available</b> and <b>Bitcoin-compatible</b> Rust implementation of the MuSig2 protocol!
  </a>
</p>

<sub>(at least, the first judging by what I could find)</sub>

[Detailed API documentation is available here](https://docs.rs/musig2/latest/musig2/).

## What?

The [MuSig2 protocol](https://eprint.iacr.org/2020/1261) allows a group of people who don't trust each other to cooperatively sign a message, and then aggregate their signatures into a single signature which is indistinguishable from a signature made by a single private key.

The group collectively controls an _aggregated public key_ which can only create signatures if everyone in the group cooperates (AKA an N-of-N multisignature scheme).

In a previous article several months ago, [I described the older MuSig1 protocol](/cryptography/musig), diving into the algebra behind it and dissecting why it works. MuSig2 is an upgrade to MuSig1, optimized to support secure signature aggregation with only **two round-trips of network communication** instead of three.

My implementation is fully compatible with the [BIP-0327](https://github.com/bitcoin/bips/blob/master/bip-0327.mediawiki) and [BIP-0340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki) specifications.

## Usage

A collection of public keys can be aggregated together into a [`KeyAggContext`](https://docs.rs/musig2/latest/musig2/struct.KeyAggContext.html) like so:

```rust
use secp256k1::{SecretKey, PublicKey};
use musig2::KeyAggContext;

// Public keys should be sorted in some canonical fashion, e.g.
// client-then-server, or lexicographical order.
let pubkeys = [
    "026e14224899cf9c780fef5dd200f92a28cc67f71c0af6fe30b5657ffc943f08f4"
        .parse::<PublicKey>()
        .unwrap(),
    "02f3b071c064f115ca762ed88c3efd1927ea657c7949698b77255ea25751331f0b"
        .parse::<PublicKey>()
        .unwrap(),
    "03204ea8bc3425b2cbc9cb20617f67dc6b202467591d0b26d059e370b71ee392eb"
        .parse::<PublicKey>()
        .unwrap(),
];

let key_agg_ctx = KeyAggContext::new(pubkeys).unwrap();

// This is the key which the group has control over.
let aggregated_pubkey: PublicKey = key_agg_ctx.aggregated_pubkey();
assert_eq!(
    aggregated_pubkey,
    "02e272de44ea720667aba55341a1a761c0fc8fbe294aa31dbaf1cff80f1c2fd940"
        .parse()
        .unwrap()
);
```

The `KeyAggContext` can optionally be _tweaked_ with additional commitments, such as a [BIP341 taproot script commitment](https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki), allowing the group to provably commit their aggregated public key to a specific value.

```rust
let tweak: [u8; 32] = sha256(/* ... */);
let tweaked_ctx = key_agg_ctx.with_taproot_tweak(&tweak)?;
```

The `musig2` crate provides an idiot-proof stateful signing API suitable for use by application developers or downstream protocol implementors. Rust's lifetime system ensures at compile time that secret nonces cannot be reused (which would suck).

Start by creating a [`FirstRound`](https://docs.rs/musig2/latest/musig2/struct.FirstRound.html), in which you exchange nonces with your co-signers.

```rust
use musig2::{FirstRound, PubNonce, SecNonceSpices};

// The group wants to sign something!
let message = "hello interwebz!";

// We're the third signer in the group by index.
let signer_index = 2;
let seckey: SecretKey =
    "10e7721a3aa6de7a98cecdbd7c706c836a907ca46a43235a7b498b12498f98f0"
    .parse()
    .unwrap();

let mut first_round = FirstRound::new(
    key_agg_ctx,
    &mut rand::rngs::OsRng,
    signer_index,
    SecNonceSpices::new()
        .with_seckey(seckey)
        .with_message(&message),
)
.unwrap();

// We would share our public nonce with our peers.
let our_pubnonce = first_round.our_public_nonce();

// We can see a list of which signers (by index) have yet to provide us
// with a nonce. Our index (2) is naturally
assert_eq!(first_round.holdouts(), &[0, 1]);

// We receive the public nonces from our peers one at a time.
first_round.receive_nonce(
    0,
    "02af252206259fc1bf588b1f847e15ac78fa840bfb06014cdbddcfcc0e5876f9c9\
     0380ab2fc9abe84ef42a8d87062d5094b9ab03f4150003a5449846744a49394e45"
        .parse::<PubNonce>()
        .unwrap()
)
.unwrap();

// `is_complete` provides a quick check to see whether we have nonces from
// every signer yet.
assert!(!first_round.is_complete());

// ...once we receive all their nonces...
first_round.receive_nonce(
    1,
    "020ab52d58f00887d5082c41dc85fd0bd3aaa108c2c980e0337145ac7003c28812\
     03956ec5bd53023261e982ac0c6f5f2e4b6c1e14e9b1992fb62c9bdfcf5b27dc8d"
        .parse::<PubNonce>()
        .unwrap()
)
.unwrap();

// ... the round will be complete.
assert!(first_round.is_complete());
```

Once the first round is complete, you can finalize it into a [`SecondRound`](https://docs.rs/musig2/latest/musig2/struct.SecondRound.html). This is the only time the signer's secret key is needed.

```rust
use musig2::{PartialSignature, SecondRound};

// Use our secret key to produce a partial signature and finish round 1.
// Our signature is cached in `second_round`.
let mut second_round: SecondRound<&str> = first_round.finalize(seckey, message).unwrap();

// We could now send our partial signature to our peers.
// Be careful not to send your signature first if your peers
// might run away without surrendering their signatures in exchange!
let our_partial_signature: PartialSignature = second_round.our_signature();

second_round.receive_signature(
    0,
    "5a476e0126583e9e0ceebb01a34bdd342c72eab92efbe8a1c7f07e793fd88f96"
        .parse::<PartialSignature>()
        .unwrap()
)
.expect("signer 0's partial signature should be valid");

// Same methods as on FirstRound are available for SecondRound.
assert!(!second_round.is_complete());
assert_eq!(second_round.holdouts(), &[1]);

// Receive a partial signature from one of our cosigners. This
// automatically verifies the partial signature and returns an
// error if the signature is invalid.
second_round.receive_signature(
    1,
    "45ac8a698fc9e82408367e28a2d257edf6fc49f14dcc8a98c43e9693e7265e7e"
        .parse::<PartialSignature>()
        .unwrap()
)
.expect("signer 1's partial signature should be valid");

assert!(second_round.is_complete());
```

If all signatures were received successfully, finalizing the second round should succeed with overwhelming probability. The result is an aggregated Schnorr signature, indistinguishable from a single-signer context.

```rust
use musig2::CompactSignature;

let final_signature: CompactSignature = second_round.finalize().unwrap();

assert_eq!(
    final_signature.to_string(),
    "38fbd82d1d27bb3401042062acfd4e7f54ce93ddf26a4ae87cf71568c1d4e8bb\
     8fca20bb6f7bce2c5b54576d315b21eae31a614641afd227cda221fd6b1c54ea"
);

musig2::verify_single(
    aggregated_pubkey,
    final_signature,
    message
)
.expect("aggregated signature must be valid");
```

## Ecosystem Compatibility

I made this crate with the aim of maximizing compatibility with other popular Bitcoin-related packages in the Rust ecosystem, such as [the `bitcoin` crate](https://crates.io/crates/bitcoin) and its cryptographic backbone, [the `secp256k1` crate](https://crates.io/crates/secp256k1).

By default, the `musig2` crate relies on [the `secp256k1` crate](https://crates.io/crates/secp256k1) for elliptic curve cryptography, which is just a binding to [`libsecp256k1`](https://github.com/bitcoin-core/secp256k1). This is the same library which powers [Bitcoin Core](https://github.com/bitcoin-core/bitcoin).

For those interested in a pure-rust build, you can alternatively configure `musig2` to use [the `k256` crate](https://crates.io/crates/k256) for elliptic curve math instead. `k256` is maintained by the [RustCrypto](https://github.com/RustCrypto) team.

```
cargo add musig2 --no-default-features --features k256
```

## Contributing

[Pull requests, feature suggestions, and bug reports are all welcome!](https://github.com/conduition/musig2)

## Links

For full details on the `musig2` crate, check out:

- <a style="font-size: 120%" href="https://docs.rs/musig2/latest/musig2/">Detailed API documentation at docs.rs</a>
- <a style="font-size: 120%" href="https://github.com/conduition/musig2">The source code on Github</a>
- <a style="font-size: 120%" href="https://crates.io/crates/musig2">The crate metadata at crates.io</a>

## Disclaimer

The `musig2` crate is beta software, not covered by warranty and has not been independently audited.
