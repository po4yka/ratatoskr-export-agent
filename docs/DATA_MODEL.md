# Export Agent local data model

## Durable local records

- directory scopes/bookmark references and access health.
- candidate files: opaque local ID, safe provider hint, stability observations.
- archive items: hash, size, provider classification, received/archive time, local relative object name.
- journal entries: lifecycle, attempts, next retry, safe error, operation/upload IDs.
- upload parts/checkpoints and backend result/completeness summary.
- reminder preferences and last successful backup/import times.

## Sensitive storage

Device tokens/keys and pairing material live only in Keychain. Local database contains references, never secret bytes or archive content.

## Constraints

Hash is the idempotent archive identity. State transitions are transactional. Paths are not synced/logged and are represented relative to approved roots where possible. Archive files are immutable after acceptance. Cleanup never removes the only preserved copy or active upload. The current schema is created fresh and its state transitions are crash-safe; development status does not permit migrations.
