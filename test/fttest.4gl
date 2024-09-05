MAIN
  CALL fgl_putfile("num001.png","xx.png")
  MENU 
    ON IDLE 3
      EXIT MENU
    COMMAND "exit"
      EXIT MENU
  END MENU
END MAIN
