## conversation_app/core/network_services.nim — the conversation services
## behind a simulated connection.
##
## One wrapper for the whole interface: every operation goes through the same
## `NetworkSimulator`, so a profile applies uniformly to whichever
## implementation is wrapped (the stand-in in the editor, the real service in
## an integration test) and no implementation carries delays of its own.

import isonim/services/network

import ./services

export network, services

proc withNetwork*(s: ConversationServices;
                  sim: NetworkSimulator): ConversationServices =
  ConversationServices(
    loadInitialScreen: proc(pageSize: int): PlatformFuture[InitialScreen] =
      sim.simulate[:InitialScreen]("loadInitialScreen",
        proc(): PlatformFuture[InitialScreen] = s.loadInitialScreen(pageSize),
        proc(v: InitialScreen): int = v.wireSize),
    loadConversations: proc(offset, limit: int): PlatformFuture[ConversationPage] =
      sim.simulate[:ConversationPage]("loadConversations",
        proc(): PlatformFuture[ConversationPage] = s.loadConversations(offset, limit),
        proc(v: ConversationPage): int = v.wireSize),
    loadTranscript: proc(id: string): PlatformFuture[seq[Message]] =
      sim.simulate[:seq[Message]]("loadTranscript",
        proc(): PlatformFuture[seq[Message]] = s.loadTranscript(id),
        proc(v: seq[Message]): int = v.wireSize),
    createConversation: proc(title: string): PlatformFuture[ConversationSummary] =
      sim.simulate[:ConversationSummary]("createConversation",
        proc(): PlatformFuture[ConversationSummary] = s.createConversation(title),
        proc(v: ConversationSummary): int = v.wireSize),
    sendPrompt: proc(id, text: string): ServiceStream[string] =
      sim.simulateStream("sendPrompt", s.sendPrompt(id, text), textBytes))

proc withNetwork*(s: ConversationServices; profile: NetworkProfile;
                  seed: int64 = 1): ConversationServices =
  s.withNetwork(newNetworkSimulator(profile, seed))
