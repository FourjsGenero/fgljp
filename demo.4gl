IMPORT FGL fgldialog
MAIN
  DEFINE arg,win STRING
  DEFINE num INT
  LET arg = arg_val(1)
  IF arg IS NOT NULL THEN
    DISPLAY "arg1:", arg, ",arg2:", arg_val(2)
    --MESSAGE "arg1:", arg, ",arg2:", arg_val(2)
    IF arg == "fc" THEN
      CALL fc10()
    END IF
  END IF
  MENU arg
    COMMAND "Long Sleep"
      MESSAGE "Going to sleep for 5 seconds"
      CALL ui.Interface.refresh()
      SLEEP 5
      MESSAGE "Sleep done"
    COMMAND "Processing"
      CALL testProcessing()
    COMMAND "sub"
      CALL sub()
    ON ACTION message ATTRIBUTE(IMAGE = "smiley", TEXT = "Message")
      LET num = num + 1
      MESSAGE SFMT("TEST%1", num)
      --ON IDLE 10
      --  MESSAGE "IDLE"
    COMMAND "10 frontcalls" 
      CALL fc10()
    COMMAND "debugger frontcall"
      CALL ui.Interface.frontCall("debugger","getcurrentwindow",[],[win])
      MESSAGE "activeWindow:",win
    COMMAND "Client Info"
      CALL fgl_winMessage("Client Info",sfmt("getFrontEndName:%1,getFrontEndVersion:%2,feinfo fename:%3",ui.Interface.getFrontEndName(), ui.Interface.getFrontEndVersion(),feinfo_fename()),"info")
    COMMAND "Show Form"
      CALL showForm("logo.png")
    COMMAND "RUN"
      RUN SFMT("fglrun demo %1 %2", arg || "+", arg_val(2))
    COMMAND "RUN WITHOUT WAITING"
      RUN SFMT("fglrun demo %1 %2", arg || "+", arg_val(2)) WITHOUT WAITING
    COMMAND "putfile"
      {
      OPEN WINDOW w AT 1,1 WITH 10 ROWS, 10 COLUMNS
      MENU
         COMMAND "exit"
           EXIT MENU
      END MENU
      }
      TRY
        CALL fgl_putfile("logo.png", "logo2.png")
        DISPLAY "fgl_putfile successful"
        MESSAGE "fgl_putfile successful"
      CATCH
        ERROR "fgl_putfile failed:",err_get(status)
      END TRY
    COMMAND "getfile"
      TRY
        CALL fgl_getfile("logo2.png", "logo3.png")
      CATCH
        ERROR err_get(status)
        CONTINUE MENU
      END TRY
      CALL showForm("logo3.png")
      MESSAGE "getfile successful"
    COMMAND "env"
      RUN "env | grep FGL"

    COMMAND "x EXIT"
      EXIT MENU
  END MENU
END MAIN

FUNCTION sub()
  MENU
    COMMAND "exit"
      EXIT MENU
  END MENU
END FUNCTION

FUNCTION testProcessing()
  DEFINE i INT
  OPEN WINDOW processing AT 1, 1 WITH 10 ROWS, 10 COLUMNS
  FOR i = 1 TO 3
    MESSAGE SFMT("Processing %1", i)
    CALL ui.Interface.refresh()
  END FOR
  CLOSE WINDOW processing
END FUNCTION

FUNCTION showForm(img STRING)
  OPEN FORM f FROM "demo"
  DISPLAY FORM f
  DISPLAY "Entry" TO entry
  DISPLAY "ui.InInterface.filenameToURI:", ui.Interface.filenameToURI(img)
  DISPLAY SFMT('{"value": "WebComponent", "src":"%1"}',
          ui.Interface.filenameToURI(img))
      TO w
  DISPLAY img TO logo
END FUNCTION

FUNCTION feinfo_fename()
  DEFINE fename STRING
  CALL ui.Interface.frontCall("standard", "feinfo", ["fename"], [fename])
  RETURN fename
END FUNCTION

FUNCTION fc10()
  DEFINE starttime DATETIME HOUR TO FRACTION(3)
  DEFINE diff INTERVAL MINUTE TO FRACTION(3)
  DEFINE fename STRING
  DEFINE i INT
  --CONSTANT MAXCNT = 1000
  CONSTANT MAXCNT = 10
  LET starttime = CURRENT
  FOR i = 1 TO MAXCNT
    LET fename=feinfo_fename()
  END FOR
  LET diff = CURRENT - starttime
  --CALL fgl_winMessage("Info",SFMT("time:%1,time for one frontcall:%2",diff,diff/MAXCNT),"info")
  DISPLAY SFMT("time:%1,time for one frontcall:%2", diff, diff / MAXCNT)
  MESSAGE SFMT("time:%1,time for one frontcall:%2", diff, diff / MAXCNT)
END FUNCTION
