## helpers/conversation_drive.nim — fake-time helpers for the conversation
## app tests.

import nim_everywhere
import nim_everywhere/async_compat

export nim_everywhere, async_compat

proc settle*(ctx: FakeAsyncContext) =
  ## Fire everything due now, including future callbacks, without moving
  ## the clock.
  for _ in 0 ..< 4:
    ctx.runPending()
    drainPlatformCallbacks()

proc step*(ctx: FakeAsyncContext; ms: int) =
  ## Advance `ms` milliseconds one at a time, so each callback fires at the
  ## time it was scheduled for and readiness marks are exact.
  ctx.settle()
  for _ in 0 ..< ms:
    ctx.advance(1)
    ctx.settle()

proc stepUntil*(ctx: FakeAsyncContext; limitMs: int;
                done: proc(): bool): int =
  ## Advance until `done()` holds, at most `limitMs`; returns the
  ## milliseconds advanced.
  ctx.settle()
  while not done() and result < limitMs:
    ctx.advance(1)
    ctx.settle()
    inc result
