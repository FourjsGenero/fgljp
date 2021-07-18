IMPORT FGL testutils
IMPORT os
MAIN
  IF arg_val(1) IS NULL THEN
    CALL testutils.myErr(sfmt("%1 <startfile>",arg_val(0)))
  END IF
  CALL testutils.readStartFile(arg_val(1))
END MAIN
