## Context

`AuthenticatedPlatformHTTPClient.perform` sends a request, and on a `401` asks the authorizer to recover the credential, resends once, and on a second `401` calls `authorizationWasRejected`, which removes the stored credential. Edge relays a receiver's refusal with its status, so a Platform user missing from a receiver's account mapping reached this path after the archive was fully uploaded. Platform and the receivers change in the same round so that no longer happens; this change is the agent's own defence.

## Decisions

### Platform's verdict is recognised by the envelope code, not the status

Platform's own authentication refusal is `401` with an `ErrorEnvelope` whose `code` is `platform.auth.unauthenticated`. A small `Decodable` holding only `code` is decoded from the body; a missing, empty, malformed or different code means the `401` is not Platform's verdict. One helper, `PlatformAuthVerdict.isPlatformUnauthenticated(_:)`, is used by the client, the archive transport mapping, the operation poller and the pairing/session transport, so the rule has one definition.

### The single refresh retry stays

The first `401` still triggers one `recoverCredential` and one resend, because the agent cannot know the body is not Platform's before reading it, and a stale access credential is the common cause. Only the removal of the pairing is conditional.

### A 403 is a dedicated permanent error

`PlatformDeviceTransportError.refusedPermanently` is additive and mapped from `403` in `transportError`. `UploadQueue` already marks every non-retryable error `control = .failed`, so the queue needs no change, exactly as for `payloadTooLarge`.

## Risks

- A Platform deployment whose refresh endpoint answered `401` without the envelope would no longer re-pair. Platform's credential routes all reject through `FailureKind::Unauthenticated`, which carries the code, so this does not occur today.
