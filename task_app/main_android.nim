## task_app/main_android.nim — Layer-4 composition root for the Android target.
##
## Order matters: the leaves module exports the leaf names (`appShell`,
## `taskInput`, ...) used by `core/views.nim`; the `include` of
## `core/views.nim` resolves those names against the imported leaves
## here.
##
## The whole composition root body is gated with `when defined(android)`
## because `isonim_android/renderer` requires either `-d:mockJni`
## (host-side test shim) or `-d:commandBuffer` (real Android JNI bridge)
## to be set — `isonim_android/jni_callbacks` raises a hard `{.error.}`
## otherwise. On Linux this module compiles as an empty shell so that
## `isonim-examples`'s default `just test` keeps working unchanged
## while the cross-compile gate (`tests/test_android_leaves_compile.nim`)
## drives the Android-target check from the same Linux host.
##
## On Android the composition root mirrors EX-M3 (`main_gpui.nim`),
## EX-M4 (`main_freya.nim`), and EX-M5 (`main_cocoa.nim`):
##   - Headless (default): builds the tree against `AndroidRenderer`
##     for programmatic interaction. Suitable for automated testing —
##     the MockJNI shim records the view tree in-process with no
##     emulator required.
##   - Window mode (`-d:androidGui`): exposes the same composition root
##     as a JNI library entry point (`buildTaskAppUI`) that the
##     Kotlin/Java host shell calls into to render the tree via the
##     command buffer. Unlike Cocoa's `-d:cocoaGui` (which owns an
##     AppKit event loop via `nsAppRun`), on Android the platform's
##     main looper is owned by the Kotlin host (the `MainActivity` in
##     `isonim-android/app/`), so Nim runs as a co-operative library
##     and the host shell drives the lifecycle. The JNI export pattern
##     mirrors `isonim_android/android_entry_native` and pairs with
##     RS-M6 for the streaming/screencap surface.
##
## To run the headless demo on a host with the MockJNI shim available
## (from the workspace root):
##
##   nim c -r -d:android -d:mockJni isonim-examples/task_app/main_android.nim
##
## To cross-compile the `-d:androidGui` library variant for a real Android
## target (arm64-v8a; ABI of the connected `R5CX1130V0X` device):
##
##   NDK_CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android34-clang"
##   nim c --os:android --cpu:arm64 --cc:clang \
##     --clang.exe:"$NDK_CC" --clang.linkerexe:"$NDK_CC" \
##     --passC:-fPIC --passL:"-shared -llog -nostdlib++ -lc++_static -lc++abi" \
##     --app:lib --noMain --mm:orc \
##     -d:android -d:commandBuffer -d:androidGui \
##     -o:libtask_app.so \
##     isonim-examples/task_app/main_android.nim

when defined(android):
  import isonim_android/renderer

  import task_app/core/vm
  import task_app/android/leaves

  export renderer, vm, leaves

  include task_app/core/views

  proc buildTaskApp*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
    ## Convenience wrapper exported for tests. Mirrors what `runApp`
    ## would do in a production driver: build the tree, return the root.
    renderTaskApp(r, vm)

  proc runTaskApp*(vm: TaskAppVM): AndroidElement =
    ## Build the task app against a fresh `AndroidRenderer` and return
    ## the root node. Resets the per-thread leaves table + the Android
    ## renderer's element tracking + the callback registry so successive
    ## test cases don't leak state into each other.
    resetAndroidLeaves()
    resetRenderer()
    let r = AndroidRenderer()
    buildTaskApp(r, vm)

  when isMainModule:
    import isonim/core/owner
    when defined(androidGui):
      # Window-mode wiring: on Android the Kotlin host shell drives the
      # platform main looper; this Nim module is built as a library
      # (`--app:lib --noMain`) and exposes JNI entry points that the
      # host calls to populate the command buffer with the task app's
      # view tree, to read the buffer back, and to dispatch UI events.
      # The host iterates `cmdbuf.commandBuffer` via the read-side
      # getter procs below and materialises real `android.view.View`
      # instances; events fire back into Nim via `handleEvent` which
      # routes through the callback registry to the VM action that the
      # leaves attached at the matching `addEventListener` call site.
      #
      # Symbol names are namespaced to
      # `Java_com_metacraft_isonim_examples_TaskAppBridge_*` so they
      # co-exist with the legacy
      # `Java_com_metacraft_isonim_android_NimBridge_*` exports during
      # the migration window. Surface shape mirrors
      # `isonim-android/nim-lib/src/isonim_android/android_entry_native.nim`,
      # so a Kotlin host shell can be lifted from the legacy
      # `NimBridge.kt` pattern with only the JNI-prefix swapped.
      import isonim_android/command_buffer as cmdbuf
      import isonim_android/callbacks
      import isonim_android/capture as androidCapture
      import isonim_render_serve/adapters/android_adapter
      import isonim_render_serve/packet as renderPacket
      type
        JNIEnvPtr = androidCapture.JNIEnvPtr
        JClass = pointer
        JString = pointer
        JByteArray = pointer
        JInt = cint
        JLong = clonglong

      # JNI function table indices (from jni.h — stable across
      # all Android versions).
      const
        idxNewStringUTF = 167
        idxGetStringUTFChars = 169
        idxReleaseStringUTFChars = 170

      proc newStringUTF(env: JNIEnvPtr; s: cstring): JString =
        let fn = cast[proc(env: JNIEnvPtr; s: cstring): JString
            {.cdecl.}](env[][idxNewStringUTF])
        fn(env, s)

      proc getStringUTFChars(env: JNIEnvPtr; s: JString;
                              isCopy: ptr bool): cstring =
        let fn = cast[proc(env: JNIEnvPtr; s: JString; isCopy: ptr bool):
            cstring {.cdecl.}](env[][idxGetStringUTFChars])
        fn(env, s, isCopy)

      proc releaseStringUTFChars(env: JNIEnvPtr; s: JString;
                                  chars: cstring) =
        let fn = cast[proc(env: JNIEnvPtr; s: JString; chars: cstring)
            {.cdecl.}](env[][idxReleaseStringUTFChars])
        fn(env, s, chars)

      proc JNI_OnLoad*(vm: pointer; reserved: pointer): JInt
          {.exportc, cdecl, dynlib.} =
        result = 0x00010006  # JNI_VERSION_1_6

      const jniPrefix = "Java_com_metacraft_isonim_examples_TaskAppBridge_"

      var appVm {.global.}: TaskAppVM

      template cmdLen(): JInt = JInt(cmdbuf.commandBuffer.len)
      template cmd(i: JInt): cmdbuf.UICommand = cmdbuf.commandBuffer[i]

      proc buildTaskAppUI(env: JNIEnvPtr; cls: JClass): JInt
          {.exportc: jniPrefix & "buildTaskAppUI", cdecl, dynlib.} =
        cmdbuf.commandBuffer.setLen(0)
        cmdbuf.nextHandle = 1
        resetCallbacks()
        resetAndroidLeaves()
        appVm = newTaskAppVM()
        discard runTaskApp(appVm)
        cmdLen()

      proc rebuildTaskAppUI(env: JNIEnvPtr; cls: JClass): JInt
          {.exportc: jniPrefix & "rebuildTaskAppUI", cdecl, dynlib.} =
        ## Full re-render from a clean command buffer using the existing
        ## VM. Callbacks are re-registered (the previous ids are
        ## superseded once the host re-binds listeners against the new
        ## command buffer). This is the entry point the Kotlin host
        ## calls after any user event so the rebuilt View tree replaces
        ## the previous one wholesale.
        cmdbuf.commandBuffer.setLen(0)
        cmdbuf.nextHandle = 1
        resetCallbacks()
        resetAndroidLeaves()
        if appVm.isNil:
          appVm = newTaskAppVM()
        discard runTaskApp(appVm)
        cmdLen()

      proc getCommandCount(env: JNIEnvPtr; cls: JClass): JInt
          {.exportc: jniPrefix & "getCommandCount", cdecl, dynlib.} =
        cmdLen()

      proc getCommandKind(env: JNIEnvPtr; cls: JClass; index: JInt): JString
          {.exportc: jniPrefix & "getCommandKind", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          newStringUTF(env, cstring($cmd(index).kind))
        else:
          newStringUTF(env, "")

      proc getCommandHandle(env: JNIEnvPtr; cls: JClass; index: JInt): JLong
          {.exportc: jniPrefix & "getCommandHandle", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          JLong(cmd(index).handle)
        else:
          0

      proc getCommandTag(env: JNIEnvPtr; cls: JClass; index: JInt): JString
          {.exportc: jniPrefix & "getCommandTag", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          newStringUTF(env, cstring(cmd(index).tag))
        else:
          newStringUTF(env, "")

      proc getCommandName(env: JNIEnvPtr; cls: JClass; index: JInt): JString
          {.exportc: jniPrefix & "getCommandName", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          newStringUTF(env, cstring(cmd(index).name))
        else:
          newStringUTF(env, "")

      proc getCommandValue(env: JNIEnvPtr; cls: JClass; index: JInt): JString
          {.exportc: jniPrefix & "getCommandValue", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          newStringUTF(env, cstring(cmd(index).value))
        else:
          newStringUTF(env, "")

      proc getCommandParentHandle(env: JNIEnvPtr; cls: JClass; index: JInt): JLong
          {.exportc: jniPrefix & "getCommandParentHandle", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          JLong(cmd(index).parentHandle)
        else:
          0

      proc getCommandChildHandle(env: JNIEnvPtr; cls: JClass; index: JInt): JLong
          {.exportc: jniPrefix & "getCommandChildHandle", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          JLong(cmd(index).childHandle)
        else:
          0

      proc getCommandRefHandle(env: JNIEnvPtr; cls: JClass; index: JInt): JLong
          {.exportc: jniPrefix & "getCommandRefHandle", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          JLong(cmd(index).refHandle)
        else:
          0

      proc getCommandCallbackId(env: JNIEnvPtr; cls: JClass; index: JInt): JInt
          {.exportc: jniPrefix & "getCommandCallbackId", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          JInt(cmd(index).callbackId)
        else:
          0

      proc getCommandEvent(env: JNIEnvPtr; cls: JClass; index: JInt): JString
          {.exportc: jniPrefix & "getCommandEvent", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          newStringUTF(env, cstring(cmd(index).event))
        else:
          newStringUTF(env, "")

      proc getCommandTitle(env: JNIEnvPtr; cls: JClass; index: JInt): JString
          {.exportc: jniPrefix & "getCommandTitle", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          newStringUTF(env, cstring(cmd(index).title))
        else:
          newStringUTF(env, "")

      proc getCommandMessage(env: JNIEnvPtr; cls: JClass; index: JInt): JString
          {.exportc: jniPrefix & "getCommandMessage", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          newStringUTF(env, cstring(cmd(index).message))
        else:
          newStringUTF(env, "")

      proc getCommandButtonCount(env: JNIEnvPtr; cls: JClass; index: JInt): JInt
          {.exportc: jniPrefix & "getCommandButtonCount", cdecl, dynlib.} =
        if index >= 0 and index < cmdLen():
          JInt(cmd(index).buttonCount)
        else:
          0

      proc handleEvent(env: JNIEnvPtr; cls: JClass; callbackId: JInt)
          {.exportc: jniPrefix & "handleEvent", cdecl, dynlib.} =
        ## Dispatch the registered callback for the given id. The
        ## callback (registered by the leaves via `r.addEventListener`)
        ## typically mutates the VM and calls `rerender(vm)`. The Kotlin
        ## host should call `rebuildTaskAppUI` afterwards to pick up the
        ## new tree from a fresh command buffer.
        fireCallback(int32(callbackId))

      proc setInputText(env: JNIEnvPtr; cls: JClass; text: JString)
          {.exportc: jniPrefix & "setInputText", cdecl, dynlib.} =
        ## Mirror the EditText's contents into the VM before the
        ## Add-button click handler runs. The leaves' click handler reads
        ## `vm.inputText.val`, so this is how the host pushes the user's
        ## typed text into the VM (the Android renderer's `<input>` has
        ## no native submit/IME event yet — see the leaves' module
        ## docstring "API gap" note).
        if appVm.isNil: return
        let chars = getStringUTFChars(env, text, nil)
        if chars != nil:
          appVm.setInputText($chars)
          releaseStringUTFChars(env, text, chars)

      # ---------------- RS-M6 capture entry point ----------------
      #
      # JNI fn-table indices used by the capture entry below.
      # `NewByteArray` allocates a fresh `byte[]` in the Java heap,
      # `SetByteArrayRegion` copies the swizzled RGBA bytes into it.
      const
        idxNewByteArray = 176
        idxSetByteArrayRegion = 208

      proc newByteArray(env: JNIEnvPtr; size: JInt): JByteArray =
        let fn = cast[proc(env: JNIEnvPtr; size: JInt): JByteArray
            {.cdecl.}](env[][idxNewByteArray])
        fn(env, size)

      proc setByteArrayRegion(env: JNIEnvPtr; arr: JByteArray;
                              start: JInt; len: JInt; buf: pointer) =
        let fn = cast[proc(env: JNIEnvPtr; arr: JByteArray;
                           start: JInt; len: JInt; buf: pointer)
            {.cdecl.}](env[][idxSetByteArrayRegion])
        fn(env, arr, start, len, buf)

      proc captureRootViewToRgba(env: JNIEnvPtr; cls: JClass;
                                 width: JInt; height: JInt): JByteArray
          {.exportc: jniPrefix & "captureRootViewToRgba", cdecl, dynlib.} =
        ## RS-M6 acceptance entry point. Drives the Nim adapter's
        ## `renderFrame` against the currently displayed task_app
        ## tree (published to Kotlin's
        ## `CaptureHelper.activeRootView` by
        ## `MainActivity.rebuildTree`) and returns canonical RGBA8888
        ## row-major bytes of length `width * height * 4`.
        ##
        ## The Nim adapter's `renderFrame` body, under
        ## `-d:android -d:commandBuffer`, calls back into Kotlin's
        ## `CaptureHelper.captureActiveRootToRgba(width, height)` via
        ## `isonim_android/capture.captureViewToRgba`, which reads
        ## the JNI env back from a threadvar. We set that threadvar
        ## here so the entire chain stays on a single thread.
        ##
        ## Cross-link: the binding RS-M6 acceptance gate is
        ## `app/src/androidTest/kotlin/com/metacraft/isonim/examples/
        ## AdapterCaptureTest.kt`.
        androidCapture.currentJniEnv = env
        let renderer = AndroidRenderer()
        # `root` is informational: the actual root the helper
        # captures is `CaptureHelper.activeRootView`, set by
        # MainActivity. We pass the int64 1 (the first command-buffer
        # handle is always 1 — see `command_buffer.nextHandle`) so
        # the AndroidFrameSource has a well-formed but otherwise
        # unused value.
        let src = newAndroidFrameSource(renderer, AndroidElement(1),
                                        width = int(width),
                                        height = int(height))
        var frame: Frame
        try:
          frame = src.renderFrame()
        except CatchableError, Defect:
          androidCapture.currentJniEnv = nil
          return newByteArray(env, 0)
        androidCapture.currentJniEnv = nil
        let n = frame.pixels.len
        let arr = newByteArray(env, JInt(n))
        if n > 0 and arr != nil:
          setByteArrayRegion(env, arr, JInt(0), JInt(n),
                             cast[pointer](unsafeAddr frame.pixels[0]))
        return arr

      # `isMainModule` block under `-d:androidGui --app:lib --noMain` is
      # a no-op; the JNI exports above are the real entry surface. Keep
      # a single createRoot so the linker doesn't strip the reactive
      # core's lifecycle helpers.
      createRoot proc(dispose: proc()) =
        dispose()
    else:
      createRoot proc(dispose: proc()) =
        let appVm = newTaskAppVM()
        let root = runTaskApp(appVm)
        let r = AndroidRenderer()
        echo "Task app Android mounted; root.childCount=", r.childCount(root)
        appVm.setInputText("first")
        let s = leavesFor(appVm)
        r.fireEvent(s.addBtn, "click")
        appVm.setInputText("second")
        r.fireEvent(s.addBtn, "click")
        echo "After adds, tasks: ", totalCount(appVm)
        dispose()

else:
  ## Linux/non-android hosts: the composition root surface is
  ## intentionally empty. See the module docstring for the EX-M6
  ## partial-linux rationale and the macOS hand-off checklist.
  discard
