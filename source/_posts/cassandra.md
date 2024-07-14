---
title: "Cassandra: My RESTful DLC Oracle API"
date: 2024-06-02
mathjax: true
category: code
---

# Cassandra

Cassandra is an unattended [Discreet Log Contract (DLC)](https://github.com/discreetlogcontracts/dlcspecs/blob/master/Introduction.md) oracle webserver written in Go and Rust. Her attestations are fully compliant with [the DLC specifications](https://github.com/discreetlogcontracts/dlcspecs), and so should be interoperable with any wallet or service which consumes the same class of announcements and attestations.

I've been working on her for some time, and I'm now confident enough in her to publish API documentation for Cassandra, in the hopes that the Bitcoin ecosystem at large will benefit from a benevolent and free oracle service, compliant with modern standards. If she becomes very popular, Cassandra's attestations may someday be gated behind a lightning or ecash paywall. For now, she is completely free and public!

## What is this?

Cassandra cryptographically announces & attests to a variety of real-world events and financial data from upstream sources automatically. You, dear user, may consume Cassandra's attestations to build conditional Bitcoin payment contracts which are contingent on the outcomes of certain events, or the prices of Bitcoin in different fiat currencies. Cassandra's cryptographic statements are exposed through the `conduition.io/oracle` API.

[Click hear to read more about how DLCs work](https://suredbits.com/discreet-log-contracts-part-1-what-is-a-discreet-log-contract/).

# API

To view general public information about the oracle:

```
$ curl https://conduition.io/oracle/info
```
```json
{
  "pubkey": "c3b1d269468f427ec56b4d0fa14c13aa4476fb05c708f8c3f036b97f839c2741"
}
```

Cassandra has two upstream event sources: ~**Polymarket**~ and **CryptoCompare**.

## Update 2024-07-14

After witnessing the unreliable nature of the Polymarket API demonstrated to me over time, I have updated Cassandra to stop announcing new Polymarket events. Polymarket's API is too brittle to use as a source of truth on which to base contractually binding signatures on which to stake real money.

- Events are often not resolved by their prescribed end date.
- Some events' data is invalid for no obvious reason (missing important data fields).
- Some events' outcomes and expected end dates are modified for no clear reason (which is illegal in a DLC protocol).
- Their API is rate limited, which prevents Cassandra from fetching timely updates for the numerous markets she is expected to track.

The description of Cassandra's Polymarket API has been removed in the interest of brevity. Existing announced polymarket events will be tracked and attested to, to the best of Cassandra's ability, but new polymarket events will not be announced. If you need to see the documentation for Cassandra's old Polymarket API, [here is a link to the now-removed API docs which are still viewable in my website's git history](https://github.com/conduition/conduition.io/blob/68be890d42d1936c8aab6a1b7c5a11544fe703d1/source/_posts/cassandra.md#polymarket-real-world-events).

The CryptoCompare event source is working just fine.

## CryptoCompare (Pricing Data)

Bitcoin is currently the only commodity/asset whose price is attested to. Pricing data is sourced from [CryptoCompare](https://www.cryptocompare.com/)'s API. Cassandra attests to hourly Bitcoin price candles for the following set of fiat currencies:

- USD
- EUR
- JPY
- GBP
- AUD
- CHF
- CAD
- SGD
- NZD

This list may change in the future, but existing announcements will always be honored as long as CryptoCompare's API remains available.

Cassandra makes 4 attestations per fiat currency - one for each data-point in a one-hour candle:

- Open price (the starting price at a specified candle time)
- Close price (the final price one hour after the specified candle time)
- Highest price in the hour
- Lowest price in the hour

These are known as `open`, `close`, `high`, and `low` respectively.

9 fiat currencies, with 4 high/low/open/close attestations per currency results in 36 attestations and 36 announcements per hour.

Cassandra announces CryptoCompare price events well ahead of time. Currently that lookahead period is 8 weeks, but this may be adjusted in the future.

Prices are signed using [digit decomposition](https://github.com/discreetlogcontracts/dlcspecs/blob/master/Oracle.md#digit-decomposition): The price is broken down into base 10 digits, and each individual digit in the price is signed as a string using a separate nonce. This allows downstream consumers of Cassandra's attestations to construct Contract Execution Transactions (CETs) for their Discreet Log Contracts with _much_ greater efficiency.


### `GET /announcements/cryptocompare/BTC/:currency/:timestamp/:pricetype`

- `currency` is a fiat currency in whose value Bitcoin's price will be measured (e.g. `USD`).
- `timestamp` is either:
  - A unix second timestamp. Should be an integer divisible by 3600, indicating the top of an hour.
  - An RFC-3339 timestamp, e.g. `2024-07-10T12:00:00Z`. Again, should be a specific hour.
- `pricetype` is any of:
  - `open`
  - `high`
  - `low`
  - `close`

The `timestamp` value indicates the time at the _beginning_ of the price candle which will be attested to. About one minute after the `timestamp` is reached, Cassandra will create attestations for the `open` prices in those currencies. One hour later, Cassandra will attest to the `high`, `low`, and `close` prices as well. We must wait the extra hour for high/low/close prices, as those prices could change up until the following one-hour candle begins.

Announcements for a given price candle are created 8 weeks ahead of the candle's open time.

Example:

```
$ curl https://conduition.io/oracle/announcements/cryptocompare/BTC/USD/2024-05-30T22:00:00Z/open
```
```json
{
  "announcement": {
    "announcementSignature": "040fdc3610a9743db98ff3300da6b8178d9022af0db0e1a6696d4cc72b306678a91968abc28c4f84bd529a81dca7526e0a361716f60faaaee240c77cef937184",
    "oraclePublicKey": "c3b1d269468f427ec56b4d0fa14c13aa4476fb05c708f8c3f036b97f839c2741",
    "oracleEvent": {
      "oracleNonces": [
        "509c2a8c14a6b6d546854e5b8b30ae7c759e8ba579686a85182360e0c76a67f3",
        "2c33eec229fced93a841e1cb49a326f6fe1aa58fb239f68f77df5008e1bc2b91",
        "538020743474563045e319a4aebccde3f71d5c75828b75e7f9284ca7920383fc",
        "9fb6eb2e8778f188355585e1a4775774ea4c1336b15d997ace9173adbdf79348",
        "9fad6983ee3a3b86cc0c1db8e0fdde4378543d3396857c5b2155f801fbe8ede7",
        "e45ab48436f99995580665994998b4f2811be77c6c32a3b8734bb5ca2ae48c85",
        "11860aaf68f0de2bf24fe83f93d936138b06c442b37d30071dd012eafef1e29a",
        "baf929e87166ad1eaf7c4f4dfa598c9a0939dae6875c698d1cd74a576973592a",
        "cb197a218ab319e0e63bc625426e094f94f1ffa91c59338f712da27bce49ed65",
        "baf0ccae8229a380e8dc6960c5d7d151256eea505fa713914d9a5b7c7b9eaa9e"
      ],
      "eventMaturityEpoch": 1717106400,
      "eventDescriptor": {
        "digitDecompositionEvent": {
          "base": 10,
          "isSigned": false,
          "unit": "USD/BTC open",
          "precision": -2,
          "nbDigits": 10
        }
      },
      "eventId": "cryptocompare-BTC-USD-open-1717106400"
    }
  },
  "serialized": "040fdc3610a9743db98ff3300da6b8178d9022af0db0e1a6696d4cc72b306678a91968abc28c4f84bd529a81dca7526e0a361716f60faaaee240c77cef937184c3b1d269468f427ec56b4d0fa14c13aa4476fb05c708f8c3f036b97f839c2741fdd822fd0186000a509c2a8c14a6b6d546854e5b8b30ae7c759e8ba579686a85182360e0c76a67f32c33eec229fced93a841e1cb49a326f6fe1aa58fb239f68f77df5008e1bc2b91538020743474563045e319a4aebccde3f71d5c75828b75e7f9284ca7920383fc9fb6eb2e8778f188355585e1a4775774ea4c1336b15d997ace9173adbdf793489fad6983ee3a3b86cc0c1db8e0fdde4378543d3396857c5b2155f801fbe8ede7e45ab48436f99995580665994998b4f2811be77c6c32a3b8734bb5ca2ae48c8511860aaf68f0de2bf24fe83f93d936138b06c442b37d30071dd012eafef1e29abaf929e87166ad1eaf7c4f4dfa598c9a0939dae6875c698d1cd74a576973592acb197a218ab319e0e63bc625426e094f94f1ffa91c59338f712da27bce49ed65baf0ccae8229a380e8dc6960c5d7d151256eea505fa713914d9a5b7c7b9eaa9e6658f6e0fdd80a16000a000c5553442f425443206f70656efffffffe000a2563727970746f636f6d706172652d4254432d5553442d6f70656e2d31373137313036343030"
}
```

The `announcement` is a JSON representation of [the `oracle_announcement` message type, described here in the DLC specifications](https://github.com/discreetlogcontracts/dlcspecs/blob/master/Messaging.md#the-oracle_announcement-type). Specifically Cassandra uses [the `dlc_messages` Rust crate to build announcements](https://docs.rs/dlc-messages/latest/dlc_messages/oracle_msgs/struct.OracleAnnouncement.html). The `serialized` field is a hex-encoded binary representation of the same announcement data.

### `GET /attestations/cryptocompare/BTC/:currency/:timestamp/:pricetype`

- `currency` is a fiat currency in whose value Bitcoin's price will be measured (e.g. `USD`).
- `timestamp` is either:
  - A unix second timestamp. Should be an integer divisible by 3600, indicating the top of an hour.
  - An RFC-3339 timestamp, e.g. `2024-07-10T12:00:00Z`. Again, should be a specific hour.
- `pricetype` is any of:
  - `open`
  - `high`
  - `low`
  - `close`

*Be aware that attestations for `high`, `low`, and `close` price types only be available one hour AFTER the `timestamp`, as these prices can only be fixed at the _end_ of their one-hour candle.*

Example:

```
$ curl https://conduition.io/oracle/attestations/cryptocompare/BTC/USD/1717106400/close
```
```json
{
  "attestation": {
    "oracle_public_key": "c3b1d269468f427ec56b4d0fa14c13aa4476fb05c708f8c3f036b97f839c2741",
    "signatures": [
      "ea3e6c8afd5cedde0bc61ed54c870daeee46362a7529bd818915f8e795d217819a038f337fcb54722e3a51a528a8f7640db44e9ca072af946fe70a1df2c3c348",
      "19307e8c8bb36b5857f02c867a25810dd02cc6c0219dc55622982ec2d80e5c610e1377098ad5471f113e7f31d9a1bd022b78fbf8e36db24154c79259527ff561",
      "1557dabcfcdfd351fc7118ae31c2a8ecfeda32407d25e01f43e297e6fdc74e4d035229fac6c6820fd40b5a69a76e72c0a3a156c6656ee554209eb01a9bca097e",
      "7f0f65efdbaed36539ed7d6fdbe56a927fc7cc659f6cdf59c7cd59b0ead7e564e23bcab93d76fb3faf396e9c2cc6d44a421e277d41cda7511dfb2c94e99f0588",
      "df369497ff5e04bbfda752e9d099c7d3e1bbd15bbaafd24d2a9b0a2c21343e00e2057865a5e17b0f1b5582f0183ec0e3a57f2702f861048cfe0050f24fa97b56",
      "7d8e3c0d5a41516a1a27ecf7390bde4da2a8d6f1f722c9abc393557dd7a3a422305b1c6797024d7204c797b15626ae52b4a78f5fdc2aef739e5eb9e7badb9646",
      "f3606b8a98fff592808eabff99b0c7689ab0e39d5d82e47fd33bbc4bbefe121a5a65a76e1c1816a9d6271b6e8dffd1298b577ea670872cd2a82de0c6d9b12e91",
      "1dab4d3e5c95567b0d98af5bf69f2d0954ab14a05ce9d3bd763f4ad3e65d86dc6f23695ba6bea4d2e447eaff40e6c9c001fa55ab0a88f3119d9605c1d18f1821",
      "574db852cd2de8707be3fe9051e8ba92f1656e398cf84ffc153109bf1caec6b2c7c25d2cc8bd55c31c230f58607030bcdfa2709bf20917bcc8069c0182fa4a2a",
      "fcdc68ab8fa32d42a5a5391de6996b91f507f330eb6a017645c5d310ad954cac33bb47a58a34aca5d7bcf454b337c2bc9334d3ff8635acc96a9e8cbc520a1532"
    ],
    "outcomes": ["0", "0", "0", "6", "8", "3", "4", "3", "4", "8"]
  },
  "price": 68343.48,
  "serialized": "c3b1d269468f427ec56b4d0fa14c13aa4476fb05c708f8c3f036b97f839c2741000aea3e6c8afd5cedde0bc61ed54c870daeee46362a7529bd818915f8e795d217819a038f337fcb54722e3a51a528a8f7640db44e9ca072af946fe70a1df2c3c34819307e8c8bb36b5857f02c867a25810dd02cc6c0219dc55622982ec2d80e5c610e1377098ad5471f113e7f31d9a1bd022b78fbf8e36db24154c79259527ff5611557dabcfcdfd351fc7118ae31c2a8ecfeda32407d25e01f43e297e6fdc74e4d035229fac6c6820fd40b5a69a76e72c0a3a156c6656ee554209eb01a9bca097e7f0f65efdbaed36539ed7d6fdbe56a927fc7cc659f6cdf59c7cd59b0ead7e564e23bcab93d76fb3faf396e9c2cc6d44a421e277d41cda7511dfb2c94e99f0588df369497ff5e04bbfda752e9d099c7d3e1bbd15bbaafd24d2a9b0a2c21343e00e2057865a5e17b0f1b5582f0183ec0e3a57f2702f861048cfe0050f24fa97b567d8e3c0d5a41516a1a27ecf7390bde4da2a8d6f1f722c9abc393557dd7a3a422305b1c6797024d7204c797b15626ae52b4a78f5fdc2aef739e5eb9e7badb9646f3606b8a98fff592808eabff99b0c7689ab0e39d5d82e47fd33bbc4bbefe121a5a65a76e1c1816a9d6271b6e8dffd1298b577ea670872cd2a82de0c6d9b12e911dab4d3e5c95567b0d98af5bf69f2d0954ab14a05ce9d3bd763f4ad3e65d86dc6f23695ba6bea4d2e447eaff40e6c9c001fa55ab0a88f3119d9605c1d18f1821574db852cd2de8707be3fe9051e8ba92f1656e398cf84ffc153109bf1caec6b2c7c25d2cc8bd55c31c230f58607030bcdfa2709bf20917bcc8069c0182fa4a2afcdc68ab8fa32d42a5a5391de6996b91f507f330eb6a017645c5d310ad954cac33bb47a58a34aca5d7bcf454b337c2bc9334d3ff8635acc96a9e8cbc520a1532000a0130013001300136013801330134013301340138"
}
```

The `attestation` is a JSON representation of [the `oracle_attestation` message type, described here in the DLC specifications](https://github.com/discreetlogcontracts/dlcspecs/blob/master/Messaging.md#the-oracle_attestation-type). Specifically Cassandra uses [the `dlc_messages` Rust crate to build attestations](https://docs.rs/dlc-messages/latest/dlc_messages/oracle_msgs/struct.OracleAttestation.html). The `serialized` field is a hex-encoded binary representation of the same attestation data.

The `price` field is the raw price attested to, denominated in units of `currency`. The outcome integer which Cassandra actually signs is `price * (10 ** precision)`, where `precision` comes from the initial announcement. Generally, `precision = -2` (for cents).

## Disclaimer

Cassandra runs and attests to outcomes without my personal supervision. Her data is sourced upstream APIs. If those services return faulty or incorrect data, then Cassandra's attestations will also be faulty. You should consider Cassandra as a layer of interoperability that enables DLCs to be built from upstream data sources. Cassandra _does not_ independently validate that data.
