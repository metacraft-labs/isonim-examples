## conversation_app/editor_states.nim — the conversation app's editor states.
##
## This is the editor's whole setup for the conversation screen: for each
## state, the stand-in's parameters and the network profile it is shown
## under. The editor constructs the ViewModel over
## `newConversationStandIn(params).withNetwork(profile)` and renders the
## View; no state sets ViewModel signals, renders a layout of its own or
## substitutes a variant of the screen. Every control works in every state,
## because the stand-in implements every operation.

import isonim/services/network

import ./core/[standin, network_services, vm]

export standin, network_services, vm

type
  ConversationEditorState* = object
    name*: string          ## The story's name in the editor.
    description*: string
    params*: StandInParams
    profile*: NetworkProfile
    expected*: LoadPhase   ## Where the first load ends, for tests.

const ConversationStoryGroup* = "Conversation App / Pages"

proc conversationEditorStates*(): seq[ConversationEditorState] =
  @[
    ConversationEditorState(name: "Typical (4G)",
      description: "12 conversations; the reply streams over a 4G connection",
      params: standInParams(), profile: FourGNetwork,
      expected: LoadPhase.ready),
    ConversationEditorState(name: "Typical (instant)",
      description: "The same data with no network delay",
      params: standInParams(), profile: InstantNetwork,
      expected: LoadPhase.ready),
    ConversationEditorState(name: "Typical (slow 3G)",
      description: "Placeholders and backfill on a slow mobile connection",
      params: standInParams(), profile: Slow3GNetwork,
      expected: LoadPhase.ready),
    ConversationEditorState(name: "Empty (4G)",
      description: "No conversations yet; New conversation starts one",
      params: standInParams(conversationCount = 0), profile: FourGNetwork,
      expected: LoadPhase.ready),
    ConversationEditorState(name: "Large (4G)",
      description: "500 conversations backfilled in pages; long transcripts",
      params: standInParams(conversationCount = 500,
        messagesPerConversation = 60),
      profile: FourGNetwork, expected: LoadPhase.ready),
    ConversationEditorState(name: "Error (4G)",
      description: "The first screen fails to load; Retry tries again",
      params: standInParams(failing = {ServiceOp.initialScreen}),
      profile: FourGNetwork, expected: LoadPhase.failed),
    ConversationEditorState(name: "Reply breaks off (4G)",
      description: "The assistant's reply stops after a few increments",
      params: standInParams(failReplyAfterChunks = 5,
        failure = "The connection was reset"),
      profile: FourGNetwork, expected: LoadPhase.ready),
  ]

proc findConversationEditorState*(name: string;
    state: var ConversationEditorState): bool =
  for s in conversationEditorStates():
    if s.name == name:
      state = s
      return true

proc newConversationVMFor*(state: ConversationEditorState;
                           seed: int64 = 1): ConversationVM =
  ## The ViewModel of `state`: over the stand-in with the state's
  ## parameters, behind the state's network profile.
  newConversationVM(newConversationStandIn(state.params).withNetwork(
    state.profile, seed))
