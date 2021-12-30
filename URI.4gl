--+implements a poor mans version of the java.net.URI class
IMPORT util
&define MYASSERT(x) IF NOT NVL(x,0) THEN CALL myErr("ASSERTION failed in line:"||__LINE__||":"||#x) END IF
--IMPORT JAVA java.net.URI

PUBLIC TYPE URI RECORD
  full STRING,
  scheme STRING,
  host STRING,
  port INT,
  path STRING,
  query STRING
END RECORD

FUNCTION lastIndexOf(s STRING, sub STRING)
  DEFINE startpos, idx, lastidx INT
  LET startpos = 1
  WHILE (idx := s.getIndexOf(sub, startpos)) > 0
    LET lastidx = idx
    LET startpos = idx + 1
  END WHILE
  RETURN lastidx
END FUNCTION

FUNCTION create(s STRING) RETURNS URI
  DEFINE u URI
  DEFINE idx, hostidx, colonidx, qidx INT
  DEFINE host, path STRING
  LET u.port = -1
  LET u.full = s
  LET hostidx = 1
  IF (idx := s.getIndexOf("://", 1)) > 0 THEN
    LET u.scheme = s.subString(1, idx - 1)
    --DISPLAY "did find scheme:'",u.scheme,"'"
    LET idx = idx + 3
    --DISPLAY "idx:",idx,",char:",s.getCharAt(idx)
    IF (hostidx := s.getIndexOf("/", idx)) > 0 THEN
      LET host = s.subString(idx, hostidx - 1)
      --DISPLAY "hostidx:",hostidx,",host:",host
      LET hostidx = hostidx
    ELSE
      LET host = s.subString(idx, s.getLength())
      LET hostidx = s.getLength() + 1
    END IF
  END IF
  IF (colonidx := host.getIndexOf(":", 1)) > 0 THEN
    LET u.host = host.subString(1, colonidx - 1)
    LET u.port = host.subString(colonidx + 1, host.getLength())
    --DISPLAY "did find host:'",u.host,"' and port:",u.port
  ELSE
    LET u.host = host
    --DISPLAY "did find host:'",u.host,"'"
  END IF

  LET path = s.subString(hostidx, s.getLength())
  IF (qidx := lastIndexOf(path, "?")) > 0 THEN
    LET u.path = path.subString(1, qidx - 1)
    LET u.query = path.subString(qidx + 1, path.getLength())
    IF u.query.getIndexOf("%", 1) > 0 THEN
      LET u.query = util.Strings.urlDecode(u.query)
    END IF
  ELSE
    LET u.path = path
  END IF
  IF u.path.getIndexOf("%", 1) > 0 THEN
    LET u.path = util.Strings.urlDecode(u.path)
  END IF
  RETURN u
END FUNCTION

FUNCTION (u URI) getScheme() RETURNS STRING
  RETURN u.scheme
END FUNCTION

FUNCTION (u URI) getPath() RETURNS STRING
  RETURN u.path
END FUNCTION

FUNCTION (u URI) getHost() RETURNS STRING
  RETURN u.host
END FUNCTION

FUNCTION (u URI) getPort() RETURNS INT
  RETURN u.port
END FUNCTION

FUNCTION (u URI) getQuery() RETURNS STRING
  RETURN u.query
END FUNCTION

FUNCTION (u URI) toString() RETURNS STRING
  RETURN SFMT("%1%2%3%4%5%6%7%8",
      u.scheme,
      IIF(u.scheme IS NULL, "", "://"),
      u.host,
      IIF(u.port == -1, "", ":"),
      IIF(u.port == -1, "", u.port),
      u.path,
      IIF(u.query IS NULL, "", "?"),
      u.query)
END FUNCTION

FUNCTION (u URI) debug() RETURNS STRING
  RETURN util.JSON.stringify(u)
END FUNCTION

FUNCTION MAIN()
  DEFINE u URI
  --DEFINE u2 java.net.URI
  DEFINE s STRING
  IF arg_val(1) IS NULL THEN
    CALL test()
    RETURN
  END IF
  LET s = arg_val(1)
  LET u = create(s)
  DISPLAY "u:", u.toString(), ",debug:", u.debug()
  --LET u2 = java.net.URI.create(s)
  --DISPLAY u2.toString(),
  --    ",scheme:",
  --    u2.getScheme(),
  --    ",host:",
  --    u2.getHost(),
  --    ",port:",
  --    u2.getPort(),
  --    ",path:",
  --    u2.getPath(),
  --    ",query:",
  --    u2.getQuery()

END FUNCTION

FUNCTION test()
  DEFINE s STRING
  DEFINE u URI
  LET s = "http://www.xx.de:23/foo/bar.png?a=b&d=f"
  LET u = create(s)
  MYASSERT(u.getScheme() == "http")
  MYASSERT(u.getHost() == "www.xx.de")
  MYASSERT(u.getPort() == 23)
  MYASSERT(u.getPath() == "/foo/bar.png")
  MYASSERT(u.getQuery() == "a=b&d=f")
  LET s = "/foo/bar.png?t=50"
  LET u = create(s)
  MYASSERT(u.getScheme().getLength() == 0)
  MYASSERT(u.getHost().getLength() == 0)
  MYASSERT(u.getPort() == -1)
  MYASSERT(u.getPath() == "/foo/bar.png")
  MYASSERT(u.getQuery() == "t=50")
  LET s = "gbc://index.html"
  LET u = create(s)
  MYASSERT(u.getScheme() == "gbc")
  MYASSERT(u.getHost() == "index.html")
  MYASSERT(u.getPort() == -1)
  MYASSERT(u.getPath().getLength() == 0)
  MYASSERT(u.getQuery().getLength() == 0)
  LET s = "abc:xx"
  LET s = "/", util.Strings.urlEncode(s), "?a=", util.Strings.urlEncode(s)
  LET u = create(s)
  MYASSERT(u.getScheme().getLength() == 0)
  MYASSERT(u.getHost().getLength() == 0)
  MYASSERT(u.getPort() == -1)
  MYASSERT(u.getPath() == "/abc:xx")
  MYASSERT(u.getQuery() == "a=abc:xx")
END FUNCTION

FUNCTION printStderr(errstr STRING)
  DEFINE ch base.Channel
  LET ch = base.Channel.create()
  CALL ch.openFile("<stderr>", "w")
  CALL ch.writeLine(errstr)
  CALL ch.close()
END FUNCTION

FUNCTION myErr(errstr STRING)
  CALL printStderr(
      SFMT("ERROR:%1 stack:\n%2", errstr, base.Application.getStackTrace()))
  EXIT PROGRAM 1
END FUNCTION
