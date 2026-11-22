//! Small time-based caches for probes whose answer changes rarely.
//!
//! The menubar app links this crate and polls every 10–30 seconds. Asking
//! `ddev list` (which talks to Docker per project) or scanning the
//! diagnostic reports that often would make the monitor a load of its
//! own. The CLI runs once per process, so for it every lookup is a miss.
//!
//! After an action the app needs the truth, not a cached answer:
//! `invalidate_all` makes every cache miss on its next use.

use std::collections::HashMap;
use std::hash::Hash;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

static EPOCH: AtomicU64 = AtomicU64::new(0);

pub fn invalidate_all() {
    EPOCH.fetch_add(1, Ordering::SeqCst);
}

fn epoch() -> u64 {
    EPOCH.load(Ordering::SeqCst)
}

struct Entry<T> {
    stored: Instant,
    epoch: u64,
    value: T,
}

impl<T: Clone> Entry<T> {
    fn fresh(&self, ttl: Duration, sticky: bool) -> Option<T> {
        let current = sticky || self.epoch == epoch();
        (current && self.stored.elapsed() <= ttl).then(|| self.value.clone())
    }
}

/// One value, e.g. the result of `ddev list`.
pub(crate) struct Ttl<T> {
    slot: Mutex<Option<Entry<T>>>,
    sticky: bool,
}

impl<T: Clone> Ttl<T> {
    pub(crate) const fn new() -> Self {
        Self {
            slot: Mutex::new(None),
            sticky: false,
        }
    }

    /// For facts no action can change (core count, installed memory):
    /// `invalidate_all` leaves these alone.
    pub(crate) const fn sticky() -> Self {
        Self {
            slot: Mutex::new(None),
            sticky: true,
        }
    }

    /// Errors are never cached: a probe that failed is retried next time.
    pub(crate) fn get_or_try<E>(
        &self,
        ttl: Duration,
        compute: impl FnOnce() -> Result<T, E>,
    ) -> Result<T, E> {
        if let Ok(guard) = self.slot.lock() {
            if let Some(value) = guard
                .as_ref()
                .and_then(|entry| entry.fresh(ttl, self.sticky))
            {
                return Ok(value);
            }
        }
        let started = epoch();
        let value = compute()?;
        if let Ok(mut guard) = self.slot.lock() {
            *guard = Some(Entry {
                stored: Instant::now(),
                epoch: started,
                value: value.clone(),
            });
        }
        Ok(value)
    }
}

/// One value per key, e.g. the newest transcript per project folder.
pub(crate) struct KeyedTtl<K, V> {
    map: Mutex<Option<HashMap<K, Entry<V>>>>,
    sticky: bool,
}

impl<K: Eq + Hash + Clone, V: Clone> KeyedTtl<K, V> {
    pub(crate) const fn new() -> Self {
        Self {
            map: Mutex::new(None),
            sticky: false,
        }
    }

    /// See [`Ttl::sticky`].
    pub(crate) const fn sticky() -> Self {
        Self {
            map: Mutex::new(None),
            sticky: true,
        }
    }

    pub(crate) fn get_or(&self, key: &K, ttl: Duration, compute: impl FnOnce() -> V) -> V {
        if let Ok(guard) = self.map.lock() {
            let hit = guard
                .as_ref()
                .and_then(|map| map.get(key))
                .and_then(|entry| entry.fresh(ttl, self.sticky));
            if let Some(value) = hit {
                return value;
            }
        }
        let started = epoch();
        let value = compute();
        if let Ok(mut guard) = self.map.lock() {
            guard.get_or_insert_with(HashMap::new).insert(
                key.clone(),
                Entry {
                    stored: Instant::now(),
                    epoch: started,
                    value: value.clone(),
                },
            );
        }
        value
    }

    /// A cached value regardless of age, for entries that stay valid as
    /// long as their key does (still subject to `invalidate_all`).
    pub(crate) fn peek(&self, key: &K) -> Option<V> {
        let guard = self.map.lock().ok()?;
        let entry = guard.as_ref()?.get(key)?;
        (self.sticky || entry.epoch == epoch()).then(|| entry.value.clone())
    }

    /// Drops every key the caller no longer cares about, so the map
    /// cannot grow with keys that will never be asked for again.
    pub(crate) fn retain(&self, keep: impl Fn(&K) -> bool) {
        if let Ok(mut guard) = self.map.lock() {
            if let Some(map) = guard.as_mut() {
                map.retain(|key, _| keep(key));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    /// `invalidate_all` is process-wide, so the tests that depend on a
    /// cache hit must not overlap with the one that invalidates.
    static SERIAL: Mutex<()> = Mutex::new(());

    #[test]
    fn sticky_caches_survive_invalidation() {
        let _guard = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let cache: Ttl<u32> = Ttl::sticky();
        let ttl = Duration::from_secs(60);
        assert_eq!(cache.get_or_try(ttl, || Ok::<u32, ()>(1)), Ok(1));
        invalidate_all();
        assert_eq!(cache.get_or_try(ttl, || Ok::<u32, ()>(2)), Ok(1));

        let keyed: KeyedTtl<u8, u32> = KeyedTtl::sticky();
        assert_eq!(keyed.get_or(&1, ttl, || 5), 5);
        invalidate_all();
        assert_eq!(keyed.peek(&1), Some(5));
    }

    #[test]
    fn computes_once_within_the_ttl_and_again_after_invalidation() {
        let _guard = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let cache: Ttl<u32> = Ttl::new();
        let calls = Cell::new(0);
        let read = || {
            cache.get_or_try(Duration::from_secs(60), || {
                calls.set(calls.get() + 1);
                Ok::<u32, ()>(calls.get())
            })
        };
        assert_eq!(read(), Ok(1));
        assert_eq!(read(), Ok(1));
        invalidate_all();
        assert_eq!(read(), Ok(2));
    }

    #[test]
    fn a_value_computed_across_an_invalidation_is_not_served_afterwards() {
        let _guard = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let ttl = Duration::from_secs(60);
        let cache: Ttl<u32> = Ttl::new();
        let stale = cache.get_or_try(ttl, || {
            invalidate_all();
            Ok::<u32, ()>(1)
        });
        assert_eq!(stale, Ok(1));
        assert_eq!(cache.get_or_try(ttl, || Ok::<u32, ()>(2)), Ok(2));

        let keyed: KeyedTtl<u8, u32> = KeyedTtl::new();
        keyed.get_or(&1, ttl, || {
            invalidate_all();
            1
        });
        assert_eq!(keyed.get_or(&1, ttl, || 2), 2);
    }

    #[test]
    fn a_zero_ttl_always_recomputes_and_errors_are_not_cached() {
        let _guard = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let cache: Ttl<u32> = Ttl::new();
        assert_eq!(
            cache.get_or_try(Duration::ZERO, || Err::<u32, &str>("down")),
            Err("down")
        );
        assert_eq!(
            cache.get_or_try(Duration::from_secs(60), || Ok::<u32, &str>(7)),
            Ok(7)
        );
        std::thread::sleep(Duration::from_millis(5));
        assert_eq!(
            cache.get_or_try(Duration::ZERO, || Ok::<u32, &str>(8)),
            Ok(8)
        );
    }

    #[test]
    fn keyed_cache_keeps_keys_apart_and_can_be_pruned() {
        let _guard = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let cache: KeyedTtl<String, u32> = KeyedTtl::new();
        let ttl = Duration::from_secs(60);
        assert_eq!(cache.get_or(&"a".to_string(), ttl, || 1), 1);
        assert_eq!(cache.get_or(&"b".to_string(), ttl, || 2), 2);
        assert_eq!(cache.get_or(&"a".to_string(), ttl, || 9), 1);
        cache.retain(|key| key == "b");
        assert_eq!(cache.get_or(&"a".to_string(), ttl, || 9), 9);
        assert_eq!(cache.get_or(&"b".to_string(), ttl, || 9), 2);
    }
}
