# Project working language

Use English for all new or modified code comments, documentation, plans, test
names, and commit messages. Chinese is permitted only in conversation with the
user. Preserve intentional localization resources and language-specific test
fixtures; this rule does not require removing supported product languages.

# Public source

Publish technical facts about the code and product only. Do not publish internal
organization arrangements, process notes, plans, or accepted-risk decisions.
Describe limitations as properties of the code.

# Verification

Before running iOS tests, read "iOS verification tiers" in `CLAUDE.md` and run only the
tier that matches the changed paths.

Before running macOS tests, read "macOS verification tiers" in `CLAUDE.md`. Run
`macos/scripts/verify-tier.sh` to get the tier and the exact filtered command. Window tests
open real windows on the boss's working Mac, so never run the full `HibossIslandTests`
outside M5, and keep to the per-task run limits.
