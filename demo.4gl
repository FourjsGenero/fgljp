MAIN
  DEFINE arg STRING
  LET arg = arg_val(1)
  IF arg IS NOT NULL THEN
    DISPLAY "arg1:", arg, ",arg2:", arg_val(2)
    MESSAGE "arg1:", arg, ",arg2:", arg_val(2)
  END IF
  MENU arg
    COMMAND "Long Sleep"
      SLEEP 10
    ON ACTION message ATTRIBUTE(IMAGE = "smiley", TEXT = "Message")
      MESSAGE "TEST"
      --ON IDLE 10
      --  MESSAGE "IDLE"
    COMMAND "Show Form"
      CALL showForm()
    COMMAND "RUN"
      RUN SFMT("fglrun demo %1 %2", arg || "+", arg_val(2))
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
