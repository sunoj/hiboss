# App Store listing

Source text for the App Store Connect listing of `ai.hiboss.app`, version 1.0.0. Nothing here
is uploaded automatically; paste each file into the matching App Store Connect field.

- `metadata/<locale>/` holds one file per field for `en-US` and `zh-Hans`: `name.txt` (≤ 30
  characters), `subtitle.txt` (≤ 30), `keywords.txt` (≤ 100, comma-separated),
  `promotional_text.txt` (≤ 170), `description.txt` (≤ 4,000), `release_notes.txt` and the
  support, marketing and privacy URLs. The layout follows fastlane `deliver`.
- `metadata/review_information/notes.txt` holds the App Review notes.
- `app-privacy.md` holds the App Privacy questionnaire answers.
- `Screenshots/` holds the listing screenshots.

The push wording in the description and review notes describes the push relay
(`docs/push-relay.md`).
