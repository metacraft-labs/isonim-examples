## The ``--encoder`` flag must actually reach the bridge.
##
## What was broken
## ---------------
##
## ``parseLauncherArgs`` has accepted ``--encoder`` since EPP-M5 and
## ``resolveEncoderKind`` maps it onto an ``EncoderKind``.  But
## ``runDemoBridgeWith`` declared ``encoder: EncoderKind = ekRawRgba``,
## and only ``cocoa.nim`` and ``gpui.nim`` ever passed the argument.
## Every other launcher — ``freya``, ``web``, ``tui``, ``tui_term``,
## ``ios``, ``android`` — called it without ``encoder=``, so the
## default silently overrode whatever the user asked for on the command
## line.  Observed on the unfixed tree:
##
##   $ isonim-examples-web --port 18777 --encoder webp
##   isonim-examples-web demo=task listening on ... encoder=raw_rgba
##
## No warning, no error — the flag was a placebo for six of the eight
## launchers.  Every ELT / FUH headline number (the 29-byte idle
## heartbeat floor, the L1=0 lossless cells) was measured on the cocoa
## launcher, the one backend that did forward the flag.
##
## The fix changes ``encoder``'s TYPE to ``Option[EncoderKind]``.  That
## is deliberate: omitting the argument now means "resolve from the
## CLI" instead of "force raw RGBA", and the two launchers that DO want
## to override the CLI (cocoa and gpui, both of which post-process the
## resolved kind against an H.264 handle) are forced by the compiler to
## say so explicitly.  A future launcher that forgets the argument gets
## the correct behaviour by default.
##
## This test drives the real ``build/backends/isonim-examples-web``
## binary — the cheapest launcher that does not forward the flag — and
## reads the encoder it reports in its startup banner.

import std/[options, os, osproc, streams, strutils, unittest]

import isonim_render_serve

import editor/backends/common

const RepoRoot = currentSourcePath().parentDir().parentDir()
const WebLauncher = RepoRoot / "build" / "backends" / "isonim-examples-web"

proc launcherEncoder(args: seq[string]; port: int): string =
  ## Boot the launcher, read the ``encoder=<name>`` field out of its
  ## startup banner, then shut it down.  Returns "" when the banner
  ## never arrived.
  let p = startProcess(WebLauncher,
                       args = @["--port", $port] & args,
                       options = {poStdErrToStdOut})
  defer:
    p.terminate()
    discard p.waitForExit()
    p.close()
  let outStream = p.outputStream
  var line = ""
  var tries = 0
  while tries < 200:
    if outStream.readLine(line):
      let idx = line.find("encoder=")
      if idx >= 0:
        var j = idx + "encoder=".len
        var name = ""
        while j < line.len and line[j] notin {')', ',', ' '}:
          name.add(line[j])
          inc j
        return name
    else:
      sleep(25)
    inc tries
  ""

suite "launcher --encoder flag":

  test "test_effective_encoder_falls_back_to_the_cli_flag":
    ## The pure resolution rule: an explicit override from the launcher
    ## wins, otherwise the CLI's ``--encoder`` decides.  "Nothing
    ## specified anywhere" is the only case that lands on raw RGBA.
    var cfg = LauncherConfig()
    cfg.encoder = "webp"
    check effectiveEncoderKind(cfg, none(EncoderKind)) ==
      selectEncoderKind(ekWebP)
    check effectiveEncoderKind(cfg, some(ekRawRgba)) == ekRawRgba
    cfg.encoder = ""
    check effectiveEncoderKind(cfg, none(EncoderKind)) == ekRawRgba
    cfg.encoder = "raw_rgba"
    check effectiveEncoderKind(cfg, none(EncoderKind)) == ekRawRgba

  test "test_web_launcher_honours_encoder_webp":
    ## The end-to-end shape of the bug: a launcher that does not pass
    ## ``encoder=`` to ``runDemoBridgeWith`` must still honour the
    ## user's ``--encoder webp``.  Expected value is computed with the
    ## same host-capability probe the launcher uses, so the assertion
    ## holds on hosts with and without libwebp — what it will not
    ## tolerate is the flag being ignored.
    require fileExists(WebLauncher)  # just build-backends
    let want = encoderKindName(selectEncoderKind(ekWebP))
    check launcherEncoder(@["--encoder", "webp"], 18771) == want

  test "test_web_launcher_honours_explicit_raw_rgba":
    require fileExists(WebLauncher)
    check launcherEncoder(@["--encoder", "raw_rgba"], 18772) == "raw_rgba"

  test "test_web_launcher_default_stays_raw_rgba":
    ## No ``--encoder`` on the command line keeps the documented
    ## F-packet baseline (FUH-M7 §2.1 records ``raw_rgba`` as the web /
    ## freya default).  The fix restores the flag; it does not change
    ## any default.
    require fileExists(WebLauncher)
    check launcherEncoder(@[], 18773) == "raw_rgba"
