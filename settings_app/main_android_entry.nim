## settings_app/main_android_entry.nim — Layer-4 JNI library entry for
## the settings-app Android target.
##
## EX-M22 architectural decision (B). The settings_app's JNI surface
## lives in a *separate* shared library (`libsettings_app.so`) so that
## the EX-M6 `libtask_app.so` stays byte-untouched. Both libraries can
## be loaded into the same Android process; their JNI symbols are
## namespaced (`Java_com_metacraft_isonim_examples_TaskAppBridge_*` vs.
## `Java_com_metacraft_isonim_examples_SettingsAppBridge_*`) so they
## never collide.
##
## Surface shape mirrors `task_app/main_android.nim` under
## `-d:androidGui`:
##
##   * `buildSettingsAppUI` / `rebuildSettingsAppUI` — build/rebuild the
##     view tree against the shared `isonim_android/command_buffer`.
##   * `getCommand*` readers — Kotlin walks the buffer entry by entry.
##   * `handleEvent` — dispatch a registered callback.
##   * `captureRootViewToRgba` — RS-M6's capture entry point, routed
##     through `isonim_android/capture.captureViewToRgba`. The Kotlin
##     `CaptureHelper.activeRootView` is set by the host MainActivity
##     when the settings demo is foregrounded.
##
## Build:
##
##   NDK_CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android34-clang"
##   nim c --os:android --cpu:arm64 --cc:clang \
##     --clang.exe:"$NDK_CC" --clang.linkerexe:"$NDK_CC" \
##     --passC:-fPIC --passL:"-shared -llog -nostdlib++ -lc++_static -lc++abi" \
##     --app:lib --noMain --mm:orc \
##     -d:android -d:commandBuffer -d:androidGui \
##     -o:libsettings_app.so \
##     isonim-examples/settings_app/main_android_entry.nim
##
## On Linux / non-Android this module compiles as an empty shell so
## the regular `just test` keeps passing.

when defined(android):
  import isonim_android/renderer

  import settings_app/core/vm
  import settings_app/core/demo_catalog
  import settings_app/main_android as settings_app

  export renderer, vm, demo_catalog, settings_app

  when isMainModule:
    import isonim/core/owner

    when defined(androidGui):
      # JNI library wiring — mirrors `task_app/main_android.nim`'s
      # `-d:androidGui` block, but with the `SettingsAppBridge` JNI
      # prefix and the `SettingsVM` lifecycle.
      import isonim_android/command_buffer as cmdbuf
      import isonim_android/callbacks
      import isonim_android/capture as androidCapture
      import isonim_render_serve/adapters/android_adapter
      import isonim_render_serve/packet

      type
        JNIEnvPtr = androidCapture.JNIEnvPtr
        JClass = pointer
        JString = pointer
        JByteArray = pointer
        JInt = cint
        JLong = clonglong

      # JNI function table indices (from jni.h — stable across all
      # Android versions). Mirrors the table in `task_app/main_android.nim`;
      # we duplicate it here so the settings library stays self-contained
      # (the task lib's helpers aren't exposed as a public surface).
      const
        idxNewStringUTF = 167
        idxGetStringUTFChars = 169
        idxReleaseStringUTFChars = 170
        idxNewByteArray = 176
        idxSetByteArrayRegion = 208

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

      # Note: the task lib also exports a `JNI_OnLoad` symbol. Multiple
      # libs loaded into the same process each get their own
      # `JNI_OnLoad` callback, so duplicating the symbol is correct.
      proc JNI_OnLoad*(vm: pointer; reserved: pointer): JInt
          {.exportc, cdecl, dynlib.} =
        discard vm
        discard reserved
        result = 0x00010006  # JNI_VERSION_1_6

      const jniPrefix = "Java_com_metacraft_isonim_examples_SettingsAppBridge_"

      var appVm {.global.}: SettingsVM

      template cmdLen(): JInt = JInt(cmdbuf.commandBuffer.len)
      template cmd(i: JInt): cmdbuf.UICommand = cmdbuf.commandBuffer[i]

      proc buildSettingsAppUI(env: JNIEnvPtr; cls: JClass): JInt
          {.exportc: jniPrefix & "buildSettingsAppUI", cdecl, dynlib.} =
        discard env
        discard cls
        cmdbuf.commandBuffer.setLen(0)
        cmdbuf.nextHandle = 1
        resetCallbacks()
        # The settings shell uses `createRenderEffect` for the active-
        # group binding + the bottom-sheet pane's lazy materialisation
        # (EX-M22). Those effects need an active reactive owner to be
        # registered against; wrap the build in `createRoot` so the
        # effect runs once immediately (populating the pane on initial
        # mount) and stays subscribed for the lifetime of the VM.
        createRoot proc(dispose: proc()) =
          let catalog = buildDemoSettingsCatalog()
          appVm = newSettingsVM(catalog)
          discard settings_app.runSettingsApp(appVm)
          # `dispose` is intentionally unused so the registered
          # `createRenderEffect`s outlive this proc and continue to
          # observe `vm.activeGroupId.val` mutations after the JNI
          # build call returns. Mute the unused-symbol check.
          {.warning[UnusedImport]: off.}
          discard repr(dispose)
        cmdLen()

      proc rebuildSettingsAppUI(env: JNIEnvPtr; cls: JClass): JInt
          {.exportc: jniPrefix & "rebuildSettingsAppUI", cdecl, dynlib.} =
        discard env
        discard cls
        cmdbuf.commandBuffer.setLen(0)
        cmdbuf.nextHandle = 1
        resetCallbacks()
        # See note in `buildSettingsAppUI` — the reactive scope is
        # needed for `createRenderEffect` to fire. The previous root is
        # implicitly torn down by the lib's next `createRoot` (effects
        # registered against a previous owner can't observe the new
        # callback table, which is fine because the rebuild starts a
        # fresh subscription against the VM's signals).
        createRoot proc(dispose: proc()) =
          if appVm.isNil:
            let catalog = buildDemoSettingsCatalog()
            appVm = newSettingsVM(catalog)
          discard settings_app.runSettingsApp(appVm)
          # `dispose` is intentionally unused so the registered
          # `createRenderEffect`s outlive this proc and continue to
          # observe `vm.activeGroupId.val` mutations after the JNI
          # build call returns. Mute the unused-symbol check.
          {.warning[UnusedImport]: off.}
          discard repr(dispose)
        cmdLen()

      proc getCommandCount(env: JNIEnvPtr; cls: JClass): JInt
          {.exportc: jniPrefix & "getCommandCount", cdecl, dynlib.} =
        discard env
        discard cls
        cmdLen()

      proc getCommandKind(env: JNIEnvPtr; cls: JClass; index: JInt): JString
          {.exportc: jniPrefix & "getCommandKind", cdecl, dynlib.} =
        discard cls
        if index >= 0 and index < cmdLen():
          newStringUTF(env, cstring($cmd(index).kind))
        else:
          newStringUTF(env, "")

      proc getCommandHandle(env: JNIEnvPtr; cls: JClass; index: JInt): JLong
          {.exportc: jniPrefix & "getCommandHandle", cdecl, dynlib.} =
        discard env
        discard cls
        if index >= 0 and index < cmdLen():
          JLong(cmd(index).handle)
        else:
          0

      proc getCommandTag(env: JNIEnvPtr; cls: JClass; index: JInt): JString
          {.exportc: jniPrefix & "getCommandTag", cdecl, dynlib.} =
        discard cls
        if index >= 0 and index < cmdLen():
          newStringUTF(env, cstring(cmd(index).tag))
        else:
          newStringUTF(env, "")

      proc getCommandName(env: JNIEnvPtr; cls: JClass; index: JInt): JString
          {.exportc: jniPrefix & "getCommandName", cdecl, dynlib.} =
        discard cls
        if index >= 0 and index < cmdLen():
          newStringUTF(env, cstring(cmd(index).name))
        else:
          newStringUTF(env, "")

      proc getCommandValue(env: JNIEnvPtr; cls: JClass; index: JInt): JString
          {.exportc: jniPrefix & "getCommandValue", cdecl, dynlib.} =
        discard cls
        if index >= 0 and index < cmdLen():
          newStringUTF(env, cstring(cmd(index).value))
        else:
          newStringUTF(env, "")

      proc getCommandParentHandle(env: JNIEnvPtr; cls: JClass; index: JInt): JLong
          {.exportc: jniPrefix & "getCommandParentHandle", cdecl, dynlib.} =
        discard env
        discard cls
        if index >= 0 and index < cmdLen():
          JLong(cmd(index).parentHandle)
        else:
          0

      proc getCommandChildHandle(env: JNIEnvPtr; cls: JClass; index: JInt): JLong
          {.exportc: jniPrefix & "getCommandChildHandle", cdecl, dynlib.} =
        discard env
        discard cls
        if index >= 0 and index < cmdLen():
          JLong(cmd(index).childHandle)
        else:
          0

      proc getCommandRefHandle(env: JNIEnvPtr; cls: JClass; index: JInt): JLong
          {.exportc: jniPrefix & "getCommandRefHandle", cdecl, dynlib.} =
        discard env
        discard cls
        if index >= 0 and index < cmdLen():
          JLong(cmd(index).refHandle)
        else:
          0

      proc getCommandCallbackId(env: JNIEnvPtr; cls: JClass; index: JInt): JInt
          {.exportc: jniPrefix & "getCommandCallbackId", cdecl, dynlib.} =
        discard env
        discard cls
        if index >= 0 and index < cmdLen():
          JInt(cmd(index).callbackId)
        else:
          0

      proc getCommandEvent(env: JNIEnvPtr; cls: JClass; index: JInt): JString
          {.exportc: jniPrefix & "getCommandEvent", cdecl, dynlib.} =
        discard cls
        if index >= 0 and index < cmdLen():
          newStringUTF(env, cstring(cmd(index).event))
        else:
          newStringUTF(env, "")

      proc handleEvent(env: JNIEnvPtr; cls: JClass; callbackId: JInt)
          {.exportc: jniPrefix & "handleEvent", cdecl, dynlib.} =
        discard env
        discard cls
        fireCallback(int32(callbackId))

      proc captureRootViewToRgba(env: JNIEnvPtr; cls: JClass;
                                 width: JInt; height: JInt): JByteArray
          {.exportc: jniPrefix & "captureRootViewToRgba", cdecl, dynlib.} =
        discard cls
        androidCapture.currentJniEnv = env
        let renderer = AndroidRenderer()
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

      # Keep a single createRoot so the linker doesn't strip the
      # reactive core's lifecycle helpers under `--app:lib --noMain`.
      createRoot proc(dispose: proc()) =
        dispose()

    else:
      # Headless (non-androidGui) mode: smoke-build the settings demo
      # against an `AndroidRenderer` to make sure the composition root
      # links cleanly. Mirrors the task lib's headless path.
      createRoot proc(dispose: proc()) =
        let catalog = buildDemoSettingsCatalog()
        let settingsVm = newSettingsVM(catalog)
        let root = settings_app.runSettingsApp(settingsVm)
        let r = AndroidRenderer()
        echo "Settings app Android entry mounted; root.childCount=",
          r.childCount(root)
        dispose()

else:
  ## Linux/non-android hosts: the JNI entry surface is intentionally
  ## empty. See `settings_app/main_android.nim` for the gating
  ## rationale and the cross-compile gate notes.
  discard
