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
      CALL showForm()
    COMMAND "RUN"
      RUN SFMT("fglrun demo %1 %2", arg || "+", arg_val(2))
    COMMAND "RUN WITHOUT WAITING"
      RUN SFMT("fglrun demo %1 %2", arg || "+", arg_val(2)) WITHOUT WAITING
    COMMAND "EXIT"
      EXIT MENU
  END MENU
END MAIN

FUNCTION showForm()
  OPEN FORM f FROM "demo"
  DISPLAY FORM f
  DISPLAY "Entry" TO entry
  DISPLAY "WebComponent" TO w
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
