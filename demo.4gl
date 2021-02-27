MAIN 
  DEFINE arg STRING
  LET arg=arg_val(1)
  DISPLAY "arg1:",arg,",arg2:",arg_val(2)
  MESSAGE "arg1:",arg,",arg2:",arg_val(2)
  MENU arg
    COMMAND "Long Sleep"
      SLEEP 10
    ON Action message ATTRIBUTE(IMAGE="smiley",TEXT="Message")
      MESSAGE "TEST"
    --ON IDLE 10
    --  MESSAGE "IDLE"
    COMMAND "RUN"
      RUN sfmt("fglrun demo %1 %2",arg||"+",arg_val(2))
    COMMAND "EXIT"
      EXIT MENU
  END MENU
END MAIN
