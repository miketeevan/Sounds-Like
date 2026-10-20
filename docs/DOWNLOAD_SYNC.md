# Download sync verification — 20 October 2026

Download intentions sync using the existing iCloud key-value entitlement. Each iPhone/iPad downloads its own offline HLS package. Foreground launch and cloud notifications reconcile the list; iOS controls background delivery. Deletions carry timestamped tombstones; newer explicit retries win. Listening history is retained separately.

Existing device downloads migrate into the shared list. The Downloads deletion confirmation describes removal on both devices. Failed transfers remain visible for manual retry rather than repeatedly retrying automatically.

Validation: iOS build passed; installed and launched on physical iPhone and iPad. Both devices contain identical synced download request records for three episodes. Timestamp ordering, deletion versus stale addition, explicit retry and request serialization checks passed. A physical two-device deletion was not performed to avoid deleting the user's saved shows.
