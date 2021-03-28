MAIN
  DEFINE arg STRING
  LET arg = arg_val(1)
  IF arg IS NOT NULL THEN
    DISPLAY "arg1:", arg, ",arg2:", arg_val(2)
    --MESSAGE "arg1:", arg, ",arg2:", arg_val(2)
    IF arg == "fc" THEN
      CALL fc()
    END IF
  END IF
  MENU arg
    COMMAND "Long Sleep"
      SLEEP 10
    ON ACTION message ATTRIBUTE(IMAGE = "smiley", TEXT = "Message")
      MESSAGE "TEST"
      --ON IDLE 10
      --  MESSAGE "IDLE"
    COMMAND "fc"
      CALL fc()
    COMMAND "Show Form"
      CALL showForm("logo.png")
    COMMAND "RUN"
      RUN SFMT("fglrun demo %1 %2", arg || "+", arg_val(2))
    COMMAND "RUN WITHOUT WAITING"
      RUN SFMT("fglrun demo %1 %2", arg || "+", arg_val(2)) WITHOUT WAITING
    COMMAND "putfile"
      CALL fgl_putfile("logo.png","logo2.png")
      MESSAGE "putfile successful"
    COMMAND "getfile"
      TRY
      CALL fgl_getfile("logo2.png","logo3.png")
      CATCH
        OPEN FORM f FROM "demo"
        DISPLAY FORM f
        DISPLAY err_get(status) TO t
        CONTINUE MENU
      END TRY
      CALL showForm("logo3.png")
      MESSAGE "getfile successful"

    COMMAND "EXIT"
      EXIT MENU
  END MENU
END MAIN

FUNCTION showForm(img STRING)
  OPEN FORM f FROM "demo"
  DISPLAY FORM f
  DISPLAY "Entry" TO entry
  DISPLAY sfmt('{"value": "WebComponent", "src":"%1"}',ui.Interface.filenameToURI(img)) TO w
  DISPLAY img TO logo
END FUNCTION

FUNCTION fc()
  DEFINE starttime DATETIME HOUR TO FRACTION(3)
  DEFINE diff INTERVAL MINUTE TO FRACTION(3)
  DEFINE i INT
  CONSTANT MAXCNT = 1000
  LET starttime = CURRENT
  FOR i = 1 TO MAXCNT
    CALL ui.Interface.frontCall("standard", "feinfo", ["fename"], [])
  END FOR
  LET diff = CURRENT - starttime
  --CALL fgl_winMessage("Info",SFMT("time:%1,time for one frontcall:%2",diff,diff/MAXCNT),"info")
  DISPLAY SFMT("time:%1,time for one frontcall:%2", diff, diff / MAXCNT)
  MESSAGE SFMT("time:%1,time for one frontcall:%2", diff, diff / MAXCNT)
END FUNCTION
