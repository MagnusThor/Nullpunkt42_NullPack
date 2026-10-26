

export interface InterceptFetchOptions {
    /**
     * Path prefix to strip or match (e.g. 'assets' or 'assets/').
     * If not specified, matching occurs against the exact relative path.
     */
    prefix?: string;
}
