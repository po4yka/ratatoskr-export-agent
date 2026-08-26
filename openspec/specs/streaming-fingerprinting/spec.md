# streaming-fingerprinting Specification

## Purpose

Computes an accepted candidate's content identity - SHA-256 digest and exact byte size - by streaming the source file in bounded chunks so memory stays flat regardless of archive size. The digest becomes the local identity every later stage uses to deduplicate, preserve, upload, and verify.

## Requirements

### Requirement: Digests are computed by bounded chunked streaming

The fingerprinter SHALL read the source file in fixed-size chunks and update the hash incrementally, SHALL NOT read the whole file into memory at once, and SHALL report the lowercase hexadecimal SHA-256 digest together with the exact byte size hashed.

#### Scenario: Chunked fixture writes hash correctly

- **WHEN** a fixture file is built from many separate small appends so its logical content spans several internal hash chunks
- **THEN** the computed digest equals the published SHA-256 known-answer digest of that exact logical content, and the reported size equals the file's on-disk byte count

#### Scenario: Empty input has the empty-string digest

- **WHEN** the fingerprinter runs over a zero-byte file
- **THEN** it reports `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` with size zero

#### Scenario: Known short input matches the published vector

- **WHEN** the fingerprinter runs over a file containing exactly the bytes `abc`
- **THEN** it reports `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` with size three

### Requirement: Hashing failures surface instead of yielding a digest

When the source cannot be read to completion - vanishing mid-hash, permission loss, or a short read - fingerprinting SHALL fail with an explicit error and SHALL NOT return any digest.

#### Scenario: Source truncated mid-hash fails loudly

- **WHEN** the source file shrinks below its observed size while hashing is in progress
- **THEN** fingerprinting throws an error and produces no digest value

### Requirement: Fingerprinting never mutates the source

Running the fingerprinter over a candidate SHALL leave the source file's bytes, name, and timestamps unchanged.

#### Scenario: Source is untouched after hashing

- **WHEN** fingerprinting completes over a fixture file
- **THEN** the file's content hash, name, size, and modification time are identical to their values before the run
