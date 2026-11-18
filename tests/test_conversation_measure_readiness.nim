## The readiness measurement command reports, per state and profile, the
## marks of the first load and of a reply, ordered as the profiles are.

import std/[json, unittest]

import conversation_app/measure_readiness

suite "measure_readiness":
  test "reports marks per state and profile, ordered by the profiles":
    let report = measureAll(@["Typical (4G)", "Error (4G)"],
                            @["instant", "4g", "slow-3g"], "Plan my week")
    let runs = report["runs"]
    check runs.len == 6
    let instant = runs[0]
    let fourG = runs[1]
    let slow = runs[2]
    check instant["state"].getStr == "Typical (4G)"
    check instant["phase"].getStr == "ready"
    for run in [instant, fourG, slow]:
      for mark in ["conversations:first", "conversations", "transcript"]:
        check run["marks"].hasKey(mark)
      check run["reply"].hasKey("reply:first")
      check run["reply"]["reply:first"].getInt < run["reply"]["reply"].getInt
    check instant["marks"]["conversations:first"].getInt <
      fourG["marks"]["conversations:first"].getInt
    check fourG["marks"]["conversations:first"].getInt <
      slow["marks"]["conversations:first"].getInt
    let failed = runs[4]
    check failed["state"].getStr == "Error (4G)"
    check failed["phase"].getStr == "failed"
    check not failed["marks"].hasKey("conversations")
    check not failed.hasKey("reply")

  test "an unknown profile is refused":
    expect ValueError:
      discard measureAll(@[], @["carrier-pigeon"], "")
