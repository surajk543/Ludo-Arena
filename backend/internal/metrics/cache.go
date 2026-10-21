package metrics

// Hot-path caches and background work (docs/architecture.md → PostgreSQL on
// the hot path).
var (
	// CacheLookups counts read-through cache lookups. result: hit | miss
	// (filled from PostgreSQL) | verify (cached set lacked the member;
	// answered by PostgreSQL) | error (Redis failed; answered by PostgreSQL).
	CacheLookups = counter("cache_lookups_total", "Redis read-through cache lookups by cache and result.", "cache", "result")
	// CacheWriteErrors counts failed cache fills / invalidations. A failed
	// invalidation can leave a stale entry until its TTL expires.
	CacheWriteErrors = counter("cache_write_errors_total", "Failed Redis cache writes by cache and operation.", "cache", "op")
	// AsyncJobs counts background jobs run off the request path. result: ok
	// | error | panic | dropped (queue full or shutting down) | abandoned
	// (still queued when the shutdown drain deadline passed).
	AsyncJobs = counter("async_jobs_total", "Background jobs by name and result.", "job", "result")
)
