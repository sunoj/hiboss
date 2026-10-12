# Box v2 — list, media and detail

Second revision of the Box surfaces on iOS and macOS. The data model, API and CLI in
`docs/hiboss-box-design.md` are unchanged; this document only covers how the native clients
present Box items. Native-first rules from `docs/ios-design-contract.md` and
`docs/macos-design-v2.md` still apply.

## Shared vocabulary

Both clients use the same words, order and formats:

- Kinds: 全部 / 链接 / 文本 / 图片 / 视频 / 文件 (All / Links / Text / Images / Videos / Files).
- Author: 我 / 智能体 (Me / Agents). The words "代理" and "来自智能体" are not used.
- Relative time: "37 秒前", "3 分钟前", "昨天 22:30"; absolute time in detail: "2026年10月11日 22:30".
- Metadata line order: kind · size · relative time · author · project.

## List row

Every kind uses one row layout:

- Leading thumbnail, fixed square size (iOS 56 pt, macOS 44 pt, rounded):
  image → the image; video → a frame with a play glyph and duration; link → globe symbol;
  file → document symbol with the extension (TXT, PDF…); text → text symbol.
- Up to three lines on the trailing side: title; one line of summary (links show the domain in
  the link colour); one metadata line in secondary style.
- Rows are grouped under section headers 今天 / 昨天 / 本周 / 更早.
- At accessibility text sizes the row stacks the thumbnail above the text; titles wrap instead of
  breaking into fragments.

## Filters

- Kind: one row of compact chips (iOS) or a segmented control (macOS).
- Author: a menu button (iOS: toolbar button; macOS: "来源：全部" pop-up). Kind and author
  filters combine; choosing one never resets the other.
- Search covers titles, notes, projects, tags and link hosts.

## iOS list styles

- Two styles for the mixed list, switched by a toolbar control: **List** (the row above, default)
  and **Cards** (two equal-size columns; text and link cards show their content, never a blank
  grey placeholder). The last choice is remembered per device.
- When the kind filter is Images or Videos, the list becomes a three-column square grid like
  Photos, whichever style is selected.

## Media viewer

Images and videos open in the app's single media viewer (iOS `ios/App/Media/MediaViewer.swift`;
the macOS viewer offers the same controls):

- Top: Close, a position counter ("2 / 7"), Share.
- Bottom: title, note, author and time; actions Copy, Info, Delete.
- Swipe left/right pages through the images and videos of the current filtered result.
- A single tap toggles the chrome; pinch and double tap zoom; videos use the system player
  controls. All controls are at least 44 pt.

## Detail

One detail layout for every kind:

- Preview (image, video frame, link card, file icon, or the full text).
- Title and note.
- An information group: author, project, tags, format and size, added time.
- Actions: Copy, Edit note, Delete. Links add Open; files add Open/Quick Look.
- Delete always asks for confirmation (iOS alert, macOS dialog) naming the item, and states that
  agents can no longer read it.
- iOS list rows also offer swipe actions: trailing Delete (same confirmation), leading Share.
- Closing a file preview returns to the detail.

## macOS layout

- Window: sidebar, list column, and a persistent detail pane on the right.
- Selecting a row shows the detail pane (large preview plus everything in Detail). With nothing
  selected the pane shows an empty state.
- Pane actions: Quick Look, Open, Copy, Share…, Delete….
- Space opens Quick Look for the selection; ↑/↓ move the selection; ⌫ asks to delete.
- Rows carry no inline Open/Delete buttons; the context menu has the same actions as the pane.
- The window title appears once.

## Verification

- iOS: tier T2 per screen (Box list, detail, viewer) with screenshots in both languages and at a
  large text size; T3 if shared components change.
- macOS: `swift build`, `swift test`, and screenshots of the list with and without a selection.
