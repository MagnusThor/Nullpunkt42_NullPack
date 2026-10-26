export interface LoadBundleOptions {
    /** Automatically hijack window.fetch upon load */
    interceptFetch?: boolean;
    /** Path prefix to strip when routing fetch calls */
    fetchPrefix?: string;
}
