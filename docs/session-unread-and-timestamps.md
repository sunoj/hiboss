# Session unread state and recorded timestamps

These rules hold on every native client (macOS and iOS). Code that shows a session row or a
recorded time follows them; a change to them is a product decision, not a refactor.

## Session indicators

| Indicator | Meaning | Clears when |
|---|---|---|
| Orange dot | The session needs a decision (`needsYou`) | The decision is answered or withdrawn |
| Blue dot | Unread: an agent→boss message is newer than the boss's last view of this session | The session is opened; while it stays visible in an active window/scene, new arrivals are read immediately |
| Green "Working" caption | The session has live work (`TodaySession.hasLiveWork`) | Activity stops |

- Needs-you takes priority over unread; a row shows at most one dot.
- The dot's slot is always reserved, so rows never shift when a dot appears or clears.
- Boss→agent messages never make a session unread.
- Blue means unread only. Working is never drawn as a blue dot (Today's working count is green too).
- On an emphasized (selected) row, the Working caption uses the selection's foreground; green on the
  blue selection is unreadable.

### Read-state storage

- Local to each device, in `UserDefaults`, as per-session last-read timestamps.
- Scoped per account: server URL plus the first 16 hex characters of the SHA-256 of the token.
  The token itself is never stored. A new token starts a fresh baseline.
- Baseline: the first time an account is seen, `now` is recorded, and sessions without an
  entry count as read up to it. An upgrade therefore lights nothing.
- Bounded: entries older than 30 days are dropped, and at most 500 sessions are kept.
- Not synced across devices. Reading on the Mac does not clear the iPhone's dot.

Implementations: `macos/Sources/HibossIsland/Overview/SessionReadStore.swift`,
`ios/App/SessionReads/`.

## Recorded timestamps

One formatter per client (`macos/Sources/HibossIsland/Formatting/SharedTimestamp.swift`,
`ios/App/Model/RelativeTime.swift`) and one rule everywhere a past time is shown:

| Age | zh-Hans | en |
|---|---|---|
| < 1 minute | 刚刚 | Just now |
| < 1 hour | 25分钟前 | 25 min ago |
| < 12 hours | 10小时25分钟前 / 10小时前 | 10 hr 25 min ago / 10 hr ago |
| ≥ 12 hours, today | 12:58 | 12:58 |
| yesterday | 昨天 12:58 | Yesterday 12:58 |
| earlier this year | 10月13日 12:58 | 13 Oct 12:58 |
| older | date with year | date with year |

- The user's calendar, locale and time zone are respected (the Buddhist calendar included). The
  current year is never printed, so "2569 BE" does not appear in normal use.
- Future dates (clock skew) use the absolute rules.
- Visible relative times re-render at least once a minute. Width changes must not move
  neighbouring layout; a trailing timestamp keeps its alignment, and a value in a facts list keeps
  leading alignment with its siblings.
- Deadlines are future times and keep their own countdown/absolute format, still without the
  current year.

Answer sources and channels use one brand-casing helper (iOS, iPadOS, macOS, watchOS, CLI, Web,
Telegram, Discord); `.capitalized` is only the fallback for unknown values.
