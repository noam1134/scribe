/** Shorter keys are refused outright: the key is the only lock. */
export const MIN_KEY_LENGTH = 32;

/**
 * Whether the path's key is the deployment's. Constant-time: both sides are
 * hashed to equal-length digests before comparing. Without a usable
 * `MAILBOX_KEY` nothing matches.
 */
export async function keyMatches(given: string, expected: string | undefined): Promise<boolean> {
	if (!expected || expected.length < MIN_KEY_LENGTH) {
		console.error(JSON.stringify({ event: "mailbox_key_unusable", message: `MAILBOX_KEY must be set and at least ${MIN_KEY_LENGTH} characters` }));
		return false;
	}
	const encoder = new TextEncoder();
	const [a, b] = await Promise.all([
		crypto.subtle.digest("SHA-256", encoder.encode(given)),
		crypto.subtle.digest("SHA-256", encoder.encode(expected)),
	]);
	return crypto.subtle.timingSafeEqual(a, b);
}
