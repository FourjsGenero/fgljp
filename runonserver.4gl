MAIN
  CALL runOnServer(arg_val(1))
END MAIN

FUNCTION runOnServer(url)
  DEFINE url STRING
  DEFINE ret, err STRING
  DISPLAY "runOnServer:", url
  TRY
    CALL ui.Interface.frontCall("mobile", "runOnServer", [url, 10], [ret])
    DISPLAY SFMT("runonserver %1 finished normal", url)
  CATCH
    LET err = err_get(status)
    DISPLAY SFMT("ERROR runonserver %1:%2", url, err)
  END TRY
END FUNCTION
