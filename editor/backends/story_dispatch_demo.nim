## editor/backends/story_dispatch_demo.nim — shared RS-M12 mount /
## mutation logic for the four native launchers (TUI / GPUI / Freya /
## Cocoa) and the Android host-side launcher.
##
## The renderer-specific launchers each maintain a single live
## `TaskAppVM` / `SettingsVM` across `select-story` events; the
## procs here reconfigure that VM (filter / active group / seed
## tasks) so the user-visible composition root reflects the
## requested story. This preserves the rendered surface and keeps
## the bridge's manifestKey-driven cadence intact.
##
## Spec: RS-M12 § *Scope* —
## ``codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org``.

import std/[json, strutils]

import isonim/core/signals

import nim_everywhere/async_compat

import isonim_render_serve

import task_app/core/vm as task_vm
import task_app/core/story_ids as task_ids
import settings_app/core/vm as settings_vm
import settings_app/core/story_ids as settings_ids

# ---------------------------------------------------------------------------
# Task app story dispatch.
# ---------------------------------------------------------------------------

proc drainOps() =
  ## The task_app VM uses an async DB; every write requires the
  ## platform event-loop to advance one tick before the resource
  ## refreshes. Without this drain the launcher's reactive graph
  ## would never see the new task list and the bridge's
  ## manifestKey-driven cadence would never re-emit. We drain
  ## generously (10 iterations) because a single addTask can chain
  ## save → onComplete → refresh → fetch → onComplete steps.
  for _ in 0 ..< 10:
    drainPlatformCallbacks()

proc seedTaskInboxDefaults*(vm: TaskAppVM) =
  ## Plant the three sample tasks every launcher mounts at startup.
  ## Kept public so a launcher's pre-RS-M12 mount path can call it
  ## directly.
  vm.addTask("Buy groceries"); drainOps()
  vm.addTask("Walk the dog"); drainOps()
  vm.addTask("Ship EX-M14"); drainOps()

proc clearTaskState*(vm: TaskAppVM) =
  let snapshot = vm.tasks.data.val
  for t in snapshot:
    vm.removeTask(t.id)
    drainOps()

proc seedTaskTwoActive(vm: TaskAppVM) =
  vm.addTask("Pick up groceries"); drainOps()
  vm.addTask("Reply to design feedback"); drainOps()
  vm.setFilter(fmAll)

proc seedTaskMixed(vm: TaskAppVM) =
  vm.addTask("Pick up groceries"); drainOps()
  vm.addTask("Reply to design feedback"); drainOps()
  let tasks = vm.tasks.data.val
  if tasks.len >= 2:
    vm.toggleTask(tasks[1].id); drainOps()

proc applyTaskStory*(vm: TaskAppVM; storyId: string) =
  ## RS-M12 task_app story-id → VM-state mapping. Story IDs that
  ## aren't specialised fall back to "Inbox defaults" with a stderr
  ## warning so the user can observe which IDs need explicit
  ## handling.
  if vm == nil: return
  clearTaskState(vm)
  case storyId
  of task_ids.TaskAppPagesInbox:
    seedTaskInboxDefaults(vm)
    vm.setFilter(fmAll)
  of task_ids.TaskAppPagesToday:
    seedTaskInboxDefaults(vm)
    vm.setFilter(fmActive)
  of task_ids.TaskAppPagesCompleted:
    seedTaskInboxDefaults(vm)
    let tasks = vm.tasks.data.val
    for t in tasks:
      vm.toggleTask(t.id); drainOps()
    vm.setFilter(fmCompleted)
  of task_ids.TaskAppTaskListEmpty, task_ids.TaskAppTaskInputEmpty:
    vm.setFilter(fmAll)
  of task_ids.TaskAppTaskListTwoActive:
    seedTaskTwoActive(vm)
  of task_ids.TaskAppTaskListMixedCompletion:
    seedTaskMixed(vm)
  of task_ids.TaskAppFilterBarAllSelected:
    seedTaskInboxDefaults(vm); vm.setFilter(fmAll)
  of task_ids.TaskAppFilterBarActiveSelected:
    seedTaskInboxDefaults(vm); vm.setFilter(fmActive)
  of task_ids.TaskAppFilterBarCompletedSelected:
    seedTaskInboxDefaults(vm)
    let tasks = vm.tasks.data.val
    if tasks.len > 0:
      vm.toggleTask(tasks[0].id); drainOps()
    vm.setFilter(fmCompleted)
  of task_ids.TaskAppSummaryBarActiveOnly:
    vm.addTask("One thing left"); drainOps()
    vm.setFilter(fmAll)
  of task_ids.TaskAppSummaryBarWithCompleted:
    seedTaskMixed(vm)
  else:
    stderr.writeLine "launcher: unknown task_app storyId \"" &
                      storyId & "\" — falling back to Inbox defaults"
    seedTaskInboxDefaults(vm)

# ---------------------------------------------------------------------------
# Settings app story dispatch.
# ---------------------------------------------------------------------------

proc applySettingsStory*(vm: SettingsVM; storyId: string) =
  if vm == nil: return
  case storyId
  of settings_ids.SettingsAppPagesPreferences,
     settings_ids.SettingsAppPagesAppearanceGroup,
     settings_ids.SettingsAppGroupAppearance,
     settings_ids.SettingsAppToggleItemOff,
     settings_ids.SettingsAppToggleItemOn,
     settings_ids.SettingsAppChoiceItemDefault,
     settings_ids.SettingsAppChoiceItemAlternate,
     settings_ids.SettingsAppNumberItemDefault,
     settings_ids.SettingsAppNumberItemClamped:
    discard vm.setActiveGroup("appearance")
  of settings_ids.SettingsAppPagesEditorGroup,
     settings_ids.SettingsAppGroupEditor:
    discard vm.setActiveGroup("editor")
  of settings_ids.SettingsAppGroupNotifications:
    discard vm.setActiveGroup("notifications")
  else:
    stderr.writeLine "launcher: unknown settings_app storyId \"" &
                      storyId & "\" — keeping current active group"

# ---------------------------------------------------------------------------
# Mutation dispatch — small, conservative table; per-renderer follow-up
# work expands the mapping. Unhandled mutations are logged so the
# editor's inspector commits are observable in launcher stderr.
# ---------------------------------------------------------------------------

proc applyTaskMutation*(vm: TaskAppVM; target, key: string;
                        value: JsonNode; scope: MutationScope) =
  if vm == nil: return
  if value == nil:
    stderr.writeLine "launcher: apply-mutation \"" & target &
                      "\".\"" & key & "\" has nil value"
    return
  const TaskRowPrefix = "task_app/views/TaskRow#"
  if key == "completed" and target.startsWith(TaskRowPrefix):
    try:
      let idStr = target[TaskRowPrefix.len .. ^1]
      let id = parseInt(idStr)
      vm.toggleTask(id)
      drainOps()
    except ValueError:
      discard
  else:
    stderr.writeLine "launcher: apply-mutation logged: " &
                      target & "." & key & " (scope=" & $scope & ")"

proc applySettingsMutation*(vm: SettingsVM; target, key: string;
                            value: JsonNode; scope: MutationScope) =
  if vm == nil or value == nil: return
  stderr.writeLine "launcher: settings apply-mutation logged: " &
                    target & "." & key & " (scope=" & $scope & ")"
