export interface Env {
	/** KV namespace holding the cached skill files. */
	SKILL_CACHE: KVNamespace;

	/** Source URL of the first skill file in SKILLS. */
	SKILL_SOURCE_URL?: string;
	/**
	 * Comma separated skill files served as /<file>. An entry "file|url" sets its source;
	 * the first entry without a url uses SKILL_SOURCE_URL, later ones are resolved relative to it.
	 */
	SKILLS?: string;
	/** A cached copy older than this (minutes) is refreshed in the background on request. */
	REFRESH_MINUTES?: string;
	/** Timeout in seconds for requests to the source. */
	TIMEOUT?: string;
}
