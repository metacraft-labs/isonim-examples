## conversation_app/measure_readiness.nim — readiness marks of the
## conversation app's editor states under chosen network profiles, as JSON.
##
## For agents and for design reviews: instead of judging by eye how fast a
## screen fills in, load each editor state under each profile on simulated
## time and read off when each element first showed real data and when it
## was complete. Runs headless and takes milliseconds of real time.
##
##   nim c -r conversation_app/measure_readiness.nim \
##     --profiles:instant,4g,slow-3g --states:"Typical (4G),Large (4G)"
##
## Options (all optional):
##   --profiles:<names>  comma-separated network presets (default: each
##                       state's own profile)
##   --states:<names>    comma-separated editor states (default: all)
##   --prompt:<text>     also send this prompt and report the reply's marks
##                       (default: "Plan my week"; empty to skip)
##
## Output: one JSON document, {"runs": [{"state", "profile", "phase",
## "marks": {...}, "reply": {...}}]}. Times are milliseconds since the load
## (or, for "reply", since the prompt was sent). A mark that never happened
## within the time limit is absent.

import std/[json, os, parseopt, strutils]

import nim_everywhere
import nim_everywhere/async_compat

import conversation_app/editor_states

const LimitMs = 120_000

proc settle(ctx: FakeAsyncContext) =
  for _ in 0 ..< 4:
    ctx.runPending()
    drainPlatformCallbacks()

proc runUntil(ctx: FakeAsyncContext; done: proc(): bool) =
  ctx.settle()
  var waited = 0
  while not done() and waited < LimitMs:
    ctx.advance(1)
    ctx.settle()
    inc waited

proc marksJson(r: ReadinessMarks): JsonNode =
  result = newJObject()
  for m in r.marks.value:
    result[m.name] = %m.atMs

proc measure*(state: ConversationEditorState; profile: NetworkProfile;
              prompt: string): JsonNode =
  ## Load `state` under `profile` on simulated time and report its marks.
  let ctx = newFakeAsyncContext()
  ctx.install()
  defer: ctx.uninstall()
  var run = state
  run.profile = profile
  let vm = newConversationVMFor(run)
  defer: vm.dispose()
  ctx.runUntil(proc(): bool =
    vm.phase.value == LoadPhase.failed or
      (vm.readiness.has("conversations") and vm.readiness.has("transcript")))
  result = %*{"state": state.name, "profile": profile.name,
              "phase": $vm.phase.value, "marks": marksJson(vm.readiness)}
  if prompt.len > 0 and vm.phase.value == LoadPhase.ready and
      vm.selectedId.value.len > 0:
    vm.setDraft(prompt)
    vm.send()
    ctx.runUntil(proc(): bool =
      vm.replyPhase.value in {ReplyPhase.idle, ReplyPhase.failed})
    result["reply"] = marksJson(vm.replyReadiness)
    if vm.replyPhase.value == ReplyPhase.failed:
      result["replyError"] = %vm.replyError.value

proc measureAll*(stateNames, profileNames: seq[string];
                 prompt: string): JsonNode =
  var runs = newJArray()
  for state in conversationEditorStates():
    if stateNames.len > 0 and state.name notin stateNames: continue
    if profileNames.len == 0:
      runs.add measure(state, state.profile, prompt)
    else:
      for name in profileNames:
        runs.add measure(state, networkPreset(name), prompt)
  %*{"runs": runs}

proc splitList(s: string): seq[string] =
  for part in s.split(','):
    let p = part.strip
    if p.len > 0: result.add p

when isMainModule:
  var states, profiles: seq[string]
  var prompt = "Plan my week"
  for kind, key, value in getopt(commandLineParams()):
    if kind in {cmdLongOption, cmdShortOption}:
      case key
      of "profiles": profiles = splitList(value)
      of "states": states = splitList(value)
      of "prompt": prompt = value
      else:
        stderr.writeLine "unknown option --" & key
        quit 2
  try:
    echo measureAll(states, profiles, prompt).pretty
  except ValueError as e:
    stderr.writeLine e.msg
    quit 2
