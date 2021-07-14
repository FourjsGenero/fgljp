#!/bin/bash
../fgljp -l test.log -X > test.start &
for i in 1 2 3 4 5
do
  grep "port" test.start
  :
done


sleep 1
fglrun ./test
if [ $? -ne 0 ]; then
  echo "fglrun test failed"
  exit 1
fi
wait
grep "fgljp FINISH" test.log
if [ $? -ne 0 ]; then
  echo "grep failed"
  exit 1
fi
rm -f test.log test.start

