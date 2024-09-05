IMPORT os
IMPORT FGL testutils

MAIN
  DEFINE fgljp STRING
  LET fgljp="..",os.Path.separator(),"fgljp"
  --test GAS mode
  CALL testutils.checkRUN(fgljp || " test")
  --test remote mode
  CALL os.Path.delete("test.start") RETURNING status 
  RUN fgljp ||" -v -l test.log -o test.start -X" WITHOUT WAITING
  CALL testutils.readStartFile("test.start")
  --CALL fgl_setenv("FGLGUIDEBUG","1")
  CALL testutils.checkRUN("fglrun test")
  CALL testutils.testPatternInFile("fgljp FINISH", "test.log", 5)
  CALL testutils.checkRUN(fgljp || " fttest")
END MAIN
