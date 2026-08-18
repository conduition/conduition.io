---
title: Brink is Now Funding My Research
date: 2026-06-03
category: bitcoin
description: I can afford breakfast now!
---

I'm deeply honored to receive [Brink's first-ever grant to focus on post-quantum research](https://brink.dev/blog/2026/06/01/conduition/).

I have so much to say and I'm incredibly excited, but I also wanted to make sure I'm transparent about what this means and how this impacts my personal incentives and research direction. Whenever large sums of money are involved, it's always worth spending a minute to reflect on ethics, incentives, and goals. This post is that.

## Why A Grant?

A few months ago, I was generously invited by [Jonas Nick](https://github.com/jonasnick), director of [Blockstream Research](https://research.blockstream.com/), to collaborate with Blockstream's team in building a BIP draft for [SHRINCS](https://delvingbitcoin.org/t/shrincs-324-byte-stateful-post-quantum-signatures-with-static-backups/2158), a hash-based signature scheme, with the goal of securing Bitcoin's base-layer against quantum computers.

As readers of my prior research will know, I am highly motivated to see at least one PQ signature scheme deployed on Bitcoin. There are numerous options, but of them all, I believe SHRINCS is the most reasonable choice available today, and for the near future.

That's why when Jonas invited me, I jumped with joy at the opportunity.

The mission statement of the project sounds simple: **Draft a BIP to deploy SHRINCS in consensus.** But deploying a new signature scheme is more complex than just adding a new opcode.

There are dozens of competing factors to consider. There is research needed to fit the SHRINCS deployment into existing consensus rules, so that any upgrade will be a backwards-compatible soft-fork. Diverse use-cases like Lightning, hardware wallets, multisig wallets, custodians, mobile wallets, etc, must all be considered, cataloged, and the signature scheme balanced to fit all of them. There are engineering considerations like code reuse, specification bloat, etc. Even if we assume the signature scheme is secure, we must also ensure the upgrade doesn't surreptitiously introduce denial-of-service attack vectors or other undesirable validator behavior. Alternatives must be weighed, and choices reasoned through verbosely.

All this work is a collaborative effort, not employment. I'm working alongside folks at Blockstream Research like Mikhail Kudinov and Oleksandr Kurbatov, but also Ethan Heilman of Cloudflare, and Mike Casey, formerly of MARA. Blockstream itself isn't paying me a cent, and Jonas isn't my boss. Indeed some days it feels like I'm the one pestering _him!_

After a few weeks, we were making substantial progress, but I had also realized this was a long-term project, which would take months more before we even had a full draft ready, let alone a deployment-ready BIP package, complete with reference code, test vectors, and an optimized implementation.

Working on this highly-technical, intense, full-time project for many months financed solely by my own savings was unsustainable.

I considered applying to work at Blockstream, which would've neatly subsumed me into the SHRINCS project. But I felt this would do SHRINCS dirty in the long-term.

- Me working at Blockstream would (rightly or not) change the political appearance of the SHRINCS BIP. It would become a product of Blockstream. I suspect the SHRINCS BIP will fare better in the court of public opinion if I maintain my status as an independent agent, so that the SHRINCS BIP has one more non-Blockstream author.
- Working at Blockstream would make Jonas my boss. Good collaboration comes when peers can approach one-another with honest feedback, and I worried a power imbalance might tarnish that. So far the Blockstream folks have been very receptive to my feedback, and I hope I have been receptive to theirs too. I believe by retaining independence, that this positive trend will persist, and lead to an objectively better BIP.

So what options are left to hungry ol' conduition? I could get a day job, or pick up contract work. But unless they're specifically paying me to work on SHRINCS, any prospective employment contract would take my focus away, probably to something silly and ephemeral. Keeping pace on SHRINCS in parallel would burn me out.

This is why I was very excited to meet [Mike Schmidt](https://x.com/bitschmidty) of [Brink](https://brink.dev). We first met briefly when he graciously [invited me onto his Bitcoin Optech podcast to ramble about isogenies](https://bitcoinops.org/en/podcast/2026/04/07/). Our paths crossed again at Bitcoin Las Vegas 2026, where [he moderated a panel on post-quantum signature schemes](https://www.youtube.com/watch?v=pPb4O9_oOGk) which I happened to be participating in.

Being a total newb to research funding, I queried Mike after the conference about how non-profit developer grant programs like Brink and OpenSats work. The paradigm seemed to fit my needs perfectly. I have existing projects that I'm already working on, which I think carry value for the Bitcoin community. Grant organizations like Brink offer direct individual funding for people working on such projects, provided the grantee can prove they know what they're doing and that their projects are realistic. The grant organization itself doesn't influence the direction of the grantee's research, aside from incentivizing the grantee to produce concrete results that are at least somewhat in-line with an initial proposal.

## Why Brink?

I decided to apply to Brink because of their alumni network, reputation, and flexibility.

Brink has [a great history](https://brink.dev/programs#brink_grantees) of supporting realistic, practical, concretely-valuable work on Bitcoin Core's C++ codebase. I personally have never even submitted a PR to Bitcoin Core, and my C++ knowledge is limited to its C-language subset. So it would be incredibly handy to have access to speak with experienced Bitcoin Core devs about how best to apply my research in the core codebase.

Once I do get to that point, being a Brink grantee would afford me some degree of credibility: At least _someone_ thinks my work isn't boring, right? And given the gravity of the quantum threat we're trying to address, it would help if our work bears this additional mark of authenticity.

Finally, Brink's grant program seemed far more flexible with respect to its encumbrance on my time and working situation, compared to other non-profit grant organizations. Brink leaves grantees mostly alone to tend their own pastures. Thankfully I've been working remotely for years, and I don't plan to stop anytime soon. Self-management is nothing new. If I were approved, my focus, time management, and personal life would remain largely unchanged. I'd just be funded to do the work I was already doing anyway, with the addition of a report to review at end-of-year, and maybe occasionally answering some questions about my work from other Brink grantees (a pleasure!).

So I applied, and Brink's grant evaluation board approved me!

## What Next?

Basically nothing changes materially in my research focus or output, except you all get slightly better-quality output, because I can now actually afford to justify spending more time working on it.

As for my material goals, I think it best to quote myself from [Brink's own announcement post](https://brink.dev/blog/2026/06/01/conduition/):

> This generous grant from Brink will help me follow through with the arc of my previous research, as I work alongside the Blockstream team and other independent brilliant individuals to design, draft, and (hopefully) implement the first truly well-researched hash-based signature upgrade proposal for Bitcoin, built on the foundations of BIP-360 and [the SHRINCS scheme](https://delvingbitcoin.org/t/shrincs-324-byte-stateful-post-quantum-signatures-with-static-backups/2158).
> <br>
> I also hope to use this funding to formalize commit/reveal rescue protocols, which may someday be needed to authenticate inactive UTXOs in the presence of a quantum computer. Today these are folklore techniques buried in the mailing list archives, in need of careful assessment and security proofs.
> <br>
> Finally, I would like to expand [my prior research on isogeny cryptography](/cryptography/isogenies-intro/), which I believe has the promise to act as a suitable long-term replacement for Bitcoin's classical elliptic curve cryptography. This will take the shape of long-form educational content accessible to Bitcoin developers, deep technical exploration of the trade-off space, experimental benchmarks, and hopefully collaboration with mainstream isogeny researchers.
> <br>
> I'd like to earnestly thank Brink for supporting this important work. Because of this grant, I can tighten my focus on these three key topics and still maintain transparency in my research. I will continue publishing articles about my discoveries and software projects on [my blog](https://conduition.io). All relevant code will be published on [my github](https://github.com/conduition) under [The Unlicense](https://unlicense.org/) without restriction or copyright, as always.

### Hash-Based Signatures

My most immediate next steps will be to drive the SHRINCS BIP to a state where it's ready for the first-stage of community feedback. This includes a full specification of the SHRINCS scheme, its parameters, and a mechanism to deploy it in consensus, all with accompanying justifications and assessments of alternatives. This I hope to have ready before EOY, though it may well be ready sooner. Once ready, we'll share it on the [mailing list](https://groups.google.com/g/bitcoindev/) and [Delving](https://delvingbitcoin.org/), to solicit feedback from the community. I imagine we'll probably need to sift through a deluge of critiques, some constructive and some... less so. In response, we may need to amend or elaborate the BIP draft and SHRINCS spec accordingly. All of this will take time.

In parallel with SHRINCS, I hope to formalize [Hypertree Pruning](/cryptography/hypertree-pruning/) - a technique needed to run SHRINCS on hardware wallets - with my first-ever academic paper. I hope to submit this paper to IACR and other cryptography-focused ePrint publications by October 2026, so that I have a chance to respond to peer-review feedback before we publish the SHRINCS BIP draft.

### Commit/Reveal

A _rescue protocol_ is a way to recover Bitcoin UTXOs that don't migrate to a PQ-safe address format in time before a quantum computer occurs. Rescue protocols require a confiscatory restriction of Bitcoin's legacy spending conditions, and so they are very controversial.

I don't know whether the entire Bitcoin community will have the willpower to activate a rescue protocol in the future, but if a powerful CRQC emerges suddenly I suspect a large fraction of the network will want to try, in order to preserve their capital's purchasing power from devaluation by a quantum-attacker. If and when this happens, users will benefit from having better information about what's possible.

[Previous research has focused on ZK-STARK rescue protocols proving BIP32 derivation](https://groups.google.com/g/bitcoindev/c/Q06piCEJhkI), commonly called "proof-of-seed" but this is a misnomer as a seed phrase is not the key ingredient. There has also been work done on [zero-knowledge proofs relying on hashed addresses](https://delvingbitcoin.org/t/pq-provers-for-p2pkh-outputs/2287).

However, there is no iron-clad law which demands we construct such rescue protocols with non-interactive ZK proofs. Many threads on the mailing list contain conjectural descriptions of interactive protocols which use basic temporal properties of the Bitcoin blockchain to commit to and then reveal quantum-sensitive data, proving an intent to move money must have existed _before_ a quantum adversary could've forged it.

- https://groups.google.com/g/bitcoindev/c/jr1QO95k6Uc
- https://groups.google.com/g/bitcoindev/c/uUK6py0Yjq0
- https://groups.google.com/g/bitcoindev/c/LpWOcXMcvk8
- https://groups.google.com/g/bitcoindev/c/oa4nDmlLzN4

These "commit/reveal" techniques can prove the same statements ZK-STARKs can prove - though not in zero-knowledge - so they allow us to construct rescue protocols in similar ways to ZK-STARKs. The main value-proposition of commit/reveal over ZK proofs is that commit/reveal relies only on simple hash functions and time anchoring - No complex arithmetization, interactive oracle proofs, or fiat-shamir transforms thereof. This means commit/reveal could be _much_ easier to implement securely, would be far less computationally intense for provers and verifiers, and would produce proofs which are orders of magnitude smaller than ZK-STARKs.

However, both options have complex trade-offs, and nobody has yet fully explored and documented these trade-offs, nor has anyone formalized a concrete, secure, and deployable commit/reveal rescue protocol. I hope to collaborate with other Bitcoiners to do exactly this, hopefully making this my next focus if and when the SHRINCS proposal matures.

### Isogenies

While hash-based signatures are great and all, we would all be much better off if someday we could regain all the "nice" properties of Schnorr, vis-a-vis compactness, BIP32, multisignature schemes, etc. While lattice crypto is certainly a promising avenue as well, I believe [isogeny cryptography](/cryptography/isogenies-intro/) holds far more potential, due to its noise-free mathematical structure and incredibly compressible signatures.

I hope to use my new funding to explore isogenies in more detail, and to produce long-form written educational content, accessible to Bitcoin devs and prospective Bitcoin isogenists.

There are many open problems in isogeny cryptography that I'd like to explore too, but there is a specific one I would really like to target. Besides their novel security assumptions, isogeny signature schemes have one major flaw holding them back from real-world deployment: _verification cost._ SQIsign and PRISM cost more than 50x the CPU cycles to verify than a SHRINCS signature. Because isogeny signatures and keys are so small and slow, the relative verification cost per byte if deployed on Bitcoin would be absurd: A block full of SQIsign signatures would take many seconds of CPU time to verify.

If it is possible to mitigate or resolve the verification cost problem, perhaps by trading off some other factor we care less about, then isogenies could indeed offer a suitable drop-in replacement for classical elliptic curve crypto. Modern isogeny signature schemes like [SQIsign](https://sqisign.org/) and [PRISM](https://eprint.iacr.org/2025/135) have extremely deep internal workings, with many knobs to turn & tweak. I'd like to profile both schemes, and identify the exact inner sub-algorithms which consume the most CPU time in the verifier, and assess any options we may have to optimize.

## Conclusion

Brink's grant isn't changing much for me except for the fact that I get to eat nicer food more often, and that I won't have to distract myself from PQ research with contracting gigs.

The grant expires at the end of Q1 2027, at which point Brink's board and I will review my progress and maybe I'll apply for a new grant if I like how things went.

By then, hopefully:

- My hypertree pruning paper will be published.
- We will have a mature public draft of the SHRINCS BIP circulating among the Bitcoin community.
- I likely will have transitioned my primary focus to either actively working on an optimized SHRINCS implementation, or formalizing commit/reveal, or studying isogenies, depending on how the winds are blowing at the time.

With these expectations in mind, 2026 is shaping up to be a thrilling year for nerds like us.
