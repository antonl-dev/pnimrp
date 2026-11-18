# SPDX-License-Identifier: MPL-2.0
# Unit tests for libmpv.nim
import ../libmpv

when isMainModule:
  import unittest

  suite "Client Tests":
    test "checkError":
      expect CatchableError:
        checkError(-1)

    test "makePackedVersion":
      check makePackedVersion(1, 107) == 0x1006B'u32

    test "getClientApiVersion":
      check getUnpackedVersionComponents(getClientApiVersion()) == clientApiVersion

    test "errorString":
      check errorString(cint(errSuccess)) == "success"
      check errorString(cint(errNoMem)) == "memory allocation failed"

    test "eventName":
      check eventName(IDNone) == "none"
      check eventName(IDShutdown) == "shutdown"

    test "create and destroy":
      let ctx = create()
      check ctx != nil
      destroy(ctx)

    test "initialize":
      let ctx = create()
      check initialize(ctx) == cint(errSuccess) # Cast errSuccess to cint
      destroy(ctx)

    test "cmdString":
      let ctx = create()
      discard initialize(ctx)
      check cmdString(ctx, "loadfile example.mp3") == cint(errSuccess) # Cast errSuccess to cint
      destroy(ctx)

    test "getPropertyString":
      let ctx = create()
      discard initialize(ctx)
      let prop = getPropertyString(ctx, "volume")
      check prop != nil
      free(prop)
      destroy(ctx)

    test "setPropertyString":
      let ctx = create()
      discard initialize(ctx)
      check setPropertyString(ctx, "volume", "50") == cint(errSuccess) # Cast errSuccess to cint
      destroy(ctx)

    test "waitEvent":
      let ctx = create()
      discard initialize(ctx)
      let event = waitEvent(ctx, 0.1)
      check event != nil
      destroy(ctx)
