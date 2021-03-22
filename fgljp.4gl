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
IMPORT JAVA java.io.ByteArrayOutputStream
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
IMPORT JAVA java.net.InetAddress
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

TYPE MyByteArray ARRAY[] OF TINYINT
TYPE TStringDict DICTIONARY OF STRING
TYPE TStringArr DYNAMIC ARRAY OF STRING
TYPE ByteArray ARRAY[] OF TINYINT

CONSTANT S_INIT = "Init"
CONSTANT S_HEADERS = "Headers"
CONSTANT S_WAITCONTENT = "WaitContent"
CONSTANT S_WAITFORFT = "WaitForFT"
CONSTANT S_ACTIVE = "Active"
CONSTANT S_WAITFORVM = "WaitForVM"
CONSTANT S_FINISH = "Finish"

CONSTANT APP_COOKIE = "XFJsApp"

CONSTANT GO_OUT = TRUE
CONSTANT CLOSED = TRUE

TYPE FTGetImage RECORD
  name STRING,
  num INT,
  cache BOOLEAN,
  node om.DomNode,
  fileSize INT,
  mtime INT,
  ft2 BOOLEAN,
  httpIdx INT
END RECORD

TYPE FTList DYNAMIC ARRAY OF FTGetImage

--record holding the state of the connection
--a connection is either a VM connection or
--a http connection
TYPE TConnectionRec RECORD
  active BOOLEAN,
  chan SocketChannel,
  dIn DataInputStream,
  dOut DataOutputStream,
  key SelectionKey,
  id INT,
  state STRING,
  starttime DATETIME HOUR TO FRACTION(1),
  isVM BOOLEAN, --VM related members
  vmVersion FLOAT, --vm reported version
  RUNchildren TStringArr, --program RUN children procId's
  httpIdx INT, --http connection waiting
  VmCmd STRING, --last VM cmd
  wait BOOLEAN, --token for socket communication
  FTV2 BOOLEAN, --VM has filetransfer V2
  ftNum INT, --current FT num
  writeNum INT, --FT id1
  writeNum2 INT, --FT id2
  writeCPut FileOutputStream,
  writeC FileOutputStream,
  procId STRING, --VM procId
  procIdParent STRING, --VM procIdParent
  procIdWaiting STRING, --VM procIdWaiting
  sessId STRING, --session Id
  didSendVMClose BOOLEAN,
  startPath STRING, --the starting GBC path
  FTs FTList, --list of running file transfers
  --meta STRING,
  clientMetaSent BOOLEAN,
  putfile STRING,
  isHTTP BOOLEAN, --HTTP related members
  path STRING,
  method STRING,
  body STRING,
  appCookie STRING,
  cdattachment BOOLEAN,
  headers TStringDict,
  contentLen INT,
  contentType STRING,
  clitag STRING,
  newtask BOOLEAN
END RECORD

--Parser token types
{
CONSTANT TOK_None = 0
CONSTANT TOK_Number = 1
CONSTANT TOK_Value = 2
CONSTANT TOK_Ident = 3
}

--encapsulation command types
CONSTANT TAuiData = 1
--CONSTANT TPing=2
--CONSTANT TInterrupt=3
--CONSTANT TCloseApp=4
CONSTANT TFileTransfer = 5

--FT command sub numbers
CONSTANT FTPutFile = 1
CONSTANT FTGetFile = 2
CONSTANT FTBody = 3
CONSTANT FTEof = 4
CONSTANT FTStatus = 5
CONSTANT FTAck = 6
CONSTANT FTOk = 0 --// Success
DEFINE FT2Str DYNAMIC ARRAY OF STRING

--FT Status codes
CONSTANT FStErrSource = 4 --, // Error with source file (read)
CONSTANT FStErrDestination = 5 --, // Error with destination file (write)
--               FStErrInterrupt = 1, // Interrupted (DVM)
--               FStErrSock =2, // Socket Error (Can't happen...)
--               FStErrAborted = 3, // Aborted
--               FStErrInvState= 6, // Invalide State (DVM)
--               FStErrNotAvail= 7

DEFINE _s DYNAMIC ARRAY OF TConnectionRec
-- keep track of RUN WITHOUT WAITING children
DEFINE _RWWchildren DICTIONARY OF TStringArr

DEFINE _utf8 Charset
DEFINE _encoder CharsetEncoder
DEFINE _decoder CharsetDecoder
DEFINE _metaSeen BOOLEAN
DEFINE _opt_port STRING
DEFINE _opt_startfile STRING
DEFINE _opt_logfile STRING
DEFINE _opt_autoclose BOOLEAN
DEFINE _opt_any BOOLEAN
DEFINE _opt_gdc BOOLEAN
DEFINE _opt_runonserver BOOLEAN
DEFINE _opt_nostart BOOLEAN
DEFINE _opt_clearcache BOOLEAN
DEFINE _logChan base.Channel
DEFINE _opt_program, _opt_program1 STRING
DEFINE _verbose BOOLEAN
DEFINE _selDict DICTIONARY OF INTEGER
DEFINE _checkGoOut BOOLEAN
DEFINE _starttime DATETIME HOUR TO FRACTION(1)
DEFINE _stderr base.Channel
DEFINE _newtasks INT

CONSTANT size_i = 4 --sizeof(int)

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
  DEFINE addr InetAddress
  DEFINE saddr InetSocketAddress
  --DEFINE pending HashSet
  --DEFINE clientkey SelectionKey
  LET _starttime = CURRENT
  CALL parseArgs()
  IF _opt_clearcache THEN
    CALL clearCache()
  END IF
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
    IF _opt_any THEN --we are reachable from outside and get firewall warnings
      LET saddr = InetSocketAddress.create(port)
    ELSE
      LET addr = InetAddress.getLoopbackAddress()
      LET saddr = InetSocketAddress.create(addr, port)
    END IF
    CALL socket.bind(saddr)
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
      RETURN SFMT("{VM id:%1 s:%2 procId:%3 t:%4 pp:%5 pw:%6}",
          x,
          _s[x].state,
          _s[x].procId,
          diff,
          _s[x].procIdParent,
          _s[x].procIdWaiting)
    WHEN _s[x].isHTTP
      RETURN SFMT("{HTTP id:%1 s:%2 p:%3 t:%4 n:%5 pid:%6}",
          x, _s[x].state, _s[x].path, diff, _s[x].newtask, _s[x].procId)
    OTHERWISE
      RETURN SFMT("{_ id:%1 s:%2 t:%3}", x, _s[x].state, diff)
  END CASE
END FUNCTION

FUNCTION canGoOut()
  LET _checkGoOut = FALSE
  --DISPLAY "_selDict.getLength:",_selDict.getLength(),",keys:",util.JSON.stringify(_selDict.getKeys())
  IF _selDict.getLength() == 0 THEN
    DISPLAY "no VM channels anymore"
    IF _opt_program IS NOT NULL OR _opt_autoclose THEN
      RETURN TRUE
    END IF
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
  LET _progdir = os.Path.fullPath(os.Path.dirName(_opt_program1))
  LET _pubdir = _progdir
  LET _privdir = os.Path.join(_progdir, "priv")
  CALL os.Path.mkdir(_privdir) RETURNING status
  CALL fgl_setenv("FGLSERVER", SFMT("localhost:%1", port - 6400))
  CALL fgl_setenv("FGL_PRIVATE_DIR", _privdir)
  CALL fgl_setenv("FGL_PUBLIC_DIR", _pubdir)
  CALL fgl_setenv("FGL_PUBLIC_IMAGEPATH", ".")
  CALL fgl_setenv("FGL_PRIVATE_URL_PREFIX", priv)
  CALL fgl_setenv("FGL_PUBLIC_URL_PREFIX", pub)
  --CALL fgl_setenv("FGLGUIDEBUG", "1")
  --should work on both Win and Unix
  --LET s= "cd ",_progdir,"&&fglrun ",os.Path.baseName(prog)
  LET s = SFMT("fglrun %1", _opt_program)
  CALL log(SFMT("RUN:%1 WITHOUT WAITING", s))
  RUN s WITHOUT WAITING
END FUNCTION

FUNCTION initFT2Str()
  LET FT2Str[FTOk + 1] = "FTOk"
  LET FT2Str[FTPutFile + 1] = "FTPutFile"
  LET FT2Str[FTGetFile + 1] = "FTGetFile"
  LET FT2Str[FTBody + 1] = "FTBody"
  LET FT2Str[FTEof + 1] = "FTEof"
  LET FT2Str[FTStatus + 1] = "FTStatus"
  LET FT2Str[FTAck + 1] = "FTAck"
END FUNCTION

FUNCTION getFT2Str(ftconst INT)
  IF FT2Str.getLength() == 0 THEN
    CALL initFT2Str()
  END IF
  RETURN FT2Str[ftconst + 1]
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
      "JSON file with start info (port,pid,FGLSERVER) if no program is directly started"
  LET o[i].opt_char = "o"
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

  LET i = o.getLength() + 1
  LET o[i].name = "clear-cache"
  LET o[i].description = "Clears the file transfer cache"
  LET o[i].opt_char = "x"
  LET o[i].arg_type = mygetopt.NONE

  LET i = o.getLength() + 1
  LET o[i].name = "listen-any"
  LET o[i].description = "fgljp is reachable from outside"
  LET o[i].opt_char = "a"
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
      WHEN 'o'
        LET _opt_startfile = opt_arg
      WHEN 'n'
        LET _opt_nostart = TRUE
      WHEN 'l'
        LET _opt_logfile = opt_arg
      WHEN 'g'
        LET _opt_gdc = TRUE
      WHEN 'r'
        LET _opt_runonserver = TRUE
      WHEN 'x'
        LET _opt_clearcache = TRUE
      WHEN 'X'
        LET _opt_autoclose = TRUE
      WHEN 'a'
        LET _opt_any = TRUE
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
  DEFINE empty TConnectionRec
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
  LET _s[c].key = clientkey
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
  DEFINE path STRING
  LET s = removeCR(s)
  LET a = splitHTTPLine(s)
  LET _s[x].method = a[1]
  LET path = a[2]
  IF path.getIndexOf("Disposition=attachment", 1) > 0 THEN
    LET _s[x].cdattachment = TRUE
  END IF
  LET _s[x].path = path
  CALL log(SFMT("parseHttpLine:%1 %2", s, printSel(x)))
  IF a[3] <> "HTTP/1.1" THEN
    CALL myErr(SFMT("'%1' must be HTTP/1.1", a[3]))
  END IF
END FUNCTION

FUNCTION setAppCookie(x INT, path STRING)
  DEFINE dict TStringDict
  DEFINE url URI
  DEFINE surl STRING
  LET surl = "http://localhost", path
  CALL getURLQueryDict(surl) RETURNING dict, url
  MYASSERT(dict.contains("app"))
  LET _s[x].appCookie = dict["app"]
  --DISPLAY ">>>>set app cookie:", dict["app"]
END FUNCTION

FUNCTION parseCookies(x INT, cookies STRING)
  DEFINE tok base.StringTokenizer
  DEFINE c, name, value STRING
  DEFINE idx INT
  LET tok = base.StringTokenizer.create(cookies, ";")
  WHILE tok.hasMoreTokens()
    LET c = tok.nextToken()
    LET c = c.trim()
    IF (idx := c.getIndexOf("=", 1)) != 0 THEN
      LET name = c.subString(1, idx - 1)
      LET value = c.subString(idx + 1, c.getLength())
      IF name.equals(APP_COOKIE) THEN
        LET _s[x].appCookie = value
        CALL log(SFMT("parseCookies: set %1=%2", APP_COOKIE, value))
        EXIT WHILE
      END IF
    END IF
  END WHILE
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
    WHEN "cookie"
      --DISPLAY "cookie:'", val, "'"
      CALL parseCookies(x, val)
    WHEN "content-length"
      LET _s[x].contentLen = val
      --DISPLAY "Content-Length:",_s[x].contentLen
    WHEN "content-type"
      LET _s[x].contentType = val
      --DISPLAY "Content-Type:", _s[x].contentType
    WHEN "if-none-match"
      LET _s[x].clitag = val
      --DISPLAY "If-None-Match", _sel.clitag
    WHEN "x-fourjs-lockfile"
      --DISPLAY ">>>>>>>>>>>>>>x-fourjs-lockfile"
  END CASE
  LET _s[x].headers[key] = val
END FUNCTION

FUNCTION finishHttp(x INT)
  LET _s[x].state = S_FINISH
  CALL checkReRegister(x)
END FUNCTION

FUNCTION checkHTTPForSend(x INT, procId STRING, vmclose BOOLEAN, line STRING)
  DEFINE key SelectionKey
  LET key = _s[x].key
  MYASSERT(_s[x].state == S_WAITFORVM)
  CALL log(
      SFMT("checkHTTPForSend procId:%1, vmclose:%2,%3",
          procId, vmclose, printSel(x)))
  IF NOT _s[x].chan.isBlocking() THEN
    CALL log(SFMT("  !blocking:%1", printSel(x)))
    CALL configureBlocking(key, _s[x].chan)
  ELSE
    CALL log(SFMT("  isBlocking:%1", printSel(x)))
  END IF
  CALL sendToClient(x, line, procId, vmclose)
  CALL finishHttp(x)
END FUNCTION

FUNCTION checkNewTasks(vmidx INT)
  DEFINE sessId STRING
  DEFINE i, len INT
  IF _newtasks <= 0
      OR (sessId := _s[vmidx].sessId) IS NULL
      OR NOT _RWWchildren.contains(sessId)
      OR _RWWchildren[sessId].getLength() == 0 THEN
    RETURN
  END IF
  --DISPLAY "checkNewTasks:", printSel(vmidx), ",_newtasks:", _newtasks, ",sess:", util.JSON.stringify(_RWWchildren), ",sessId:",_s[vmidx].sessId
  --FOR i = 1 TO _s.getLength()
  --  IF _s[i].newtask THEN
  --    DISPLAY "  newtask http:", printSel(i)
  --  END IF
  --END FOR
  LET len = _s.getLength()
  CALL log(
      SFMT("checkNewTasksk sessId:%1, children:%2",
          sessId, util.JSON.stringify(_RWWchildren[sessId])))
  FOR i = 1 TO len
    IF _s[i].newtask AND _s[i].procId == sessId THEN
      CALL checkHTTPForSend(i, sessId, FALSE, "")
    END IF
  END FOR
END FUNCTION

FUNCTION handleVM(vmidx INT, vmclose BOOLEAN)
  DEFINE procId STRING
  DEFINE line STRING
  DEFINE httpIdx INT
  IF NOT vmclose THEN
    CALL checkNewTasks(vmidx)
  END IF
  LET procId = _s[vmidx].procId
  LET line = _s[vmidx].VmCmd
  LET httpIdx = _s[vmidx].httpIdx
  IF httpIdx == 0 THEN
    CALL log(SFMT("handleVM line:'%1' but no httpIdx", limitPrintStr(line)))
    RETURN
  END IF
  CALL checkHTTPForSend(httpIdx, procId, vmclose, line)
  MYASSERT(httpIdx != 0)
  LET _s[vmidx].httpIdx = 0
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
  CALL checkNewTasks(vmidx)
  IF _s[pidx].httpIdx == 0 THEN
    CALL log("checkNewTask(): parent httpIdx is NULL")
    RETURN
  END IF
  CALL handleVM(pidx, FALSE)
END FUNCTION

FUNCTION handleUAProto(x INT, path STRING)
  DEFINE body, procId, vmCmd, surl, appId, sessId STRING
  DEFINE qidx, vmidx INT
  DEFINE vmclose, newtask BOOLEAN
  DEFINE hdrs TStringArr
  --DEFINE key SelectionKey
  DEFINE dict TStringDict
  DEFINE url URI
  LET qidx = path.getIndexOf("?", 1)
  LET qidx = IIF(qidx > 0, qidx, path.getLength() + 1)
  CASE
    WHEN path.getIndexOf("/ua/r/", 1) == 1
      LET procId = path.subString(7, qidx - 1)
      LET sessId = procId
      CALL log(SFMT("handleUAProto procId:%1", procId))
    WHEN path.getIndexOf("/ua/sua/", 1) == 1
      LET surl = "http://localhost", path
      CALL getURLQueryDict(surl) RETURNING dict, url
      LET appId = dict["appId"]
      LET procId = path.subString(9, qidx - 1)
      IF appId <> "0" THEN
        --LET procId = _selDict[procId].t[appId]
        LET procId = appId
        MYASSERT(procId IS NOT NULL)
      END IF
    WHEN path.getIndexOf("/ua/newtask/", 1) == 1
      LET procId = path.subString(13, qidx - 1)
      LET sessId = procId
      LET _s[x].sessId = procId
      LET newtask = TRUE
    WHEN (path.getIndexOf("/ua/ping/", 1)) == 1
      CALL log("handleUAProto ping")
      LET hdrs = getCacheHeaders(FALSE, "")
      CALL writeResponseCtHdrs(x, "", "text/plain; charset=UTF-8", hdrs)
      RETURN
  END CASE
  MYASSERT(procId IS NOT NULL)
  IF NOT newtask THEN
    IF _s[x].method == "POST" THEN
      LET body = _s[x].body
      --DISPLAY "POST body:'", body, "'"
      IF body.getLength() > 0 THEN
        IF NOT writeToVMWithProcId(x, body, procId) THEN
          IF NOT _s[x].state.equals(S_WAITFORVM) THEN
            CALL http404(x, path)
          END IF
          RETURN
        END IF
      END IF
    END IF
    IF NOT _selDict.contains(procId) THEN
      DISPLAY "procId:",
          procId,
          " not in _selDict:",
          util.JSON.stringify(_selDict.getKeys())
    END IF
    MYASSERT(_selDict.contains(procId))
    LET vmidx = _selDict[procId]
    LET vmCmd = _s[vmidx].VmCmd
    IF sessId IS NOT NULL THEN
      LET _s[vmidx].sessId = sessId
      CALL _RWWchildren[sessId].clear()
    ELSE
      LET sessId = _s[vmidx].sessId
    END IF
  END IF
  CASE
    WHEN (vmCmd IS NOT NULL)
        OR (newtask AND hasChildrenForVMIdx(vmidx, sessId))
        OR (vmidx > 0 AND (vmclose := (_s[vmidx].state == S_FINISH)) == TRUE)
      CALL sendToClient(x, IIF(newtask, "", vmCmd), procId, vmclose)
    WHEN vmCmd IS NULL
      --DISPLAY "  !!!!vmCmd IS NULL, switch to wait state"
      LET _s[x].state = S_WAITFORVM
      IF newtask THEN
        LET _newtasks = _newtasks + 1
        LET _s[x].newtask = newtask
        LET _s[x].procId = procId
      ELSE
        LET _s[vmidx].httpIdx = x
      END IF
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

FUNCTION hasChildrenForVMIdx(vmidx INT, sessId STRING)
  DEFINE children TStringArr
  LET children = getChildrenForVMIdx(vmidx, sessId)
  RETURN children.getLength() > 0
END FUNCTION

--we lookup the RUN children first,
--then the RUN WITHOUT WAITING children
FUNCTION getChildrenForVMIdx(vmidx INT, sessId STRING)
  DEFINE empty TStringArr
  IF vmidx > 0 AND _s[vmidx].RUNchildren.getLength() > 0 THEN
    RETURN _s[vmidx].RUNchildren
  END IF
  IF sessId IS NOT NULL AND _RWWchildren.contains(sessId) THEN
    IF _RWWchildren[sessId].getLength() > 0 THEN
      RETURN _RWWchildren[sessId]
    END IF
  END IF
  RETURN empty
END FUNCTION

--sets all headers sent to the HTTP side
--and the VM command, close or new task
FUNCTION sendToClient(x INT, vmCmd STRING, procId STRING, vmclose BOOLEAN)
  DEFINE hdrs DYNAMIC ARRAY OF STRING
  DEFINE newProcId STRING
  DEFINE vmidx INT
  DEFINE children TStringArr
  --DEFINE pp STRING
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
  LET hdrs[hdrs.getLength() + 1] = "X-FourJs-Server-Features: ft-lock-file"
  --LET pp=_selDict[procId].procIdParent
  --IF pp IS NULL OR  NOT _selDict.contains(pp) THEN
  LET hdrs[hdrs.getLength() + 1] = SFMT("X-FourJs-Id: %1", procId)
  --END IF
  --LET hdrs[hdrs.getLength() + 1] = "X-FourJs-PageId: 1"
  --DISPLAY "sendToClient procId:", procId, ", ", printSel(x)
  IF _s[x].sessId IS NULL THEN --sessId is set in the newtask case
    MYASSERT(_selDict.contains(procId))
    LET vmidx = _selDict[procId]
    IF vmCmd.getLength() > 0 THEN
      LET _s[vmidx].VmCmd = NULL
    END IF
  END IF
  LET children = getChildrenForVMIdx(vmidx, _s[x].sessId)
  IF children.getLength() > 0 THEN
    LET newProcId = children[1]
    CALL children.deleteElement(1)
    LET hdrs[hdrs.getLength() + 1] = SFMT("X-FourJs-NewTask: %1", newProcId)
    IF _s[x].newtask THEN
      LET _newtasks = _newtasks - 1
      LET _s[x].newtask = FALSE
    END IF
    --DISPLAY "send X-FourJs-NewTask: ", newProcId
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

FUNCTION handleGBCPath(x INT, path STRING)
  DEFINE fname STRING
  DEFINE cut BOOLEAN
  DEFINE idx1, idx2, idx3 INT
  LET cut = TRUE
  IF path.getIndexOf("/gbc/index.html", 1) == 1 THEN
    CALL setAppCookie(x, path)
  END IF
  IF _opt_program IS NOT NULL THEN
    LET fname = path.subString(6, path.getLength())
    LET fname = cut_question(fname)
    LET fname = gbcResourceName(fname)
    --DISPLAY "fname:", fname
    CALL processFile(x, fname, TRUE)
  ELSE
    IF path.getIndexOf("/gbc/webcomponents/", 1) == 1 THEN
      LET fname = path.subString(20, path.getLength())
      LET idx1 = fname.getIndexOf("/", 20)
      IF idx1 > 0
          AND (idx2 := fname.getIndexOf("/", idx1)) > 0
          AND (idx3 := fname.getIndexOf("/__VM__/", idx1)) == idx2 THEN
        LET fname = fname.subString(idx3 + 1, fname.getLength())
        LET cut = FALSE --we pass the whole URL
      END IF
    ELSE
      IF path.getIndexOf("/gbc/__VM__/", 1) == 1 THEN
        LET fname = path.subString(6, path.getLength())
        LET cut = FALSE --we pass the whole URL
      ELSE
        LET fname = "gbc://", path.subString(6, path.getLength())
      END IF
    END IF
    LET fname = IIF(cut, cut_question(fname), fname)
    CALL processRemoteFile(x, fname)
  END IF
END FUNCTION

FUNCTION httpHandler(x INT)
  DEFINE text, path STRING
  LET path = _s[x].path
  CALL log(SFMT("httpHandler '%1' for:%2", path, printSel(x)))
  CASE
    WHEN path == "/"
      LET text = "<!DOCTYPE html><html><body>This is fgljp</body></html>"
      CALL writeResponse(x, text)
    WHEN path.getIndexOf("/ua/", 1) == 1 --ua proto
      CALL handleUAProto(x, path)
    WHEN path.getIndexOf("/gbc/", 1) == 1 --gbc asset
      CALL handleGBCPath(x, path)
      RETURN
    WHEN _s[x].cdattachment
      CALL handleCDAttachment(x)
    OTHERWISE
      IF NOT findFile(x, path) THEN
        CALL http404(x, path)
      END IF
  END CASE
END FUNCTION

FUNCTION findFile(x INT, path STRING)
  DEFINE qidx INT
  DEFINE relpath STRING
  LET qidx = path.getIndexOf("?", 1)
  IF qidx > 0 THEN
    LET path = path.subString(1, qidx - 1)
  END IF
  LET path = util.Strings.urlDecode(path)
  LET relpath = ".", path
  IF NOT os.Path.exists(relpath) THEN
    CALL log(
        SFMT("findFile:relpath '%1' doesn't exist, pwd:%2",
            relpath, os.Path.pwd()))
    IF _opt_program IS NULL THEN --ask VM
      CALL processRemoteFile(x, path)
      RETURN TRUE
    END IF
    RETURN FALSE
  END IF
  CALL processFile(x, relpath, TRUE)
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

FUNCTION vmidxFromAppCookie(x INT, fname STRING)
  DEFINE procId STRING
  DEFINE vmidx INT
  LET procId = _s[x].appCookie
  IF procId IS NULL THEN
    CALL log(
        SFMT("vmidxFromAppCookie:no App Cookie set for:%1,%2",
            fname, printSel(x)))
    RETURN 0
  END IF
  IF NOT _selDict.contains(procId) THEN
    CALL log(
        SFMT("vmidxFromAppCookie:no app anymore for:%1,procId:%2,%3",
            fname, procId, printSel(x)))
    RETURN 0
  END IF
  LET vmidx = _selDict[procId]
  CALL log(
      SFMT("vmidxFromAppCookie %1,procId:%2,vmidx:%3",
          printSel(x), procId, vmidx))
  RETURN vmidx
END FUNCTION

FUNCTION processRemoteFile(x INT, fname STRING)
  DEFINE vmidx INT
  LET vmidx = vmidxFromAppCookie(x, fname)
  IF vmidx < 1 THEN
    CALL http404(x, fname)
    RETURN
  END IF
  LET _s[x].state = S_WAITFORVM
  CALL checkRequestFT(x, vmidx, fname)
END FUNCTION

FUNCTION processFile(x INT, fname STRING, cache BOOLEAN)
  DEFINE ext, ct, txt STRING
  DEFINE etag STRING
  DEFINE hdrs TStringArr
  --DISPLAY "processFile:", x, " ", fname
  IF NOT os.Path.exists(fname) THEN
    CALL http404(x, fname)
    RETURN
  END IF
  IF _s[x].method == "POST" THEN
    --DISPLAY "processFile:", fname, " return 200 OK"
    LET hdrs = getCacheHeaders(FALSE, "")
    CALL writeResponseInt2(x, "", "", hdrs, "200 OK")
    RETURN
  END IF
  --DISPLAY "!!!!!!processFile:", fname
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
    WHEN ext == "html" OR ext == "css" OR ext == "js" OR ext == "txt"
      CASE
        WHEN ext == "html"
          LET ct = "text/html"
        WHEN ext == "js"
          LET ct = "application/x-javascript"
        WHEN ext == "css"
          LET ct = "text/css"
        WHEN ext == "txt"
          LET ct = "text/plain"
      END CASE
      LET txt = readTextFile(fname)
      LET hdrs = getCacheHeaders(cache, etag)
      --DISPLAY "processTextFile:", fname, " ct:", ct
      CALL writeResponseCtHdrs(x, txt, ct, hdrs)
    OTHERWISE
      LET ct = "application/octet-stream"
      CASE
        WHEN ext == "gif"
          LET ct = "image/gif"
        WHEN ext == "woff"
          LET ct = "application/font-woff"
        WHEN ext == "ttf"
          LET ct = "application/octet-stream"
      END CASE
      LET hdrs = getCacheHeaders(cache, etag)
      --DISPLAY "processFile:", fname, " ct:", ct
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
  LET _s[x].cdattachment = FALSE
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

FUNCTION writeToVMWithProcId(x INT, s STRING, procId STRING)
  DEFINE vmidx INT
  IF NOT _selDict.contains(procId) THEN
    RETURN FALSE
  END IF
  LET vmidx = _selDict[procId]
  IF _s[vmidx].putfile IS NOT NULL THEN
    --DISPLAY ">>>>hold reply:'", s, "' because of putfile"
    LET _s[x].state = S_WAITFORVM
    LET _s[x].procId = procId
    RETURN FALSE
  END IF
  CALL writeToVM(vmidx, s)
  RETURN TRUE
END FUNCTION

--we need to correct encapsulation
FUNCTION handleClientMeta(vmidx INT, meta STRING)
  DEFINE ftreply STRING
  LET meta = replace(meta, '{encapsulation "0"}', '{encapsulation "1"}')
  LET ftreply = IIF(_s[vmidx].FTV2, "2", "1")
  LET meta =
      replace(meta, '{filetransfer "0"}', SFMT('{filetransfer "%1"}', ftreply))
  --DISPLAY "meta:", meta
  RETURN meta
END FUNCTION

FUNCTION writeToVM(vmidx INT, s STRING)
  CALL log(SFMT("writeToVM:%1", s))
  IF _opt_program IS NULL THEN
    IF NOT _s[vmidx].clientMetaSent THEN
      MYASSERT(s.getIndexOf("meta ", 1) == 1)
      LET _s[vmidx].clientMetaSent = TRUE
      LET s = handleClientMeta(vmidx, s)
    END IF
    CALL writeToVMEncaps(vmidx, s)
  ELSE
    CALL writeToVMNoEncaps(vmidx, s)
  END IF
END FUNCTION

FUNCTION writeToVMNoEncaps(vmidx INT, s STRING)
  DEFINE jstring java.lang.String
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

FUNCTION handleCDAttachment(x INT)
  DEFINE vmidx, i INT
  DEFINE path STRING
  DEFINE hdrs TStringArr
  LET path = _s[x].path
  LET vmidx = vmidxFromAppCookie(x, path)
  IF vmidx < 1 THEN
    CALL http404(x, path)
    RETURN
  END IF
  IF NOT _s[vmidx].putfile.equals(path) THEN
    LET _s[vmidx].putfile = path
    LET _s[x].cdattachment = FALSE
    LET hdrs = getCacheHeaders(FALSE, "")
    --DISPLAY ">>>>>send 204 No Content:", printSel(x)
    CALL writeResponseInt2(x, "", "", hdrs, "204 No Content")
  ELSE
    LET _s[vmidx].putfile = NULL
    --actually deliver the putfile
    IF NOT findFile(x, path) THEN
      CALL http404(x, path)
    END IF

    FOR i = 1 TO _s.getLength()
      IF _s[i].state == S_WAITFORVM
          AND (vmidx := vmidxFromAppCookie(x, path)) > 0 THEN
        DISPLAY SFMT("!!!!found x:%1 for vmidx:%2 body:%3 ",
            i, vmidx, _s[i].body, printSel(i))
        MYASSERT(_s[i].procId IS NOT NULL)
        MYASSERT(writeToVMWithProcId(x, _s[i].body, _s[i].procId) == TRUE)
        LET _s[vmidx].httpIdx = i --mark the connection for VM answer
        EXIT FOR
      END IF
    END FOR
  END IF
END FUNCTION

FUNCTION checkCDAttachment(x INT, hdrs TStringArr)
  DEFINE qidx INT
  DEFINE path, fname STRING
  IF NOT _s[x].cdattachment THEN
    RETURN
  END IF
  LET path = _s[x].path
  LET qidx = path.getIndexOf("?", 1)
  LET path = IIF(qidx > 0, path.subString(1, qidx - 1), path)
  LET path = util.Strings.urlDecode(path)
  LET fname = os.Path.baseName(path)
  --DISPLAY ">>>>>>>>>>>>send attach:", path, ",fname:", fname
  LET qidx = hdrs.getLength() + 1
  LET hdrs[qidx] = SFMT('Content-Disposition: attachment; filename="%1"', fname)
END FUNCTION

FUNCTION writeHTTPHeaders(x INT, headers TStringArr)
  DEFINE i, len INT
  CALL checkCDAttachment(x, headers)
  LET len = headers.getLength()
  FOR i = 1 TO len
    CALL writeHTTPLine(x, headers[i])
  END FOR
  IF _s[x].appCookie IS NOT NULL THEN
    --DISPLAY "!!!!!!!!!!!!!!!!!!write appCookie:", _s[x].appCookie
    CALL writeHTTPLine(
        x,
        SFMT("Set-Cookie: %1=; Path=/; Max-Age=-1; expires=Thu, 01 Jan 1970 00:00:00 GMT",
            APP_COOKIE))
    CALL writeHTTPLine(
        x,
        SFMT("Set-Cookie: %1=%2; Path=/; expires=Thu, 21 Oct 2121 07:28:00 GMT",
            APP_COOKIE, _s[x].appCookie))
  END IF
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
  IF ct IS NOT NULL THEN
    CALL writeHTTPLine(x, SFMT("Content-Type: %1", ct))
  END IF
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
  DEFINE valueIdx1, valueIdx2 INT
  DEFINE value STRING
  CALL extractMetaVarSub(
      line, varname, forceFind)
      RETURNING value, valueIdx1, valueIdx2
  RETURN value
END FUNCTION

FUNCTION extractMetaVarSub(
    line STRING, varname STRING, forceFind BOOLEAN)
    RETURNS(STRING, INT, INT)
  DEFINE idx1, idx2, len INT
  DEFINE key, value STRING
  LET key = SFMT('{%1 "', varname)
  LET len = key.getLength()
  LET idx1 = line.getIndexOf(key, 1)
  IF (forceFind == FALSE AND idx1 <= 0) THEN
    RETURN "", 0, 0
  END IF
  MYASSERT(idx1 > 0)
  LET idx2 = line.getIndexOf('"}', idx1 + len)
  IF (forceFind == FALSE AND idx2 < idx1 + len) THEN
    RETURN "", 0, 0
  END IF
  MYASSERT(idx2 > idx1 + len)
  LET value = line.subString(idx1 + len, idx2 - 1)
  CALL log(SFMT("extractMetaVar: '%1'='%2'", varname, value))
  RETURN value, idx1 + len, idx2 - 1
END FUNCTION

FUNCTION extractProcId(p STRING)
  DEFINE pidx1 INT
  LET pidx1 = p.getIndexOf(":", 1)
  MYASSERT(pidx1 > 0)
  RETURN p.subString(pidx1 + 1, p.getLength())
END FUNCTION

FUNCTION handleMetaSel(vmidx INT, line STRING)
  DEFINE pp, procIdWaiting, sessId, encaps, compression, rtver STRING
  DEFINE ftV STRING
  DEFINE ppidx INT
  DEFINE children TStringArr
  LET _s[vmidx].isVM = TRUE
  LET _s[vmidx].VmCmd = line
  LET _s[vmidx].state = IIF(_opt_program IS NOT NULL, S_ACTIVE, S_WAITFORFT)
  CALL log(SFMT("handleMetaSel:%1", line))
  LET encaps = extractMetaVar(line, "encapsulation", TRUE)
  LET compression = extractMetaVar(line, "compression", TRUE)
  --DISPLAY "encaps:", encaps, ",compression:", compression
  IF compression IS NOT NULL THEN
    MYASSERT(compression.equals("none")) --avoid that someone enables zlib
  END IF
  LET ftV = extractMetaVar(line, "filetransferVersion", FALSE)
  LET _s[vmidx].FTV2 = IIF(ftV == "2", TRUE, FALSE)
  LET rtver = extractMetaVar(line, "runtimeVersion", TRUE)
  LET _s[vmidx].vmVersion = parseVersion(rtver)
  LET _s[vmidx].procId = extractProcId(extractMetaVar(line, "procId", TRUE))
  --DISPLAY "procId:'", _s[vmidx].procId, "'"
  LET procIdWaiting = extractMetaVar(line, "procIdWaiting", FALSE)
  IF procIdWaiting IS NOT NULL THEN
    LET procIdWaiting = extractProcId(procIdWaiting)
    LET _s[vmidx].procIdWaiting = procIdWaiting
  END IF
  LET pp = extractMetaVar(line, "procIdParent", FALSE)
  IF pp IS NOT NULL THEN
    LET pp = extractProcId(pp)
    --DISPLAY "procIdParent of:", _s[vmidx].procId, " is:", pp
    IF _selDict.contains(pp) THEN
      LET ppidx = _selDict[pp]
      IF (sessId := _s[ppidx].sessId) IS NOT NULL THEN
        LET _s[vmidx].sessId = sessId
        IF _RWWchildren.contains(sessId) THEN
          LET children =
              _RWWchildren[sessId] --could be RUN WITHOUT WAITING child
        END IF
      END IF
      IF procIdWaiting == pp THEN
        LET children = _s[ppidx].RUNchildren --procIdWaiting forces a RUN child
      END IF
      LET children[children.getLength() + 1] = _s[vmidx].procId
      --DISPLAY "!!!!set children of:",
      --    printSel(ppidx),
      --    " to:",
      --    util.JSON.stringify(children)
      LET _s[vmidx].procIdParent = pp
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
  IF _opt_program IS NULL THEN
    CALL log("decideStartOrNewTask: send filetransfer")
    CALL writeToVMNoEncaps(vmidx, "filetransfer\n")
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
  DEFINE empty TConnectionRec
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
      {
      DISPLAY "did set _selDict:",
          _s[c].procId,
          " ",
          util.JSON.stringify(_selDict)
      }
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
  LET _s[c].key = newkey
  CALL newkey.attach(ji)
END FUNCTION

FUNCTION handleStart(vmidx INT)
  DEFINE url, procId, startPath STRING
  LET procId = _s[vmidx].procId
  LET startPath = SFMT("gbc/index.html?app=%1", procId)
  LET url = SFMT("%1%2", _htpre, startPath)
  LET _s[vmidx].startPath = url
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

FUNCTION configureBlocking(key SelectionKey, chan SocketChannel)
  CALL key.interestOps(0)
  CALL key.cancel()
  CALL chan.configureBlocking(TRUE)
END FUNCTION

FUNCTION handleConnectionInt(c INT, key SelectionKey, chan SocketChannel)
  DEFINE dIn DataInputStream
  DEFINE go_out, closed BOOLEAN
  DEFINE line STRING
  LET dIn = _s[c].dIn
  --DISPLAY "before: buf pos:",buf.position(),",caApacity:",buf.capacity(),",limit:",buf.limit()
  CALL configureBlocking(key, chan)
  WHILE NOT go_out
    IF _s[c].isHTTP AND _s[c].state == S_WAITCONTENT THEN
      CALL handleWaitContent(c, dIn)
      EXIT WHILE
    END IF
    CALL ReadLine(c, dIn) RETURNING line, go_out
    IF NOT go_out THEN
      IF line.getLength() == 0 THEN
        CALL handleEmptyLine(c) RETURNING go_out, closed
      ELSE
        CALL handleLine(c, line) RETURNING go_out
      END IF
    END IF
  END WHILE
  IF NOT closed THEN
    CALL checkReRegister(c)
  END IF
  CALL log(
      SFMT("handleConnection end of:%1%2",
          printSel(c), IIF(closed, " closed", "")))
END FUNCTION

--we need to read the encapsulated VM data and decice
--upon the type byte what is to do
FUNCTION readEncaps(vmidx INT, dIn DataInputStream)
  DEFINE s1, s2, bodySize, dataSize INT
  DEFINE type TINYINT
  DEFINE line, err STRING
  LET _s[vmidx].wait = FALSE
  TRY
    LET s1 = dIn.readInt()
  CATCH
    LET err = err_get(status)
    --DISPLAY "err:'",err,"'"
    IF err.equals("Java exception thrown: java.io.EOFException.\n")
        OR err.equals(
            "Java exception thrown: java.io.IOException: Connection reset by peer.\n") THEN
      --DISPLAY "!!!readEncaps EOF!!!"
      RETURN TAuiData, ""
    END IF
    CALL myErr(err)
  END TRY
  LET bodySize = ntohl(s1)
  LET s2 = dIn.readInt()
  LET dataSize = ntohl(s2)
  --DISPLAY SFMT("s1:%1,s2:%2,bodySize:%3,dataSize:%4",
  --    s1, s2, bodySize, dataSize)
  IF (bodySize <> dataSize) THEN
    DISPLAY "!!!!!!readEncaps bodySize:", bodySize, "<> dataSize:", dataSize
  END IF
  MYASSERT(bodySize == dataSize)
  LET type = dIn.readByte()
  CASE
    WHEN type = TAuiData
      LET line = dIn.readLine()
      CALL lookupNextImage(vmidx)
    WHEN type = TFileTransfer
      CALL handleFT(vmidx, dIn, dataSize)
    OTHERWISE
      CALL myErr(SFMT("unhandled encaps type:%1", type))
  END CASE
  RETURN type, line
END FUNCTION

FUNCTION didReadCompleteVMCmd(buf ByteBuffer)
  DEFINE b1, b2, b3 TINYINT
  DEFINE pos INT
  LET pos = buf.position()
  --DISPLAY sfmt("didReadCompleteVM pos:%1,limit:%2,capacity:%3",buf.position(),buf.limit(),buf.capacity())
  IF pos < 3 THEN
    RETURN FALSE
  END IF
  CALL buf.position(pos - 3)
  --check for '}}\n', read the last 3 bytes
  --its very unlikely that this is an end of another UTF-8 sequence
  IF (b1 := buf.get()) == 125
      AND (b2 := buf.get()) == 125
      AND (b3 := buf.get()) == 10 THEN
    RETURN TRUE
  END IF
  CALL buf.position(pos)
  --DISPLAY "b1:",ASCII(b1),",b2:",ASCII(b2),",b3:",ASCII(b3)
  RETURN FALSE
END FUNCTION

--unfortunately we can't use neither
--DataInputStream.readLine nor
--BufferedReader.readLine because both stop already at '\r'
--this forces us to read byte chunks until we discover '}}\n'
FUNCTION readLineFromVM(vmindex INT)
  DEFINE buf, newbuf ByteBuffer
  DEFINE chan SocketChannel
  DEFINE didRead, newsize, num, len INT
  DEFINE js java.lang.String
  DEFINE s STRING
  LET chan = _s[vmindex].chan
  LET buf = ByteBuffer.allocate(30000)
  LET didRead = chan.read(buf)
  IF didRead == -1 THEN
    RETURN ""
  END IF
  --DISPLAY sfmt("didRead:%1,num:%2,pos:%3,limit:%4",didRead,num,buf.position(),buf.limit())
  WHILE NOT didReadCompleteVMCmd(buf)
    IF buf.position() == buf.limit() THEN --need to realloc
      LET newsize = buf.capacity() * 2
      LET newbuf = ByteBuffer.allocate(newsize)
      CALL buf.flip()
      CALL newbuf.put(buf)
      MYASSERT(newbuf.position() == buf.capacity())
      LET buf = newbuf
    END IF
    MYASSERT(buf.position() < buf.limit())
    LET didRead = chan.read(buf)
    IF didRead == -1 THEN
      RETURN ""
    END IF
    LET num = num + 1
    --DISPLAY sfmt("didRead:%1,num:%2,pos:%3,limit:%4",didRead,num,buf.position(),buf.limit())
  END WHILE
  CALL buf.flip()
  LET js = _decoder.decode(buf).toString()
  LET len = js.length()
  MYASSERT(js.charAt(len - 1) == "\n") --my guess is Java string indexing is a picosecond faster than VM indexing
  LET s = js.substring(0, len - 1)
  RETURN s
END FUNCTION

FUNCTION ReadLine(c INT, dIn DataInputStream)
  DEFINE line STRING
  DEFINE type TINYINT
  IF _s[c].isVM THEN
    IF _opt_program IS NULL AND _s[c].state == S_ACTIVE THEN
      CALL readEncaps(c, dIn) RETURNING type, line
      IF type != TAuiData THEN
        --DISPLAY "-------go out with type:",type
        RETURN "", GO_OUT
      END IF
    ELSE
      LET line = readLineFromVM(c)
    END IF
  ELSE
    LET line = dIn.readLine()
  END IF
  RETURN line, FALSE
END FUNCTION

FUNCTION handleEmptyLine(c INT)
  --DISPLAY "line '' isVM:", _s[c].isVM, ",isHTTP:", _s[c].isHTTP
  IF _s[c].isVM THEN
    CALL handleVMFinish(c)
    RETURN GO_OUT, FALSE
  ELSE
    IF NOT _s[c].isHTTP AND NOT _s[c].isVM THEN
      CALL log(
          SFMT("handleConnectionInt: ignore empty line for:%1", printSel(c)))
      CALL closeSel(c)
      RETURN GO_OUT, CLOSED
    END IF
    MYASSERT(_s[c].isHTTP AND _s[c].state == S_HEADERS)
    IF _s[c].contentLen > 0 THEN
      LET _s[c].state = S_WAITCONTENT
      RETURN GO_OUT, FALSE
    ELSE
      --DISPLAY "Finish of :", _s[c].path
      LET _s[c].state = S_FINISH
      CALL httpHandler(c)
      RETURN GO_OUT, FALSE
    END IF
  END IF
END FUNCTION

--main HTPP/VM connection state machine
FUNCTION handleLine(c INT, line STRING)
  --DISPLAY SFMT("handleLine:%1,line:%2", c, limitPrintStr(line))
  CASE
    WHEN NOT _s[c].isVM AND NOT _s[c].isHTTP
      CASE
        WHEN line.getIndexOf("meta ", 1) == 1
          CALL handleMetaSel(c, line)
          RETURN GO_OUT
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
      MYASSERT(_s[c].state == S_HEADERS)
      CALL parseHttpHeader(c, line)
      --CASE _s[c].state
      --  WHEN S_HEADERS
      --    CALL parseHttpHeader(c, line)
      --END CASE
    WHEN _s[c].isVM
      IF _s[c].state == S_WAITFORFT THEN
        MYASSERT(line == "filetransfer")
        --DISPLAY "<<<<<filetransfer received"
        LET _s[c].state = S_ACTIVE
        CALL lookupNextImage(c)
        RETURN GO_OUT
      END IF
      LET _s[c].VmCmd = line
      CALL handleVM(c, FALSE)
      RETURN GO_OUT
    OTHERWISE
      CALL myErr("Unhandled case")
  END CASE
  RETURN FALSE
END FUNCTION

FUNCTION merge2BA(
    ba ByteArray, prev ByteArray, baRead INT, blen INT, MAXB INT)
    RETURNS(ByteArray, ByteArray, INT, INT)
  DEFINE bout ByteArrayOutputStream
  DEFINE nul ByteArray
  DEFINE startidx INT
  MYASSERT(prev IS NOT NULL)
  LET bout = ByteArrayOutputStream.create()
  CALL bout.write(prev)
  CALL bout.write(ba, 0, baRead)
  LET ba = bout.toByteArray()
  LET baRead = MAXB + baRead
  LET startidx = baRead - blen - 2
  --DISPLAY SFMT("merge2BA to baRead:%1,startidx:%2", baRead, startidx)
  RETURN ba, nul, baRead, startidx
END FUNCTION

FUNCTION handleMultiPartUpload(
    x INT, dIn DataInputStream, path STRING, ct STRING)
  DEFINE bidx, blen INT
  DEFINE boundary, line STRING
  DEFINE tok base.StringTokenizer
  DEFINE ctlen, state, didRead, startidx, baoff INT
  DEFINE baRead, toRead, numRead, maxToRead, jslen INT
  DEFINE merged, ba, prev ByteArray
  DEFINE fo FileOutputStream
  DEFINE jstring java.lang.String
  CONSTANT MAXB = 30000
  --DEFINE MAXB INT
  CONSTANT STARTBOUNDARY = 1
  CONSTANT STARTCONTENT = 2
  LET ctlen = _s[x].contentLen
  LET bidx = ct.getIndexOf("boundary=", 1)
  MYASSERT(bidx > 0)
  LET boundary = ct.subString(bidx + 9, ct.getLength())
  --strip off unwanted continuations
  LET tok = base.StringTokenizer.create(boundary, " \t;")
  IF tok.hasMoreTokens() THEN
    LET boundary = tok.nextToken()
  END IF
  --start value has 2 dashes more...
  LET boundary = "--", boundary
  LET fo = createFO(path)
  WHILE TRUE
    --read the headers until the empty line
    LET line = dIn.readLine()
    LET numRead = numRead + line.getLength() + 2
    --DISPLAY "handleMultiPartUpload line:'", line, "'"
    CASE
      WHEN line.getIndexOf(boundary, 1) == 1
        LET state = STARTBOUNDARY
      WHEN line.getLength() == 0
        CASE
          WHEN state == STARTBOUNDARY
            LET state = STARTCONTENT
            EXIT WHILE
          OTHERWISE
            CALL myErr("invalid state")
        END CASE
    END CASE
  END WHILE
  --set boundary to the end value
  LET boundary = "\r\n", boundary, "--"
  LET blen = boundary.getLength()
  --LET MAXB = blen + 2
  LET ba = ByteArray.create(MAXB)
  --warning: hairy code
  --we have 2 buffers, ba and prev, and need to delay the write to disk
  --until we are sure that the boundary isn't contained in the
  --written buffer
  WHILE TRUE
    LET maxToRead = ctlen - numRead
    LET toRead = MAXB - baRead
    --DISPLAY sfmt("before read ctlen:%1,maxToRead:%2,toRead:%3",ctlen,maxToRead,toRead)
    MYASSERT(maxToRead > 0)
    MYASSERT(toRead > 0)
    LET toRead = IIF(maxToRead < toRead, maxToRead, toRead)
    LET didRead = dIn.read(ba, baoff, toRead)
    LET numRead = numRead + didRead
    LET maxToRead = ctlen - numRead
    MYASSERT(maxToRead >= 0)
    IF didRead <= 0 THEN
      DISPLAY "handleMultiPartUpload read failed:didRead:", didRead
      RETURN
    END IF
    LET baRead = baoff + didRead
    LET startidx = baRead - blen - 2
    IF startidx < 0 THEN
      IF prev IS NOT NULL THEN
        --merge the previous array in to be able to
        --check for the boundary
        CALL merge2BA(
            ba, prev, baRead, blen, MAXB)
            RETURNING ba, prev, baRead, startidx
      ELSE
        MYASSERT(baRead < MAXB)
        LET baoff = baRead
        CONTINUE WHILE
      END IF
    END IF
    LABEL testboundary:
    MYASSERT(startidx >= 0)
    LET jslen = baRead - startidx
    --DISPLAY SFMT(" create jstring with startidx:%1,jslen:%2,blen:%3",
    --    startidx, jslen, blen)
    LET jstring =
        java.lang.String.create(ba, startidx, jslen, StandardCharsets.US_ASCII)
    LET bidx = jstring.lastIndexOf(boundary, startidx)
    --DISPLAY SFMT("bidx:%1,jstring:'%2',boundary:'%3'", bidx, jstring, boundary)
    IF bidx != -1 THEN
      --DISPLAY "!!!!!!!do write ba to disk"
      IF merged IS NOT NULL THEN
        --DISPLAY "  merged in prev"
      END IF
      IF prev IS NOT NULL THEN
        --DISPLAY "  write also prev"
        CALL fo.write(prev)
      END IF
      CALL fo.write(ba, 0, bidx)
      EXIT WHILE
    ELSE
      --DISPLAY "no boundary found maxToRead:", maxToRead
      --we didn't find the boundary, now we have 2 cases, either
      --buf is completely full or we need to repeat until full
      IF maxToRead == 0 THEN
        MYASSERT(prev IS NOT NULL)
        CALL merge2BA(
            ba, prev, baRead, blen, MAXB)
            RETURNING ba, prev, baRead, startidx
        GOTO testboundary
      END IF
      IF ba == merged THEN
        CALL myErr("ba==merged")
      END IF
      IF baRead == MAXB THEN
        --DISPLAY "  create new buf"
        IF prev IS NOT NULL THEN
          --DISPLAY " and write prev"
          CALL fo.write(prev)
        END IF
        LET prev = ba
        LET ba = ByteArray.create(MAXB)
        LET baRead = 0
        LET baoff = 0
      ELSE
        MYASSERT(baRead < MAXB)
        LET baoff = baRead
      END IF
    END IF
  END WHILE
  CALL fo.close()
END FUNCTION

FUNCTION createFO(path STRING)
  DEFINE fo FileOutputStream
  LET path = ".", path
  LET fo = FileOutputStream.create(path);
  RETURN fo
END FUNCTION

FUNCTION handleSimplePost(x INT, dIn DataInputStream, path STRING)
  DEFINE fo FileOutputStream
  DEFINE bytearr ByteArray
  --DEFINE jstring java.lang.String
  LET bytearr = ByteArray.create(_s[x].contentLen)
  CALL dIn.readFully(bytearr)
  --LET jstring = java.lang.String.create(bytearr, StandardCharsets.UTF_8)
  --DISPLAY "  bytearr:", jstring
  LET fo = createFO(path)
  CALL fo.write(bytearr)
  CALL fo.close()
END FUNCTION

FUNCTION handleWaitContent(x INT, dIn DataInputStream)
  DEFINE bytearr ByteArray
  DEFINE jstring java.lang.String
  DEFINE path, ct STRING
  LET path = _s[x].path
  CALL log(SFMT("handleWaitContent %1, read:%2", path, _s[x].contentLen))
  IF path.getIndexOf("/ua/", 1) == 1 THEN
    LET bytearr = ByteArray.create(_s[x].contentLen)
    CALL dIn.readFully(bytearr)
    LET jstring = java.lang.String.create(bytearr, StandardCharsets.UTF_8)
    LET _s[x].body = jstring
  ELSE
    LET ct = _s[x].contentType
    IF ct.getIndexOf("multipart/form-data", 1) > 0 THEN
      CALL handleMultiPartUpload(x, dIn, path, ct)
    ELSE
      CALL handleSimplePost(x, dIn, path)
    END IF
  END IF
  {
  IF _s[x].body.getIndexOf("GET", 1) > 0
      OR _s[x].body.getIndexOf("POST", 1) > 0 THEN
    DISPLAY "wrong body:", _s[x].body
    MYASSERT(FALSE)
  END IF
  }
  LET _s[x].state = S_FINISH
  CALL httpHandler(x)
END FUNCTION

FUNCTION handleVMFinish(c INT)
  DEFINE procId STRING
  DEFINE vmidx, httpIdx INT
  CALL log(SFMT("handleVMFinish:%1", printSel(c)))
  LET procId = _s[c].procId
  MYASSERT(_selDict.contains(procId))
  LET vmidx = _selDict[procId]
  MYASSERT(vmidx == c)
  LET httpIdx = _s[vmidx].httpIdx
  IF httpIdx != 0 THEN
    CALL handleVM(vmidx, TRUE)
  END IF
  LET _s[vmidx].state = S_FINISH
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
  DEFINE empty TConnectionRec
  DEFINE state STRING
  LET state = _s[c].state
  IF (state <> S_FINISH AND state <> S_WAITFORVM)
      OR (newChan := (_keepalive AND state == S_FINISH AND _s[c].isHTTP))
          == TRUE THEN
    IF newChan THEN
      --CALL log(sfmt("re register id:%1", _s[c].id))
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

FUNCTION setWait(vmidx INT)
  MYASSERT(_s[vmidx].wait == FALSE)
  --DISPLAY ">>setWait"
  LET _s[vmidx].wait = TRUE
END FUNCTION

--FUNCTION getNameC(buf ByteBuffer)
FUNCTION getNameC(dIn DataInputStream)
  DEFINE name STRING
  DEFINE arr MyByteArray
  DEFINE namesize, xlen INT
  DEFINE jstring java.lang.String
  LET namesize = ntohl(dIn.readInt())
  LET arr = MyByteArray.create(namesize)
  TRY
    --CALL buf.get(arr)
    CALL dIn.readFully(arr)
  CATCH
    CALL myErr(err_get(status))
  END TRY
  LET jstring = java.lang.String.create(arr, _utf8)
  LET xlen = jstring.length() - 1
  --cut terminating 0
  LET name = jstring.substring(0, xlen)
  --the following did work too, but unclear why the terminating 0 was ignored
  --LET name = _decoder.decode(buf).toString();
  CALL log(
      SFMT("getNameC name:%1 len:%2 ,namesize:%3, bytes:%4",
          name, name.getLength(), namesize, namesize + 4))
  RETURN name, namesize + 4
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
  IF isWin() THEN
    CALL b.replace(",", ",,", 0)
  ELSE
    CALL b.replace("|", "||", 0)
  END IF
  CALL b.replace("_", "__", 0)
  --//make the file name a flat name
  IF isWin() THEN
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
  LET surl = replace(surl, " ", "+")
  LET surl = replace(surl, "\\", "/")
  IF surl.getIndexOf(":", 1) == 2 THEN --drive letter
    LET surl = "http:", surl.subString(3, surl.getLength())
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

FUNCTION scanCacheParameters(vmidx INT, fileName STRING, ftg FTGetImage)
  DEFINE d TStringDict
  DEFINE url URI
  CALL getURLQueryDict(fileName) RETURNING d, url
  LET ftg.fileSize = d["s"]
  LET ftg.mtime = d["t"]
  CALL updateImg(vmidx, ftg.*)
END FUNCTION

FUNCTION createOutputStream(
    vmidx INT, num INT, fn STRING, putfile BOOLEAN)
    RETURNS BOOLEAN
  DEFINE f java.io.File
  --DEFINE fc FileChannel
  DEFINE fc FileOutputStream
  IF putfile THEN
    MYASSERT(_s[vmidx].writeCPut IS NULL)
  ELSE
    MYASSERT(_s[vmidx].writeC IS NULL)
  END IF
  --CALL log(sfmt("createOutputStream:'%1'",fn))
  LET f = File.create(fn)
  TRY
    --LET fc = FileOutputStream.create(f, FALSE).getChannel()
    LET fc = FileOutputStream.create(f, FALSE)
    IF putfile THEN
      LET _s[vmidx].writeCPut = fc
    ELSE
      LET _s[vmidx].writeC = fc
    END IF
    CALL log(
        SFMT("createOutputStream:did create file output stream for:%1", fn))
  CATCH
    CALL warning(SFMT("createOutputStream:%1", err_get(status)))
    IF num <> 0 THEN
      CALL sendFTStatus(vmidx, num, FStErrDestination)
    END IF
    RETURN FALSE
  END TRY
  RETURN TRUE
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
  IF NOT _verbose THEN
    RETURN ""
  END IF
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
  RETURN os.Path.separator() == "\\"
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

FUNCTION sendFileToVM(vmidx INT, num INT, name STRING)
  DEFINE buf ByteBuffer
  DEFINE bytesRead INT
  DEFINE chan FileChannel
  LET chan = createInputStream(FTName(name))
  IF chan IS NULL THEN
    CALL sendFTStatus(vmidx, num, FStErrSource)
    RETURN
  END IF
  CALL sendAck(vmidx, num, name)
  LET buf = ByteBuffer.allocate(30000)
  WHILE (bytesRead := chan.read(buf)) > 0
    --DISPLAY "bytesRead:", bytesRead
    CALL buf.flip()
    CALL sendBody(vmidx, num, buf)
    CALL buf.position(0)
    CALL buf.limit(30000)
  END WHILE
  CALL sendEof(vmidx, num)
  CALL setWait(vmidx)
END FUNCTION

FUNCTION resetWriteNum(vmidx INT, num INT)
  IF _s[vmidx].writeNum2 == num THEN
    LET _s[vmidx].writeNum2 = 0
  ELSE
    MYASSERT(_s[vmidx].writeNum != 0 AND _s[vmidx].writeNum == num)
    LET _s[vmidx].writeNum = 0
  END IF
END FUNCTION

FUNCTION handleFT(vmidx INT, dIn DataInputStream, dataSize INT)
  DEFINE ftType TINYINT
  DEFINE ftg FTGetImage
  DEFINE name STRING
  DEFINE fileSize, num, fstatus, numBytes, remaining INT
  --DEFINE written INT
  DEFINE found BOOLEAN
  DEFINE ba MyByteArray
  LET ftType = dIn.readByte() --buf.get()
  --LET num = ntohl(buf.getInt())
  LET num = ntohl(dIn.readInt())
  LET remaining = dataSize - 5
  CALL log(
      SFMT("handleFT ftType:%1,num:%2, remaining:%3",
          IIF((_logChan IS NOT NULL) OR _verbose, getFT2Str(ftType), ""),
          num,
          remaining))
  CASE ftType
    WHEN FTPutFile
      --LET fileSize = ntohl(buf.getInt())
      LET fileSize = ntohl(dIn.readInt())
      CALL getNameC(dIn) RETURNING name, numBytes
      LET remaining = remaining - 4 - numBytes

      CALL log(
          SFMT("FTPutFile name:%1,num:%2,_s[vmidx].writeNum:%3,_s[vmidx].writeNum2:%4'",
              name, num, _s[vmidx].writeNum, _s[vmidx].writeNum2))
      IF _s[vmidx].writeNum != 0 THEN
        LET _s[vmidx].writeNum2 = num
      ELSE
        LET _s[vmidx].writeNum = num
      END IF
      CALL log(
          SFMT("  _s[vmidx].writeNum:%1,_s[vmidx].writeNum2:%2",
              _s[vmidx].writeNum, _s[vmidx].writeNum2))
      IF createOutputStream(vmidx, num, FTName(name), TRUE) THEN
        CALL sendAck(vmidx, num, name)
        CALL setWait(vmidx)
      END IF
    WHEN FTGetFile
      CALL getNameC(dIn) RETURNING name, numBytes
      LET remaining = remaining - numBytes
      IF remaining > 0 THEN --read extension list
        LET ba = MyByteArray.create(remaining)
        CALL dIn.readFully(ba)
        LET remaining = 0
      END IF
      CALL log(
          SFMT("FTGetFile name:'%1',num:%2, remaining:%3",
              name, num, remaining))
      CALL sendFileToVM(vmidx, num, name)
    WHEN FTAck
      CALL getNameC(dIn) RETURNING name, numBytes
      LET remaining = remaining - numBytes
      CALL log(
          SFMT("FTAck name:'%1',num:%2,vmVersion:%3",
              name, num, _s[vmidx].vmVersion))
      IF _s[vmidx].vmVersion >= 3.2 AND name == "!!__cached__!!" THEN
        CALL loadFileFromCache(vmidx, num)
        CALL resetWriteNum(vmidx, num)
        CALL lookupNextImage(vmidx)
      ELSE
        CALL ftgFromNum(vmidx, num) RETURNING found, ftg.*
        IF found THEN
          --DISPLAY "ftg:", util.JSON.stringify(ftg)
          IF name.getIndexOf("?s=", 1) <> 0 THEN
            CALL scanCacheParameters(vmidx, name, ftg.*)
          END IF
          MYASSERT(createOutputStream(vmidx, 0, cacheFileName(ftg.name), FALSE) == TRUE)
        ELSE
          DISPLAY "!!no ftg for:", num
        END IF
      END IF
    WHEN FTBody
      LET numBytes = dataSize - 5
      LET ba = MyByteArray.create(numBytes)
      CALL dIn.readFully(ba)
      LET remaining = remaining - numBytes
      CALL log(
          SFMT("FTbody for num:%1", num)
          --",pos:%2,limit:%3",
          --num, buf.position(), buf.limit())
          )
      CALL log(
          SFMT("  _s[vmidx].writeNum:%1,_s[vmidx].writeNum2:%2",
              _s[vmidx].writeNum, _s[vmidx].writeNum2))
      MYASSERT(num == _s[vmidx].writeNum OR num == _s[vmidx].writeNum2)
      IF num > 0 THEN
        MYASSERT(_s[vmidx].writeCPut IS NOT NULL)
        --LET written = _s[vmidx].writeCPut.write(buf)
        CALL _s[vmidx].writeCPut.write(ba)
        --DISPLAY "written FTPutfile:", written
      ELSE
        MYASSERT(_s[vmidx].writeC IS NOT NULL)
        --LET written = _s[vmidx].writeC.write(buf)
        CALL _s[vmidx].writeC.write(ba)
        --DISPLAY "written:", written
      END IF
    WHEN FTEof
      CALL log(SFMT("FTEof for num:%1", num))
      MYASSERT(num == _s[vmidx].writeNum OR num == _s[vmidx].writeNum2)
      IF num > 0 THEN
        MYASSERT(_s[vmidx].writeCPut IS NOT NULL)
        CALL _s[vmidx].writeCPut.close()
        LET _s[vmidx].writeCPut = NULL
      ELSE
        MYASSERT(_s[vmidx].writeC IS NOT NULL)
        CALL _s[vmidx].writeC.close()
        LET _s[vmidx].writeC = NULL
      END IF
      CALL ftgFromNum(vmidx, num) RETURNING found, ftg.*
      IF found THEN
        CALL handleDelayedImage(vmidx, ftg.*)
      END IF
      CALL resetWriteNum(vmidx, num)
      CALL sendFTStatus(vmidx, num, FTOk)
      CALL lookupNextImage(vmidx)
    WHEN FTStatus
      --LET fstatus = ntohl(buf.readInt())
      LET fstatus = ntohl(dIn.readInt())
      LET remaining = remaining - 4
      CALL log(SFMT("FTStatus for num:%1,status:%2", num, fstatus))
      CASE fstatus
        WHEN FTOk --ok
        WHEN FStErrSource
          CALL resetWriteNum(vmidx, num)
          CALL ftgFromNum(vmidx, num) RETURNING found, ftg.*
          MYASSERT(found == TRUE)
          CALL handleFTNotFound(vmidx, ftg.*)
        OTHERWISE
          CALL myErr("unhandled fstatus")
      END CASE

    OTHERWISE
      CALL myErr("unhandled FT case")
  END CASE
  MYASSERT(remaining == 0)
END FUNCTION

FUNCTION loadFileFromCache(vmidx INT, num INT)
  DEFINE ftg FTGetImage
  DEFINE found BOOLEAN
  CALL ftgFromNum(vmidx, num) RETURNING found, ftg.*
  IF NOT found THEN
    RETURN
  END IF
  --VAR cachedFile=cacheFileName(ftg.name)
  LET ftg.cache = FALSE
  CALL handleDelayedImage(vmidx, ftg.*)
END FUNCTION

FUNCTION checkCached4Fmt(src STRING) RETURNS(BOOLEAN, STRING, INT, INT)
  DEFINE mid, realPath STRING
  DEFINE url URI
  DEFINE d TStringDict
  DEFINE s, t INT
  IF src.getIndexOf("__VM__/", 1) == 0 OR src.getIndexOf("?", 1) == 0 THEN
    RETURN FALSE, NULL, 0, 0
  END IF
  LET mid = src.subString(8, src.getLength())
  CALL getURLQueryDict(mid) RETURNING d, url
  IF d.getLength() == 0 THEN
    RETURN FALSE, NULL, 0, 0
  END IF
  LET s = d["s"]
  LET t = d["t"]
  LET realPath = url.getPath()
  RETURN TRUE, realPath, s, t
END FUNCTION

FUNCTION handleDelayedImage(vmidx INT, ftg FTGetImage)
  DEFINE cachedFile STRING
  DEFINE x INT
  MYASSERT(ftg.httpIdx > 0)
  LET x = ftg.httpIdx
  LET cachedFile = cacheFileName(ftg.name);
  CALL handleDelayedImageInt(vmidx, ftg.*, cachedFile)
  CALL processFile(x, cachedFile, TRUE)
  CALL finishHttp(x)
END FUNCTION

FUNCTION handleFTNotFound(vmidx INT, ftg FTGetImage)
  DEFINE x, idx INT
  DEFINE name, vmName STRING
  MYASSERT(ftg.httpIdx > 0)
  LET x = ftg.httpIdx
  CALL removeImg(vmidx, ftg.*)
  LET name = ftg.name
  CALL log(SFMT("handleFTNotFound: %1", name))
  CASE
    WHEN name.getIndexOf("gbc://", 1) == 1
      LET vmName = name.subString(7, name.getLength())
    WHEN name.getIndexOf("webcomponents/", 1) == 1
      LET idx = name.getIndexOf("/", 15)
      IF idx > 0 THEN
        LET vmName = name.subString(idx + 1, name.getLength())
      END IF
  END CASE
  IF vmName IS NOT NULL THEN
    CALL log(SFMT("  retry FT request with:%1", vmName))
    CALL checkRequestFT(x, vmidx, vmName)
  ELSE
    CALL http404(x, ftg.name)
    CALL finishHttp(x)
  END IF
END FUNCTION

FUNCTION handleDelayedImageInt(vmidx INT, ftg FTGetImage, cachedFile STRING)
  DEFINE t INT
  CALL log(SFMT("handleDelayedImage:", vmidx, util.JSON.stringify(ftg)))
  CALL removeImg(vmidx, ftg.*)
  IF NOT ftg.cache OR {data==nil OR} ftg.mtime == 0 THEN
    {
    DISPLAY "  return NOT ftg.cache OR ftg.mtime, cachedFile:",
        cachedFile,
        ", exists:",
        os.Path.exists(cachedFile)
    }
    RETURN
  END IF
  LET cachedFile = cacheFileName(ftg.name);
  MYASSERT(os.Path.exists(cachedFile))
  MYASSERT(os.Path.size(cachedFile) == ftg.fileSize)
  LET t = getLastModified(cachedFile)
  IF t <> ftg.mtime THEN
    CALL setLastModified(cachedFile, ftg.mtime)
    LET t = getLastModified(cachedFile)
    MYASSERT(ftg.mtime == t)
    --IF ftg.mtime <> t THEN
    --  DISPLAY "currt2:", t, "<>", ftg.mtime
    --END IF
    MYASSERT(getLastModified(cachedFile) == ftg.mtime)
  END IF
END FUNCTION

FUNCTION checkFT2(val STRING) RETURNS(BOOLEAN, STRING, BOOLEAN)
  DEFINE realName STRING
  DEFINE cached4, exist, ft2 BOOLEAN
  DEFINE s, s2, t, t2 INT
  CALL checkCached4Fmt(val) RETURNING cached4, realName, s, t
  CALL log(SFMT("cached4:%1 realName:'%2' s:%3,t:%4", cached4, realName, s, t))
  IF cached4 THEN
    CALL lookupInCache(realName) RETURNING exist, s2, t2
    IF exist AND s == s2 AND t == t2 THEN
      CALL log(SFMT("found in cache:'%1' with s:%2,t:%3", realName, s, t))
      RETURN TRUE, realName, TRUE
    ELSE
      CALL log(
          SFMT("not found in cache:'%1' with exist:%2 s:%3,s2:%4,t:%5,t2:%6",
              realName, exist, s, s2, t, t2))
      LET val = realName
      LET ft2 = TRUE
    END IF
  END IF
  RETURN FALSE, val, ft2
END FUNCTION

FUNCTION getFTs(vmidx INT)
  RETURN _s[vmidx].FTs
END FUNCTION

FUNCTION checkRequestFT(x INT, vmidx INT, fname STRING)
  DEFINE ftg FTGetImage
  DEFINE cached, ft2 BOOLEAN
  DEFINE FTs FTList
  DEFINE realName, cachedName STRING
  IF fname IS NULL THEN
    DISPLAY "No FT value for:", vmidx
    RETURN
  END IF
  CALL checkFT2(fname) RETURNING cached, realName, ft2
  IF cached THEN --we have the file already in the cache
    LET cachedName = cacheFileName(realName)
    CALL log(
        SFMT("checkRequestFT got cached realName:%1 with:%2",
            realName, cachedName))
    CALL processFile(x, cachedName, TRUE)
    CALL finishHttp(x)
    RETURN
  ELSE
    LET fname = realName
  END IF
  MYASSERT(_s[vmidx].ftNum IS NOT NULL)
  LET _s[vmidx].ftNum = _s[vmidx].ftNum - 1
  LET ftg.num = _s[vmidx].ftNum
  LET ftg.name = fname
  LET ftg.cache = TRUE
  LET ftg.httpIdx = x
  --LET ftg.node = n
  LET ftg.ft2 = ft2
  CALL log(
      SFMT("requestFT for :%1,num:%2,%3",
          fname, _s[vmidx].ftNum, printSel(vmidx)))
  LET FTs = getFTs(vmidx)
  LET FTs[FTs.getLength() + 1].* = ftg.*
  MYASSERT(NOT _s[vmidx].state.equals(S_FINISH))
  IF NOT _s[vmidx].state = S_ACTIVE THEN
    RETURN
  END IF
  CALL lookupNextImage(vmidx)
END FUNCTION

FUNCTION removeImg(vmidx INT, ftg FTGetImage)
  DEFINE i INT
  DEFINE FTs FTList
  LET FTs = getFTs(vmidx)
  --DISPLAY "before removal:", util.JSON.stringify(_s[vmidx].FTs)
  CALL log(
      SFMT("removeImg:%1 num:%2 len:%3, FTs:%4",
          ftg.name,
          ftg.num,
          FTs.getLength(),
          IIF(_verbose, util.JSON.stringify(FTs), "")))
  FOR i = 1 TO FTs.getLength()
    --remove the same number but also pending images with the same name
    IF FTs[i].num == ftg.num OR FTs[i].name == ftg.name THEN
      CALL log(
          SFMT("  removed:%1 at:%2:%3",
              ftg.name, i, IIF(_verbose, util.JSON.stringify(FTs[i]), "")))
      CALL FTs.deleteElement(i)
      LET i = i - 1
    END IF
  END FOR
  --DISPLAY "after removal:", util.JSON.stringify(_s[vmidx].FTs)
END FUNCTION

FUNCTION updateImg(vmidx INT, ftg FTGetImage)
  DEFINE len, i INT
  DEFINE FTs FTList
  LET FTs = getFTs(vmidx)
  LET len = FTs.getLength()
  FOR i = 1 TO len
    IF FTs[i].num == ftg.num THEN
      LET FTs[i].* = ftg.*
      RETURN
    END IF
  END FOR
END FUNCTION

FUNCTION ftgFromNum(vmidx INT, num INT) RETURNS(BOOLEAN, FTGetImage)
  DEFINE len, i INT
  DEFINE ftg FTGetImage
  DEFINE FTs FTList
  LET FTs = getFTs(vmidx)
  LET len = FTs.getLength()
  FOR i = 1 TO len
    IF FTs[i].num == num THEN
      LET ftg.* = FTs[i].*
      RETURN TRUE, ftg.*
    END IF
  END FOR
  CALL log(SFMT("ftgFromNum: did not find image for:%1", num))
  RETURN FALSE, ftg.*
END FUNCTION

FUNCTION lookupNextImage(vmidx INT)
  DEFINE ftg FTGetImage
  DEFINE len INT
  DEFINE FTs FTList
  LET FTs = getFTs(vmidx)
  LET len = FTs.getLength()
  CALL log(
      SFMT("lookupNextImage wait:%1,writeNum:%2,len:%3,writeC IS NOT NULL:%4",
          _s[vmidx].wait,
          _s[vmidx].writeNum,
          len,
          _s[vmidx].writeC IS NOT NULL))
  IF _s[vmidx].wait
      OR (_s[vmidx].writeNum != 0)
      OR (len == 0)
      OR (_s[vmidx].writeC IS NOT NULL) THEN
    IF _s[vmidx].writeNum == 0 AND len == 0 AND _s[vmidx].writeC IS NULL THEN
      CALL log("lookupNextImage: all files transferred!")
      --ELSE
      --DISPLAY "  _s[vmidx].writeNum != 0"
    END IF
    RETURN
  END IF
  MYASSERT(FTs.getLength() > 0)
  LET ftg.* = FTs[1].*
  --DISPLAY "  lookupNextImage:", util.JSON.stringify(ftg)
  LET _s[vmidx].writeNum = ftg.num
  IF _s[vmidx].vmVersion >= 3.2 THEN
    CALL checkCacheSendInformation(vmidx, ftg.*)
  ELSE
    CALL sendGetImage(vmidx, ftg.num, ftg.name)
  END IF
END FUNCTION

FUNCTION checkCacheSendInformation(vmidx INT, ftg FTGetImage)
  --//we append the new special query to indicate we want to get
  --//size and mtime information in the ack answer
  DEFINE s, t INT
  DEFINE exist BOOLEAN
  DEFINE name STRING
  IF ftg.cache THEN
    CALL lookupInCache(ftg.name) RETURNING exist, s, t
  END IF
  LET name = SFMT("%1%2?s=%3&t=%4", IIF(ftg.ft2, "__VM__/", ""), ftg.name, s, t)
  CALL sendGetImage(vmidx, ftg.num, name)
END FUNCTION

FUNCTION sendGetImage(vmidx INT, num INT, fileName STRING)
  CALL sendGetImageOrAck(vmidx, num, fileName, TRUE)
END FUNCTION

FUNCTION sendAck(vmidx INT, num INT, fileName STRING)
  --DISPLAY SFMT("sendAck vmidx:%1,num:%2,fileName:%3", vmidx, num, fileName)
  CALL sendGetImageOrAck(vmidx, num, fileName, FALSE)
END FUNCTION

FUNCTION sendGetImageOrAck(
    vmidx INT, num INT, fileName STRING, getImage BOOLEAN)
  DEFINE fileNameBuf ByteBuffer
  DEFINE pktlen, extlen, len INT
  DEFINE ext STRING
  DEFINE pkt ByteBuffer
  DEFINE b0 TINYINT
  DEFINE extBuf ByteBuffer
  LET fileNameBuf = _encoder.encode(CharBuffer.wrap(fileName))
  LET len = fileNameBuf.limit()
  CALL log(
      SFMT("sendGetImageOrAck num:%1,fileName:'%2',getImage:%3",
          num, fileName, getImage))
  MYASSERT(len == fileName.getLength())
  LET pktlen = 1 + 2 * size_i + len; --1st byte FT instruction
  IF getImage THEN --append imagelist
    LET ext = ".png;.PNG;.gif;.GIF;.jpg;.JPG;.tif;.TIF;.bmp;.BMP"
    LET extlen = ext.getLength()
    LET pktlen = pktlen + size_i + extlen + 1;
  END IF
  LET pkt = ByteBuffer.allocate(pktlen)
  --DISPLAY "pktlen:", pktlen
  LET b0 = IIF(getImage, FTGetFile, FTAck)
  CALL pkt.put(b0) --put first byte
  CALL pkt.putInt(num) --ByteBuffers putInt is always in network byte order
  CALL pkt.putInt(len) --so no htonl is needed
  CALL pkt.put(fileNameBuf)

  IF (getImage) THEN
    CALL pkt.putInt(extlen)
    LET extBuf = _encoder.encode(CharBuffer.wrap(ext))
    CALL pkt.put(extBuf)
    LET b0 = 0
    CALL pkt.put(b0) --terminating 0
  END IF
  CALL encapsMsgToVM(vmidx, TFileTransfer, pkt)
END FUNCTION

FUNCTION sendBody(vmidx INT, num INT, buf ByteBuffer)
  DEFINE pkt ByteBuffer
  DEFINE pktlen INT
  DEFINE b0 TINYINT
  LET pktlen = 1 + size_i + buf.limit()
  LET pkt = ByteBuffer.allocate(pktlen)
  LET b0 = FTBody
  CALL pkt.put(b0) --put first byte
  CALL pkt.putInt(num) --ByteBuffers putInt is always in network byte order
  CALL pkt.put(buf)
  CALL encapsMsgToVM(vmidx, TFileTransfer, pkt)
END FUNCTION

FUNCTION sendEof(vmidx INT, num INT)
  DEFINE pkt ByteBuffer
  DEFINE pktlen INT
  DEFINE b0 TINYINT
  LET pktlen = 1 + size_i
  LET pkt = ByteBuffer.allocate(pktlen)
  LET b0 = FTEof
  CALL pkt.put(b0) --put first byte
  CALL pkt.putInt(num)
  CALL encapsMsgToVM(vmidx, TFileTransfer, pkt)
END FUNCTION

FUNCTION sendFTStatus(vmidx INT, num INT, code INT)
  DEFINE pkt ByteBuffer
  DEFINE pktlen INT
  DEFINE b0 TINYINT
  LET pktlen = 1 + 2 * size_i
  LET pkt = ByteBuffer.allocate(pktlen)
  LET b0 = FTStatus
  CALL pkt.put(b0)
  CALL pkt.putInt(num)
  CALL pkt.putInt(code)
  CALL encapsMsgToVM(vmidx, TFileTransfer, pkt)
END FUNCTION

FUNCTION sendCommandToVM(vmidx INT, msg STRING)
  --DEFINE cmd STRING
  MYASSERT(_s[vmidx].wait == FALSE)
  --LET _cmdCount = _cmdCount + 1
  --LET cmd = SFMT("event _om %1{}{%2}\n", _cmdCount, msg);
  CALL log(SFMT("sendCommandToVM:%1", msg))
  CALL writeToVMEncaps(vmidx, msg)
END FUNCTION

FUNCTION writeToVMEncaps(vmidx INT, cmd STRING)
  DEFINE b ByteBuffer
  CALL setWait(vmidx)
  LET b = _encoder.encode(CharBuffer.wrap(cmd))
  CALL log(SFMT("writeToVMEncaps vmidx:%1,cmd:%2", vmidx, limitPrintStr(cmd)))
  --encode() doesn't set position()
  CALL b.position(b.limit()) --because encapsMsgToVM calls flip()
  CALL encapsMsgToVM(vmidx, TAuiData, b)
END FUNCTION

FUNCTION encapsMsgToVM(vmidx INT, type TINYINT, pkt ByteBuffer)
  DEFINE buf ByteBuffer
  DEFINE whole_len INT
  DEFINE len INT
  CALL pkt.flip()
  LET len = pkt.limit()
  --DISPLAY "encapsMsgToVM: len:", len, ",_s[vmidx].wait:", _s[vmidx].wait
  LET whole_len = (2 * size_i) + 1 + len
  LET buf = ByteBuffer.allocate(whole_len)
  CALL buf.putInt(len) --comp_length
  CALL buf.putInt(len) --body_length
  CALL buf.put(type)
  CALL buf.put(pkt)
  --DISPLAY "pkt len:", len, ",buf pos:", buf.position()
  CALL buf.flip()
  --CALL writeChannel(_currChan, buf)
  CALL writeChannel(_s[vmidx].chan, buf)
END FUNCTION

FUNCTION clearCache()
  DEFINE cacheDir STRING
  LET cacheDir = "cacheFT"
  IF NOT os.Path.exists(cacheDir) THEN
    RETURN
  END IF
  CALL rmrf(cacheDir)
END FUNCTION

FUNCTION rmrf(dirname STRING)
  DEFINE cmd, curr STRING
  LET curr = os.Path.fullPath(os.Path.pwd())
  MYASSERT(os.Path.isDirectory(dirname) AND NOT curr.equals(os.Path.fullPath(dirname)))
  IF isWin() THEN
    LET cmd = SFMT("rmdir /s /q %1", quote(dirname))
  ELSE
    LET cmd = SFMT("rm -rf %1", quote(dirname))
  END IF
  --DISPLAY "rmrf:",cmd
  RUN cmd
END FUNCTION
