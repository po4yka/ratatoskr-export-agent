## ADDED Requirements

### Requirement: One Platform operation owns the resumable transfer
The agent SHALL prepare one provider-bound operation, durably persist its transfer session before presenting progress, query acknowledged chunks after interruption, send only missing chunks, and finalize the same operation.

#### Scenario: Relaunch resumes missing chunks
- **WHEN** the application terminates after a subset of chunks are acknowledged
- **THEN** relaunch queries the original operation and sends only its missing chunks before finalization
