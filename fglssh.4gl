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
DEFINE _opt_ssh_usr STRING
DEFINE _opt_fgltty STRING --if set we use fgltty instead of ssh
DEFINE _opt_fgltty_pw STRING --fgltty password
DEFINE _opt_fgltty_load STRING --fgltty load config
DEFINE _fglfeid, _fglfeid2 STRING
DEFINE _remotePort INT
CONSTANT ALLO = "Allocated port "
CONSTANT MAXLINES = 10
MAIN
  DEFINE entries fgljp.TStartEntries
  DEFINE tmp STRING
  CALL fgl_setenv("FGLJPSSH_PARENT", "1")
  CALL parseArgs()
  LET _fglfeid = fgljp.genSID(TRUE)
  CALL fgl_setenv("_FGLFEID", _fglfeid)
  LET _fglfeid2 = fgljp.genSID(TRUE)
  CALL fgl_setenv("_FGLFEID2", _fglfeid2)
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
  DISPLAY "fglssh terminated"
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
  LET o[i].name = "login-name"
  LET o[i].description = "remote ssh user"
  LET o[i].opt_char = "l"
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

  CALL mygetopt.initialize(gr, "fglssh", mygetopt.copyArguments(1), o)
  WHILE mygetopt.getopt(gr) == mygetopt.SUCCESS
    LET opt_arg = mygetopt.opt_arg(gr)
    LET opt_char = mygetopt.opt_char(gr)
    CASE mygetopt.opt_char(gr)
      WHEN 'v'
        LET _verbose = TRUE
      WHEN 'h'
        CALL mygetopt.displayUsage(gr, "<remote host> ?ssh_command?")
        EXIT PROGRAM 0
      WHEN 'l'
        LET _opt_ssh_usr = opt_arg
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
          LET opt_name = o[mygetopt.option_index(gr)].name
          --DISPLAY "Got long option ", opt_name
          CASE opt_name
            WHEN "load"
              LET _opt_fgltty_load = opt_arg
          END CASE
        END IF
    END CASE
  END WHILE
  IF (cnt := mygetopt.getMoreArgumentCount(gr)) >= 1 THEN
    FOR i = 1 TO cnt
      --DISPLAY "myopt count:", mygetopt.getMoreArgument(gr, i)
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
  OPTIONS MESSAGE LINE 3
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
  LET cmd = SFMT("fglrun %1 > %2 2>&1", fgljp_p, tmp)
  IF _opt_fgltty IS NULL THEN
    --windows ssh: we need a separate console for fgljp to avoid Ctrl-c
    --affecting it, the mini whide.exe hides the extra console window
    --not needed for fgltty
    LET cmd =
        IIF(fgljp.isWin(),
            SFMT('%1\\win\\whide cmd /c "%2"',
                os.Path.dirName(arg_val(0)), cmd),
            cmd)
  END IF
  RUN cmd WITHOUT WAITING
  LET ch = waitOpen(tmp)
  LET line = waitReadLine(ch, tmp)
  DISPLAY "start_fgljp:", line
  CALL util.JSON.parse(line, entries)
  RETURN entries.*, tmp
END FUNCTION

FUNCTION getLocalUser()
  DEFINE usr, usr_envname, trial STRING
  LET usr_envname = IIF(fgljp.isWin(), "USERNAME", "USER")
  LET trial = fgl_getenv(usr_envname)
  LET usr = IIF(trial IS NOT NULL, trial, NULL)
  IF usr IS NULL THEN
    LET trial = fgl_getenv("LOGNAME")
    LET usr = IIF(trial IS NOT NULL, trial, NULL)
  END IF
  RETURN usr
END FUNCTION

FUNCTION extract_user(destination STRING) RETURNS(STRING, STRING)
  DEFINE idx INT
  DEFINE usr, host STRING
  LET idx = destination.getIndexOf("@", 1)
  IF idx > 0 THEN
    LET host = destination.subString(idx + 1, destination.getLength())
    LET usr = destination.subString(1, idx - 1)
  ELSE
    IF _opt_ssh_usr IS NOT NULL THEN
      LET usr = _opt_ssh_usr
    ELSE
      LET usr = getLocalUser()
    END IF
    LET host = destination
  END IF
  RETURN usr, host
END FUNCTION

FUNCTION replace_tags(cmds STRING, localPort INT) RETURNS STRING
  CONSTANT AT_FGL =
      "FGLSERVER=%1; export FGLSERVER; FGLGUI=1; export FGLGUI; _FGLFEID=%2; export _FGLFEID; _FGLFEID2=%3; export _FGLFEID2";
  CONSTANT AT_FGLKSH =
      'FGLSERVER="%1"; export FGLSERVER; FGLGUI=1; export FGLGUI; _FGLFEID="%2"; export _FGLFEID; _FGLFEID2="%3"; export _FGLFEID2'
  CONSTANT AT_FGLNT =
      "set FGLSERVER=%1&&set FGLGUI=1&&set _FGLFEID=%2&&set _FGLFEID2=%3";
  CONSTANT AT_FGLCSH =
      "setenv FGLSERVER %1&&setenv FGLGUI 1&&setenv _FGLFEID %2&&setenv _FGLFEID %3";
  DEFINE at_fgl_s, at_fglnt_s, at_fglksh_s, at_fglcsh_s, rUser, host STRING
  DEFINE rsvr, srvnum STRING
  LET srvnum =
      IIF(_opt_fgltty IS NOT NULL, "[_FGL_GDC_REAL_PORT_]", _remotePort - 6400)
  LET rsvr = "localhost:", srvnum
  LET at_fgl_s = SFMT(AT_FGL, rsvr, _fglfeid, _fglfeid2);
  LET at_fglnt_s = SFMT(AT_FGLNT, rsvr, _fglfeid, _fglfeid2);
  LET at_fglksh_s = SFMT(AT_FGLKSH, rsvr, _fglfeid, _fglfeid2);
  LET at_fglcsh_s = SFMT(AT_FGLCSH, rsvr, _fglfeid, _fglfeid2);
  LET cmds = search_and_replace_tag(cmds, "@FGL", at_fgl_s)
  LET cmds = search_and_replace_tag(cmds, "@FGLNT", at_fglnt_s)
  LET cmds = search_and_replace_tag(cmds, "@FGLKSH", at_fglksh_s)
  LET cmds = search_and_replace_tag(cmds, "@FGLCSH", at_fglcsh_s)
  LET cmds = search_and_replace_tag(cmds, "@SRVNUM", "[_FGL_GDC_REAL_PORT_]")
  LET cmds = search_and_replace_tag(cmds, "@USR", getLocalUser())
  LET cmds = search_and_replace_tag(cmds, "@FEID", _fglfeid)
  LET cmds = search_and_replace_tag(cmds, "@FEID2", _fglfeid2)
  LET cmds = search_and_replace_tag(cmds, "@E_SRV", "export FGLSERVER")
  CALL extract_user(_opt_ssh_host) RETURNING rUser, host
  LET cmds = search_and_replace_tag(cmds, "@USER", rUser)
  LET cmds = search_and_replace_tag(cmds, "@PORT", SFMT("%1", localPort))
  RETURN cmds
END FUNCTION

FUNCTION start_fgltty(localPort INT)
  DEFINE cmd, usr, host, line, cmds STRING
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
        SFMT('%1 -c "FGLSERVER=localhost:[_FGL_GDC_REAL_PORT_] _FGLFEID=%2 _FGLFEID2=%3 bash -li"',
            cmd, _fglfeid, _fglfeid2)
  ELSE
    LET cmds = replace_tags(_opt_ssh_args, localPort)
    LET cmd = SFMT('%1 -c %2', cmd, quote(cmds))
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
  DEFINE idx, idx2, aLen, i INT
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
  LET _remotePort = line.subString(idx + aLen + 1, idx2 - 1)
  MYASSERT(_remotePort IS NOT NULL)
  LET rFGLSERVER = SFMT("localhost:%1", _remotePort - 6400)
  IF _opt_tunnelonly THEN
    CALL menu_tunnelonly(rFGLSERVER)
  ELSE
    IF _opt_ssh_bash THEN
      --make usage of the master control socket of possible (avoids re auth)
      LET cmd = IIF(fgljp.isWin(), "ssh -t", SFMT("ssh -t -S %1", tmps))
      LET cmd =
          IIF(_opt_ssh_port IS NULL, cmd, SFMT("%1 -p %2", cmd, _opt_ssh_port))
      --simply export FGLSERVER at the remote side
      LET cmd =
          SFMT("%1 %2 FGLSERVER=%3 _FGLFEID=%4 _FGLFEID2=%5 bash -li",
              cmd, _opt_ssh_host, rFGLSERVER, _fglfeid, _fglfeid2)
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
      --DISPLAY "_opt_ssh_args:", _opt_ssh_args
      LET cmd =
          SFMT("%1 -t -o SendEnv=FGLSERVER -o SendEnv=_FGLFEID -o SendEnv=_FGLFEID2 %2 %3",
              cmd, _opt_ssh_host, quote(replace_tags(_opt_ssh_args, localPort)))
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

FUNCTION copy2clip(txt STRING)
  DEFINE c base.Channel
  LET c = base.Channel.create()
  CALL c.setDelimiter("")
  CASE
    WHEN isWin()
      CALL c.openPipe("clip", "w")
    WHEN fgljp.isMac()
      CALL c.openPipe("pbcopy", "w")
    OTHERWISE
      CALL c.openPipe("xclip -selection c", "w")
  END CASE
  CALL c.write(txt)
  CALL c.close()
END FUNCTION

FUNCTION menu_tunnelonly(rFGLSERVER STRING)
  DEFINE cmd, cmdb1, cmdb2, cmdnt1, cmdnt2, cmdc1, cmdc2 STRING
  --DISPLAY "1         2         3         4         5         6         7         8         " AT 3,1

  --DISPLAY "01234567890123456789012345678901234567890123456789012345678901234567890123456789" AT 4,1
  DISPLAY "bash:" AT 4, 1
  LET cmdb1 =
      SFMT('export FGLSERVER=%1;export _FGLFEID=%2;', rFGLSERVER, _fglfeid)
  DISPLAY cmdb1 AT 5, 1
  LET cmdb2 = SFMT('export _FGLFEID2=%1;', _fglfeid2)
  DISPLAY cmdb2 AT 6, 1
  DISPLAY "cmd:" AT 8, 1
  LET cmdnt1 = SFMT("set FGLSERVER=%1&&set _FGLFEID=%2", rFGLSERVER, _fglfeid)
  DISPLAY cmdnt1 AT 9, 1
  LET cmdnt2 = SFMT("set _FGLFEID2=%1", _fglfeid2)
  DISPLAY cmdnt2 AT 10, 1
  DISPLAY "csh:" AT 12, 1
  LET cmdc1 =
      SFMT("setenv FGLSERVER=%1&&setenv _FGLFEID=%2", rFGLSERVER, _fglfeid)
  DISPLAY cmdc1 AT 13, 1
  LET cmdc2 = SFMT("setenv _FGLFEID2=%1", _fglfeid2)
  DISPLAY cmdc2 AT 14, 1
  MENU "Remote tunnel for fglrun active"
    COMMAND "Bash" "Copies the environment for bash hosts to clipboard"
      LET cmd = SFMT("%1%2", cmdb1, cmdb2)
      CALL copy2clip(cmd)
      MESSAGE "did copy environment for bash" ATTRIBUTE(RED)
    COMMAND "Windows" "Copies the environment for Windows hosts to clipboard"
      LET cmd = SFMT("%1&&%2", cmdnt1, cmdnt2)
      CALL copy2clip(cmd)
      MESSAGE "did copy environment for Windows" ATTRIBUTE(RED)
    COMMAND "Csh" "Copies the environment for CSH hosts to clipboard"
      LET cmd = SFMT("%1&&%2", cmdc1, cmdc2)
      CALL copy2clip(cmd)
      MESSAGE "did copy environment for CSH" ATTRIBUTE(RED)
    COMMAND "Exit" "Exits and closes the tunnel"
      EXIT MENU
  END MENU
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

FUNCTION search_and_replace_tag(src, srch_search, srch_replace) RETURNS STRING
  DEFINE src, srch_search, srch_replace STRING
  DEFINE idx INT
  DEFINE found BOOLEAN
  CALL search_tag(src, 1, srch_search) RETURNING found, idx
  IF found THEN
    LET src = replace_tag(src, idx, srch_search, srch_replace)
  END IF
  RETURN src
END FUNCTION

FUNCTION replace_tag(src, start, srch_search, srch_replace) RETURNS STRING
  DEFINE src, srch_search, srch_replace STRING
  DEFINE start INT
  DEFINE end INT
  LET end = start + srch_search.getLength()
  LET src =
      src.subString(1, start - 1),
      srch_replace,
      src.subString(end, src.getLength())
  RETURN src
END FUNCTION

--checks if the given character is a delimiter character
FUNCTION isDelimiterChar(ch)
  DEFINE ch, delimiters STRING
  DEFINE idx INTEGER
  IF ch IS NULL THEN
    RETURN 1
  END IF
  LET delimiters = " \t()<>[]{}:,;.?!\"'-+/*=&%$^:#~|@\n\r"
  LET idx = delimiters.getIndexOf(ch, 1)
  RETURN idx <> 0
END FUNCTION

--returns if the search string was found and the position
FUNCTION search_tag(txt, startpos, srch_search) RETURNS(BOOLEAN, INT)
  DEFINE txt, srch_search STRING
  DEFINE startpos INT
  DEFINE found BOOLEAN
  DEFINE idxfound INT
  DEFINE leftChar, rightChar STRING
  CONSTANT AT_SIGN = "@"

  LET idxfound = txt.getIndexOf(srch_search, startpos)
  {DISPLAY "int_search :",
      srch_search,
      ",startpos:",
      startpos,
      ",textlen:",
      txt.getLength(),
      ",idxfound:",
      idxfound}
  LET found = idxfound <> 0
  IF found THEN
    --check if there are delimiters at the left or the right
    IF idxfound > 1 THEN
      LET leftChar = txt.getCharAt(idxfound - 1)
      IF NOT AT_SIGN.equals(txt.getCharAt(idxfound))
          AND NOT isDelimiterChar(leftChar) THEN
        LET found = FALSE
      END IF
    END IF
    IF found AND idxfound + srch_search.getLength() <= txt.getLength() THEN
      LET rightChar = txt.getCharAt(idxfound + srch_search.getLength())
      IF NOT isDelimiterChar(rightChar) THEN
        LET found = FALSE
      END IF
    END IF
  END IF -- found
  RETURN found, idxfound
END FUNCTION
