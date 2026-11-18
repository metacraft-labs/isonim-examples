## isonim-examples/editor/conversation_mount.nim — mounts the conversation
## app's stories live into the editor's preview.
##
## For a story of the "Conversation App / Pages" group, the mount hook
## builds the ViewModel of its editor state (the stand-in with the state's
## parameters, behind the state's network profile) and renders the View into
## the preview frame with the browser renderer. Everything works as in the
## product: the list backfills, prompts stream replies, Retry and New
## conversation do what they say. The editor disposes of the ViewModel and
## its effects when the story is left (the mount runs in its own root).
##
## Stories of other groups are not mounted; their preview is the document
## the preview hook returns.

import isonim/editor/types
from isonim/editor/viewmodels import PreviewMountHook, PreviewMountHost

import conversation_app/editor_states

proc isConversationStory*(story: StoryRef): bool =
  var state: ConversationEditorState
  story.group == ConversationStoryGroup and
    findConversationEditorState(story.name, state)

when defined(js):
  import std/dom
  import isonim/core/owner
  import isonim/editor/dom_renderer
  import conversation_app/core/views

  proc demoPreviewMount*(story: StoryRef; host: PreviewMountHost) =
    var state: ConversationEditorState
    if story.group != ConversationStoryGroup or
        not findConversationEditorState(story.name, state):
      return
    let vm = newConversationVMFor(state)
    let r = DomRenderer(doc: host.ownerDocument)
    let root = renderConversationApp[DomRenderer, DomElement](r, vm)
    r.setAttribute(root, "data-editor-state", state.name)
    r.setAttribute(root, "data-network-profile", state.profile.name)
    host.appendChild(root)
    # The ViewModel owns a reactive root of its own; release it with the
    # mount.
    onCleanup proc() = vm.dispose()
else:
  let demoPreviewMount*: PreviewMountHook = nil
    ## Mounting needs a browser; native builds keep the document preview.
