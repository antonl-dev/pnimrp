proc createLoggInstance*: File =
    var logFile: File
    let filePathNameExt = "log.log"
    discard logFile.open(filePathNameExt, fmAppend)
    return logFile

proc logToFile*(logFile: File; content: string) =
    logFile.writeLine content
    logFile.flushFile()

proc closeLogg*(logFile: File) =
    logFile.close()
