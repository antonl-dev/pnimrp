# SPDX-License-Identifier: MPL-2.0
# Unit tests for link.nim
import ../link

when isMainModule:
    import unittest

    suite "Link Tests":
        test "validateLink":
            let result = validateLink("https://example.com")
            check result.isValid == true
            check result.protocol == "https"
            check result.domain == "example.com"

        test "invalidLink":
            let result = validateLink("invalid-url")
            check result.isValid == false
