#+ the fgl getopt module backported to 3.10
IMPORT os

#+ GetoptOptions.arg_type flag: Option has no value argument.
PUBLIC CONSTANT NONE = 1
#+ GetoptOptions.arg_type flag: Option has a mandatory value argument.
PUBLIC CONSTANT REQUIRED = 2
#+ GetoptOptions.arg_type flag: Option has an optional value argument.
PUBLIC CONSTANT OPTIONAL = 3

#+ getopt() method status: Last argument processing succeeded.
PUBLIC CONSTANT SUCCESS = 0
#+ getopt() method status: All possible options have been processed.
PUBLIC CONSTANT EOF = 1
#+ getopt() method status: The last option processing failed.
PUBLIC CONSTANT BAD_OPTION = 2

PRIVATE CONSTANT ALIGN_SIZE = 30 # Alignment of usage display

#+
#+ Getopt array of option definitions
#+
#+ This type defines a dynamic array of a record structure to hold command line
#+ options definitions information.
#+ Define a variable of the getopt.GetoptOptions type and fill it with an
#+ array initializer.
#+ Once the array is initialized, it can be passed to the initDefault() or
#+ initialize() method, to setup a Getopt variable in order to process
#+ command line arguments with the getopt() method.
#+
#+ Record members:
#+
#+ -  name: defines the long name of the command line option.
#+
#+ -  description: is the text to explain the command line option.
#+
#+ -  opt_char: is the single-char command line option name.
#+
#+ -  arg_type: can be one of getopt.NONE, getopt.OPTIONAL, getopt.REQUIRED
#+
PUBLIC TYPE GetoptOptions DYNAMIC ARRAY OF RECORD
  name STRING,
  description STRING,
  opt_char CHAR,
  arg_type INTEGER
END RECORD

#+
#+ Getopt object type
#+
#+ This type defines the Getopt record that is used with getopt methods to
#+ parse and validate command line options.
#+ A variable of the type Getopt must be defined and initialized with the
#+ initDefault() or initialize() method, before using the getopt() method
#+ in a WHILE loop, to process command line options.
#+ After initializing the Getopt variable, the argv dynamic array contains
#+ all command line arguments starting from the index offset provided to
#+ the initialize() method.
#+
#+ Record members:
#+
#+ -  opt_ind: Current command line argument index that is processed.
#+
#+ -  opt_char: The single-character short name of the current processed option.
#+
#+ -  opt_arg: If present, holds the value parameter of the processed option
#+             (--option=value). Otherwise, this member is NULL.
#+
PUBLIC TYPE Getopt RECORD
  # Private members - don't modify
  argv DYNAMIC ARRAY OF STRING,
  status INTEGER,
  _options GetoptOptions,
  prog_name STRING,
  next_char STRING,
  option_index INTEGER,

  # Public read only members
  opt_ind INTEGER,
  opt_char CHAR,
  opt_arg STRING
END RECORD

PUBLIC TYPE GetoptR DYNAMIC ARRAY OF Getopt

MAIN
  DEFINE gr GetoptR
  DEFINE _options GetoptOptions
  { =
      [(name: "version",
              description: "Version information",
              opt_char: 'v',
              arg_type: NONE),
          (name: "help",
              description: "This help page",
              opt_char: 'h',
              arg_type: NONE),
          (name: "hello",
              description: "Hello everybody!",
              opt_char: NULL,
              arg_type: REQUIRED),
          (name: "bonjour",
              description: "Bonjour tout le monde!",
              opt_char: 'B',
              arg_type: OPTIONAL),
          (name: "number",
              description: "Accept also negativ numbers",
              opt_char: 'n',
              arg_type: REQUIRED)]


  }
  DEFINE ind, option_index INTEGER
  DEFINE cnt INTEGER
  DEFINE opt_char, opt_arg STRING

  -- CALL g.initDefault(_options)
  CALL initialize(gr, arg_val(0), copyArguments(1), _options)

  WHILE getopt(gr) == SUCCESS
    LET opt_char = gr[1].opt_char
    LET opt_arg = gr[1].opt_arg
    LET option_index = gr[1].option_index
    CASE opt_char
      WHEN 'v'
        DISPLAY "Version: 1.54"
      WHEN 'h'
        CALL displayUsage(gr, "filename ...")
      WHEN 'H'
        DISPLAY "Got option -H and value arg is ", opt_arg
      WHEN 'B'
        IF opt_arg IS NOT NULL THEN
          DISPLAY "Got option -B and value arg is ", opt_arg
        ELSE
          DISPLAY "Got option -B and no arg"
        END IF
      WHEN 'n'
        DISPLAY "Got option -n and value arg is ", opt_arg
      OTHERWISE
        IF opt_char IS NULL THEN
          DISPLAY "Got long option ", _options[option_index].name
          CASE _options[option_index].name
            WHEN "hello"
              DISPLAY "Got option --hello and arg is ", opt_arg
          END CASE
        END IF
    END CASE
  END WHILE

  IF invalidOptionSeen(gr) THEN # ERROR
    CALL displayUsage(gr, "filename ...")
    EXIT PROGRAM 1
  ELSE
    LET cnt = getMoreArgumentCount(gr)
    IF cnt > 0 THEN
      FOR ind = 1 TO cnt
        DISPLAY SFMT("Additional argument: %1", getMoreArgument(gr, ind))
      END FOR
    END IF
  END IF

END MAIN

#+ Copy the command line arguments into an array of string
#+
#+ @param ind First argument to copy
#+
#+ @return An array of string
PUBLIC FUNCTION copyArguments(ind INTEGER) RETURNS DYNAMIC ARRAY OF STRING
  DEFINE argv DYNAMIC ARRAY OF STRING
  DEFINE i INTEGER
  DEFINE argc INTEGER

  LET argc = 0
  FOR i = ind TO num_args()
    LET argc = argc + 1
    LET argv[argc] = arg_val(i)
  END FOR
  RETURN argv
END FUNCTION

#+ Expand argument list (@file)
#+
#+ @param argv The arguments list to expand
#+
#+ @return An array of string
PRIVATE FUNCTION expandArguments(
  argv DYNAMIC ARRAY OF STRING)
  RETURNS(INTEGER, DYNAMIC ARRAY OF STRING)
  DEFINE rv DYNAMIC ARRAY OF STRING
  DEFINE i INTEGER
  DEFINE argc INTEGER
  DEFINE arg STRING
  DEFINE ch base.Channel
  DEFINE fileName STRING
  DEFINE ln STRING

  LET argc = 0
  FOR i = 1 TO argv.getLength()
    LET arg = argv[i]
    IF arg.substring(1, 1) == '@' THEN
      LET fileName = arg.substring(2, arg.getLength())
      IF NOT os.path.exists(fileName) THEN
        DISPLAY SFMT("getopt: File %1 not found.", fileName)
        RETURN BAD_OPTION, NULL
      END IF
      LET ch = base.Channel.create()
      CALL ch.openFile(fileName, "r")
      WHILE (ln := ch.readLine()) IS NOT NULL
        LET ln = ln.trim()
        IF ln.getLength() > 0 THEN
          LET argc = argc + 1
          LET rv[argc] = ln
        END IF
      END WHILE
      CALL ch.close()
    ELSE
      LET argc = argc + 1
      LET rv[argc] = argv[i]
    END IF
  END FOR

  RETURN SUCCESS, rv
END FUNCTION

#+
#+ Getopt isAnOption method.
#+
#+ This method checks whether a given parameter is an option or not
#+
#+ @param param The parameter string you want to check if it is an option
#+
#+ @return TRUE if parameter is a valid option, FALSE otherwise
#+
PRIVATE FUNCTION isAnOption(gr GetoptR, param STRING) RETURNS BOOLEAN
  # An option must start with - or --
  IF param.getCharAt(1) == '-' THEN
    LET param = param.subString(2, param.getLength())
    IF param.getCharAt(1) == '-' THEN
      # Handle long option
      LET param = param.subString(2, param.getLength())
      IF gr[1]._options.search("name", param) > 0 THEN
        RETURN TRUE # Is a long option
      END IF
    ELSE
      IF param.getLength() == 1 THEN
        # Handle short option
        IF gr[1]._options.search("opt_char", param) > 0 THEN
          RETURN TRUE # Is a short option
        END IF
      END IF
    END IF
  END IF
  RETURN FALSE
END FUNCTION

#+
#+ Getopt object initialization method.
#+
#+ This method initializes the Getopt object by using the program name passed
#+ as parameter, a dynamic array of strings with the arguments to process, and
#+ the definition of the options of the program.
#+
#+ The second parameter (argv) can be used to implement command line syntax
#+ with a verb as first argument:
#+
#+ @code
#+ fglrun myprog capture --verbose --filename=file1
#+ fglrun myprog duplicate --source=file1 --destination=file2
#+
#+ The argv list can be provided with the copyArguments(index) function.
#+
#+ @param prog_name  The name of the program
#+ @param argv       The program arguments
#+ @param options    The GetoptOptions array of options definitions
#+
#+
PUBLIC FUNCTION initialize(
  gr GetoptR,
  prog_name STRING,
  argv DYNAMIC ARRAY OF STRING,
  options GetoptOptions)
  LET gr[1].prog_name = prog_name
  LET gr[1].next_char = NULL
  LET gr[1].opt_ind = 0
  LET gr[1].opt_char = ""
  LET gr[1].opt_arg = NULL
  LET gr[1].status = SUCCESS
  CALL options.copyTo(gr[1]._options)
  CALL expandArguments(argv) RETURNING gr[1].status, gr[1].argv
END FUNCTION

#+
#+ Default Getopt object initialization method.
#+
#+ This method initializes the Getopt object by using arg_val(0) as program
#+ name and starting command line argument processing at index 1.
#+
#+ @param options    The GetoptOptions array of options definitions
#+
PUBLIC FUNCTION initDefault(gr GetoptR, options GetoptOptions)
  CALL initialize(gr, os.Path.baseName(arg_val(0)), copyArguments(1), options)
END FUNCTION

#+
#+ Returns the number of arguments left, which are not part of the options,
#+ or -1 if the options are not yet fully parsed.
#+
#+ @return The number of additional arguments.
#+
PUBLIC FUNCTION getMoreArgumentCount(gr GetoptR) RETURNS INTEGER
  IF gr[1].status == EOF THEN
    RETURN gr[1].argv.getLength() - gr[1].opt_ind + 1
  END IF
  RETURN -1
END FUNCTION

#+
#+ Returns the argument not part of the options, at the specified index.
#+
#+ The index starts at 1, for the first argument after the last option
#+ (The index offset resulting from the used options is taken into account).
#+
#+ Returns NULL if the index is not valid.
#+
#+ @code
#+ LET cnt = g.getMoreArgumentCount()
#+ IF cnt THEN
#+     FOR ind = 1 TO cnt
#+         DISPLAY SFMT("Additional argument: %1", g.getMoreArgument(ind))
#+     END FOR
#+ END IF
#+
#+ @param ind The (offset-adapted) index of the additional argument.
#+
#+ @return The value of the additional argument.
#+
PUBLIC FUNCTION getMoreArgument(gr GetoptR, ind INTEGER) RETURNS STRING
  DEFINE x INTEGER
  LET x = gr[1].opt_ind + ind - 1
  IF x > 0 AND x <= gr[1].argv.getLength() THEN
    RETURN gr[1].argv[x]
  ELSE
    RETURN NULL
  END IF
END FUNCTION

#+
#+ This method can be used while processing command line options with getopt(),
#+ to check if there are more options to be processed.
#+
#+ @return TRUE if the option parsing is done.
#+
PUBLIC FUNCTION isEof(gr GetoptR) RETURNS BOOLEAN
  RETURN gr[1].status == EOF
END FUNCTION

#+
#+ This method can be used after processing the command line arguments with
#+ getopt() in a loop, to check if the processing failed because of an invalid
#+ options.
#+
#+ @return TRUE if the option parsing detected an invalid argument.
#+
PUBLIC FUNCTION invalidOptionSeen(gr GetoptR) RETURNS BOOLEAN
  RETURN gr[1].status == BAD_OPTION
END FUNCTION

#+
#+ This method can be used after processing the command line arguments with
#+ getopt() in a loop, to check if the processing succeeded.
#+
#+ @return TRUE if the option parsing succeeded.
#+
PUBLIC FUNCTION isSuccess(gr GetoptR) RETURNS BOOLEAN
  RETURN gr[1].status == SUCCESS
END FUNCTION

#+
#+ This is the main method to call in a loop, to parse command line arguments
#+ according to the GetoptOptions definitions of the Getopt object.
#+
#+ @code
#+ WHILE g.getopt() == getopt.SUCCESS
#+     CASE g.opt_char
#+         WHEN "v"
#+             DISPLAY "Version: 1.54"
#+             EXIT PROGRAM 0
#+         ...
#+     END CASE
#+ END WHILE
#+
#+ @return The processing status (getopt.SUCCESS | getopt.EOF | getopt.BAD_ARGUMENT)
#+
PUBLIC FUNCTION getopt(gr GetoptR) RETURNS INTEGER
  DEFINE arg STRING

  IF gr[1].status != SUCCESS THEN
    RETURN gr[1].status
  END IF
  IF gr[1].next_char IS NULL THEN
    LET gr[1].opt_ind = gr[1].opt_ind + 1

    # Check if EOF
    IF gr[1].opt_ind > gr[1].argv.getLength() THEN
      RETURN eof(gr)
    END IF

    LET arg = gr[1].argv[gr[1].opt_ind]

    # Parameter is not an option - end of option parsing
    IF arg.getCharAt(1) != '-' THEN
      RETURN eof(gr)
    END IF

    IF arg == "--" THEN
      LET gr[1].opt_ind = gr[1].opt_ind + 1 # Skip -- end of option marker
      RETURN eof(gr)
    END IF

    # Check for long option parameters
    IF arg.getCharAt(2) == '-' THEN
      RETURN parseLong(gr)
    ELSE
      RETURN parseShort(gr)
    END IF
  ELSE
    # Parse concatenated short options
    RETURN parseShort(gr)
  END IF
END FUNCTION

#+
#+ Displays the command line usage of a program.
#+
#+ @param more_args The non option string to add to usage
#+
PUBLIC FUNCTION displayUsage(gr GetoptR, more_args STRING)
  DEFINE ind INTEGER
  DEFINE delta INTEGER
  DEFINE sb base.StringBuffer
  LET sb = base.StringBuffer.create()
  IF more_args IS NOT NULL THEN
    DISPLAY SFMT("Usage: %1 [options] %2\n", gr[1].prog_name, more_args)
  ELSE
    DISPLAY SFMT("Usage: %1 [options]\n", gr[1].prog_name)
  END IF
  IF more_args IS NOT NULL THEN
    DISPLAY "Options:"
  END IF
  FOR ind = 1 TO gr[1]._options.getLength()
    CALL sb.clear()
    IF gr[1]._options[ind].opt_char IS NULL THEN
      CASE gr[1]._options[ind].arg_type
        WHEN NONE
          CALL sb.append(SFMT("    --%1", gr[1]._options[ind].name))
        WHEN OPTIONAL
          CALL sb.append(SFMT("    --%1 [<arg>]", gr[1]._options[ind].name))
        WHEN REQUIRED
          CALL sb.append(SFMT("    --%1 <arg>", gr[1]._options[ind].name))
      END CASE
    ELSE
      CASE gr[1]._options[ind].arg_type
        WHEN NONE
          CALL sb.append(
            SFMT("    -%1, --%2",
              gr[1]._options[ind].opt_char, gr[1]._options[ind].name))
        WHEN OPTIONAL
          CALL sb.append(
            SFMT("    -%1, --%2 [<arg>]",
              gr[1]._options[ind].opt_char, gr[1]._options[ind].name))
        WHEN REQUIRED
          CALL sb.append(
            SFMT("    -%1, --%2 <arg>",
              gr[1]._options[ind].opt_char, gr[1]._options[ind].name))
      END CASE
    END IF
    IF sb.getLength() <= ALIGN_SIZE THEN
      LET delta = ALIGN_SIZE - sb.getLength()
      DISPLAY SFMT("%1%2%3",
        sb.toString(), delta SPACES, gr[1]._options[ind].description)
    ELSE
      DISPLAY SFMT("%1\n%2%3",
        sb.toString(), ALIGN_SIZE SPACES, gr[1]._options[ind].description)
    END IF
  END FOR
END FUNCTION

# Set status to EOF
PRIVATE FUNCTION eof(gr GetoptR) RETURNS INTEGER
  LET gr[1].opt_char = NULL
  LET gr[1].opt_arg = NULL
  LET gr[1].status = EOF
  RETURN gr[1].status
END FUNCTION

# Set status to BAD_OPTION
PRIVATE FUNCTION bad_option(gr GetoptR) RETURNS INTEGER
  LET gr[1].opt_char = NULL
  LET gr[1].opt_arg = NULL
  LET gr[1].status = BAD_OPTION
  RETURN gr[1].status
END FUNCTION

# Parse current argument as a long option name
PRIVATE FUNCTION parseLong(gr GetoptR) RETURNS INTEGER
  DEFINE arg STRING
  DEFINE equal_sign_index INTEGER
  DEFINE ind INTEGER
  DEFINE opt STRING
  DEFINE opt_found INTEGER
  DEFINE arg_key STRING
  DEFINE arg_val STRING
  DEFINE ambiguous BOOLEAN
  DEFINE exact BOOLEAN

  LET arg = gr[1].argv[gr[1].opt_ind]

  # Split arg in key=value or just key
  LET equal_sign_index = arg.getIndexOf("=", 3)
  IF equal_sign_index > 3 THEN
    LET arg_key = arg.subString(3, equal_sign_index - 1)
    LET arg_val = arg.subString(equal_sign_index + 1, arg.getLength())
  ELSE
    LET arg_key = arg.subString(3, arg.getLength())
    LET arg_val = NULL
  END IF

  # Search through all options to get an exact match, a partial match, and ensure
  # partial match is unique or else we have an ambiguous match, which has to be rejected.
  FOR ind = 1 TO gr[1]._options.getLength()
    LET opt = gr[1]._options[ind].name
    IF arg_key.equals(opt) THEN
      LET opt_found = ind
      LET exact = TRUE
      EXIT FOR
    ELSE
      IF opt.getIndexOf(arg_key, 1) > 0 THEN
        IF NOT opt_found THEN
          LET opt_found = ind
        ELSE
          LET ambiguous = TRUE
        END IF
      END IF
    END IF
  END FOR

  IF ambiguous AND NOT exact THEN
    DISPLAY SFMT("%1: ambiguous match: --%2", gr[1].prog_name, arg_key)
    RETURN bad_option(gr)
  END IF

  IF opt_found == 0 THEN
    DISPLAY SFMT("%1: invalid option: --%2", gr[1].prog_name, arg_key)
    RETURN bad_option(gr)
  END IF

  LET gr[1].option_index = opt_found
  # Check for argument value
  IF arg_val IS NOT NULL THEN
    CASE gr[1]._options[opt_found].arg_type
      WHEN NONE
        DISPLAY SFMT("%1: erroneous argument: --%2", gr[1].prog_name, arg_key)
        RETURN BAD_OPTION
      OTHERWISE
        LET gr[1].opt_char = gr[1]._options[opt_found].opt_char
        LET gr[1].opt_arg = arg_val
        RETURN SUCCESS
    END CASE
  END IF

  # Check there is no parameter
  IF gr[1]._options[opt_found].arg_type == NONE THEN
    LET gr[1].opt_char = gr[1]._options[opt_found].opt_char
    LET gr[1].opt_arg = NULL
    RETURN SUCCESS
  ELSE
    # Otherwise optional or required
    IF gr[1].opt_ind + 1 <= gr[1].argv.getLength() THEN
      IF NOT isAnOption(gr, gr[1].argv[gr[1].opt_ind + 1]) THEN
        # Found parameter
        LET gr[1].opt_ind = gr[1].opt_ind + 1
        LET gr[1].opt_char = gr[1]._options[opt_found].opt_char
        LET gr[1].opt_arg = gr[1].argv[gr[1].opt_ind]
        RETURN SUCCESS
      END IF
    END IF
    # Parameter optional, return success
    IF gr[1]._options[opt_found].arg_type == OPTIONAL THEN
      LET gr[1].opt_char = gr[1]._options[opt_found].opt_char
      LET gr[1].opt_arg = NULL
      RETURN SUCCESS
    END IF
  END IF

  DISPLAY SFMT("%1: missing argument: --%2", gr[1].prog_name, arg_key)
  RETURN bad_option(gr)

END FUNCTION

# Parse current argument as a short option name
PRIVATE FUNCTION parseShort(gr GetoptR) RETURNS INTEGER
  DEFINE arg STRING
  DEFINE equal_sign_index INTEGER
  DEFINE ind INTEGER
  DEFINE opt_found INTEGER
  DEFINE arg_key STRING
  DEFINE arg_val STRING

  IF gr[1].next_char IS NULL THEN
    LET arg = gr[1].argv[gr[1].opt_ind]

    # Split arg in key=value or just key
    LET equal_sign_index = arg.getIndexOf("=", 2)
    IF equal_sign_index > 2 THEN
      LET arg_key = arg.subString(2, equal_sign_index - 1)
      LET arg_val = arg.subString(equal_sign_index + 1, arg.getLength())
    ELSE
      LET arg_key = arg.subString(2, arg.getLength())
      IF arg_key.getLength() > 1 THEN
        LET gr[1].next_char = arg_key.subString(2, arg_key.getLength())
        LET arg_key = arg_key.subString(1, 1)
      ELSE
        LET gr[1].next_char = NULL
      END IF
      LET arg_val = NULL
    END IF
  ELSE
    # Parse concatenated short option
    LET arg_key = gr[1].next_char.subString(1, 1)
    IF gr[1].next_char.getLength() > 1 THEN
      LET gr[1].next_char =
        gr[1].next_char.subString(2, gr[1].next_char.getLength())
    ELSE
      LET gr[1].next_char = NULL
    END IF
    LET arg_val = NULL
  END IF

  # Lookup for single char
  FOR ind = 1 TO gr[1]._options.getLength()
    IF arg_key.equals(gr[1]._options[ind].opt_char) THEN
      LET opt_found = ind
      EXIT FOR
    END IF
  END FOR

  IF opt_found == 0 THEN
    DISPLAY SFMT("%1: invalid option character: -%2", gr[1].prog_name, arg_key)
    RETURN bad_option(gr)
  END IF

  LET gr[1].option_index = opt_found
  # Check there is no parameter
  IF gr[1]._options[opt_found].arg_type == NONE THEN
    IF arg_val IS NOT NULL THEN
      DISPLAY SFMT("%1: erroneous argument: -%2", gr[1].prog_name, arg_key)
      RETURN bad_option(gr)
    ELSE
      LET gr[1].opt_char = gr[1]._options[opt_found].opt_char
      LET gr[1].opt_arg = NULL
      RETURN SUCCESS
    END IF
  ELSE
    # Otherwise optional or required
    IF arg_val IS NOT NULL THEN
      LET gr[1].opt_char = gr[1]._options[opt_found].opt_char
      LET gr[1].opt_arg = arg_val
      RETURN SUCCESS
    END IF
    IF gr[1].opt_ind + 1 <= gr[1].argv.getLength() THEN
      IF NOT isAnOption(gr, gr[1].argv[gr[1].opt_ind + 1]) THEN
        # Found parameter
        LET gr[1].opt_ind = gr[1].opt_ind + 1
        LET gr[1].opt_char = gr[1]._options[opt_found].opt_char
        LET gr[1].opt_arg = gr[1].argv[gr[1].opt_ind]
        RETURN SUCCESS
      END IF
    END IF
    # Parameter optional, return success
    IF gr[1]._options[opt_found].arg_type == OPTIONAL THEN
      LET gr[1].opt_char = gr[1]._options[opt_found].opt_char
      LET gr[1].opt_arg = NULL
      RETURN SUCCESS
    END IF
  END IF

  DISPLAY SFMT("%1: missing argument: -%2", gr[1].prog_name, arg_key)
  RETURN bad_option(gr)

END FUNCTION
