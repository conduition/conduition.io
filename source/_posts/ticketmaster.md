---
title: Reverse Engineering TicketMaster's Rotating Barcodes (SafeTix)
date: 2024-02-04
mathjax: true
category: coding
---

_"Screenshots won't get you in", but Chrome DevTools will._

<a href="#Reverse-Engineering">Click here to skip the rant and go straight to the nerdy stuff.</a>

I recently purchased tickets to a concert from TicketMaster. If they had issued me normal, printable PDF tickets I could save offline to my phone, this article would've never been penned. But of course this is 2024: Nothing we do online can be simple anymore.

After finalizing the purchase, TicketMaster discloses that I can't print off tickets for this event. Instead, they issue tickets via a system called Mobile Entry, AKA _SafeTix._ This takes the form of a rotating barcode displayed inside TicketMaster's web-app or android/ios app.

<img src="/images/ticketmaster/safetix-barcode.gif">

Perhaps I'm getting old, but I remember a time when printable tickets were ubiquitous. One could print off tickets after buying them online or even (gasp) _in-person,_ and bring these paper tickets to get entry into the event when you arrive. They can be saved as PDFs and viewed on pretty much any device on the planet. PDF tickets work even if your phone loses internet connection. Paper tickets work even if you don't have a phone. If you bought the ticket off the event's official ticketing agency (not a sketchy reseller), you know for sure that they're real. There's no risk that your ticket won't get you in. You can easily send them to a friend over WhatsApp, iMessage, Signal, email, or even by-hand with printed tickets.

These rotating barcodes on the other hand are far from perfect. I experienced this first-hand last year when I attended another _very popular_ concert where they used a similar rotating-QR-code-ticket system. Numerous people including myself and my friends were floundering at the entry gate citing a bevy of broken barcode problems. The #1 was:

> My phone has no internet connection, so my QR code won't load.

The venue was so crowded that cell-towers and WiFi were overloaded. Internet access was spottier than a Dalmatian with chickenpox.

The company responsible for this ticketing nightmare (I can't remember their name) obviously had no phone support line, and even if they did it probably wouldn't have worked. The venue employees were completely helpless. Our only hope was to keep refreshing the ticket app, wildly waving our phones in the air in the hopes we might catch a brief moment of cell-network coverage with which to fetch and then display the ticket QR codes to the venue staff.

In the end, I luckily caught some cell-service and loaded our ticket QR codes. We left behind a slew of other ticketholders waving their phones around at the gate. I have no idea whether they ever got through.

I paid three hundred US dollars for this high-tech experience.

## The Marketing

TicketMaster markets their SafeTix technology as a cure-all for scammers and scalpers.

> SafeTix™ are powered by a new and unique barcode that automatically refreshes every few seconds so it cannot be stolen or copied, keeping your tickets safe and secure.

> Ticketmaster SafeTix are powered by a new and unique barcode that automatically refreshes every 15 seconds. This greatly reduces the risk of ticket fraud from stolen or illegal counterfeit tickets.

<sub><a href="https://www.ticketmaster.com/safetix">Source</a></sub>

> Our secure ticket technology reduces the risk of ticket fraud, eliminating the possibilities of theft or counterfeiting. Once you’ve purchased your mobile tickets on Ticketmaster, you can always rest assured you’re getting the seats you paid for.

<sub><a href="https://blog.ticketmaster.com/mobile-ticketing-an-essential-for-safe-entry/">Source</a></sub>

There's also this gem:

> If you take a closer look at your ticket, you may notice that it has a gliding movement, making it in a sense, alive. That movement is our ticket technology actively working to safeguard you every second.

Bullshit, TicketMaster. It's a CSS animation. Get over yourself.

The part that got me worried:

> The barcode on your mobile ticket includes technology to protect it, which means screenshots or printouts of your ticket will not be scannable.

This triggered flashbacks to the concert last year, and I pictured myself once more haphazardly waving my phone around, praying for service like Saul Goodman in the desert.

<div style="display: flex; flex-direction: row;">
  <img style="width: 50%; margin: 10px; border-radius: 5px;" src="/images/ticketmaster/saul-goodman-1.webp">
  <img style="width: 50%; margin: 10px; border-radius: 5px;" src="/images/ticketmaster/saul-goodman-2.webp">
</div>

But TicketMaster was prepared for this anxiety:

> Concerned about cell phone service at venues? This ticket has you covered. Once you view it in our App, your ticket is automatically saved so it's always ready.

Great, so as long as I trust their app not to have a seizure on the day of the concert, I should be fine. Too bad I really don't trust that, besides the fact that I don't want to install their spyware on my phone.

## Motivations

It's pretty clear why TicketMaster is pushing this technology:

- SafeTix makes it harder for people to resell tickets outside of TicketMaster's closed, high-margin ticket-resale marketplace, where they make a boatload of money by buying low and selling high to customers with no alternative.
- It pushes users to install TicketMaster's proprietary closed-source app, which gives TicketMaster more insight into their users' devices and behavior.
- People can't save and transfer tickets outside of Ticketmaster. This forces ticketholders to surrender their friends' contact information to TicketMaster, who can use this data to build social graphs, or conduct other privacy-invasive practices.

TicketMaster will never admit to these motivations, but it cannot be doubted that these effects have manifested regardless of TicketMaster's intent, and they're all good news for TicketMaster's shareholders, if not for their customers.

## The Contradiction

If you have any experience with computers and software, then having read all of TicketMaster's marketing, you might come to the same question I did.

**How can tickets be saved offline if they can't also be transferred outside of TicketMaster?**

This ticket is digital. Saving data offline is the same as copying it to your hard drive. If data can be copied, it can be transmitted. If it can be transmitted, it can be shared. If it can be shared, _it can be sold._

This is a contradiction in TicketMaster's marketing. They can't have robust DRM on their tickets if those tickets can still be viewed offline.

So what is TicketMaster really doing to create these rotating barcodes?

# Reverse Engineering

My first order of business was inspecting the barcodes themselves to see what I could learn. Their format is quite simple. They are [PDF417](https://en.wikipedia.org/wiki/PDF417) barcodes which encode [UTF-8 text](https://en.wikipedia.org/wiki/UTF-8). As I mentioned earlier, that blue bar which sweeps across the barcode is just a gimmicky [CSS animation](https://www.w3schools.com/css/css3_animations.asp): It doesn't actually prevent screenshots of the barcode from scanning, because PDF417 has error correction properties built-in.

It seems like some older barcodes encode different formats of text, but the barcodes my TicketMaster web-app was generating embed data which looks like this:

```
B4cq2BdFCpFl90TDuYD3pWfRDSO6eQ3bR0YQqsDnyfciuVFkKp+m0zI+a2lgfonY::140013::481994::1707070843
```

<sub>Disclaimer: This isn't from a real SafeTix barcode. I don't want TicketMaster to be able to identify and harass me.</sub>

This looks like four distinct pieces of data, delimited by colons. First, there is some [Base64](https://en.wikipedia.org/wiki/Base64)-encoded data, followed by two six-digit numbers, with a [unix timestamp](https://en.wikipedia.org/wiki/Unix_time) trailing at the end.

When the barcode rotates every 15 seconds, its content changes slightly. The base64 data remains static, but both 6-digit numbers and the timestamp change.

```
B4cq2BdFCpFl90TDuYD3pWfRDSO6eQ3bR0YQqsDnyfciuVFkKp+m0zI+a2lgfonY::358190::038184::1707070859
```

These six-digit numbers behave a lot like [Time-based One-Time Passwords (TOTPs)](https://en.wikipedia.org/wiki/Time-based_One-Time_Password) - This is what powers 2FA apps like [Authy](https://authy.com/) or [Google Authenticator](https://play.google.com/store/apps/details?id=com.google.android.apps.authenticator2). These are rotating 6-digit codes which can be generated from a shared secret and a timestamp.

My instinct was that the first two numbers are indeed TOTPs, generated from different secrets, using the unix timestamp appended at the end of the barcode data. This makes sense: TicketMaster wouldn't want to reinvent the wheel with this system, so they used a tried and tested cryptographic tool as a building block.

The base64 data was still a mystery. Decoding it into its constituent 48 bytes, it doesn't seem to contain any meaningful data structures that I could discern. It seems more or less like random data, and since it doesn't change when the barcode rotates, it's probably some kind of random bearer token which identifies the ticketholder and their ticket.

When the ticket is scanned at the venue, TicketMaster (or perhaps the venue) looks up the ticket metadata using that bearer token, and then validates the two OTPs against two secrets stored in its database. If both steps pass, then your ticket is valid and the staff can let you in.

## Here's the Secret

TOTPs are very customizable, but generally the software industry has settled on a set of common defaults for TOTP standardization. You really only need to have two things to generate a TOTP:

- The shared secret, which is just a byte array.
- A working clock.

If you have both of those, you can generate as many TOTPs as you'd like, _entirely offline._

There are two TOTPs in the barcode data, so there are probably two shared secrets I need to find. If I have both of those, plus the bearer token, I can create as many valid barcodes as I want.

So now my goal is much clearer: I need to find out where these tokens & secrets come from.

## Debugging the Web App

I booted up an Android phone and connected its Chrome browser to the Chrome DevTools on my desktop computer. This gives me a view into TicketMaster's API and source code.

By [recording network requests](https://developer.chrome.com/docs/devtools/network/reference/) as I loaded the TicketMaster barcode viewer, I found one particularly interesting request:

```
POST /api/render-ticket/secure-barcode?time=1707071877481&amid=XXXXXXXXXXXXXXX&_format=json
```

Its response data:

```json
{
  "deviceId": "8f651107-acad-42a4-b3a6-019aaac41960",
  "deviceType": "WEB",
  "deviceOs": "ANDROID",
  "userAgent": "Mozilla/5.0 (Linux; Android 10; K) XXXXXXXXXXXXXXX",
  "nfcCapableDevice": true,
  "tickets": [
    {
      "eventId": "myevent.50.38991943985838B9",
      "section": "3",
      "row": "A",
      "seat": "1",
      "barcode": "481848590102K",
      "addedValue": false,
      "generalAdmission": false,
      "fan": null,
      "token": "eyJiIjoiNDgxODQ4NTkwMTAySyIsInQiOiJUR1JMWUNxQWYyQ1MvQmxILzh5dThZdkhoV055TW8xUW9CYTI5UTVqVkN4V2xBcE5NbnczSlJkeU9UcFVVWUFDIiwiY2siOiJiOTg0MzJlZDIzYjhmMmJkYTgyMzQ4MjE2MjI5ZjRkMjdjZTlkMDYzIiwiZWsiOiJiMzUxOTM2NGUwYzc5MTRjMWY5ZDU5ZDM1NjUyYTA0MDY3ZDJmNjQ3IiwicnQiOiJyb3RhdGluZ19zeW1ib2xvZ3kifQ==",
      "renderType": "rotating_symbology",
      "passData": {
        "android": {
          "jwt": "eyJhbGciOiJSUzI1NiJ9.XXXXXXXXXXXXXXXXXX.YYYYYYYYYYYYYYYYYYYYYYYYYY"
        }
      },
      "bindingRequired": true,
      "deviceKeyBindingRequired": false,
      "deviceSignatureRequired": false,
      "segmentType": "NFC_ROTATING_SYMBOLOGY",
      "ticketId": "50.3.A.1"
    }
  ],
  "globalUserId": "k39Fj4lNfOS4Zq481bxIWg"
}
```

<sub>Disclaimer: Identifying data has been scrambled to protect the guilty.</sub>

Note the `token` property in the object in the `tickets` array. I base64-decoded it, and I found it was actually just a another JSON object:

```json
{
  "b": "481848590102K",
  "t": "TGRLYCqAf2CS/BlH/8yu8YvHhWNyMo1QoBa29Q5jVCxWlApNMnw3JRdyOTpUUYAC",
  "ck": "b98432ed23b8f2bda82348216229f4d27ce9d063",
  "ek": "b3519364e0c7914c1f9d59d35652a04067d2f647",
  "rt": "rotating_symbology"
}
```

- The `b` property seems to be the same as the `barcode` property on the ticket object.
- The `rt` property seems to be the same as the `renderType` property on the main ticket object.
- The `t` property is a base64-encoded byte array, 48 bytes long.
- The `ck` and `ek` properties are both hex-encoded byte arrays, each 20 bytes long.

I re-scanned the latest barcode shown on the TicketMaster web-app:

```
TGRLYCqAf2CS/BlH/8yu8YvHhWNyMo1QoBa29Q5jVCxWlApNMnw3JRdyOTpUUYAC::492436::240860::1707074879
```

Nice. So `t` is the static bearer token. I wonder if `ck` and `ek` are the TOTP secrets I'm after.

Upon some further investigation into TicketMaster's minified website source code, in a file called `presence-secure-entry.js`, I found the actual function the web-app uses to generate barcode data, which is labeled `generateSignedToken`.

```js
key: "generateSignedToken",
value: function(t) {
    var e = arguments.length > 1 && void 0 !== arguments[1] && arguments[1];
    if (this.displayType === l.ROTATING) {
        var n = [this.eventKey, this.customerKey]
          , a = t;
        if (this.eventKey) {
            var u = new Date(a);
            a = u instanceof Date && "Invalid Date" !== "".concat(u) ? u : new Date
        }
        var A = n.reduce((function(t, n) {
            if (n) {
                var u;
                try {
                    u = i.b32encode(o.a.hexToByteString(n))
                } catch (t) {
                    u = ""
                }
                var A = r.a(u, 15).now(a, e);
                t.push(A)
            }
            return t
        }
        ), [this.rawToken]);
        if (this.eventKey) {
            var s = Math.floor(a.getTime() / 1e3);
            A.push(s)
        }
        return A.join("::")
    }
    return this.barcode
}
```

The minification makes it a bit harder to read, but it seems like `ek` and `ck` probably refer to the `eventKey` and `customerKey` respectively, while the bearer token `t` is referenced as `rawToken` in the above code.

It appears the two TOTPs are generated with a 15-second time step interval, but are otherwise constructed in the same way as the ubiquitous industry-standard SHA-1 TOTPs we see in any mobile 2FA app. The first one is generated with the `eventKey`, and the second with the `customerKey`. Finally, the unix timestamp used for both TOTPs is appended to help with verification on the server-side.

To verify my interpretation, I installed `oathtool`, a TOTP command-line tool. I plugged `ck`, `ek` and the unix timestamp into a SHA-1 TOTP generator with a 15-second step interval:

```console
$ sudo apt install oathtool -y
...
$ date=$(python3 -c 'import datetime; print(datetime.datetime.fromtimestamp(1707074879).isoformat())')
$ oathtool --totp --time-step-size 15s -N "$date" b3519364e0c7914c1f9d59d35652a04067d2f647
492436
$ oathtool --totp --time-step-size 15s -N "$date" b98432ed23b8f2bda82348216229f4d27ce9d063
240860
```

Bingo! 🎉 This matches the TOTPs in the barcode:

```
TGRLYCqAf2CS/BlH/8yu8YvHhWNyMo1QoBa29Q5jVCxWlApNMnw3JRdyOTpUUYAC::492436::240860::1707074879
```

The `eventKey` is probably unique to the particular event that is being ticketed, and `customerKey` is probably unique to the ticketholder. They don't appear to change at all, unlike the `rawToken` which seems to rotate every time I refresh the TicketMaster web-app. However, if I leave the page alone for several hours, the `rawToken` doesn't change, suggesting it should remain valid even after closing the web-app.

<sub>What about the `passData.android.jwt` field? Does that come into play anywhere? I'll save you some work on that front. Turns out it's not actually needed for ticket verification at all, but rather just an authentication token used for saving the ticket to a user's [Google Wallet](https://wallet.google/). I don't use Google Wallet. Being a rather privacy-conscious individual, I stay well clear of Google services as much as possible.</sub>

## Pirating Tickets

I now know everything I would need to duplicate TicketMaster's barcodes in a custom app, or even resell a ticket outside of TicketMaster's closed marketplace. All I would need to do is extract the base64 `token` property from the `/api/render-ticket/secure-barcode` API endpoint, or engineer a way to fetch that token dynamically using TicketMaster session credentials.

That base64 `token` string ***IS*** the ticket, as far as the venue staff at the gates are concerned. If you have a valid `rawToken`, `eventKey`, and `customerKey`, you can generate valid [PDF417 barcodes](https://en.wikipedia.org/wiki/PDF417), indistinguishable from the official TicketMaster app. Short of checking photo IDs at the entry gate, the venue staff can't tell whether the person at the gate is the same person who the ticket is registered to on TicketMaster.

Quite hilariously, TicketMaster actually makes token-extraction easy on us: The `token` is logged to the browser console automatically when the barcode renderer component is mounted on the web page.

```js
r.a.log(
  "'render' called on '".concat(
    "pseview-".concat(J.get(this)),
    "' with token '", this.token, "'"
  )
)
```

This means we don't even need to mess around injecting custom user-scripts into the page to get the `token` out. You can just open your SafeTix barcode on the TicketMaster web-app, [connect your phone's Chrome instance to your laptop's Chrome DevTools](https://developer.chrome.com/blog/devtools-mobile/), and open the console. You'll see the `token` printed right there. You can copy and use it wherever you'd like.

## Lifetimes

The only unknown factor here is the `rawToken` lifetime. It's difficult to know for sure how TicketMaster's backend server uses `rawToken` to look up the ticket. It's likely that a new `rawToken` is generated every time the client contacts the `/api/render-ticket/secure-barcode` endpoint.

I have no idea how long each `rawToken` remains valid. It's possible that only a single `rawToken` could be valid for a given TicketMaster account at a time. Indeed TicketMaster devs probably designed the system that way to prevent extracting multiple tickets which are concurrently valid.

If multiple `token`s are valid concurrently, one person could buy dozens of tickets, extract however many ticket `token`s they'd like, and resell them under-the-table. I would really love if TicketMaster didn't think of that, because then I could extract the ticket `token`s for my friends and distribute them without having to go through TicketMaster's data-harvesting pipeline.

The only authoritative source I could find on this is [an obscure document on TicketMaster's developer API docs website](https://developer.ticketmaster.com/products-and-docs/apis/partner/safetix/).

> Partners will need to refresh the token 20 hours prior to the start of the event and whenever the ticket is displayed in your app.

> FAQ
>
> 1. How often must the token be refreshed? You should refresh the token anytime a fan opens and views a ticket within your app and 20 hours prior to the event. If you are unable to refresh the token when the fan views the ticket at the gate, then the SDK would attempt to use the token refreshed 20 hours prior. The token should still be valid. You do not need to refresh the token every 20 hours.

Based on this, it might be reasonable to assume the `rawToken` is only valid for a 20 hour period, which would mean you'd need to fetch the `rawToken` at most 20 hours before the event to be able to resell or transfer it without TicketMaster's permission. However, if all you want to do is save a ticket offline, this is more than adequate. I even built a little [Expo](https://expo.dev) app I call _TicketGimp_ which renders SafeTix barcodes if you give it a `token`.

<img style="width: 300px;" src="/images/ticketmaster/ticketgimp.png">

I look forward to testing it out when my concert comes around.

## Conclusion

I think we can all agree: [Fuck TicketMaster](https://duckduckgo.com/?q=fuck+ticketmaster&ia=web). I hope their sleazy product managers and business majors read this and throw a tantrum. I hope their devs read this and feel embarrassed. It's rare that I feel genuine malice towards other developers, but to those who designed this system, I say: _Shame._

Shame on you for abusing your talent to [exclude the technologically-disadvantaged](https://www.ticketnews.com/2021/07/mobile-only-ticketing-push-leaving-many-without-smartphones-behind/).

Shame on you for letting the marketing team [dress this dark-pattern as a safety measure](https://business.ticketmaster.com/business-solutions/safetix-the-game-changer-in-digital-ticketing/).

Shame on you for supporting a company with [such cruel business practices](https://www.hollywoodreporter.com/business/business-news/live-nation-ticketmaster-class-action-1235070131/).

Software developers are the wizards and shamans of the modern age. We ought to use our powers with the austerity and integrity such power implies. You're using them to exclude people from entertainment events.

Have fun refactoring your ticket verification system.

<a style="font-size: 1.5em;" href="https://www.breakupticketmaster.com/">Break up TicketMaster</a>.
