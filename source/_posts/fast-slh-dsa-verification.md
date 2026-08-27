---
title: SLH-DSA vs Schnorr Verification
date: 2026-01-25
mathjax: true
category: code
description: Detailed comparison of SLH-DSA and BIP340 Schnorr verification algorithms.
---

In [my last article](/code/fast-slh-dsa/), I showed how SLH-DSA (SPHINCS+), the post-quantum hash-based signature scheme, can be accelerated by several orders of magnitude using parallelization tools like SIMD, multithreading, and graphics APIs.

I made some imprecise statements in that article about how, if batched, SLH-DSA verification can approach the throughput of elliptic curve signature schemes, which today are the cutting edge in classical cryptography. Today I'd like to flesh that comparison out more fully, and answer some questions I've received about this. Verification speed is one of the most important factors to consider for any signature scheme used in distributed systems with many verifiers, so it's important that we be thorough.

Specifically, I will be comparing the throughput my implementation of SLH-DSA-SHA2-128s against an implementation of [BIP340 Schnorr](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki) signature verification on the secp256k1 curve. SLH-DSA-SHA2-128s is the NIST-standardized parameter set which results in the smallest signatures, but is also in the weakest security class, comparable in classical security to BIP340 on secp256k1 (128 bits).

### Disclaimers

All benchmarks are taken on my person machine, and where applicable I have noted the use of multithreading, batching, or hardware acceleration. Note we cannot empirically compare the verification algorithms themselves - one can only benchmark actual code, after all. While this comparison should be insightful, do not take it as a blanket statement of "A is always X times slower than B".

For the purpose of this article, I am only comparing verification _throughput_ which is different than _latency._ Throughput is a measure of how quickly some code can process a queue of many tasks, while latency is the delay with which that code can process a single task. In our context, latency measures "how quickly can you verify a single signature?" while throughput measures "how many signatures can you verify in a single second?"

Now let's review the implementations to be compared.

## slhvk

> https://github.com/conduition/slhvk

This SLH-DSA implementation is written by yours-truly, and it achieves the highest verification throughput of any open-source SLH-DSA codebase that I know of. As detailed in [my last article](/code/fast-slh-dsa/#Vulkan-for-SLH-DSA), `slhvk` uses Vulkan - an open vendor-neutral graphics API typically used by video game developers - to parallelize the many independent hash function calls which are required to generate SLH-DSA signatures and keypairs. By writing the core algorithms in a platform-neutral shader language, we allow hardware vendors to maximize the parallelism of the code, and reduce runtime compared to hand-written multithreading and SIMD. We can also run the same code on a GPU if available, for even faster results.

I optimized `slhvk`'s verification code specifically to maximize throughput. I did this by [writing a single, monolithic verification shader](https://github.com/conduition/slhvk/blob/main/src/shaders/verify.comp) which computes the entire SLH-DSA verify algorithm for a single signature within a single Vulkan worker. One signature is verified per shader invocation, basically. If you're not familiar with GPU programming, a shader invocation is similar to a CPU thread but at a smaller scale.

This architecture results in very poor latency because a single verification op doesn't benefit from parallelism at all. However it benefits throughput massively, because Vulkan can parallelize hundreds or even thousands of independent verification ops using CPU or GPU hardware more efficiently than we, the programmer, can hope to do by hand, making full use of all available cores, SIMD instructions, and device memory access patterns.

`slhvk` implements only the SLH-DSA-SHA2-128s parameter set from [FIPS205](https://csrc.nist.gov/pubs/fips/205/ipd), but can easily be modified to support alternative parameter sets with a 128-bit security level.

## libsecp256k1

> https://github.com/bitcoin-core/secp256k1

In the classical cryptography corner, we have one of the most well-optimized cryptographic libraries available anywhere today, the Bitcoin Core team's secp256k1 library.

We will be specifically benchmarking the functions [`secp256k1_xonly_pubkey_parse`](https://github.com/bitcoin-core/secp256k1/blob/ebb35882da9ff62313ae601d3ff8c4e857271f06/include/secp256k1_extrakeys.h#L47-L51) and [`secp256k1_schnorrsig_verify`](https://github.com/bitcoin-core/secp256k1/blob/ebb35882da9ff62313ae601d3ff8c4e857271f06/include/secp256k1_schnorrsig.h#L178-L184) from the Schnorr signature module of libsecp256k1.

BIP340 Schnorr signatures can be aggregated into a batch and verified using specialized elliptic curve math, resulting a speedup over naive sequential verification. However, *I will not be benchmarking BIP340 batch verification,* for two reasons.

1. [Batch verification has not made it into the master branch of libsecp256k1](https://github.com/bitcoin-core/secp256k1/pull/1134) as of time of writing.
2. [It has been shown that the speedup from batch verification is logarithmic in the number of signatures](https://github.com/bitcoin-core/secp256k1/blob/15ea24cb8c1bd239a7a39939da1952cf6d3a35b0/doc/speedup-batch/tweakcheck-speedup-batch.png), with minimal increase in overall throughput (at least at the scale we're concerned with). See [this article](https://blog.btrust.tech/schnorr-and-steady-wins-the-race-the-case-for-batch-validation/) for more details.

## Benchmarking Approach

As mentioned earlier, to compare the two implementations I will be measuring _throughput,_ which for clarity and intuition I will denominate in _signatures-per-second,_ or "sig/sec". Higher throughput is better, for obvious reasons. With simple arithmetic you can convert these metrics to any other unit you'd prefer to think in, such as nanosec/sig as I used in my last article.

To avoid interference from separate workloads on my machine, I shut down all other running user applications and resource-hungry daemons before running any benchmarks.

When a CPU begins working on a difficult task from idle, it starts out cool and efficient but quickly heats up and slows down to prevent itself from melting. Since we are concerned with signature verification throughput under a heavy workload, we want to know how the code performs when the CPU is running under peak (high) temperature. To avoid the initial CPU temperature variance skewing these results too much, throughput measurement will only be taken over a longish period under load (30 seconds).

Also note that benchmarks do not measure initial setup costs, such as precomputation of curve points with libsecp256k1, or shader compilation with `slhvk`.

### On Parallelism

Note that comparing my `slhvk` implementation against libsecp256k1 naively, using [`slhvk`'s own benchmarking program](https://github.com/bitcoin-core/secp256k1) and measuring its throughput against [the `secp256k1_schnorrsig_verify` benchmark inside libsecp256k1](https://github.com/bitcoin-core/secp256k1/blob/471e3a130d4e0961d087c25a8daae83c846b675f/src/modules/schnorrsig/bench_impl.h#L37-L46), would be unfair to libsecp256k1 because the `secp256k1_schnorrsig_verify` benchmark _runs in a single-threaded context._ libsecp256k1 doesn't include any multithreading code of its own, and thus won't make full use of available hardware on multi-core CPUs, whereas `slhvk` makes full use of hardware owing to its dependence on Vulkan.

As such, I've also written a multithreaded benchmark program using libsecp256k1 to maximize the overall throughput of `secp256k1_schnorrsig_verify` on my machine, making for a fairer comparison under a workload of many thousands of independent signatures. For convenience, I wrote this benchmark program in Rust, using [the libsecp256k1 Rust bindings](https://github.com/rust-bitcoin/rust-secp256k1/) which perform about the same as the plain C code upstream (I verified this).

```rust
use secp256k1::{Keypair, Secp256k1};
use std::time::{Duration, Instant};

fn main() {
    let ctx = Secp256k1::new();
    let keypair = Keypair::from_seckey_str(
        &ctx,
        "C90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B14E5C9",
    )
    .unwrap();
    let message = b"hey there";
    let signature = ctx
        .sign_schnorr_no_aux_rand(message, &keypair)
        .to_byte_array();
    let pubkey_bytes = keypair.x_only_public_key().0.serialize();

    let thread_count = 32;
    let task_size = 4096;
    let min_duration = Duration::from_secs(30);
    let start = Instant::now();

    let mut sigcount = 0;
    while start.elapsed() < min_duration {
        let threads = (0..thread_count)
            .map(|_| {
                std::thread::spawn(move || {
                    let ctx = Secp256k1::new();
                    for _ in 0..task_size {
                        let pubkey =
                            secp256k1::XOnlyPublicKey::from_byte_array(pubkey_bytes).unwrap();
                        pubkey
                            .verify(
                                &ctx,
                                message,
                                &secp256k1::schnorr::Signature::from_byte_array(signature),
                            )
                            .unwrap();
                    }
                })
            })
            .collect::<Vec<_>>();

        for thread in threads {
            thread.join().unwrap();
        }
        sigcount += thread_count * task_size;
    }

    let elapsed = start.elapsed().as_secs_f64();
    let throughput = (sigcount as f64) / elapsed;

    println!(
        "t={thread_count} w={task_size} verified {sigcount} sigs \
        in {elapsed:.2}s : throughput = {throughput:.1} sig/sec"
    );
}
```

For this parallelized verification benchmark, I used 32 threads and a consistent per-thread workload of 4096 signatures. I chose these parameters after some experimenting to find the optimal parameters for my particular machine. I matched this in my `slhvk` benchmark by giving it batches of 4096 signatures to verify at a time (`slhvk`'s API processes signatures in batches, by its very nature as a monolithic compute shader).

## Results

After benchmarking each implementation, we arrive at the following sigs/second throughput measurements (higher is better).

| Implementation | sigs/sec |
|-|-|
| libsecp256k1 Schnorr | 42879 |
| libsecp256k1 Schnorr + Multithreading | 278836 |
| `slhvk` | 63971 |

<!-- Made with: https://graphmaker.org/bar-graph/

Labels:
  schnorr,schnorr+multithread,slhvk
Values:
  42879,278836,63971
 -->

<img style="border-radius: 8px;" src="/images/slh-dsa/verification-throughput-chart.svg">

## Analysis

Surprisingly, a naive single-threaded verifier checking BIP340 signatures sequentially with libsecp256k1 performs poorly compared to `slhvk`, even though they are using the most well-optimized open-source secp256k1 implementation in the world.

Of course this gap would probably close if the naive verifier used the forthcoming BIP340 batch verification implementation, and `slhvk` is certainly outperformed by BIP340 verification if the verifier makes proper use of available CPU cores to parallelize.

Even then, the size of the performance gap is not enormous - It is less than one order of magnitude, which surprised me. Many people consider SLH-DSA to be an implicit tortoise, always slower than its competitors. This is certainly true of SLH-DSA signing, but not of verification. SLH-DSA verification can perform reasonably well even when comparing against classical algorithms, provided its implementation is properly optimized to use available hardware.

Recall also that we are measuring only one parameter set of SLH-DSA. An optimized implementation of a smaller SLH-DSA parameter set could very well outperform BIP340, though possibly at the cost of larger signature sizes or weaker key-reuse security.

## Conclusion

**Under heavy workload, a parallelized SLH-DSA-SHA2-128s verifier can perform as well as a single-threaded BIP340 verifier, but not as well as multi-threaded BIP340.**

## A Note on ML-DSA

Alongside SLH-DSA, there is also ML-DSA/Dilithum, which is also under consideration by many as a post-quantum replacement for elliptic curve signatures.

I felt it would be useful to mention the approximate single-threaded throughput of [Dilithium's reference implementation (with AVX2 optimization)](https://github.com/pq-crystals/dilithium/tree/master/avx2), is **around 70,000 signatures per second** on my machine. However, I did not include this measurement in my analysis as I could not easily verify its accuracy. The ML-DSA reference implementation benchmark outputs highly variable measurements, with speeds measured in clock cycles rather than real-world time. Doing the math from my CPU clock speed, I worked out the throughput abstractly. Since it seems to perform favorably compared to libsecp256k1 already, I did not venture the effort to parallelize ML-DSA with multithreading.
