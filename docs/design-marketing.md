<!-- Marketing design for hiboss.org and the App Store listing: audience, message hierarchy,
     visual system and its relation to design v4, rejected alternatives, and how to regenerate assets. -->
# Marketing design: site and App Store

This document covers the public site in `site/`, the App Store screenshots and listing copy in
`docs/design-marketing/app-store/`, and the promotional cards in `docs/design-marketing/promo/`.
The store creative checker retains third-party brand exclusions, including the names of
removed Discord and Telegram boss channels.
The apps themselves follow `docs/design-v4.md`; nothing here changes them.

## Who it is for

1. **A developer who already lets coding agents do real work.** They run Claude Code, Codex or a
   similar agent for long tasks and have been burned by one of two things: an agent that stopped and
   waited for hours, or an agent that did not stop. They will self-host if the setup is honest and
   short. This is the primary reader of the home page and the store listing.
2. **A person running several agent sessions at once.** They need to see which session is waiting
   and answer without opening a terminal. The Sessions and Today screenshots speak to them.
3. **A reviewer deciding whether to trust it.** Before installing, they look for the licence, where
   the data goes and what the app refuses to do. The "Your server, your data" section, the privacy
   page and the "Silence is never approval" point speak to them.

The site is not written for people who have never used a coding agent. It does not explain what an
agent is.

A store visitor without a server is a special case: the listing tells them twice that the app has
a demo on its first screen, because otherwise the first launch is a sign-in form they cannot pass.

## Message hierarchy

**Headline promise: "Your agents ask. You decide."** (zh: "智能体来问，你来拍板。")
It names both parties and gives the reader the role they want. It was already the site's title and
the store's promotional line; it is now also the store subtitle, the first screenshot caption and
the Open Graph card, so every surface opens with the same words.

Four proof points follow, in this order everywhere they appear:

| # | Proof point | What backs it |
|---|---|---|
| 1 | One tap, where the question appears | Options on the Today card, notification actions, the Live Activity, the Mac Island, and the web console; first answer wins (`docs/philosophy.md` §3.6, `README.md`) |
| 2 | Silence is never approval | The card line "No answer in … picks “…”. That is not approval.", the "Default picked · not approval" banner, and `auto_default` in the CLI (`docs/reference/cli-reference.md`) |
| 3 | Quiet until it needs you | Panels and progress posts send no notification (`docs/philosophy.md` §2) |
| 4 | Your server, your data | MIT licence, Cloudflare Worker with D1 and R2 in the owner's account, no analytics SDK (`README.md`, `site/privacy/`) |

Point 2 is the one no neighbouring tool says, so it gets its own home-page section, the second
store screenshot and the square social card. Point 4 closes the page because it answers the last
question a reader has before installing.

Each claim on the site, in the listing and in the launch post was checked against the documents
named above or against the app's strings (`ios/App/Localizable.xcstrings`). Nothing states that the
iPhone app is available on the App Store: the download page still says "Coming soon".

## Visual system

### Relation to design v4

v4 gives every colour one job inside the apps and reserves the icon's colours for "where the brand
speaks: the website, onboarding, the App Store and the all-clear state"
(`docs/design-v4/mockups/Brand.dc.html`). The marketing system takes both halves literally:

- **Chrome is v4.** Page background, surfaces, text, hairlines and the filled button use `Ground`,
  `Surface`, `Ink`, `SecondaryText`, `TertiaryText` and `Hairline` with the same light and dark
  values. A screenshot placed on the page sits on the colour it was captured on.
- **`Signal`, `Live` and `Settled` keep their jobs.** They appear only as the dot in a status chip
  above a feature: `Signal` on the three decision features ("Needs you"), `Live` on panels and
  progress ("No notification"), `Settled` on the closing all-clear section. They are never used for
  links, buttons or decoration, so the orange a reader sees on the page means the same thing as the
  orange in the screenshot beside it.
- **The brand speaks through the sky and the island.** The hero and the download header sit under a
  day sky in light appearance and a night sky in dark, built from the scenes' own gradient stops
  (`#8FD0F0 → #E8F6FB`, `#0D1B2A → #1D3B52`) with the scenes' sun and moon. The island itself, from
  `docs/design-v4/scenes/`, appears once, in the closing section.
- **Shapes come from `Theme/Layout.swift`.** Buttons are 12 px rounded rectangles at least 48 px
  tall, one filled per group; cards are 16 px; chips are capsules. The previous site used capsule
  buttons and a teal accent (`#0E6B5C`) that exists nowhere in the product.

### The scene rule on marketing surfaces

v4 says the scene is used "only for the all-clear state and onboarding. Never on or next to a
decision." Marketing keeps that rule rather than relaxing it:

- The island is shown only beside the all-clear screenshot ("Nothing needs you"), at the end of the
  home page. It is never placed beside a screenshot that contains an open decision.
- The hero, the download page, the store frames and the promo cards do show decisions, so they use
  the sky and its sun or moon only: the weather of the island, not the island.

This gives the home page its shape. It opens with a question waiting under the sky and ends on the
island with nothing waiting, which is the promise the icon makes.

### Type

System fonts only (`system-ui`, then PingFang SC for Chinese), because the site loads no external
resources and the apps use the system's type. Three decisions carry the personality:

- The headline is set as two voices: "Your agents ask." at weight 500, "You decide." at weight 800.
  The agent's line is quiet; the boss's line is firm.
- Headings are large, tight and sentence case (h1 up to 76 px at −0.034em; h2 up to 44 px).
  Chinese headings drop the negative tracking and get more line height.
- No uppercase labels, no tracked-out eyebrows, no arrows on links. Where a label above a heading
  exists it is a status chip that carries the colour job described above.

Body text is 17 px at 1.55, with a measure under 36em for lead paragraphs.

### Imagery

- **Every app screen is a capture of the real app in demo mode**, taken with
  `docs/design-marketing/tools/capture.sh` on a simulator, with the status bar set to 09:41 and
  nothing retouched. The only drawn UI on the site is the existing interactive Island demo, which
  is labelled as a demo and keeps its native screenshot fallback.
- Phone and iPad bezels are plain dark rounded rectangles. They are frames, not device renderings.
- The Mac Island image is the existing native capture; no new Mac captures were made.
- No generated images are used. Image generation budget used: 0 of 12.

### Motion

The site has one orchestrated moment and it already existed: the Island demo docks to the top of the
viewport when its section scrolls into view. Nothing else animates. Buttons change border or
opacity on hover. `prefers-reduced-motion` is respected by the demo and removes the transitions.

### App Store frames

Each frame is a caption (weight 800) and one supporting line over the sky, then a real capture that
runs off the bottom edge. Light captures sit under the day sky and dark captures under the night
sky, so appearance alternates through the set without a separate colour scheme. Captions restate
the proof points in the hierarchy's order.

| # | Caption | Screen | iPad |
|---|---|---|---|
| 1 | Your agents ask. You decide. | Today with an image decision | yes |
| 2 | Silence is never approval. | Decision detail with the default notice | yes |
| 3 | Every question keeps its context. | Session thread (dark) | yes |
| 4 | See who needs you, and who is working. | Sessions list | no |
| 5 | A Box your agents can read. | Box | yes |
| 6 | Nothing needs you. | All-clear Today (dark) | yes |

The iPad set has five frames. On iPad the Sessions list shows an empty detail column until a
session is selected, and frame 3 already shows the list next to a thread.

## Creative assets: product page header and search results

One image per locale serves both placements (`PRODUCT_PAGE_HEADER_ASSET` and
`APP_STORE_SEARCH_RESULTS_ASSET`): Apple's universal asset.

| Property | Value |
|---|---|
| File | PNG, exactly 5244×2950 (16:9), no alpha channel |
| Art safe area | 1402×962 at x 1921, y 660; the headline and the island stay inside it |
| Auxiliary art area | the rest of the canvas; sky, sea, sun or moon, clouds or stars, waves |

The store crops this image differently per device, so nothing outside the safe area carries
meaning. The universal asset was chosen over a separate 3840×1646 header and a 3:2 search image
because one composition holds in every crop tried (see the previews), and one file per locale is
less to keep in step.

- **Art.** The island, alone under the sky, with the headline above it. No app screen appears, so
  the scene rule holds: the island is never beside a decision. The island is the v4 scene artwork,
  placed unchanged; the tool extends only the sky, the sea and their sun, moon, clouds, stars and
  waves across the canvas.
- **Default asset** (`creative/<locale>/universal.png`): the day scene with "Your agents ask. You
  decide." / "智能体来问，你来拍板。", set in the same two weights as the site headline.
- **Self-hosted variant** (`creative/<locale>/universal-self-hosted.png`): the night scene with
  "Your server. Your data." / "你的服务器，你的数据。", for the second custom product page.
- **Previews** (`creative/previews/`): each asset cropped to 21:9 and 3:2, wide and tight, with
  the safe area drawn as a dashed box. A wide crop keeps one full canvas dimension. A tight crop
  gives the safe area the share of the frame that Apple's separate header and search specs give
  theirs. Both are centred on the safe area; the exact crops the store applies are not published.

Regenerate and verify:

```sh
node docs/design-marketing/tools/creative.mjs docs/design-marketing/app-store/creative
docs/design-marketing/tools/check.sh
```

`check.sh` requires PNG, the exact pixel size and no alpha for every asset, and that each has its
four previews.

## Custom product pages

`app-store/custom-pages.json` is the manifest: for each page its name, purpose, and per locale the
promotional text, the ordered frames for iPhone 6.9" and iPad 13", and the creative asset. It holds
no keywords. Frames are chosen from the existing 22; no new frame is made.

| Page | For | Opens with | Frames (iPhone) | Creative asset |
|---|---|---|---|---|
| Answer from your phone | people running AI coding agents who want to answer away from the desk | the decision card | today, default, session, sessions, all-clear | default (day) |
| Self-hosted and private | people who want infrastructure they run themselves | the all-clear screen and "on a server you run" | all-clear, today, default, box, session | self-hosted (night) |

The iPad order is the same with the Sessions frame left out, since the iPad set has none. Promotional
text stays within 170 characters and names no third-party product; `check.sh` enforces both, and
that every listed frame exists for its locale and device.

## Alternatives rejected

- **A hero built from the icon's character.** The Brand sheet says the icon stays an icon and is
  never redrawn or used as decoration. A large illustrated boss would also put the island beside a
  decision.
- **An illustrated or generated hero instead of a screenshot.** The audience is deciding whether a
  tool is real. A real Today screen answers that faster than any picture, and the brief's red line
  on painted UI makes a mock-up hero unusable.
- **The `Web-Home` mockup's HTML decision card in the hero.** It is a drawing of the product, not
  the product.
- **Dark-only "terminal" styling.** It is the default look for developer tools and it would throw
  away the brand's one distinctive asset, the day and night island. Dark mode is fully supported
  instead, and gets the night sky.
- **Keeping the teal accent.** It matched nothing in the apps and competed with `Signal` and `Live`
  in every screenshot.
- **Brand colours (Sky, Lagoon, Sand, Palm) as link and button colours.** v4 reserves them for
  scenes. Links are `Ink` with an underline; the sky gradient carries the brand colour.
- **A sticky header.** The Island demo must dock at the top edge of the viewport
  (`site/test_island_dock.py`); a sticky header would fight it for the same pixels.
- **A testimonial or logo strip, usage numbers.** None exist, so none are shown.
- **"The boss is free" as the headline.** It is the brand idea, but it reads as leisure before the
  reader knows what the product does. It is expressed by the closing island instead.
- **A Live panels store frame and a Progress store frame.** The panel wall with sample panels is
  reached through onboarding's "Explore the demo", not through a launch flag, and the Progress
  demo posts describe layout cases rather than shipped work. The site keeps its earlier capture of
  the panels screen.

## Other promotional assets, and why

- `promo/og-en.jpg`, `promo/og-zh.jpg` (1200×630): the link preview. `site/assets/og.jpg` is a copy
  of the English card.
- `promo/square-en.jpg`, `promo/square-zh.jpg` (1080×1080): one card for the "Silence is never
  approval" point. It is the claim most likely to be quoted on its own, and link-preview cards crop
  badly in feeds that prefer square images.
- `promo/launch-post.md`: a launch post and a short version, in both languages.

No video, press kit or banner set was made.

## Regenerating

All tools are in `docs/design-marketing/tools/`. The compositors need `playwright-core` on
`NODE_PATH` and a local Chrome, and must run on a Mac because the text is set in the system fonts.

```sh
# 1. Build the app for the simulator (ios/README.md), then capture on a simulator you own.
docs/design-marketing/tools/capture.sh <udid> <HiBoss.app> <raw>/iphone   # iPhone 17 Pro Max
docs/design-marketing/tools/capture.sh <udid> <HiBoss.app> <raw>/ipad     # iPad Pro 13-inch
# 2. Derive everything from the raw captures.
docs/design-marketing/tools/site-shots.sh <raw>/iphone
node docs/design-marketing/tools/frame-store.mjs <raw>/iphone <raw>/ipad docs/design-marketing/app-store
node docs/design-marketing/tools/promo.mjs <raw>/iphone docs/design-marketing/promo
cp docs/design-marketing/promo/og-en.jpg site/assets/og.jpg
python3 docs/design-marketing/tools/listing.py
# 3. Copy the frames to the listing folder, then verify.
docs/design-marketing/tools/store-screenshots.sh
docs/design-marketing/tools/check.sh
```

Site renders for review are not stored in the repository. This writes 44 JPEGs (11 pages, desktop
1440 and mobile 390, light and dark) and fails on a wrong dark background, a broken image, an
off-site request, or horizontal overflow at 320, 390, 768 or 1440 px:

```sh
site/build.sh /absolute/new/site-dir
node docs/design-marketing/tools/render-site.mjs /absolute/new/site-dir /absolute/render-dir
```

The Today status chip sometimes shows a clock time instead of "Just now" right after launch; look
at the Today and all-clear captures and recapture a scene that shows one
(`capture.sh <udid> <app> <dir> today allclear`).

Captions are in `app-store/captions.json` and listing copy in `app-store/listing.json`. Raw captures
are not stored in the repository.

## Known limits

- Demo content follows the app's language (`demoCopy` in `ios/App/Preview/DemoSession.swift`):
  questions, options, Box titles and Progress posts are Chinese in the zh-Hans frames. Session
  labels, branch names and agent names stay as identifiers, as they would in a real project.
  Fixtures behind test-only launch flags (threads, notes, the media decision, the transcript
  stream) are English only.
- Demo data names no third-party service. The demo project is `storefront`.
- `panels-*.jpg` on the site is the earlier capture; the store set has no live-panels frame.
- The proposed keywords contain no third-party product names; the description names Claude Code and
  Codex as agents the product works with.
- `ios/AppStore/metadata/` is written by `tools/listing.py` and `ios/AppStore/Screenshots/` by
  `tools/store-screenshots.sh`; both are copies of what this folder holds.
