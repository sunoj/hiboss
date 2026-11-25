// Shared decision answerability for every web reply surface.
// Open membership comes from the server; local deadlines can only close answers.

export function answerability(
	id: string, openIds: ReadonlySet<string>, loaded: boolean,
	withdrawn: ReadonlySet<string>, deadline: string | null, now: number
): 'checking' | 'open' | 'closed' {
	if (withdrawn.has(id) || (deadline && Date.parse(deadline) <= now)) return 'closed';
	if (!loaded) return 'checking';
	return openIds.has(id) ? 'open' : 'closed';
}
