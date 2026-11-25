# Restock Radar

An iPhone app that keeps reloading the Lazada products you add and **sets off an alarm the moment one comes back in stock**.

## What it does

- **Add items:** paste a Lazada product link. Short share links such as `s.lazada.sg/…` work too.
- **Auto-refresh:** each item reloads on its own timer, from 15 seconds to 30 minutes. 1 minute is the default.
- **Stock check:** after each reload, the app reads the page:
  - an active **Add to Cart / Buy Now** button means **IN STOCK**
  - a visible **Out of Stock / Sold out** label, or greyed-out buttons, means **Out of stock**
- **Alert:** when an item flips to IN STOCK, you get a loud alarm (it plays even on silent), vibration, a full-screen green alert and a notification. Tap **Open in Lazada** to go straight to the product in the Lazada app.
- **Extras:** price shown for each item, optional price-change alerts, a history of the last 30 checks, and per-item custom detection text in case the automatic check gets one wrong.
- **Lazada's "slide to verify" check:** if Lazada shows it, the app pauses and tells you. Open the built-in browser, slide the check, then tap **Resume**.

## Important limits

1. **The app must stay open on screen.** iPhone freezes apps in the background, so checks stop when you switch away or lock the phone. Turn on **Keep screen on while watching** (on by default) and leave the phone on a charger. You'll get a reminder notification if you leave the app while it's watching.
2. **Auto-buy runs inside Restock Radar, not the Lazada app.** iPhone doesn't let one app tap buttons in another app. So Restock Radar buys through Lazada's website in its own built-in browser, logged in to your account. The Lazada app doesn't need to be open, but Restock Radar does.
3. **Don't set very short timers.** 30–60 seconds per item is the sweet spot. Faster than that makes Lazada show the verify check more often. Items are checked one at a time, so 10 items on a 15-second timer won't really refresh every 15 seconds.
4. **The stock check works by reading the page.** If Lazada changes its page design, open the item, look at **"What the app saw last time"**, and fill in **Custom detection** with the exact words the page shows (for example `Add to Cart` / `Out of Stock`).

---

## Official Pokémon store only, chosen by keyword

**Only the official store.** The built-in list holds the 55 card products sold by **Pokémon Store Online Singapore**, the official store Pokémon Singapore links to (`s.lazada.sg/a.0S2bl`).
- They come from the store's own "trading card game" listing on 25 Nov 2026.
- Deck shields, deck cases, playmats, card boxes and frames are left out, because they have no cards inside.
- The full list is in `pokemon_tcg_lazada_links.csv`.

**"What to buy" (main screen):** pick product types and sets. Every official product matching both is ticked.
- Product types: Elite Trainer Box, Booster Box (36-pack display), Booster Bundle, Sleeved Booster, Premium Collection, Ultra-Premium Collection, Build & Battle Box, ex Box, Tin, Blister, Collections (binder, poster, figure, sticker), Battle Deck.
- Sets: Delta Reign, 30th Celebration, Pitch Black, Chaos Rising, Perfect Order, Ascended Heroes, Phantasmal Flames, Mega Evolution, Prismatic Evolutions, Destined Rivals, Black Bolt, White Flare, Journey Together, Surging Sparks, 151, Paldean Fates, plus "Other products".
- On by default: ETB, Booster Box, Booster Bundle, Sleeved Booster, Premium and Ultra-Premium Collection, for every set (19 products today).

**New listings are added automatically.** While running, the app rereads the official store's card listing every 25–45 minutes (random). New products are added, and ticked if they match your keywords. Prismatic Evolutions, 151 and some others aren't sold by the official store right now. They show as "watching" and are added the moment they're listed.

**Only the official seller is ever opened or bought.** "Only the official Pokémon store" is on in Settings. A product you add yourself from another seller is checked, but the app never acts on it.

**Before your first run, tap "Check all links".** The app opens each product once, slowly, and marks it ✓ or **Link broken**.

## Two ways to buy (Settings → "When a ticked product is back")

**1. Open it in the Lazada app (default, no Mac):** Restock Radar keeps refreshing at random intervals. The moment a product is back, it opens that product in the **Lazada app**.
- You tap **Buy Now → Place Order** and approve the payment in your bank app.
- Back in Restock Radar, tap **I bought it** to move the product to **Bought**.
- iPhone doesn't let one app press buttons in another app, so those taps are yours.

**2. Buy it automatically here:** Restock Radar does the whole checkout itself, in its own Lazada browser. See "Auto-buy" below.

---

## Optional extra: LazadaBot (only if you have a Mac)

You don't need this. Restock Radar's own auto-buy (below) runs entirely on the iPhone.

An iPhone app isn't allowed to tap buttons inside another app. The one tool Apple provides that can is Xcode's UI testing. LazadaBot uses it to drive the real Lazada app on your phone. It keeps refreshing the product, then the moment it's in stock it presses Buy Now → Place Order → Pay.

**What you need:**
- A Mac with Xcode
- Your iPhone connected by cable, or over Wi-Fi once paired
- The phone unlocked, with Auto-Lock set to Never

**Set up once:**
1. On the iPhone, open the Lazada app and log in.
2. In Lazada, set a default address and default payment method. Cash on Delivery or a wallet without a PIN goes all the way through.
3. In Xcode, give both targets (**RestockRadar** and **LazadaBot**) your Apple ID team under *Signing & Capabilities*. Use unique bundle IDs.
4. On the iPhone, turn on **Developer Mode** (Settings → Privacy & Security) and **Trust** your Apple ID (Settings → General → VPN & Device Management).
5. On the iPhone, set **Settings → Display & Brightness → Auto-Lock → Never**.
6. In Xcode, open **Settings → Behaviors → Testing**. Under **Fails**, tick **Play sound**. That's how the bot tells you it needs you, for example to type a PIN.

**Each time:**
1. Open `LazadaBot/BotConfig.swift` and set:
   - `productLink` (the full `www.lazada.sg/products/…` link)
   - `maxPrice`
   - `option` (if the product has choices)
   - `placeRealOrder`
2. At the top of Xcode, pick the **LazadaBot** scheme and your iPhone.
3. Press **⌘U** (Product → Test). You'll see Lazada open on the phone and refresh every few seconds. Progress shows in Xcode's console.
4. Start with `placeRealOrder = false`. The bot stops at checkout so you can see it works. Then set it to `true`.

If Lazada asks for a PIN, OTP, CVV or slider check, the bot stops, Xcode plays the sound, and you finish on the phone.

---

## Auto-buy (buys the moment it's back)

**Setup (once):** tap the gear icon at the top left of the main screen.
1. **Log in to Lazada** inside the app. Use phone number or email; Google/Facebook login may not work inside apps.
2. In Lazada, set a **default address** and **default payment method**.
   - Lazada Wallet or Cash on Delivery go all the way through.
   - Cards usually need a bank code (OTP). When that screen appears, the app sounds the alarm and hands over to you, so you just type the code.
3. **Test mode** is ON to start with. In test mode the app goes all the way to checkout, then stops before **Place Order**.

**Adding a product:** tap **+**, paste the link, and fill in the auto-buy details right there. You can change them later by tapping the product.
- **Max total you'll pay** is required. The app won't buy if the product price or the checkout total is higher.
- **Option to pick** is only for products with choices. Type the option's exact words, for example `Elite Trainer Box`.
- Leave **Auto-buy when it's back** on. Switch it off for an alarm only.

**Paying:** the app uses whichever payment method is ticked on Lazada's checkout page, for example your saved card.
- With a card, your bank usually asks you to approve: an OTP, or a tap in your bank app. The app presses Place Order, sounds the alarm, and you approve. That takes a few seconds.
- PayNow (QR code), GrabPay and PayLah! all hand over to another app, so they always need you.

**Running it:**
1. Tick the products you want automated. **Tick all** / **Untick all** are in the list header.
2. Tap **Start**.
3. Each ticked product refreshes after a random wait, 45–90 seconds by default with an occasional longer break. You can change the range in Settings → Refresh timing.
4. When something is bought, it comes off the list and goes into **Bought**.

**Test it first.** Open any item that's in stock right now and tap **Test auto-buy now**. Watch it go to checkout. If it gets stuck, tell Claude the step it stopped at. When it works, turn Test mode off; the app asks you to confirm.

**What happens on a restock:**
1. The app presses Buy Now.
2. It picks your option, if you set one.
3. It checks the price against your max.
4. It presses Place Order, then Pay.
5. It shows **ORDER PLACED!**

If Lazada asks for a slider check, a code or a login, the alarm goes off and the page is waiting for you.

**Safety limits:**
- It buys 1 unit.
- Each product is bought once, then moved to **Bought**. To buy another, add it again.
- It gives up after 3 minutes.

Lazada's rules don't allow automated buying tools. Using one could get your account limited, so you use it at your own risk.

---

## Installing it on your iPhone

Apple only lets you put your own apps on a phone after they're built with Xcode, which runs on a Mac. Pick the route that fits what you have.

### Route A: you have a Mac (easiest, about 15 minutes)

1. Install **Xcode** from the Mac App Store (free).
2. Unzip this folder and double-click **`RestockRadar.xcodeproj`**.
3. In Xcode, click **RestockRadar** at the top of the left sidebar, choose the **RestockRadar** target, then open the **Signing & Capabilities** tab.
   - **Team:** choose **Add an Account…** and sign in with your normal Apple ID. Then pick "*Your Name* (Personal Team)".
   - **Bundle Identifier:** already set to `com.douglaslew.restockradar`. Change it only if Xcode says it is taken.
4. Plug your iPhone into the Mac and tap **Trust** on the phone.
5. On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it on, and restart when asked.
6. At the top of Xcode, choose your iPhone as the run destination, then press **▶ Run**.
7. The first time, the phone will say the developer isn't trusted. Open **Settings → General → VPN & Device Management**, tap your Apple ID, then tap **Trust**. Open the app again.

With a free Apple ID, the app stops opening after **7 days**. Plug in and press Run again to renew it. A paid Apple Developer account ($99/year) makes it last a year.

### Route B: no Mac (Windows PC + GitHub, about 30 minutes)

A free GitHub account builds the app on one of GitHub's Macs. Sideloadly then installs it from your PC.

1. Make a free account at github.com, then create a **new private repository**.
2. Upload everything in this folder (**Add file → Upload files**, then drag in the contents).
   - The `.github` folder is hidden on some computers. If it doesn't upload, choose **Add file → Create new file**, name it `.github/workflows/build-ipa.yml`, and paste in the contents of that file from this folder.
3. Open the repo's **Actions** tab, choose **Build iPhone app (.ipa)**, then **Run workflow**. Wait about 5 minutes for the green tick.
4. Click the finished run and download **RestockRadar-ipa** under *Artifacts*. Unzip it to get `RestockRadar.ipa`.
5. Install **Sideloadly** on your PC (sideloadly.io). It also needs iTunes and iCloud from Apple's website, not the Microsoft Store versions.
6. Plug in your iPhone, drag `RestockRadar.ipa` into Sideloadly, type your Apple ID, then click **Start**.
7. On the iPhone, turn on **Developer Mode** and **Trust** your Apple ID, as in Route A steps 5 and 7.

The same 7-day limit applies. Sideloadly can re-sign the app automatically while your PC is on and on the same Wi-Fi.

---

## Using it

1. In the Lazada app, open the Pokémon product, tap **Share**, then **Copy Link**.
2. In Restock Radar, tap **+**, then **Paste from clipboard**, pick a timer, and tap **Add**. The app checks it straight away and fills in the name and price.
3. Tap **Start watching**. Leave the app open with the phone plugged in.
4. When the alarm goes off, tap **Open in Lazada** and check out. For items with auto-buy armed, the app checks out for you.

Swipe left on an item to check it now or delete it. Tap an item to rename it, change its timer, switch it off, or set custom detection text.

## How the code is laid out

| File | What it does |
|---|---|
| `Monitor.swift` | The engine: the timer loop, loading pages in a hidden browser, the alarm and verify-pause logic |
| `Detector.swift` | The JavaScript that reads the page, and the rules that decide in stock or out of stock |
| `BuyScript.swift` | Auto-buy: works out which checkout step the page is on, and presses buttons by their words |
| `LazadaBot/BotConfig.swift` | Your settings for the Lazada-app bot |
| `LazadaBot/LazadaBotTests.swift` | The bot that drives the real Lazada app |
| `AutoBuySettingsView.swift` | Settings (gear icon): login, test mode, refresh timing, desktop site |
| `ItemStore.swift` | Saves your list on the phone |
| `ContentView.swift`, `AddItemView.swift`, `ItemDetailView.swift`, `Components.swift` | The screens |
| `AlarmPlayer.swift` | Alarm sound (made in code) and vibration |
| `Notifier.swift` | Notifications; tapping one opens Lazada |
