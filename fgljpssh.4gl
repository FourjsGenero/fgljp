IMPORT os
IMPORT util
IMPORT FGL fgljp
IMPORT JAVA java.lang.Thread
&define MYASSERT(x) IF NOT NVL(x,0) THEN CALL fgljp.myErr("ASSERTION failed in line:"||__LINE__||":"||#x) END IF
&define MYASSERT_MSG(x,msg) IF NOT NVL(x,0) THEN CALL fgljp.myErr("ASSERTION failed in line:"||__LINE__||":"||#x||","||msg) END IF
MAIN
  DEFINE entries fgljp.TStartEntries
  DEFINE tmp STRING
  CALL start_fgljp() RETURNING entries.*, tmp
  CALL start_ssh(entries.port)
  IF os.Path.exists(tmp) THEN
    CALL kill(entries.pid)
    CALL os.Path.delete(tmp) RETURNING status
  END IF
  DISPLAY "fgljpssh terminated"
END MAIN

FUNCTION waitOpen(fname STRING)
  DEFINE ch base.Channel
  DEFINE i INT
  DEFINE opened BOOLEAN
  LET ch = base.Channel.create()
  FOR i = 1 TO 10000
    TRY
      CALL ch.openFile(fname, "r")
      LET opened = TRUE
      --DISPLAY "did open:",fname
      EXIT FOR
    CATCH
      --DISPLAY "waitOpen:",i," ",err_get(status)
      CALL Thread.sleep(1)
    END TRY
  END FOR
  MYASSERT_MSG(opened == TRUE, sfmt("Can't open %1", fname))
  RETURN ch
END FUNCTION

FUNCTION waitReadLine(ch base.Channel, fname STRING) RETURNS STRING
  DEFINE i INT
  DEFINE line STRING
  FOR i = 1 TO 10000
    LET line = ch.readLine()
    IF line IS NOT NULL THEN
      DISPLAY line
      RETURN line
    ELSE
      CALL Thread.sleep(1)
    END IF
  END FOR
  CALL fgljp.myErr(SFMT("Could not read a line from %1", fname))
  RETURN NULL
END FUNCTION

FUNCTION start_fgljp() RETURNS(fgljp.TStartEntries, STRING)
  DEFINE ch base.Channel
  DEFINE dir, tmp, line, fgljp_p STRING
  DEFINE entries fgljp.TStartEntries
  LET dir = os.Path.dirName(arg_val(0))
  LET fgljp_p = os.Path.join(dir, "fgljp")
  LET tmp = fgljp.makeTempName()
  RUN SFMT("%1 > %2", fgljp_p, tmp) WITHOUT WAITING
  LET ch = waitOpen(tmp)
  LET line = waitReadLine(ch, tmp)
  CALL util.JSON.parse(line, entries)
  RETURN entries.*, tmp
END FUNCTION

FUNCTION start_ssh(localPort INT)
  DEFINE tmp, tmps, line, cmd STRING
  DEFINE ch base.Channel
  DEFINE idx, idx2, remotePort, aLen INT
  DEFINE rFGLSERVER STRING
  CONSTANT ALLO = "Allocated port "
  LET aLen = length(ALLO)
  LET tmp = fgljp.makeTempName()
  MYASSERT(NOT os.Path.exists(tmp))
  --LET tmp=tmp
  LET tmps = fgljp.makeTempName()
  LET tmps = tmps, "sock"
  --we use the 0 remote port and let this connection open until we die
  IF NOT fgljp.isWin() THEN
    LET cmd =
        SFMT("ssh -f -N -M -S %1 -R 0:localhost:%2 %3 2>%4",
            tmps, localPort, arg_val(1), tmp)
  ELSE
    LET cmd =
        SFMT("ssh -N -R 0:localhost:%1 %2 2>%3", localPort, arg_val(1), tmp)
  END IF
  --DISPLAY "RUN cmd:",cmd
  RUN cmd WITHOUT WAITING
  LET ch = waitOpen(tmp)
  LET line = waitReadLine(ch, tmp)
  --DISPLAY "ssh alloc line:",line
  MYASSERT_MSG((idx := line.getIndexOf("Allocated port ", 1)) > 0, sfmt("Can't get allocated port out of '%1'", line))
  MYASSERT((idx2 := line.getIndexOf(" ", idx + aLen + 1)) > 0)
  LET remotePort = line.subString(idx + aLen + 1, idx2 - 1)
  MYASSERT(remotePort IS NOT NULL)
  LET rFGLSERVER = SFMT("localhost:%1", remotePort - 6400)
  DISPLAY "remotePort:", remotePort, ",remote (LC_)FGLSERVER:", rFGLSERVER
  CALL fgl_setenv("FGLSERVER", rFGLSERVER)
  CALL fgl_setenv("LC_FGLSERVER", rFGLSERVER)
  RUN SFMT("ssh -o SendEnv=FGLSERVER %1", arg_val(1))
  IF NOT fgljp.isWin() THEN
    --DISPLAY "terminate port forwarder ssh"
    RUN SFMT("ssh -S %1 -O exit %2", tmps, arg_val(1))
  END IF
END FUNCTION

FUNCTION kill(pid INT)
  IF fgljp.isWin() THEN
    RUN SFMT("taskkill /PID %1 /T", pid)
  ELSE
    RUN SFMT("kill %1", pid)
  END IF
END FUNCTION
