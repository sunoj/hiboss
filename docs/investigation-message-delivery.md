KB consulted: `kb 'hiboss codex agent session project registration'` and
`kb 'message title Markdown content'` matched documented-versus-wired gates,
runtime instruction scope, and shell message quoting lessons.

# Message attribution and content contract

## Confirmed implementation gaps

- Runtime detection supported aid and Claude but ignored Codex thread/session signals.
  A configured Codex identity could consequently be bypassed by default-profile selection.
- Hook installation only configured Claude's settings. Codex onboarding installed guidance
  without lifecycle hooks. Guidance alone did not register an execution session.
- Send requests read the cached session ID without registering a missing Codex session.
  Messages without a session cannot inherit the repository's session/project attribution.
- The positional `send` argument populated `body`, displayed as the title in native
  message details. `--summary` populated the push preview, and `--content` populated
  details. Sending a complete report positionally produced a long title and no details.
- Native message context displayed content verbatim rather than interpreting Markdown.

The revised contract keeps titles within 144 Unicode scalars, preserves full Markdown
details in `metadata.content`, detects Codex identity, and registers missing Codex
sessions before sending. Hook setup now supports Codex's input/output format and explicit
hook trust. The API field names and stored historical source text remain unchanged.

## Verification scope

CLI mock-server integration covers Unicode title bounds, complete Markdown file delivery,
runtime/profile selection, per-thread project registration, missing-hook recovery,
hook installation/removal, and hook JSON context. Worker integration covers send and
edit bounds, complete Markdown storage, and long boss replies.

Shared native rendering and the generated UI test target require iOS T3, plus HibossKit
and Mac checks. Focused native evidence covers Markdown blocks, inline formatting,
Unicode title preservation, light/dark details, and accessibility-size historical text.
Production message storage and deployment state are outside these local fixture checks.
