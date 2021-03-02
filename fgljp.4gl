#+ fgljp fgl GAS proxy using java interfaces
OPTIONS
SHORT CIRCUIT
&define MYASSERT(x) IF NOT NVL(x,0) THEN CALL myErr("ASSERTION failed in line:"||__LINE__||":"||#x) END IF
&define MYASSERT_MSG(x,msg) IF NOT NVL(x,0) THEN CALL myErr("ASSERTION failed in line:"||__LINE__||":"||#x||","||msg) END IF
&define UNUSED_VAR(var) INITIALIZE var TO NULL
IMPORT os
IMPORT util
IMPORT FGL mygetopt
IMPORT JAVA com.fourjs.fgl.lang.FglRecord
IMPORT JAVA java.time.LocalDateTime
IMPORT JAVA java.time.ZoneOffset
IMPORT JAVA java.time.Instant
IMPORT JAVA java.io.File
IMPORT JAVA java.io.FileInputStream
IMPORT JAVA java.io.FileOutputStream
IMPORT JAVA java.io.DataInputStream
IMPORT JAVA java.io.DataOutputStream
IMPORT JAVA java.io.IOException
IMPORT JAVA java.io.InputStream
IMPORT JAVA java.io.InputStreamReader
IMPORT JAVA java.io.BufferedReader
IMPORT JAVA java.nio.channels.SelectionKey
IMPORT JAVA java.nio.channels.Selector
IMPORT JAVA java.nio.channels.ServerSocketChannel
IMPORT JAVA java.nio.channels.SocketChannel
IMPORT JAVA java.nio.channels.FileChannel
IMPORT JAVA java.nio.channels.Channels
IMPORT JAVA java.nio.file.Files
IMPORT JAVA java.nio.file.Path
IMPORT JAVA java.nio.file.Paths
IMPORT JAVA java.nio.file.LinkOption
IMPORT JAVA java.nio.file.attribute.FileTime
IMPORT JAVA java.nio.ByteOrder
IMPORT JAVA java.nio.ByteBuffer
IMPORT JAVA java.nio.CharBuffer
IMPORT JAVA java.nio.charset.Charset
IMPORT JAVA java.nio.charset.CharsetDecoder
IMPORT JAVA java.nio.charset.CharsetEncoder
IMPORT JAVA java.nio.charset.StandardCharsets
IMPORT JAVA java.net.URI
IMPORT JAVA java.net.ServerSocket
IMPORT JAVA java.net.InetSocketAddress
IMPORT JAVA java.util.Set --<SelectionKey>
IMPORT JAVA java.util.HashSet
IMPORT JAVA java.util.regex.Matcher
IMPORT JAVA java.util.regex.Pattern
IMPORT JAVA java.util.Iterator --<SelectionKey>
IMPORT JAVA java.lang.String
IMPORT JAVA java.lang.Object
IMPORT JAVA java.lang.Integer
--IMPORT JAVA java.lang.Byte
--IMPORT JAVA java.lang.Boolean
--IMPORT JAVA java.util.Arrays
CONSTANT _keepalive = TRUE

PUBLIC TYPE TStartEntries RECORD
  port INT,
  FGLSERVER STRING,
  pid INT,
  url STRING
END RECORD

--TYPE MyByteArray ARRAY[] OF TINYINT
TYPE TStringDict DICTIONARY OF STRING
TYPE TStringArr DYNAMIC ARRAY OF STRING
TYPE ByteArray ARRAY[] OF TINYINT

CONSTANT S_INIT = "Init"
CONSTANT S_HEADERS = "Headers"
CONSTANT S_WAITCONTENT = "WaitContent"
CONSTANT S_ACTIVE = "Active"
CONSTANT S_WAITFORVM = "WaitForVM"
CONSTANT S_FINISH = "Finish"

--record attached to each channels key
--holds the state of the connection
TYPE TSelectionRec RECORD
  active BOOLEAN,
  chan SocketChannel,
  dIn DataInputStream,
  dOut DataOutputStream,
  id INT,
  state STRING,
  starttime DATETIME HOUR TO FRACTION(1),
  isVM BOOLEAN, --VM related members
  children TStringArr, --program children procId's
  childCnt INT, --program children procId's
  --t TStringDict,
  httpKey SelectionKey, --http connection waiting
  VmCmd STRING, --last VM cmd
  procId STRING, --VM procId
  procIdParent STRING, --VM procIdParent
  procIdWaiting STRING, --VM procIdWaiting
  didSendVMClose BOOLEAN,
  --meta STRING,
  --metaSeen BOOLEAN,
  isHTTP BOOLEAN, --HTTP related members
  path STRING,
  method STRING,
  body STRING,
  headers TStringDict,
  contentLen INT,
  clitag STRING
END RECORD

DEFINE _s DYNAMIC ARRAY OF TSelectionRec

DEFINE _utf8 Charset
DEFINE _encoder CharsetEncoder
DEFINE _decoder CharsetDecoder
DEFINE _metaSeen BOOLEAN
DEFINE _wait BOOLEAN --token for socket communication
DEFINE _opt_port STRING
DEFINE _opt_startfile STRING
DEFINE _opt_logfile STRING
DEFINE _opt_autoclose BOOLEAN
DEFINE _opt_gdc BOOLEAN
DEFINE _opt_runonserver BOOLEAN
DEFINE _opt_nostart BOOLEAN
DEFINE _logChan base.Channel
DEFINE _opt_program, _opt_program1 STRING
DEFINE _verbose BOOLEAN
DEFINE _selDict DICTIONARY OF INTEGER
DEFINE _checkGoOut BOOLEAN
DEFINE _starttime DATETIME HOUR TO FRACTION(1)
DEFINE _stderr base.Channel

--CONSTANT size_i = 4 --sizeof(int)

DEFINE _isMac BOOLEAN
DEFINE _askedOnMac BOOLEAN
DEFINE _gbcdir STRING
DEFINE _owndir STRING
DEFINE _privdir STRING
DEFINE _pubdir STRING
DEFINE _progdir STRING
DEFINE _htpre STRING
DEFINE _serverkey SelectionKey
DEFINE _server ServerSocketChannel
DEFINE _didAcceptOnce BOOLEAN
DEFINE _selector Selector
DEFINE _fglserver STRING

MAIN
  DEFINE socket ServerSocket
  DEFINE port INT
  --DEFINE numkeys INT
  DEFINE htpre STRING
  DEFINE uapre, gbcpre, priv, pub STRING
  --DEFINE pending HashSet
  --DEFINE clientkey SelectionKey
  LET _starttime = CURRENT
  CALL parseArgs()
  LET _utf8 = StandardCharsets.UTF_8
  LET _encoder = _utf8.newEncoder()
  LET _decoder = _utf8.newDecoder()
  LET _fglserver = fgl_getenv("FGLSERVER")
  LET _server = ServerSocketChannel.open();
  CALL _server.configureBlocking(FALSE);
  LET socket = _server.socket();
  IF _opt_program IS NOT NULL AND _opt_port IS NULL THEN
    LET port = 8787
    LET _opt_autoclose = TRUE
  ELSE
    LET port = IIF(_opt_port IS NOT NULL, parseInt(_opt_port), 6400)
  END IF
  ---CALL log(SFMT("use port:%1 for bind()", port))
  LABEL bind_again:
  TRY
    CALL socket.bind(InetSocketAddress.create(port));
  CATCH
    CALL log(SFMT("socket.bind:%1", err_get(status)))
    IF _opt_program IS NOT NULL AND _opt_port IS NULL THEN
      LET port = port + 1
      IF port < 9000 THEN
        GOTO bind_again
      END IF
    END IF
  END TRY
  LET port = socket.getLocalPort()
  IF _opt_program IS NULL THEN
    CALL writeStartFile(port)
  END IF
  CALL log(
      SFMT("listening on real port:%1,FGLSERVER:%2",
          port, fgl_getenv("FGLSERVER")))
  LET htpre = SFMT("http://localhost:%1/", port)
  LET _htpre = htpre
  LET uapre = htpre, "ua/"
  LET gbcpre = htpre, "gbc/"
  LET priv = htpre, "priv/"
  --LET pub = htpre, "pub/"
  LET pub = htpre
  LET _selector = java.nio.channels.Selector.open()
  LET _serverkey = _server.register(_selector, SelectionKey.OP_ACCEPT);
  IF _opt_program IS NOT NULL THEN
    CALL checkGBCAvailable()
    CALL setup_program(priv, pub, port)
  END IF
  WHILE TRUE
    IF _didAcceptOnce AND _checkGoOut AND canGoOut() THEN
      EXIT WHILE
    END IF
    IF _verbose THEN
      CALL printKeys("before select,registered keys:", _selector.keys())
    END IF
    CALL _selector.select();
    CALL processKeys("processKeys selectedKeys():", _selector.selectedKeys())
  END WHILE
END MAIN

FUNCTION processKeys(what STRING, inkeys Set)
  DEFINE keys Set
  DEFINE key SelectionKey
  DEFINE it Iterator
  IF inkeys.size() == 0 THEN
    RETURN
  END IF
  LET keys = HashSet.create(inkeys) --create a clone to avoid mutation errors
  IF _verbose THEN
    CALL printKeys(what, keys)
  END IF
  LET it = keys.iterator()
  WHILE it.hasNext()
    LET key = CAST(it.next() AS SelectionKey);
    IF key.equals(_serverkey) THEN --accept a new connection
      MYASSERT(key.attachment() IS NULL)
      LET _didAcceptOnce = TRUE
      CALL acceptNew()
    ELSE
      CALL handleConnection(key)
    END IF
    --CALL pending.remove(key)
  END WHILE
  --IF pending.size() > 0 THEN
  --  CALL printKeys("!!!!pending Keys left:", pending)
  --  CALL processKeys("pending keys:",pending,HashSet.create())
  --END IF
END FUNCTION

FUNCTION printSel(x INT)
  DEFINE diff INTERVAL MINUTE TO FRACTION(1)
  IF NOT _verbose THEN
    RETURN ""
  END IF
  MYASSERT(_s[x].id == x)
  LET diff = CURRENT - _s[x].starttime
  CASE
    WHEN _s[x].isVM
      RETURN SFMT("{VM id:%1 s:%2 procId:%3 t:%4}",
          x, _s[x].state, _s[x].procId, diff)
    WHEN _s[x].isHTTP
      RETURN SFMT("{HTTP id:%1 s:%2 p:%3 t:%4}",
          x, _s[x].state, _s[x].path, diff)
    OTHERWISE
      RETURN SFMT("{_ id:%1 s:%2 t:%3}", x, _s[x].state, diff)
  END CASE
END FUNCTION

FUNCTION canGoOut()
  LET _checkGoOut = FALSE
  --DISPLAY "_selDict.getLength:",_selDict.getLength(),",keys:",util.JSON.stringify(_selDict.getKeys())
  IF _selDict.getLength() == 0 THEN
    DISPLAY "no VM channels anymore"
    RETURN TRUE
  END IF
  RETURN FALSE
END FUNCTION

FUNCTION printKey(key SelectionKey)
  DEFINE ji java.lang.Integer
  IF key.equals(_serverkey) THEN
    RETURN "{serverkey}"
  ELSE
    LET ji = CAST(key.attachment() AS java.lang.Integer)
    RETURN printSel(ji.intValue())
  END IF
END FUNCTION

FUNCTION printKeys(what STRING, keys Set)
  DEFINE it Iterator
  DEFINE o STRING
  DEFINE key SelectionKey
  LET it = keys.iterator()
  WHILE it.hasNext()
    LET key = CAST(it.next() AS SelectionKey);
    LET o = o, " ", printKey(key)
  END WHILE
  DISPLAY what, o
END FUNCTION

FUNCTION setup_program(priv STRING, pub STRING, port INT)
  DEFINE s STRING
  LET _owndir = os.Path.fullPath(os.Path.dirName(arg_val(0)))
  LET _privdir = os.Path.join(_owndir, "priv")
  LET _progdir = os.Path.fullPath(os.Path.dirName(_opt_program1))
  LET _pubdir = _progdir
  CALL os.Path.mkdir(_privdir) RETURNING status
  CALL fgl_setenv("FGLSERVER", SFMT("localhost:%1", port - 6400))
  CALL fgl_setenv("FGL_PRIVATE_DIR", _privdir)
  CALL fgl_setenv("FGL_PUBLIC_DIR", _pubdir)
  CALL fgl_setenv("FGL_PUBLIC_IMAGEPATH", ".")
  CALL fgl_setenv("FGL_PRIVATE_URL_PREFIX", priv)
  CALL fgl_setenv("FGL_PUBLIC_URL_PREFIX", pub)
  --should work on both Win and Unix
  --LET s= "cd ",_progdir,"&&fglrun ",os.Path.baseName(prog)
  LET s = SFMT("fglrun %1", _opt_program)
  CALL log(SFMT("RUN:%1 WITHOUT WAITING", s))
  RUN s WITHOUT WAITING
END FUNCTION

FUNCTION writeStartFile(port INT)
  DEFINE entries TStartEntries
  DEFINE ch base.Channel
  LET entries.port = port
  LET entries.FGLSERVER = SFMT("localhost:%1", port - 6400)
  LET entries.pid = fgl_getpid()
  DISPLAY util.JSON.stringify(entries)
  IF _opt_startfile IS NULL THEN
    RETURN
  END IF
  LET ch = base.Channel.create()
  CALL ch.openFile(_opt_startfile, "w")
  CALL ch.writeLine(util.JSON.stringify(entries))
  CALL ch.close()
END FUNCTION

PRIVATE FUNCTION parseArgs()
  DEFINE gr mygetopt.GetoptR
  DEFINE o mygetopt.GetoptOptions
  DEFINE opt_arg STRING
  DEFINE i, cnt INT

  LET i = o.getLength() + 1
  LET o[i].name = "startfile"
  LET o[i].description =
      "JSON file with start info if no program is directly started"
  LET o[i].opt_char = "a"
  LET o[i].arg_type = mygetopt.REQUIRED

  LET i = o.getLength() + 1
  LET o[i].name = "version"
  LET o[i].description = "Version information"
  LET o[i].opt_char = "V"
  LET o[i].arg_type = mygetopt.NONE

  LET i = o.getLength() + 1
  LET o[i].name = "help"
  LET o[i].description = "program help"
  LET o[i].opt_char = "h"
  LET o[i].arg_type = mygetopt.NONE

  LET i = o.getLength() + 1
  LET o[i].name = "verbose"
  LET o[i].description = "detailed log"
  LET o[i].opt_char = "v"
  LET o[i].arg_type = mygetopt.NONE

  LET i = o.getLength() + 1
  LET o[i].name = "port"
  LET o[i].description = "Listening port"
  LET o[i].opt_char = "p"
  LET o[i].arg_type = mygetopt.REQUIRED

  LET i = o.getLength() + 1
  LET o[i].name = "logfile"
  LET o[i].description = "File written for logs and success"
  LET o[i].opt_char = "l"
  LET o[i].arg_type = mygetopt.REQUIRED

  LET i = o.getLength() + 1
  LET o[i].name = "runonserver"
  LET o[i].description =
      "connects GMI/GMA via runonserver to the spawned program (internal dev)"
  LET o[i].opt_char = "r"
  LET o[i].arg_type = mygetopt.NONE

  LET i = o.getLength() + 1
  LET o[i].name = "gdc"
  LET o[i].description = "connects GDC to the spawned program (internal dev)"
  LET o[i].opt_char = "g"
  LET o[i].arg_type = mygetopt.NONE

  LET i = o.getLength() + 1
  LET o[i].name = "nostart"
  LET o[i].description =
      "spawns the program and displays the program URL on stdout"
  LET o[i].opt_char = "n"
  LET o[i].arg_type = mygetopt.NONE

  LET i = o.getLength() + 1
  LET o[i].name = "autoclose"
  LET o[i].description = "If the connecton ends fgljp closes"
  LET o[i].opt_char = "X"
  LET o[i].arg_type = mygetopt.NONE

  CALL mygetopt.initialize(gr, "fgljp", mygetopt.copyArguments(1), o)
  WHILE mygetopt.getopt(gr) == mygetopt.SUCCESS
    LET opt_arg = gr[1].opt_arg
    CASE gr[1].opt_char
      WHEN 'V'
        DISPLAY "1.00"
        EXIT PROGRAM 0
      WHEN 'v'
        LET _verbose = TRUE
      WHEN 'h'
        CALL mygetopt.displayUsage(gr, "<program> ?arg? ?arg?")
        EXIT PROGRAM 0
      WHEN 'p'
        LET _opt_port = opt_arg
        CALL parseInt(_opt_port) RETURNING status
      WHEN 'a'
        LET _opt_startfile = opt_arg
      WHEN 'n'
        LET _opt_nostart = TRUE
      WHEN 'l'
        LET _opt_logfile = opt_arg
      WHEN 'g'
        LET _opt_gdc = TRUE
      WHEN 'r'
        LET _opt_runonserver = TRUE
      WHEN 'X'
        LET _opt_autoclose = TRUE
    END CASE
  END WHILE
  IF (cnt := mygetopt.getMoreArgumentCount(gr)) >= 1 THEN
    FOR i = 1 TO cnt
      LET _opt_program = _opt_program, mygetopt.getMoreArgument(gr, i), " "
      IF i == 1 THEN
        LET _opt_program1 = _opt_program
      END IF
    END FOR
  END IF
END FUNCTION

PRIVATE FUNCTION myErr(errstr STRING)
  DEFINE ch base.Channel
  LET ch = base.Channel.create()
  CALL ch.openFile("<stderr>", "w")
  CALL ch.writeLine(
      SFMT("ERROR:%1 stack:\n%2", errstr, base.Application.getStackTrace()))
  CALL ch.close()
  EXIT PROGRAM 1
END FUNCTION

{
FUNCTION createBufferedReader()
  DEFINE ins InputStream
  DEFINE ir InputStreamReader
  LET ins = _sel.chan.socket().getInputStream()
  --LET ir = InputStreamReader.create(ins,"ISO-8859-1"); --need an 8bit encoding
  LET ir = InputStreamReader.create(ins, "utf-8"); --need an 8bit encoding
  LET _sel.br = BufferedReader.create(ir);
END FUNCTION
}

FUNCTION findFreeSelIdx()
  DEFINE i, len INT
  LET len = _s.getLength()
  FOR i = 1 TO len
    IF NOT _s[i].active THEN
      RETURN i
    END IF
  END FOR
  LET i = len + 1
  RETURN i
END FUNCTION

FUNCTION acceptNew()
  DEFINE chan SocketChannel
  DEFINE clientkey SelectionKey
  --DEFINE buf java.nio.ByteBuffer
  DEFINE ins InputStream
  --DEFINE ir InputStreamReader
  DEFINE dIn DataInputStream
  --DEFINE br BufferedReader
  DEFINE c INT
  DEFINE empty TSelectionRec
  DEFINE ji java.lang.Integer
  LET chan = _server.accept()
  IF chan IS NULL THEN
    --CALL log("acceptNew: chan is NULL") --normal in non blocking
    RETURN
  END IF
  LET ins = chan.socket().getInputStream()
  --LET ir = InputStreamReader.create(ins,"ISO-8859-1"); --need an 8bit encoding
  --LET ir = InputStreamReader.create(ins,"utf-8"); --need an 8bit encoding
  --LET br = BufferedReader.create(ir);
  LET dIn = DataInputStream.create(ins);
  CALL chan.configureBlocking(FALSE);
  LET clientkey = chan.register(_selector, SelectionKey.OP_READ);
  --CALL clientkey.interestOps(0)
  --LET buf = ByteBuffer.allocate(2048) --allocate initial buffer for meta
  LET c = findFreeSelIdx()
  LET _s[c].* = empty.*
  LET _s[c].state = S_INIT
  LET _s[c].chan = chan
  --LET _selId = _selId + 1
  --LET s[c].ins=ins
  --LET s[c].br = br
  LET _s[c].dIn = dIn
  LET _s[c].starttime = CURRENT
  LET _s[c].active = TRUE
  LET _s[c].id = c
  LET ji = java.lang.Integer.create(c)
  CALL clientkey.attach(ji)
END FUNCTION

FUNCTION attachEncapsBuf(key SelectionKey)
  --prepare the next encapsulated read
  CALL key.attach(ByteBuffer.allocate(9))
END FUNCTION

FUNCTION attachBodySizeBuf(key SelectionKey, bodySize INT, type TINYINT)
  --prepare read of user data
  DEFINE xsize INT
  DEFINE buf ByteBuffer
  LET xsize = 9 + bodySize
  --DISPLAY "attachBodySizeBuf:", bodySize, ",type:", type,",xsize:",xsize
  LET buf = ByteBuffer.allocate(xsize)
  CALL buf.putInt(bodySize)
  CALL buf.putInt(bodySize)
  CALL buf.put(type)
  CALL key.attach(buf)
END FUNCTION

FUNCTION removeCR(s STRING)
  IF s.getCharAt(s.getLength()) == '\r' THEN
    LET s = s.subString(1, s.getLength() - 1)
  END IF
  RETURN s
END FUNCTION

FUNCTION splitHTTPLine(s)
  DEFINE a DYNAMIC ARRAY OF STRING
  DEFINE s STRING
  DEFINE t base.StringTokenizer
  LET t = base.StringTokenizer.create(s, ' ')
  LET a[1] = t.nextToken()
  LET a[2] = t.nextToken()
  LET a[3] = t.nextToken()
  RETURN a
END FUNCTION

FUNCTION parseHttpLine(x INT, s STRING)
  DEFINE a DYNAMIC ARRAY OF STRING
  LET s = removeCR(s)
  LET a = splitHTTPLine(s)
  LET _s[x].method = a[1]
  LET _s[x].path = a[2]
  CALL log(SFMT("parseHttpLine:%1 %2", s, printSel(x)))
  IF a[3] <> "HTTP/1.1" THEN
    CALL myErr(SFMT("'%1' must be HTTP/1.1", a[3]))
  END IF
END FUNCTION

FUNCTION parseHttpHeader(x INT, s STRING)
  DEFINE cIdx INT
  DEFINE key, val STRING
  LET s = removeCR(s)
  LET cIdx = s.getIndexOf(":", 1)
  MYASSERT(cIdx > 0)
  LET key = s.subString(1, cIdx - 1)
  LET key = key.toLowerCase()
  LET val = s.subString(cIdx + 2, s.getLength())
  --DISPLAY "key:",key,",val:'",val,"'"
  CASE key
    WHEN "content-length"
      LET _s[x].contentLen = val
      --DISPLAY "Content-Length:", _sel.contentLen
    WHEN "if-none-match"
      LET _s[x].clitag = val
      --DISPLAY "If-None-Match", _sel.clitag
  END CASE
  LET _s[x].headers[key] = val
END FUNCTION

FUNCTION handleVM(vmidx INT, vmclose BOOLEAN)
  DEFINE procId STRING
  DEFINE line STRING
  DEFINE httpKey SelectionKey
  DEFINE ji java.lang.Integer
  DEFINE x INT
  LET procId = _s[vmidx].procId
  LET line = _s[vmidx].VmCmd
  LET httpKey = _s[vmidx].httpKey
  MYASSERT(httpKey IS NOT NULL)
  LET ji = CAST(httpKey.attachment() AS java.lang.Integer)
  LET x = ji.intValue()
  MYASSERT(_s[x].state == S_WAITFORVM)
  IF NOT _s[x].chan.isBlocking() THEN
    CALL log(SFMT("  !blocking:%1", printSel(x)))
    CALL _s[x].chan.keyFor(_selector).cancel()
    CALL _s[x].chan.configureBlocking(TRUE)
  ELSE
    CALL log(SFMT("  isBlocking:%1", printSel(x)))
  END IF
  CALL sendToClient(x, line, procId, vmclose)
  LET _s[x].state = S_FINISH
  CALL checkReRegister(x)
  LET _s[vmidx].httpKey = NULL
  LET _s[vmidx].VmCmd = NULL
  LET _s[vmidx].didSendVMClose = vmclose
END FUNCTION

FUNCTION checkNewTask(vmidx INT)
  DEFINE pidx INT
  DEFINE procIdParent STRING
  LET procIdParent = _s[vmidx].procIdParent
  MYASSERT(procIdParent IS NOT NULL)
  LET pidx = _selDict[procIdParent]
  --DISPLAY "checkNewTask:", procIdParent, " for meta:", _s[vmidx].VmCmd
  IF _s[pidx].httpKey IS NULL THEN
    DISPLAY "checkNewTask(): parent httpKey is NULL"
    RETURN
  END IF
  CALL handleVM(pidx, FALSE)
END FUNCTION

FUNCTION handleUAProto(x INT, path STRING)
  DEFINE body, procId, vmCmd, surl, appId STRING
  DEFINE qidx, vmidx INT
  DEFINE vmclose BOOLEAN
  DEFINE hdrs TStringArr
  DEFINE key SelectionKey
  DEFINE dict TStringDict
  DEFINE url URI
  LET qidx = path.getIndexOf("?", 1)

  CASE
    WHEN path.getIndexOf("/ua/r/", 1) == 1
      MYASSERT(qidx > 0)
      LET procId = path.subString(7, qidx - 1)
      CALL log(SFMT("handleUAProto procId:%1", procId))
    WHEN path.getIndexOf("/ua/sua/", 1) == 1
      LET surl = "http://localhost", path
      CALL getURLQueryDict(surl) RETURNING dict, url
      LET appId = dict["appId"]
      LET qidx = path.getIndexOf("?", 1)
      LET procId = path.subString(9, qidx - 1)
      IF appId <> "0" THEN
        --LET procId = _selDict[procId].t[appId]
        LET procId = appId
        MYASSERT(procId IS NOT NULL)
      END IF
    WHEN (path.getIndexOf("/ua/ping/", 1)) == 1
      CALL log("handleUAProto ping")
      LET hdrs = getCacheHeaders(FALSE, "")
      CALL writeResponseCtHdrs(x, "", "text/plain; charset=UTF-8", hdrs)
      RETURN
  END CASE
  MYASSERT(procId IS NOT NULL)

  IF _s[x].method == "POST" THEN
    LET body = _s[x].body
    --DISPLAY "POST body:'", body, "'"
    IF body.getLength() > 0 THEN
      CALL writeToVM(body, procId)
    END IF
  END IF
  LET vmidx = _selDict[procId]
  LET vmCmd = _s[vmidx].VmCmd
  LET _s[x].procIdWaiting = _s[vmidx].procIdWaiting
  CASE
    WHEN vmCmd IS NOT NULL OR (vmclose := (_s[vmidx].state == S_FINISH)) == TRUE
      CALL sendToClient(x, vmCmd, procId, vmclose)
    WHEN vmCmd IS NULL
      --DISPLAY "  !!!!vmCmd IS NULL, switch to wait state"
      LET _s[x].state = S_WAITFORVM
      LET key = _s[x].chan.keyFor(_selector)
      --CALL key.attach(_sel)
      --store in the VM dict our Http key
      LET _s[vmidx].httpKey = key
  END CASE
END FUNCTION

FUNCTION getCacheHeaders(cache BOOLEAN, etag STRING)
  DEFINE hdrs DYNAMIC ARRAY OF STRING
  IF cache THEN
    LET hdrs[hdrs.getLength() + 1] = "Cache-Control: max-age=1,public"
    LET hdrs[hdrs.getLength() + 1] = SFMT("ETag: %1", etag)
  ELSE
    LET hdrs[hdrs.getLength() + 1] = "Cache-Control: no-cache"
    LET hdrs[hdrs.getLength() + 1] = "Pragma: no-cache"
    LET hdrs[hdrs.getLength() + 1] = "Expires: -1"
  END IF
  RETURN hdrs
END FUNCTION

FUNCTION sendNotModified(x INT, fname STRING, etag STRING)
  DEFINE hdrs DYNAMIC ARRAY OF STRING
  LET hdrs[hdrs.getLength() + 1] = "Cache-Control: max-age=1,public"
  LET hdrs[hdrs.getLength() + 1] = SFMT("ETag: %1", etag)
  CALL log(SFMT("sendNotModified:%1", fname))
  CALL writeResponseInt2(
      x, "", "text/plain; charset=UTF-8", hdrs, "304 Not Modified")
END FUNCTION

{
FUNCTION syncSelDictFor(procId STRING)
  DEFINE key SelectionKey
  DEFINE sel TSelectionRec
  LET key = _selDict[procId].chan.keyFor(_selector)
  LET sel.* = _selDict[procId].*
  CALL key.attach(sel)
END FUNCTION
}

FUNCTION sendToClient(x INT, vmCmd STRING, procId STRING, vmclose BOOLEAN)
  DEFINE hdrs DYNAMIC ARRAY OF STRING
  DEFINE newProcId STRING
  DEFINE vmidx INT
  --DEFINE pp STRING
  --DEFINE num INT
  LET hdrs[hdrs.getLength() + 1] = "Pragma: no-cache"
  LET hdrs[hdrs.getLength() + 1] = "Expires: -1"
  LET hdrs[hdrs.getLength() + 1] = "X-XSS-Protection: 1; mode=block"
  LET hdrs[hdrs.getLength() + 1] = "Cache-Control: no-cache, no-store"
  LET hdrs[hdrs.getLength() + 1] = "Transfer-Encoding: Identity"
  LET hdrs[hdrs.getLength() + 1] = "X-Content-Type-Options: nosniff"
  LET hdrs[hdrs.getLength() + 1] = "Vary: Content-Encoding"
  --LET hdrs[hdrs.getLength() + 1] = "X-FourJs-Version: 2.0"
  LET hdrs[hdrs.getLength() + 1] = "X-FourJs-Request-Result: 10000"
  LET hdrs[hdrs.getLength() + 1] = "X-FourJs-Timeout: 10000"
  LET hdrs[hdrs.getLength() + 1] = "X-FourJs-WebComponent: webcomponents"
  LET hdrs[hdrs.getLength() + 1] = "X-FourJs-Development: true"
  LET hdrs[hdrs.getLength() + 1] = "X-FourJs-Server: GAS/3.20.14-202012101044"
  --LET pp=_selDict[procId].procIdParent
  --IF pp IS NULL OR  NOT _selDict.contains(pp) THEN
  LET hdrs[hdrs.getLength() + 1] = SFMT("X-FourJs-Id: %1", procId)
  --END IF
  --LET hdrs[hdrs.getLength() + 1] = "X-FourJs-PageId: 1"
  --DISPLAY "reset VmCmd of:",procId
  MYASSERT(_selDict.contains(procId))
  LET vmidx = _selDict[procId]
  LET _s[vmidx].VmCmd = NULL
  IF _s[vmidx].children.getLength() > 0 THEN
    LET newProcId = _s[vmidx].children[1]
    CALL _s[vmidx].children.deleteElement(1)
    LET hdrs[hdrs.getLength() + 1] = SFMT("X-FourJs-NewTask: %1", newProcId)
  END IF
  IF vmclose THEN --must be the last check in _selDict
    LET hdrs[hdrs.getLength() + 1] = "X-FourJs-Closed: true"
    CALL _selDict.remove(procId)
    --DISPLAY "  _selDict after remove:", util.JSON.stringify(_selDict.getKeys())
    LET _checkGoOut = TRUE
  END IF
  CALL log(
      SFMT("sendToClient:%1%2",
          limitPrintStr(vmCmd), IIF(vmclose, " vmclose", "")))
  IF vmCmd.getLength() > 0 THEN
    LET vmCmd = vmCmd, "\n"
  END IF
  CALL writeResponseInt2(x, vmCmd, "text/plain; charset=UTF-8", hdrs, "200 OK")
END FUNCTION

FUNCTION httpHandler(x INT)
  DEFINE text, path, fname STRING
  LET path = _s[x].path
  CALL log(SFMT("httpHandler '%1' for:%2", path, printSel(x)))
  CASE
    WHEN path == "/"
      DISPLAY "send root"
      LET text = "<!DOCTYPE html><html><body>Hello root</body></html>"
      CALL writeResponse(x, text)
    WHEN path.getIndexOf("/ua/", 1) == 1 --ua proto
      CALL handleUAProto(x, path)
    WHEN path.getIndexOf("/gbc/", 1) == 1 --gbc asset
      LET fname = path.subString(6, path.getLength())
      LET fname = cut_question(fname)
      LET fname = gbcResourceName(fname)
      --DISPLAY "fname:", fname
      CALL processFile(x, fname, TRUE)
    OTHERWISE
      IF NOT findFile(x, path) THEN
        CALL http404(x, path)
      END IF
  END CASE
END FUNCTION

FUNCTION findFile(x INT, path STRING)
  DEFINE qidx INT
  LET qidx = path.getIndexOf("?", 1)
  IF qidx > 0 THEN
    LET path = path.subString(1, qidx - 1)
  END IF
  LET path = ".", path
  IF NOT os.Path.exists(path) THEN
    CALL log(SFMT("findFile:'%1' doesn't exist", path))
    RETURN FALSE
  END IF
  CALL processFile(x, path, TRUE)
  RETURN TRUE
END FUNCTION

FUNCTION gbcResourceName(fname STRING)
  DEFINE trial STRING
  CASE
    WHEN fname.getIndexOf("webcomponents", 1) > 0
      LET fname = fname.subString(15, fname.getLength())
      --first look in <programdir>/webcomponents
      LET trial = os.Path.join(_progdir, fname)
      IF os.Path.exists(trial) THEN
        LET fname = trial
      ELSE
        --lookup the fgl web components
        --DISPLAY "Can't find:",trial
        LET fname = os.Path.join(fgl_getenv("FGLDIR"), fname)
      END IF
      --WHEN fname == "js/gbc.bootstrap.js"
      --  DISPLAY "!!fake bootstrap"
      --  LET fname = os.Path.join(_owndir, "gbc.bootstrap.js")
    OTHERWISE
      LET fname = os.Path.join(_gbcdir, fname)
  END CASE
  --DISPLAY "gbcResourceName:", fname
  RETURN fname
END FUNCTION

FUNCTION readTextFile(fname)
  DEFINE fname, res STRING
  DEFINE t TEXT
  LOCATE t IN FILE fname
  LET res = t
  RETURN res
END FUNCTION

FUNCTION processFile(x INT, fname STRING, cache BOOLEAN)
  DEFINE ext, ct, txt STRING
  DEFINE etag STRING
  DEFINE hdrs TStringArr
  IF NOT os.Path.exists(fname) THEN
    CALL http404(x, fname)
    RETURN
  END IF
  --DISPLAY "processFile:",fname
  IF cache THEN
    LET etag = SFMT("%1.%2", os.Path.mtime(fname), os.Path.size(fname))
    IF _s[x].clitag IS NOT NULL AND _s[x].clitag == etag THEN
      CALL sendNotModified(x, fname, etag)
      RETURN
    END IF
  END IF
  LET ext = os.Path.extension(fname)
  LET ct = NULL
  CASE
    WHEN ext == "html" OR ext == "css" OR ext == "js"
      CASE
        WHEN ext == "html"
          LET ct = "text/html"
        WHEN ext == "js"
          LET ct = "application/x-javascript"
        WHEN ext == "css"
          LET ct = "text/css"
      END CASE
      LET txt = readTextFile(fname)
      LET hdrs = getCacheHeaders(cache, etag)
      CALL writeResponseCtHdrs(x, txt, ct, hdrs)
    OTHERWISE
      CASE
        WHEN ext == "gif"
          LET ct = "image/gif"
        WHEN ext == "woff"
          LET ct = "application/font-woff"
        WHEN ext == "ttf"
          LET ct = "application/octet-stream"
      END CASE
      LET hdrs = getCacheHeaders(cache, etag)
      CALL writeResponseFileHdrs(x, fname, ct, hdrs)
  END CASE
END FUNCTION

FUNCTION cut_question(fname)
  DEFINE fname STRING
  DEFINE idx INT
  IF (idx := fname.getIndexOf("?", 1)) <> 0 THEN
    RETURN fname.subString(1, idx - 1)
  END IF
  RETURN fname
END FUNCTION

FUNCTION http404(x INT, fn STRING)
  DEFINE content STRING
  LET content =
      SFMT("<!DOCTYPE html><html><body>Can't find: '%1'</body></html>", fn)
  CALL log(SFMT("http404:%1", fn))
  CALL writeResponseInt(x, content, "text/html", "404 Not Found")
END FUNCTION

FUNCTION createDout(chan SocketChannel)
  DEFINE dOut DataOutputStream
  LET dOut = DataOutputStream.create(chan.socket().getOutputStream())
  RETURN dOut
END FUNCTION

FUNCTION writeHTTPLine(x INT, s STRING)
  LET s = s, "\r\n"
  CALL writeHTTP(x, s)
END FUNCTION

FUNCTION writeHTTP(x INT, s STRING)
  DEFINE js java.lang.String
  LET js = s
  IF s IS NULL THEN
    RETURN
  END IF
  LET _s[x].dOut =
      IIF(_s[x].dOut IS NOT NULL, _s[x].dOut, createDout(_s[x].chan))
  MYASSERT(_s[x].dOut IS NOT NULL)
  TRY
    CALL _s[x].dOut.write(js.getBytes(StandardCharsets.UTF_8))
  CATCH
    DISPLAY "ERROR writeHTTP:", err_get(status)
  END TRY
END FUNCTION

FUNCTION writeToVM(s STRING, procId STRING)
  DEFINE jstring java.lang.String
  DEFINE vmidx INT
  CALL log(SFMT("writeToVM:%1", s))
  MYASSERT(_selDict.contains(procId))
  LET vmidx = _selDict[procId]
  LET jstring = s
  CALL writeChannel(_s[vmidx].chan, _encoder.encode(CharBuffer.wrap(jstring)))
END FUNCTION

FUNCTION writeHTTPFile(x INT, fn STRING)
  DEFINE f java.io.File
  LET f = File.create(fn)
  LET _s[x].dOut =
      IIF(_s[x].dOut IS NOT NULL, _s[x].dOut, createDout(_s[x].chan))
  CALL _s[x].dOut.write(Files.readAllBytes(f.toPath()))
END FUNCTION

FUNCTION writeResponse(x INT, content STRING)
  CALL writeResponseInt(x, content, "text/html; charset=UTF-8", "200 OK")
END FUNCTION

FUNCTION writeResponseCtHdrs(
    x INT, content STRING, ct STRING, headers DYNAMIC ARRAY OF STRING)
  CALL writeResponseInt2(x, content, ct, headers, "200 OK")
END FUNCTION

FUNCTION writeResponseCt(x INT, content STRING, ct STRING)
  CALL writeResponseInt(x, content, ct, "200 OK")
END FUNCTION

FUNCTION writeHTTPCommon(x INT)
  DEFINE h STRING
  LET h = "Date: ", TODAY USING "DDD, DD MMM YYY", " ", TIME, " GMT"
  CALL writeHTTPLine(x, h)
  CALL writeHTTPLine(
      x, IIF(_keepalive, "Connection: keep-alive", "Connection: close"))
END FUNCTION

FUNCTION writeResponseInt(x INT, content STRING, ct STRING, code STRING)
  DEFINE headers DYNAMIC ARRAY OF STRING
  CALL writeResponseInt2(x, content, ct, headers, code)
END FUNCTION

FUNCTION writeHTTPHeaders(x INT, headers TStringArr)
  DEFINE i, len INT
  LET len = headers.getLength()
  FOR i = 1 TO len
    CALL writeHTTPLine(x, headers[i])
  END FOR
END FUNCTION

FUNCTION writeResponseInt2(
    x INT,
    content STRING,
    ct STRING,
    headers DYNAMIC ARRAY OF STRING,
    code STRING)
  DEFINE content_length INT
  MYASSERT(_s[x].chan.isBlocking())

  CALL writeHTTPLine(x, SFMT("HTTP/1.1 %1", code))
  CALL writeHTTPCommon(x)

  LET content_length = content.getLength()
  CALL writeHTTPHeaders(x, headers)
  CALL writeHTTPLine(x, SFMT("Content-Length: %1", content_length))
  CALL writeHTTPLine(x, SFMT("Content-Type: %1", ct))
  CALL writeHTTPLine(x, "")
  CALL writeHTTP(x, content)
END FUNCTION

FUNCTION writeResponseFileHdrs(x INT, fn STRING, ct STRING, headers TStringArr)
  IF NOT os.Path.exists(fn) THEN
    CALL http404(x, fn)
    RETURN
  END IF

  CALL writeHTTPLine(x, "HTTP/1.1 200 OK")
  CALL writeHTTPCommon(x)

  CALL writeHTTPHeaders(x, headers)
  CALL writeHTTPLine(x, SFMT("Content-Length: %1", os.Path.size(fn)))
  CALL writeHTTPLine(x, SFMT("Content-Type: %1", ct))
  CALL writeHTTPLine(x, "")
  CALL writeHTTPFile(x, fn)
END FUNCTION

FUNCTION extractMetaVar(line STRING, varname STRING, forceFind BOOLEAN)
  DEFINE idx1, idx2, len INT
  DEFINE key, value STRING
  LET key = SFMT('{%1 "', varname)
  LET len = key.getLength()
  LET idx1 = line.getIndexOf(key, 1)
  IF (forceFind == FALSE AND idx1 <= 0) THEN
    RETURN ""
  END IF
  MYASSERT(idx1 > 0)
  LET idx2 = line.getIndexOf('"}', idx1 + len)
  IF (forceFind == FALSE AND idx2 < idx1 + len) THEN
    RETURN ""
  END IF
  MYASSERT(idx2 > idx1 + len)
  LET value = line.subString(idx1 + len, idx2 - 1)
  CALL log(SFMT("extractMetaVar: '%1'='%2'", varname, value))
  RETURN value
END FUNCTION

FUNCTION extractProcId(p STRING)
  DEFINE pidx1 INT
  LET pidx1 = p.getIndexOf(":", 1)
  MYASSERT(pidx1 > 0)
  RETURN p.subString(pidx1 + 1, p.getLength())
END FUNCTION

FUNCTION handleMetaSel(vmidx INT, line STRING)
  DEFINE pp, pw STRING
  DEFINE ppidx INT
  DEFINE children TStringArr
  LET _s[vmidx].isVM = TRUE
  LET _s[vmidx].VmCmd = line
  LET _s[vmidx].state = S_ACTIVE
  CALL log(SFMT("handleMetaSel:%1", line))
  LET _s[vmidx].procId = extractProcId(extractMetaVar(line, "procId", TRUE))
  --DISPLAY "procId:'", _s[vmidx].procId, "'"
  LET pp = extractMetaVar(line, "procIdParent", FALSE)
  IF pp IS NOT NULL THEN
    LET pp = extractProcId(pp)
    IF _selDict.contains(pp) THEN
      LET ppidx = _selDict[pp]
      LET children = _s[ppidx].children
      LET children[children.getLength() + 1] = _s[vmidx].procId
      --DISPLAY "!!!!!!!!!!!!1set children to:", util.JSON.stringify(children)
      LET _s[vmidx].procIdParent = pp
    END IF
  END IF
  LET pw = extractMetaVar(line, "procIdWaiting", FALSE)
  IF pw IS NOT NULL THEN
    LET pw = extractProcId(pw)
    IF pw == pp THEN
      MYASSERT(_selDict.contains(pp))
      LET _s[vmidx].procIdWaiting = pp
    END IF
  END IF
  CALL decideStartOrNewTask(vmidx)
END FUNCTION

FUNCTION decideStartOrNewTask(vmidx INT)
  --either start client or send newTask
  IF _s[vmidx].procIdParent IS NOT NULL THEN
    CALL checkNewTask(vmidx)
  ELSE
    CALL handleStart(vmidx)
  END IF
END FUNCTION

FUNCTION handleMeta(key SelectionKey, buf ByteBuffer, pos INT)
  DEFINE line STRING
  UNUSED_VAR(key)
  UNUSED_VAR(pos)
  LET line = _decoder.decode(buf).toString()
  {
  IF _currline.getIndexOf("\n", 1) == 0 THEN
    CALL buf.position(pos) --continue at pos
    CALL warning(SFMT("_currline not complete:%1", _currline))
    RETURN
  END IF
  }
  IF line.getIndexOf("meta ", 1) == 1 THEN
    CALL log(SFMT("got meta:%1", line))
  ELSE
    DISPLAY "got http:", line
  END IF
  LET _metaSeen = TRUE

  --CALL attachEncapsBuf(key)
  --{frontEndID2 "123"}
  --LET meta =
  --  SFMT('meta Client{ {name "%1"} {version "%2"} {encapsulation "1"} {filetransfer "%3"} {encoding "UTF-8"}\n',
  --    _clientName, _clientVersion, ft)
  --CALL writeChannel(_currChan, _encoder.encode(CharBuffer.wrap(meta)))
END FUNCTION

FUNCTION handleConnection(key SelectionKey)
  DEFINE chan SocketChannel
  DEFINE readable BOOLEAN
  DEFINE ji java.lang.Integer
  DEFINE empty TSelectionRec
  DEFINE c INT
  TRY
    LET readable = key.isReadable()
  CATCH
    LET ji = CAST(key.attachment() AS java.lang.Integer)
    DISPLAY "ERROR handleConnection:", printSel(ji.intValue()), err_get(status)
    MYASSERT(false)
  END TRY
  IF NOT readable THEN
    CALL warning("handleConnection: NOT key.isReadable()")
    RETURN
  END IF
  LET chan = CAST(key.channel() AS SocketChannel)
  LET ji = CAST(key.attachment() AS java.lang.Integer)
  LET c = ji.intValue()
  CALL log(SFMT("handleConnection:%1 %2", printSel(c), c))
  CALL handleConnectionInt(c, key, chan)
  IF _s[c].isVM THEN
    IF _s[c].didSendVMClose THEN
      LET _s[c].* = empty.* --resets also active
    ELSE
      LET _selDict[_s[c].procId] = c --store the selector index of the procId
    END IF
  END IF
END FUNCTION

FUNCTION reRegister(c INT)
  DEFINE newkey SelectionKey
  DEFINE numKeys INT
  DEFINE chan SocketChannel
  DEFINE ji java.lang.Integer
  LET chan = _s[c].chan
  CALL log(SFMT("re register:%1", printSel(c)))
  --re register the channel again
  CALL chan.configureBlocking(FALSE)
  LET numKeys = _selector.selectNow()
  LET newkey = chan.register(_selector, SelectionKey.OP_READ);
  LET ji = java.lang.Integer.create(c)
  CALL newkey.attach(ji)
END FUNCTION

FUNCTION handleStart(vmidx INT)
  DEFINE url, procId STRING
  LET procId = _s[vmidx].procId
  LET url = SFMT("%1gbc/index.html?app=%2", _htpre, procId)
  CASE
    WHEN _opt_runonserver OR _opt_gdc
      LET url = SFMT("%1ua/r/%2", _htpre, procId)
      IF _opt_gdc THEN
        CALL checkGDC(url)
      ELSE
        CALL connectToGMI(url)
      END IF
    WHEN _opt_nostart --we just write the starting URL on stdout
      DISPLAY url
    OTHERWISE
      CALL openBrowser(url)
  END CASE
END FUNCTION

FUNCTION connectToGMI(url STRING) --works only for the emulator
  --DISPLAY "runOnServer:", url
  --need to reset the env
  CALL fgl_setenv("FGLSERVER", _fglserver)
  CALL fgl_setenv("FGL_PRIVATE_DIR", "")
  CALL fgl_setenv("FGL_PUBLIC_DIR", "")
  CALL fgl_setenv("FGL_PUBLIC_IMAGEPATH", "")
  CALL fgl_setenv("FGL_PRIVATE_URL_PREFIX", "")
  CALL fgl_setenv("FGL_PUBLIC_URL_PREFIX", "")
  RUN SFMT("fglrun runonserver %1", url) WITHOUT WAITING
END FUNCTION

FUNCTION connectToGDC(url STRING) --works only for the emulator
  --DISPLAY "runOnServer:", url
  --need to reset the env
  CALL fgl_setenv("FGLSERVER", _fglserver)
  CALL fgl_setenv("FGL_PRIVATE_DIR", "")
  CALL fgl_setenv("FGL_PUBLIC_DIR", "")
  CALL fgl_setenv("FGL_PUBLIC_IMAGEPATH", "")
  CALL fgl_setenv("FGL_PRIVATE_URL_PREFIX", "")
  CALL fgl_setenv("FGL_PUBLIC_URL_PREFIX", "")
  RUN SFMT("fglrun runongdc %1", url) WITHOUT WAITING
END FUNCTION

FUNCTION handleConnectionInt(c INT, key SelectionKey, chan SocketChannel)
  DEFINE dIn DataInputStream
  DEFINE line, procId STRING
  DEFINE bytearr ByteArray
  DEFINE jstring java.lang.String
  DEFINE closed BOOLEAN
  DEFINE httpKey SelectionKey
  DEFINE vmidx INT
  LET dIn = _s[c].dIn
  --DISPLAY "before: buf pos:",buf.position(),",caApacity:",buf.capacity(),",limit:",buf.limit()
  CALL key.interestOps(0)
  CALL key.cancel()
  CALL chan.configureBlocking(TRUE)
  WHILE TRUE
    IF _s[c].isHTTP AND _s[c].state == S_WAITCONTENT THEN
      CALL log(
          SFMT("S_WAITCONTENT of :%1, read:%2 bytes",
              _s[c].path, _s[c].contentLen))
      LET bytearr = ByteArray.create(_s[c].contentLen)
      CALL dIn.read(bytearr)
      LET jstring = java.lang.String.create(bytearr, StandardCharsets.UTF_8)
      LET _s[c].body = jstring
      {
      IF _s[c].body.getIndexOf("GET", 1) > 0
          OR _s[c].body.getIndexOf("POST", 1) > 0 THEN
        DISPLAY "wrong body:", _s[c].body
        MYASSERT(FALSE)
      END IF
      }
      LET _s[c].state = S_FINISH
      CALL httpHandler(c)
      EXIT WHILE
    END IF
    TRY
      IF _s[c].isVM THEN
        LET line = dIn.readLine() --read[]
      ELSE
        LET line = dIn.readLine()
      END IF
    CATCH
      CALL log(SFMT("readLine error:%1", err_get(status)))
      CALL chan.close()
      RETURN
    END TRY
    --DISPLAY "line:",limitPrintStr(line)
    IF line.getLength() == 0 THEN
      --DISPLAY "line '' isVM:", _s[c].isVM, ",isHTTP:", _s[c].isHTTP
      IF _s[c].isVM THEN
        CALL log(SFMT("VM finished:%1", printSel(c)))
        LET procId = _s[c].procId
        MYASSERT(_selDict.contains(procId))
        LET vmidx = _selDict[procId]
        LET httpKey = _s[vmidx].httpKey
        IF httpKey IS NOT NULL THEN
          CALL handleVM(vmidx, TRUE)
        END IF
        LET _s[c].state = S_FINISH
        EXIT WHILE
      ELSE
        IF NOT _s[c].isHTTP AND NOT _s[c].isVM THEN
          CALL log(
              SFMT("handleConnectionInt: ignore empty line for:%1",
                  printSel(c)))
          CALL closeSel(c)
          LET closed = TRUE
          EXIT WHILE
        END IF
        MYASSERT(_s[c].isHTTP AND _s[c].state == S_HEADERS)
        IF _s[c].contentLen > 0 THEN
          LET _s[c].state = S_WAITCONTENT
          EXIT WHILE
        ELSE
          --DISPLAY "Finish of :", _s[c].path
          LET _s[c].state = S_FINISH
          CALL httpHandler(c)
          EXIT WHILE
        END IF
      END IF
    END IF
    CASE
      WHEN NOT _s[c].isVM AND NOT _s[c].isHTTP
        CASE
          WHEN line.getIndexOf("meta ", 1) == 1
            CALL handleMetaSel(c, line)
            EXIT WHILE
          WHEN line.getIndexOf("GET ", 1) == 1
              OR line.getIndexOf("PUT ", 1) == 1
              OR line.getIndexOf("POST ", 1) == 1
              OR line.getIndexOf("HEAD ", 1) == 1
            CALL parseHttpLine(c, line)
            LET _s[c].isHTTP = TRUE
            LET _s[c].state = S_HEADERS
          OTHERWISE
            CALL myErr(SFMT("Unexpected connection handshake:%1", line))
        END CASE
      WHEN _s[c].isHTTP
        CASE _s[c].state
          WHEN S_HEADERS
            CALL parseHttpHeader(c, line)
        END CASE
      WHEN _s[c].isVM
        LET _s[c].VmCmd = line
        CALL handleVM(c, FALSE)
        EXIT WHILE
    END CASE
  END WHILE
  IF NOT closed THEN
    CALL checkReRegister(c)
  END IF
  CALL log(
      SFMT("handleConnection end of:%1%2",
          printSel(c), IIF(closed, " closed", "")))
END FUNCTION

FUNCTION closeSel(x INT)
  IF _s[x].dIn IS NOT NULL THEN
    CALL _s[x].dIn.close()
  END IF
  IF _s[x].dOut IS NOT NULL THEN
    CALL _s[x].dOut.close()
  END IF
  CALL _s[x].chan.close()
  LET _s[x].active = FALSE
END FUNCTION

FUNCTION checkReRegister(c INT)
  DEFINE newChan BOOLEAN
  DEFINE empty TSelectionRec
  IF (_s[c].state <> S_FINISH AND _s[c].state <> S_WAITFORVM)
      OR (newChan := (_keepalive AND _s[c].state == S_FINISH AND _s[c].isHTTP))
          == TRUE THEN
    IF newChan THEN
      --DISPLAY "re register id:", _s[c].id, ",available:", _s[c].dIn.available()
      LET empty.dIn = _s[c].dIn
      LET empty.dOut = _s[c].dOut
      LET empty.chan = _s[c].chan
      LET empty.id = _s[c].id
      LET _s[c].* = empty.*
      LET _s[c].active = TRUE
      LET _s[c].starttime = CURRENT
      LET _s[c].state = S_INIT
    END IF
    CALL reRegister(c)
  END IF
END FUNCTION

FUNCTION handleConnectionIntOld(key SelectionKey, chan SocketChannel)
  DEFINE bytesRead, pos, pos_l, bodySize, dataSize INT
  DEFINE buf java.nio.ByteBuffer
  DEFINE type TINYINT
  DEFINE neededPos INT
  DEFINE b TINYINT
  LET buf = CAST(key.attachment() AS ByteBuffer)

  TRY
    LET bytesRead = chan.read(buf);
    DISPLAY "bytesRead:", bytesRead
  CATCH
    CALL warning(SFMT("handleConnectionInt:caught error:%1", err_get(status)))
    LET bytesRead = -1
  END TRY
  --DISPLAY "handleConnectionInt bytesRead:", bytesRead," new pos:",buf.position()
  IF bytesRead == -1 THEN
    CALL key.cancel()
    CALL chan.close()
    RETURN
  END IF
  MYASSERT(bytesRead != 0)
  LET pos = buf.position()
  LET pos_l = pos - 1
  LET b = buf.get(pos_l) --check last char
  IF b <> 10 THEN --ORD("\n")
    DISPLAY "line not complete yet"
    RETURN
  END IF
  CALL buf.flip() --set pos to 0
  IF NOT _metaSeen THEN
    CALL handleMeta(key, buf, pos)
  ELSE
    IF pos < 9 THEN
      CALL buf.position(pos) --continue at pos
      CALL buf.limit(buf.capacity())
      --DISPLAY "currmsg not complete,pos:", pos
      RETURN
    END IF
    LET bodySize = ntohl(buf.getInt())
    LET dataSize = ntohl(buf.getInt()) --data Size
    IF (bodySize != dataSize) THEN
      DISPLAY "bodySize:", bodySize, ",dataSize:", dataSize
    END IF
    MYASSERT(bodySize == dataSize)
    LET type = buf.get()
    IF buf.capacity() == 9 THEN --provide the right buffer size
      CALL attachBodySizeBuf(key, bodySize, type)
      RETURN
    END IF
    LET neededPos = buf.position() + bodySize
    CASE
      WHEN pos < neededPos
        {
        DISPLAY "need more AUI data read for bodySize:",
            bodySize,
            ",type:",
            type
        DISPLAY "buf position:",
            buf.position(),
            ",pos:",
            pos,
            ", neededPos:",
            neededPos

        }
        CALL buf.position(pos)
        CALL buf.limit(buf.capacity())
      WHEN pos == neededPos
        LET _wait = FALSE
        CASE
          WHEN 1 == 1
            {CALL key.cancel()
            CALL chan.close()
            LET _vmChan = NULL
            LET _metaSeen = FALSE
            }
            CALL writeToLog("SUCCESS")
            IF _opt_autoclose THEN
              EXIT PROGRAM
            END IF
          OTHERWISE
            CALL myErr(SFMT("unhandled encaps type:%1", type))
        END CASE
        CALL attachEncapsBuf(key)
      OTHERWISE
        CALL myErr("unhandled read case")
    END CASE
  END IF
END FUNCTION

FUNCTION setWait()
  MYASSERT(_wait == FALSE)
  --DISPLAY ">>setWait"
  LET _wait = TRUE
END FUNCTION

FUNCTION FTName(name STRING) RETURNS STRING
  RETURN clientSideName(name, "FT") --all getfile/putfile lands in "FT"
END FUNCTION

FUNCTION cacheFileName(name STRING) RETURNS STRING
  RETURN clientSideName(
      name, "cacheFT") --all client side resources are in "cacheFT"
END FUNCTION

FUNCTION replace(src STRING, oldStr STRING, newString STRING)
  DEFINE b base.StringBuffer
  LET b = base.StringBuffer.create()
  CALL b.append(src)
  CALL b.replace(oldStr, newString, 0)
  RETURN b.toString()
END FUNCTION

FUNCTION clientSideName(name STRING, subDir STRING) RETURNS STRING
  DEFINE b base.StringBuffer
  LET b = base.StringBuffer.create()
  CALL b.append(name)
  IF NOT os.Path.exists(subDir) THEN
    MYASSERT(os.Path.mkdir(subDir) == 1)
  END IF
  --//first quote our replacement characters
  IF fgl_getenv("WINDIR") IS NOT NULL THEN
    CALL b.replace(",", ",,", 0)
  ELSE
    CALL b.replace("|", "||", 0)
  END IF
  CALL b.replace("_", "__", 0)
  --//make the file name a flat name
  IF fgl_getenv("WINDIR") IS NOT NULL THEN
    CALL b.replace("/", ",", 0)
    CALL b.replace("\\", ",", 0)
  ELSE
    CALL b.replace("/", "|", 0)
    CALL b.replace("\\", "|", 0)
  END IF
  CALL b.replace("..", "_", 0)
  CALL b.replace(" ", "_", 0)
  CALL b.replace(":", "_", 0)
  --CALL log(sfmt("clientSideName %1 returns %2",name,os.Path.join(subDir, b.toString())))
  RETURN os.Path.join(subDir, b.toString())
END FUNCTION

FUNCTION getURL(surl STRING) RETURNS URI
  DEFINE url URI
  LET url = URI.create(surl)
  RETURN url
END FUNCTION

FUNCTION getURLQueryDict(surl STRING) RETURNS(TStringDict, URI)
  DEFINE url URI
  DEFINE q, pstr, name, value STRING
  DEFINE idx INT
  DEFINE tok base.StringTokenizer
  DEFINE d TStringDict
  IF fgl_getenv("WINDIR") IS NOT NULL THEN
    LET surl = replace(surl, "\\", "/")
  END IF
  LET url = URI.create(surl)
  LET q = url.getQuery()
  LET tok = base.StringTokenizer.create(q, "&")
  WHILE tok.hasMoreTokens()
    LET pstr = tok.nextToken()
    IF (idx := pstr.getIndexOf("=", 1)) != 0 THEN
      LET name = pstr.subString(1, idx - 1)
      LET value = pstr.subString(idx + 1, pstr.getLength())
      LET d[name] = value
    END IF
  END WHILE
  --DISPLAY "getURLQueryDict:", util.JSON.stringify(d)
  RETURN d, url
END FUNCTION

FUNCTION createOutputStream(fn STRING) RETURNS FileChannel
  DEFINE f java.io.File
  DEFINE fc FileChannel
  LET f = File.create(fn)
  TRY
    LET fc = FileOutputStream.create(f, FALSE).getChannel()
    CALL log(
        SFMT("createOutputStream:did create file output stream for:%1", fn))
  CATCH
    CALL warning(SFMT("createOutputStream:%1", err_get(status)))
    RETURN NULL
  END TRY
  RETURN fc
END FUNCTION

FUNCTION createInputStream(fn STRING) RETURNS FileChannel
  DEFINE readC FileChannel
  TRY
    LET readC = FileInputStream.create(fn).getChannel()
    --DISPLAY "createInputStream: did create file input stream for:", fn
  CATCH
    CALL warning(SFMT("createInputStream:%1", err_get(status)))
  END TRY
  RETURN readC
END FUNCTION

FUNCTION hasPrefix(s STRING, prefix STRING)
  RETURN s.getIndexOf(prefix, 1) == 1
END FUNCTION

FUNCTION getLastModified(fn STRING)
  DEFINE m INT
  LET m = util.Datetime.toSecondsSinceEpoch(os.Path.mtime(fn))
  RETURN m
END FUNCTION

FUNCTION getPath(fn STRING) RETURNS java.nio.file.Path
  --here the Java bridge gets rather unhandy for ... functions
  TYPE JStrArray ARRAY[] OF java.lang.String
  DEFINE arr JStrArray
  DEFINE p java.nio.file.Path
  LET arr = JStrArray.create(0)
  LET p = Paths.get(fn, arr)
  RETURN p
END FUNCTION

FUNCTION setLastModified(fn STRING, t INT)
  DEFINE p Path
  DEFINE ld LocalDateTime
  DEFINE inst Instant
  DEFINE ft FileTime
  LET p = getPath(fn)
  --VAR m INT
  --LET m=t*1000
  --LET ft = FileTime.fromMillis(m) : doesn't work
  LET ld = LocalDateTime.ofEpochSecond(t, 0, ZoneOffset.UTC)
  LET inst = ld.toInstant(ZoneOffset.UTC)
  LET ft = FileTime.from(inst)
  CALL Files.setLastModifiedTime(p, ft)
END FUNCTION

FUNCTION lookupInCache(name STRING) RETURNS(BOOLEAN, INT, INT)
  DEFINE cachedFile STRING
  DEFINE s, t INT
  LET cachedFile = cacheFileName(name);
  IF NOT os.Path.exists(cachedFile) THEN
    --DISPLAY sfmt("did not find cachedFile:'%1' for name:'%2'",
    --     cachedFile,name)
    RETURN FALSE, 0, 0
  END IF
  LET s = os.Path.size(cachedFile)
  LET t = getLastModified(cachedFile)
  --DISPLAY "t:", t, ",os.Path.mtime:", os.Path.mtime(cachedFile)
  RETURN TRUE, s, t
END FUNCTION

FUNCTION writeChannel(chan SocketChannel, buf ByteBuffer)
  WHILE buf.hasRemaining() --need to loop because
    CALL chan.write(buf) --chan is non blocking
  END WHILE
END FUNCTION

FUNCTION getByte(x, pos) --pos may be 0..3
  DEFINE x, pos, b INTEGER
  LET b = util.Integer.shiftRight(x, 8 * pos)
  LET b = util.Integer.and(b, 255)
  RETURN b
END FUNCTION

FUNCTION htonl(value) RETURNS INT
  DEFINE value INT
  RETURN ByteBuffer.allocate(4)
      .putInt(value)
      .order(ByteOrder.nativeOrder()).getInt(0);
END FUNCTION

FUNCTION ntohl(value) RETURNS INT
  DEFINE value INT
  RETURN ByteBuffer.allocate(4)
      .putInt(value)
      .order(ByteOrder.BIG_ENDIAN)
      .getInt(0);
END FUNCTION

FUNCTION limitPrintStr(s STRING)
  DEFINE len INT
  LET len = s.getLength()
  IF len > 323 THEN
    RETURN s.subString(1, 160) || "..." || s.subString(len - 160, len)
  ELSE
    RETURN s
  END IF
END FUNCTION

FUNCTION alert(s STRING)
  DISPLAY "ALERT:", s
END FUNCTION

FUNCTION parseVersion(version STRING)
  DEFINE fversion, testversion FLOAT
  DEFINE pointpos, major, idx INTEGER
  LET pointpos = version.getIndexOf(".", 1)
  IF pointpos == 0 OR pointpos = 1 THEN
    --version string did not contain a '.' or no major number
    CALL myErr(SFMT("parseVersion: no valid version (wrong dot):%1", version))
  ELSE
    LET major = version.subString(1, pointpos - 1)
    IF major IS NULL
        OR major
            > 100 THEN --one needs to adjust the 100 hopefully only after 300 years
      CALL myErr(
          SFMT("parseVersion: no valid major number:'%1' in version:%2",
              version.subString(1, pointpos - 1), version))
    END IF
  END IF
  --go a long as possible thru the string after '.' and remember the last
  --valid conversion, so it doesn't matter if a '.' or something else is right hand side of major.minor
  LET idx = 1
  LET fversion = NULL
  WHILE (testversion := version.subString(1, pointpos + idx)) IS NOT NULL
      AND pointpos + idx <= version.getLength()
    LET fversion = testversion
    --DISPLAY "fversion:",fversion," out of:",version.subString(1,pointpos+idx)
    LET idx = idx + 1
  END WHILE
  IF fversion IS NULL OR fversion == 0.0 THEN --we had no valid conversion
    CALL myErr(SFMT("parseVersion: can't convert to float:%1", version))
  END IF
  RETURN fversion
END FUNCTION

FUNCTION EQ(s1 STRING, s2 STRING) RETURNS BOOLEAN
  RETURN s1.equals(s2)
END FUNCTION

FUNCTION EQI(s1 STRING, s2 STRING) RETURNS BOOLEAN
  DEFINE s1l, s2l STRING
  LET s1l = s1.toLowerCase()
  LET s2l = s2.toLowerCase()
  RETURN s1l.equals(s2l)
END FUNCTION

FUNCTION NEQ(s1 STRING, s2 STRING) RETURNS BOOLEAN
  RETURN NOT EQ(s1, s2)
END FUNCTION

FUNCTION hasAttr(n om.DomNode, attrName STRING)
  DEFINE cnt, i INT
  LET cnt = n.getAttributesCount()
  FOR i = 1 TO cnt
    IF n.getAttributeName(i) == attrName THEN
      RETURN TRUE
    END IF
  END FOR
  RETURN FALSE
END FUNCTION

FUNCTION quoteVMStr(s STRING)
  DEFINE sb base.StringBuffer
  DEFINE len, i INT
  DEFINE c STRING
  LET sb = base.StringBuffer.create()
  LET len = s.getLength()
  FOR i = 1 TO len
    LET c = s.getCharAt(i)
    CASE c
      WHEN '\\'
        CALL sb.append('\\\\')
      WHEN '\n'
        CALL sb.append('\\n')
      WHEN '"'
        CALL sb.append('\\"')
      WHEN '$'
        CALL sb.append('\\$')
      WHEN '{'
        CALL sb.append('\\{')
      WHEN '}'
        CALL sb.append('\\}')
      OTHERWISE
        CALL sb.append(c)
    END CASE
  END FOR
  RETURN sb.toString()
END FUNCTION

FUNCTION getMatcherForRegex(regex STRING, toExamine STRING) RETURNS Matcher
  DEFINE pat Pattern
  LET pat = Pattern.compile(regex)
  RETURN pat.matcher(toExamine)
END FUNCTION

FUNCTION parseInt(s STRING)
  DEFINE intVal INT
  LET intVal = s
  MYASSERT(intVal IS NOT NULL)
  RETURN intVal
END FUNCTION

FUNCTION writeToLog(s STRING)
  DEFINE diff INTERVAL MINUTE TO FRACTION(1)
  DEFINE chan base.Channel
  LET diff = CURRENT - _starttime
  IF _logChan IS NULL AND _opt_logfile IS NOT NULL THEN
    LET _logChan = base.Channel.create()
    CALL _logChan.openFile(_opt_logfile, "w")
  END IF
  IF _logChan IS NOT NULL THEN
    LET chan = _logChan
  ELSE
    CALL checkStderr()
    LET chan = _stderr
  END IF
  CALL chan.writeNoNL(diff)
  CALL chan.writeNoNL(" ")
  CALL chan.writeLine(s)
END FUNCTION

FUNCTION checkStderr()
  IF _stderr IS NULL THEN
    LET _stderr = base.Channel.create()
    CALL _stderr.openFile("<stderr>", "w")
  END IF
END FUNCTION

FUNCTION log(s STRING)
  IF NOT _verbose THEN
    RETURN
  END IF
  CALL writeToLog(s)
END FUNCTION

FUNCTION warning(s STRING)
  DISPLAY "!!!!!!!!WARNING:", s
END FUNCTION

PRIVATE FUNCTION _findGBCIn(dirname)
  DEFINE dirname STRING
  IF os.Path.exists(os.Path.join(dirname, "index.html"))
      AND os.Path.exists(os.Path.join(dirname, "index.html"))
      AND os.Path.exists(os.Path.join(dirname, "VERSION")) THEN
    LET _gbcdir = dirname
    RETURN TRUE
  END IF
  RETURN FALSE
END FUNCTION

FUNCTION checkGBCAvailable()
  IF NOT _findGBCIn(os.Path.join(os.Path.pwd(), "gbc")) THEN
    IF NOT _findGBCIn(fgl_getenv("FGLGBCDIR")) THEN
      IF NOT _findGBCIn(
          os.Path.join(fgl_getenv("FGLDIR"), "web_utilities/gbc/gbc")) THEN
        CALL myErr(
            "Can't find a GBC in <pwd>/gbc, fgl_getenv('FGLGBCDIR') or $FGLDIR/web_utilities/gbc/gbc")
      END IF
    END IF
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

FUNCTION checkGDC(url STRING)
  DEFINE gdc, cmd STRING
  LET gdc = getGDCPath()
  IF NOT os.Path.exists(gdc) THEN
    CALL myErr(SFMT("Can't find GDC executable at '%1'", gdc))
  END IF
  IF NOT os.Path.executable(gdc) THEN
    DISPLAY "Warning:os.Path not executable:", gdc
  END IF
  LET cmd = SFMT("%1 -u %2", quote(gdc), url)
  CALL log(SFMT("GDC cmd:%1", cmd))
  RUN cmd WITHOUT WAITING
END FUNCTION

FUNCTION getGDCPath()
  DEFINE cmd, fglserver, fglprofile, executable, native, dbg_unset, redir, orig
      STRING
  LET orig = fgl_getenv("FGLSERVER")
  LET fglserver = fgl_getenv("GDCFGLSERVER")
  CALL fgl_setenv("FGLSERVER", fglserver)
  LET fglprofile = fgl_getenv("FGLPROFILE")
  IF fglprofile IS NOT NULL THEN
    LET native = os.Path.join(_owndir, "fglprofile")
    CALL fgl_setenv("FGLPROFILE", native)
  END IF
  LET dbg_unset = IIF(isWin(), "set FGLGUIDEBUG=", "unset FGLGUIDEBUG")
  --LET redir = IIF(isWin(), "2>nul", "2>/dev/null")
  LET cmd =
      SFMT("%1&&fglrun %2 %3",
          dbg_unset, quote(os.Path.join(_owndir, "getgdcpath")), redir)
  LET executable = getProgramOutput(cmd)
  IF fglprofile IS NOT NULL THEN
    CALL fgl_setenv("FGLPROFILE", fglprofile)
  END IF
  DISPLAY "gdc path:", executable
  CALL fgl_setenv("FGLSERVER", orig)
  RETURN executable
END FUNCTION

FUNCTION openBrowser(url)
  DEFINE url, cmd, browser STRING
  --DISPLAY "start GWC-JS URL:", url
  IF fgl_getenv("SLAVE") IS NOT NULL THEN
    CALL log("gdcm SLAVE set,return")
    RETURN
  END IF
  LET browser = fgl_getenv("BROWSER")
  IF browser IS NOT NULL AND browser <> "default" AND browser <> "standard" THEN
    IF browser == "gdcm" THEN
      CASE
        WHEN isMac()
          LET browser = "./gdcm.app/Contents/MacOS/gdcm"
        WHEN isWin()
          LET browser = ".\\gdcm.exe"
        OTHERWISE
          LET browser = "./gdcm"
      END CASE
    END IF
    IF isMac() AND browser <> "./gdcm.app/Contents/MacOS/gdcm" THEN
      LET cmd = SFMT("open -a %1 %2", quote(browser), url)
    ELSE
      LET cmd = SFMT("%1 %2", quote(browser), url)
    END IF
  ELSE
    CASE
      WHEN isWin()
        LET cmd = SFMT("start %1", url)
      WHEN isMac()
        LET cmd = SFMT("open %1", url)
      OTHERWISE --assume kinda linux
        LET cmd = SFMT("xdg-open %1", url)
    END CASE
  END IF
  CALL log(SFMT("openBrowser:%1", cmd))
  RUN cmd WITHOUT WAITING
END FUNCTION

FUNCTION isWin()
  RETURN fgl_getenv("WINDIR") IS NOT NULL
END FUNCTION

FUNCTION isMac()
  IF NOT _askedOnMac THEN
    LET _askedOnMac = TRUE
    LET _isMac = isMacInt()
  END IF
  RETURN _isMac
END FUNCTION

FUNCTION isMacInt()
  IF NOT isWin() THEN
    RETURN getProgramOutput("uname") == "Darwin"
  END IF
  RETURN FALSE
END FUNCTION

FUNCTION getProgramOutput(cmd) RETURNS STRING
  DEFINE cmd, cmdOrig, tmpName, errStr STRING
  DEFINE txt TEXT
  DEFINE ret STRING
  DEFINE code INT
  --DISPLAY "RUN cmd:", cmd
  LET cmdOrig = cmd
  LET tmpName = makeTempName()
  LET cmd = cmd, ">", tmpName, " 2>&1"
  --DISPLAY "run:", cmd
  RUN cmd RETURNING code
  --DISPLAY "code:", code
  LOCATE txt IN FILE tmpName
  LET ret = txt
  CALL os.Path.delete(tmpName) RETURNING status
  IF code THEN
    LET errStr = ",\n  output:", ret
    CALL os.Path.delete(tmpName) RETURNING code
    CALL myErr(SFMT("failed to RUN:%1%2", cmdOrig, errStr))
  ELSE
    --remove \r\n
    IF ret.getCharAt(ret.getLength()) == "\n" THEN
      LET ret = ret.subString(1, ret.getLength() - 1)
    END IF
    IF ret.getCharAt(ret.getLength()) == "\r" THEN
      LET ret = ret.subString(1, ret.getLength() - 1)
    END IF
  END IF
  RETURN ret
END FUNCTION

#+computes a temporary file name
FUNCTION makeTempName()
  DEFINE tmpDir, tmpName, curr STRING
  DEFINE sb base.StringBuffer
  IF isWin() THEN
    LET tmpDir = fgl_getenv("TEMP")
  ELSE
    LET tmpDir = "/tmp"
  END IF
  LET curr = CURRENT
  LET sb = base.StringBuffer.create()
  CALL sb.append(curr)
  CALL sb.replace(" ", "_", 0)
  CALL sb.replace(":", "_", 0)
  CALL sb.replace(".", "_", 0)
  CALL sb.replace("-", "_", 0)
  CALL sb.append(".tmp")
  LET curr = sb.toString()
  LET tmpName = os.Path.join(tmpDir, SFMT("fgl_%1_%2", fgl_getpid(), curr))
  RETURN tmpName
END FUNCTION
