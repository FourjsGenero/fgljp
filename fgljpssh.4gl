IMPORT os
IMPORT util
IMPORT FGL fgljp
IMPORT FGL mygetopt
IMPORT JAVA java.lang.Thread
IMPORT JAVA java.lang.ProcessBuilder
IMPORT JAVA java.lang.ProcessBuilder.Redirect
IMPORT JAVA java.lang.Process
IMPORT JAVA java.lang.String
IMPORT JAVA java.io.InputStreamReader
IMPORT JAVA java.io.BufferedReader
&define MYASSERT(x) IF NOT NVL(x,0) THEN CALL fgljp.myErr("ASSERTION failed in line:"||__LINE__||":"||#x) END IF
&define MYASSERT_MSG(x,msg) IF NOT NVL(x,0) THEN CALL fgljp.myErr("ASSERTION failed in line:"||__LINE__||":"||#x||","||msg) END IF
TYPE SArray ARRAY[] OF java.lang.String
DEFINE _verbose BOOLEAN
DEFINE _opt_tunnelonly BOOLEAN
DEFINE _opt_ssh_bash BOOLEAN
DEFINE _opt_ssh_host STRING
DEFINE _opt_ssh_args STRING
DEFINE _opt_ssh_port STRING
DEFINE _opt_fgltty STRING --if set we use fgltty instead of ssh
DEFINE _opt_fgltty_pw STRING --fgltty password
DEFINE _opt_fgltty_load STRING --fgltty load config
CONSTANT ALLO = "Allocated port "
CONSTANT MAXLINES = 10
MAIN
  DEFINE entries fgljp.TStartEntries
  DEFINE tmp STRING
  CALL fgl_setenv("FGLJPSSH_PARENT", "1")
  CALL parseArgs()
  CALL start_fgljp() RETURNING entries.*, tmp
  IF _opt_fgltty IS NOT NULL THEN
    CALL start_fgltty(entries.port)
  ELSE
    CALL start_ssh(entries.port)
  END IF
  IF os.Path.exists(tmp) THEN
    CALL kill(entries.pid)
    CALL os.Path.delete(tmp) RETURNING status
  END IF
  DISPLAY "fgljpssh terminated"
END MAIN

FUNCTION parseArgs()
  DEFINE gr mygetopt.GetoptR
  DEFINE o mygetopt.GetoptOptions
  DEFINE opt_char, opt_arg, opt_name STRING
  DEFINE i, cnt INT
  DEFINE nullstr STRING

  LET i = o.getLength() + 1
  LET o[i].name = "tunnel-only"
  LET o[i].description = "invokes fgljp, tunnels to remote and prints FGLSERVER"
  LET o[i].opt_char = "t"
  LET o[i].arg_type = mygetopt.NONE

  LET i = o.getLength() + 1
  LET o[i].name = "bash"
  LET o[i].description =
      "starts a remote interactive bash (avoids editing sshd_config for AcceptEnv)"
  LET o[i].opt_char = "b"
  LET o[i].arg_type = mygetopt.NONE

  LET i = o.getLength() + 1
  LET o[i].name = "help"
  LET o[i].description = "program help"
  LET o[i].opt_char = "h"
  LET o[i].arg_type = mygetopt.NONE

  LET i = o.getLength() + 1
  LET o[i].name = "port"
  LET o[i].description = "remote ssh port number"
  LET o[i].opt_char = "p"
  LET o[i].arg_type = mygetopt.REQUIRED

  LET i = o.getLength() + 1
  LET o[i].name = "fgltty"
  LET o[i].description = "use fgltty instead of ssh"
  LET o[i].opt_char = "y"
  LET o[i].arg_type = mygetopt.REQUIRED

  LET i = o.getLength() + 1
  LET o[i].name = "fgltty-password"
  LET o[i].description = "clear text password for fgltty"
  LET o[i].opt_char = "x"
  LET o[i].arg_type = mygetopt.REQUIRED

  LET i = o.getLength() + 1
  LET o[i].name = "verbose"
  LET o[i].description = "detailed log"
  LET o[i].opt_char = "v"
  LET o[i].arg_type = mygetopt.NONE

  LET i = o.getLength() + 1
  LET o[i].name = "load"
  LET o[i].description = "load a fgltty config"
  LET o[i].arg_type = mygetopt.REQUIRED

  CALL mygetopt.initialize(gr, "fgljpssh", mygetopt.copyArguments(1), o)
  WHILE mygetopt.getopt(gr) == mygetopt.SUCCESS
    LET opt_arg = mygetopt.opt_arg(gr)
    LET opt_char = mygetopt.opt_char(gr)
    CASE mygetopt.opt_char(gr)
      WHEN 'v'
        LET _verbose = TRUE
      WHEN 'h'
        CALL mygetopt.displayUsage(gr, "<remote host> ?ssh_command?")
        EXIT PROGRAM 0
      WHEN 't'
        LET _opt_tunnelonly = TRUE
      WHEN 'b'
        LET _opt_ssh_bash = TRUE
      WHEN 'p'
        LET _opt_ssh_port = opt_arg
      WHEN 'y'
        LET _opt_fgltty = opt_arg
        --small sanity check
        IF NOT os.Path.exists(_opt_fgltty) THEN
          CALL myErr(SFMT("fgltty not found at:%1", _opt_fgltty))
        END IF
      WHEN 'x'
        LET _opt_fgltty_pw = opt_arg
      OTHERWISE
        IF opt_char IS NULL THEN
          --LET o = mygetopt.options(gr)
          LET opt_name = o[mygetopt.option_index(gr)].name
          DISPLAY "Got long option ", opt_name
          CASE opt_name
            WHEN "load"
              LET _opt_fgltty_load = opt_arg
          END CASE
        END IF
    END CASE
  END WHILE
  IF (cnt := mygetopt.getMoreArgumentCount(gr)) >= 1 THEN
    FOR i = 1 TO cnt
      IF i = 1 THEN
        LET _opt_ssh_host = mygetopt.getMoreArgument(gr, i)
      ELSE
        LET _opt_ssh_args = _opt_ssh_args, mygetopt.getMoreArgument(gr, i), " "
      END IF
    END FOR
  END IF
  IF _opt_tunnelonly AND _opt_ssh_bash THEN
    CALL myErr("--tunnel-only(-t) and --bash(-b) options are exclusive")
  END IF
  IF _opt_tunnelonly AND _opt_fgltty IS NOT NULL THEN
    --not possible for now...fgltty is an interactive GUI program
    --its of course up to you to leave it just open
    CALL myErr("--tunnel-only(-t) and --fgltty(-y) options are exclusive")
  END IF
  LET nullstr = "0"
  IF _opt_tunnelonly AND NOT nullstr.equals(fgl_getenv("FGLGUI")) THEN
    CALL myErr("Please set FGLGUI=0 for --tunnel-only(-t)")
  END IF
  IF _opt_ssh_host IS NULL OR _opt_ssh_host.getLength() == 0 THEN
    CALL mygetopt.displayUsage(gr, "<remote host> ?ssh_command?")
    EXIT PROGRAM 1
  END IF
  LET _opt_ssh_args =
      IIF(_opt_ssh_args.getLength() > 0,
          SFMT(" %1", _opt_ssh_args),
          _opt_ssh_args)
END FUNCTION

FUNCTION waitOpen(fname STRING)
  DEFINE ch base.Channel
  DEFINE i INT
  DEFINE opened BOOLEAN
  LET ch = base.Channel.create()
  FOR i = 1 TO 100
    TRY
      CALL ch.openFile(fname, "r")
      LET opened = TRUE
      --DISPLAY "did open:",fname
      EXIT FOR
    CATCH
      --DISPLAY "waitOpen:",i," ",err_get(status)
      CALL Thread.sleep(100)
    END TRY
  END FOR
  MYASSERT_MSG(opened == TRUE, sfmt("Can't open %1", fname))
  RETURN ch
END FUNCTION

FUNCTION waitReadLine(ch base.Channel, fname STRING) RETURNS STRING
  DEFINE line STRING
  LET fname = NULL
  WHILE TRUE
    LET line = ch.readLine()
    IF line IS NOT NULL THEN
      --DISPLAY line
      RETURN line
    ELSE
      CALL Thread.sleep(100)
    END IF
  END WHILE
  --never reached
  --CALL fgljp.myErr(SFMT("Could not read a line from %1", fname))
  RETURN NULL
END FUNCTION

FUNCTION fArr2jArr(farr DYNAMIC ARRAY OF STRING) RETURNS SArray
  DEFINE sarr SArray
  DEFINE i INT
  LET sarr = SArray.create(farr.getLength())
  FOR i = 1 TO farr.getLength()
    LET sarr[i] = farr[i]
  END FOR
  RETURN sarr
END FUNCTION

--uses Java API's to redirect the ssh stderr to us to capture the
--port forwarding output
--the Process is used later on to be able to terminate it
FUNCTION start_process(cmds DYNAMIC ARRAY OF STRING) RETURNS(STRING, Process)
  DEFINE is InputStreamReader
  DEFINE br BufferedReader
  DEFINE pb ProcessBuilder
  DEFINE proc Process
  DEFINE line STRING
  LET pb = ProcessBuilder.create(fArr2jArr(cmds))
  --ensure ssh reads from our stdin
  CALL pb.redirectInput(ProcessBuilder.Redirect.INHERIT)
  --and writes to our stdout (Passwd etc)
  CALL pb.redirectOutput(ProcessBuilder.Redirect.INHERIT)
  LET proc = pb.start()
  LET is = InputStreamReader.create(proc.getErrorStream())
  LET br = BufferedReader.create(is)
  WHILE TRUE
    LET line = br.readLine()
    --CALL printStderr(sfmt("start_process:'%1'",line))
    IF line.getIndexOf(ALLO, 1) > 0 THEN
      EXIT WHILE
    END IF
  END WHILE
  RETURN line, proc
END FUNCTION

FUNCTION start_fgljp() RETURNS(fgljp.TStartEntries, STRING)
  DEFINE ch base.Channel
  DEFINE dir, tmp, line, fgljp_p, cmd STRING
  DEFINE entries fgljp.TStartEntries
  LET dir = os.Path.dirName(arg_val(0))
  LET fgljp_p = os.Path.join(dir, "fgljp.42m")
  LET tmp = fgljp.makeTempName()
  LET cmd = SFMT("fglrun %1 > %2", fgljp_p, tmp)
  IF _opt_fgltty IS NULL THEN
    --windows ssh: we need a separate console for fgljp to avoid Ctrl-c
    --affecting it, TODO: write a wrapper to hide the console window
    --not needed for fgltty
    LET cmd = IIF(fgljp.isWin(), SFMT('%1\\win\\whide cmd /c "%2"', os.Path.dirname(arg_val(0)), cmd), cmd)
  END IF
  RUN cmd WITHOUT WAITING
  LET ch = waitOpen(tmp)
  LET line = waitReadLine(ch, tmp)
  DISPLAY "start_fgljp:", line
  CALL util.JSON.parse(line, entries)
  RETURN entries.*, tmp
END FUNCTION

FUNCTION extract_user(destination STRING) RETURNS(STRING, STRING)
  DEFINE idx INT
  DEFINE usr, usr_envname, trial, host STRING
  LET idx = destination.getIndexOf("@", 1)
  IF idx > 0 THEN
    LET host = destination.subString(idx + 1, destination.getLength())
    LET usr = destination.subString(1, idx - 1)
  ELSE
    LET usr_envname = IIF(fgljp.isWin(), "USERNAME", "USER")
    LET trial = fgl_getenv(usr_envname)
    LET usr = IIF(trial IS NOT NULL, trial, NULL)
    IF usr IS NULL THEN
      LET trial = fgl_getenv("LOGNAME")
      LET usr = IIF(trial IS NOT NULL, trial, NULL)
    END IF
    LET host = destination
  END IF
  RETURN usr, host
END FUNCTION

FUNCTION start_fgltty(localPort INT)
  DEFINE cmd, usr, host, line STRING
  DEFINE ch base.Channel
  LET cmd = SFMT("%1 -P SSH ", quote(_opt_fgltty))
  CALL extract_user(_opt_ssh_host) RETURNING usr, host
  IF usr IS NOT NULL THEN
    LET cmd = SFMT("%1 -u %2", cmd, quote(usr))
  END IF
  LET cmd = SFMT("%1 -H %2", cmd, quote(host))
  IF _opt_ssh_port IS NOT NULL THEN
    LET cmd = SFMT("%1 -p %2", cmd, _opt_ssh_port)
  END IF
  IF _opt_fgltty_pw IS NOT NULL THEN
    LET cmd = SFMT('%1 -x %2', cmd, quote(_opt_fgltty_pw))
  END IF
  IF _opt_fgltty_load IS NOT NULL THEN
    LET cmd = SFMT('%1 -load %2', cmd, quote(_opt_fgltty_load))
  END IF
  LET cmd = SFMT("%1 -apf %2", cmd, localPort)
  IF _opt_ssh_bash THEN
    LET cmd =
        SFMT('%1 -c "FGLSERVER=localhost:[_FGL_GDC_REAL_PORT_] bash -li"', cmd)
  ELSE
    LET cmd = SFMT('%1 -c %2', quote(_opt_ssh_args))
  END IF
  IF cmd.getCharAt(1) == '"' AND fgljp.isWin() THEN
    --quote whole cmd again
    LET cmd = '"', cmd, '"'
  END IF
  DISPLAY "cmd:", cmd
  LET ch = base.Channel.create()
  CALL ch.openPipe(cmd, "r")
  WHILE (line := ch.readLine()) IS NOT NULL
    IF _verbose THEN
      DISPLAY "fgltty:", line
    END IF
  END WHILE
  CALL ch.close()
END FUNCTION

FUNCTION start_ssh(localPort INT)
  DEFINE tmp, tmps, line, cmd STRING
  DEFINE ch base.Channel
  DEFINE idx, idx2, remotePort, aLen, i INT
  DEFINE rFGLSERVER STRING
  DEFINE cmdarr DYNAMIC ARRAY OF STRING
  DEFINE proc Process
  LET aLen = length(ALLO)
  LET tmp = fgljp.makeTempName()
  MYASSERT(NOT os.Path.exists(tmp))
  --we use the 0 remote port and let this connection open until we die
  --exclusively for forwaring the remote side to out fgljp propgram
  -- -N means we do no perform a command
  IF fgljp.isWin() THEN
    --unfortunately there isn't the master control socket property
    --in the standard Win32/64 ssh client
    --fglrun hangs on a popen() for this process, so we use Java in this
    --case to start and read from the process...
    --furthermore the -4 (IPv4) flag is necessary to make the relay to localhost happen
    --note 'localhost' is much slower than '127.0.0.1' when forwarding
    LET cmd = SFMT('["ssh","-4","-N","-R","0:127.0.0.1:%1"]', localPort)
    CALL util.JSON.parse(cmd, cmdarr)
    IF _opt_ssh_port IS NOT NULL THEN
      LET cmdarr[cmdarr.getLength() + 1] = "-p"
      LET cmdarr[cmdarr.getLength() + 1] = _opt_ssh_port
    END IF
    LET cmdarr[cmdarr.getLength() + 1] = _opt_ssh_host
    --DISPLAY util.JSON.stringify(cmdarr)
    CALL start_process(cmdarr) RETURNING line, proc
  ELSE
    --compute a master control socket name
    LET tmps = fgljp.makeTempName()
    LET tmps = tmps, "sock"
    LET cmd =
        IIF(_opt_ssh_port IS NOT NULL, SFMT("ssh -p %1", _opt_ssh_port), "ssh")
    LET cmd =
        SFMT("%1 -f -N -M -S %2 -R 0:localhost:%3 %4 2>%5",
            cmd, tmps, localPort, _opt_ssh_host, tmp)
    RUN cmd WITHOUT WAITING
    LET ch = waitOpen(tmp)
    FOR i = 1 TO MAXLINES
      LET line = waitReadLine(ch, tmp)
      IF line.getIndexOf(ALLO, 1) > 0 THEN
        EXIT FOR
      ELSE
        CALL printStderr(line)
      END IF
    END FOR
  END IF
  DISPLAY "ssh port forward line:", line
  DEFER INTERRUPT --prevent Ctrl-c bailing us out
  MYASSERT_MSG((idx := line.getIndexOf(ALLO, 1)) > 0, sfmt("Can't get allocated port out of '%1'", line))
  MYASSERT((idx2 := line.getIndexOf(" ", idx + aLen + 1)) > 0)
  LET remotePort = line.subString(idx + aLen + 1, idx2 - 1)
  MYASSERT(remotePort IS NOT NULL)
  LET rFGLSERVER = SFMT("localhost:%1", remotePort - 6400)
  IF _opt_tunnelonly THEN
    DISPLAY "export FGLSERVER=", rFGLSERVER AT 3, 1
    MENU "Remote tunnel for fglrun active"
      COMMAND "Exit"
        EXIT MENU
    END MENU
  ELSE
    IF _opt_ssh_bash THEN
      --make usage of the master control socket of possible (avoids re auth)
      LET cmd = IIF(fgljp.isWin(), "ssh -t", SFMT("ssh -t -S %1", tmps))
      LET cmd =
          IIF(_opt_ssh_port IS NULL, cmd, SFMT("%1 -p %2", cmd, _opt_ssh_port))
      --simply export FGLSERVER at the remote side
      LET cmd =
          SFMT("%1 %2 FGLSERVER=%3 bash -li", cmd, _opt_ssh_host, rFGLSERVER)
    ELSE
      --send FGLSERVER via -o SendEnv -> AcceptEnv entry in sshd_config is needed
      CALL fgl_setenv("FGLSERVER", rFGLSERVER)
      CALL fgl_setenv(
          "LC_FGLSERVER",
          rFGLSERVER) --ssh Mac hack: the remote side has LC_FGLSERVER set without editing sshd_config
      --note: master control socket option not possible here because the env will not be passed again
      LET cmd =
          IIF(_opt_ssh_port IS NOT NULL,
              SFMT("ssh -p %1", _opt_ssh_port),
              "ssh")
      LET cmd =
          SFMT("%1 -t -o SendEnv=FGLSERVER %2%3",
              cmd, _opt_ssh_host, _opt_ssh_args)
    END IF
    DISPLAY "cmd is:'", cmd, "'"
    RUN cmd
  END IF
  --DISPLAY "terminate port forwarder ssh"
  IF fgljp.isWin() THEN
    CALL proc.destroyForcibly()
  ELSE
    CALL ch.close()
    LET cmd =
        IIF(_opt_ssh_port IS NOT NULL, SFMT("ssh -p %1", _opt_ssh_port), "ssh")
    --close the master control connection
    RUN SFMT("%1 -S %2 -O exit %3", cmd, tmps, _opt_ssh_host)
    CALL os.Path.delete(tmp) RETURNING status
    CALL os.Path.delete(tmps) RETURNING status
  END IF
END FUNCTION

FUNCTION kill(pid INT)
  IF fgljp.isWin() THEN
    RUN SFMT("taskkill /F /PID %1 /T >NUL 2>&1", pid)
  ELSE
    RUN SFMT("kill %1", pid)
  END IF
END FUNCTION

FUNCTION already_quoted(path)
  DEFINE path, first, last STRING
  LET first = NVL(path.getCharAt(1), "NULL")
  LET last = NVL(path.getCharAt(path.getLength()), "NULL")
  IF isWin() THEN
    RETURN (first == '"' AND last == '"')
  END IF
  RETURN (first == "'" AND last == "'") OR (first == '"' AND last == '"')
END FUNCTION

FUNCTION quote(path)
  DEFINE path STRING
  IF path.getIndexOf(" ", 1) > 0 THEN
    IF NOT already_quoted(path) THEN
      LET path = '"', path, '"'
    END IF
  ELSE
    IF already_quoted(path) AND isWin() THEN --remove quotes(Windows)
      LET path = path.subString(2, path.getLength() - 1)
    END IF
  END IF
  RETURN path
END FUNCTION
