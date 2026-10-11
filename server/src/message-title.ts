// Validates the short title of an agent-to-boss message without truncating content.
// Exports messageTitleError; counts Unicode scalar values consistently with the CLI.

export function messageTitleError(title: string): string | null {
  return Array.from(title).length > 144
    ? 'message title exceeds 144 characters; put Markdown details in metadata.content'
    : null;
}
