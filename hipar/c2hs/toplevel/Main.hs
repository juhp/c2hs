--  C -> Haskell Compiler: main module
--
--  Author : Manuel M. T. Chakravarty
--  Derived: 12 August 99
--
--  Version $Revision: 1.12 $ from $Date: 2001/05/02 13:14:44 $
--
--  Copyright (c) [1999..2001] Manuel M. T. Chakravarty
--
--  This file is free software; you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation; either version 2 of the License, or
--  (at your option) any later version.
--
--  This file is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--- DESCRIPTION ---------------------------------------------------------------
--
--  This is the main module of the compiler.  It sets the version, processes
--  the command line arguments, and controls the compilation process.
--
--  Originally, derived from `Main.hs' of the Nepal Compiler.
--
--- DOCU ----------------------------------------------------------------------
--
--  language: Haskell 98
--
--  Usage:
--  ------
--
--    c2hs [ option... ] header-file binding-file
--
--  The compiler is supposed to emit a Haskell program that expands all hooks
--  in the given binding file.
--
--  File name suffix:
--  -----------------
--
--  Note: These also depend on suffixes defined in the compiler proper.
--
--  .h   C header file
--  .i   pre-processeed C header file
--  .hs	 Haskell file
--  .chs Haskell file with Haskell->C hooks (binding file)
--
--  Options:
--  --------
--
--  -C CPPOPTS
--  --cppopts=CPPOPTS
--        Pass the additional options CPPOPTS to the C preprocessor.
--
--        Repeated occurences accumulate.
--
--  -c CPP
--  --cpp=CPP
--        Use the executable CPP to invoke CPP.
--
--        In the case of repeated occurences, the last takes effect.
--
--  -d TYPE
--  --dump=TYPE
--        Dump intermediate representation:
--
--	  + if TYPE is `trace', trace the compiler phases (to stderr)
--	  + if TYPE is `genbind', trace binding generation (to stderr)
--	  + if TYPE is `chs', dump the binding file (insert `.dump' into the
--	    file name to avoid overwriting the original file)
--
--  -h, -?
--  --help
--        Dump brief usage information to stderr.
--
--  -k
--  --keep
--        Keep the intermediate file that contains the pre-processed C header
--        (it end with `.i').
--
--  -o FILE
--  --output=FILE
--        Place output in file FILE.
--
--        If `-o' is not specified, the default is to put the output for
--	  `source.chs' in `source.hs'.
--
--  -v,
--  --version
--        Print (on standard error output) the version and copyright
--	  information of the compiler (before doing anything else).
--
--
--  --old-ffi [=yes|=no]
--	  Generate hooks using pre-standard FFI libraries.  This currently
--	  affects only call hooks where instead of `Addr' types 
--	  `Ptr <someOtherType>' is used.
--
--- TODO ----------------------------------------------------------------------
--

module Main (main)
where

import List	  (isPrefixOf)
import Monad      (when, unless)

import Common     (errorCodeFatal)
import GetOpt     (ArgOrder(..), OptDescr(..), ArgDescr(..), usageInfo,
		   getOpt)
import FNameOps   (suffix, basename, stripSuffix)
import Errors	  (interr)

import C2HSState  (CST, nop, runC2HS, fatal, fatalsHandledBy, getId,
		   ExitCode(..), stderr, putStrCIO, hPutStrCIO, hPutStrLnCIO,
		   exitWithCIO, getArgsCIO, getProgNameCIO, ioeGetErrorString,
		   ioeGetFileName, removeFileCIO, systemCIO, fileFindInCIO,
		   SwitchBoard(..), Traces(..), setTraces, traceSet,
		   setSwitch, getSwitch, putTraceStr)
import C	  (AttrC, hsuffix, isuffix, loadAttrC)
import CHS	  (CHSModule, loadCHS, dumpCHS, hssuffix, chssuffix)
import GenBind	  (expandHooks)
import Version    (version, copyright, disclaimer)
import C2HSConfig (cpp, cppopts, hpaths)


-- wrapper running the compiler
-- ============================

main :: IO ()
main  = runC2HS (version, copyright, disclaimer) compile


-- option handling
-- ===============

-- header is output in case of help, before the descriptions of the options;
-- errTrailer is output after an error message
--
header :: String -> String -> String -> String
header version copyright disclaimer  = 
  version ++ "\n" ++ copyright ++ "\n" ++ disclaimer
  ++ "\n\nUsage: c2hs [ option... ] header-file binding-file\n"

trailer, errTrailer :: String
trailer    = "\n\
	     \The header file must be a C header file matching the given \
	     \binding file.\n\
	     \The dump TYPE can be\n\
	     \  trace   -- trace compiler phases\n\
	     \  chs     -- dump the binding file (adds `.dump' to the name)\n"
errTrailer = "Try the option `--help' on its own for more information.\n"

-- supported option types
--
data Flag = CPPOpts String      -- additional options for C preprocessor
	  | CPP     String      -- program name of C preprocessor
	  | Dump    DumpType    -- dump internal information
	  | Help	        -- print brief usage information
	  | Keep	        -- keep the .i file
	  | Output  String      -- file where the generated file should go
	  | Version	        -- print version information on stderr
	  | OldFFI  Bool	-- use the pre-standard FFI (pre-GHC 4.11)
	  | Error   String      -- error occured during processing of options
	  deriving Eq

data DumpType = Trace	      -- compiler trace
	      | GenBind	      -- trace `GenBind'
	      | CHS	      -- dump binding file
	      deriving Eq

-- option description suitable for `GetOpt'
--
options :: [OptDescr Flag]
options  = [
  Option ['C'] 
	 ["cppopts"] 
	 (ReqArg CPPOpts "CPPOPTS") 
	 "pass CPPOPTS to the C preprocessor",
  Option ['c'] 
	 ["cpp"] 
	 (ReqArg CPP "CPP") 
	 "use executable CPP to invoke C preprocessor",
  Option ['d'] 
	 ["dump"] 
	 (ReqArg dumpArg "TYPE") 
	 "dump internal information (for debugging)",
  Option ['h', '?'] 
	 ["help"] 
	 (NoArg Help) 
	 "brief help (the present message)",
  Option ['k'] 
	 ["keep"] 
	 (NoArg Keep) 
	 "keep pre-processed C header",
  Option ['o'] 
	 ["output"] 
	 (ReqArg Output "FILE") 
	 "output result to FILE (should end in .hs)",
  Option ['v'] 
	 ["version"] 
	 (NoArg Version) 
	 "show version information",
  Option []
	 ["old-ffi"]
	 (OptArg oldFFISwitch "OLDFFI")
	 "use the FFI without `Ptr a'"]

-- convert argument of `Dump' option
--
dumpArg           :: String -> Flag
dumpArg "trace"    = Dump Trace
dumpArg "genbind"  = Dump GenBind
dumpArg "chs"      = Dump CHS
dumpArg _          = Error "Illegal dump type."

-- convert argument of `old-ffi' option
--
oldFFISwitch              :: Maybe String -> Flag
oldFFISwitch (Just "yes")  = OldFFI True
oldFFISwitch (Just "no" )  = OldFFI False
oldFFISwitch Nothing       = OldFFI True
oldFFISwitch _		   = 
  Error "Please supply either `yes' or `no' to the `--old-ffi' option."

-- main process (set up base configuration, analyse command line, and execute
-- compilation process)
--
-- * Exceptions are caught and reported
--
compile :: CST s ()
compile  = 
  do
    setup
    cmdLine <- getArgsCIO
    case getOpt RequireOrder options cmdLine of
      ([Help]   , []  , []) -> doExecute [Help]    []
      ([Version], []  , []) -> doExecute [Version] []
      (opts     , args, []) 
        | properArgs args -> doExecute opts args
        | otherwise       -> raiseErrs [wrongNoOfArgsErr]
      (_   , _   , errs)  -> raiseErrs errs
  where
    properArgs [header, bnd] = suffix header == hsuffix 
			       && suffix bnd == chssuffix 
    properArgs _             = False
    --
    doExecute opts args = do
			    execute opts args
			      `fatalsHandledBy` failureHandler
			    exitWithCIO ExitSuccess
    --
    wrongNoOfArgsErr = "There must be exactly one header file (suffix .h)\n\
		       \followed by exactly one binding file (suffix .chs).\n"
    --
    -- exception handler
    --
    failureHandler err =
      do
	let msg   = ioeGetErrorString err
	    fnMsg = case ioeGetFileName err of
		       Nothing -> ""
		       Just s  -> " (file: `" ++ s ++ "')"
	hPutStrLnCIO stderr (msg ++ fnMsg)
	exitWithCIO $ ExitFailure 1

-- set up base configuration
--
setup :: CST s ()
setup  = do
	   setCPP     cpp
	   addCPPOpts cppopts
	   addHPaths  hpaths

-- output error message
--
raiseErrs      :: [String] -> CST s a
raiseErrs errs = do
		   hPutStrCIO stderr (concat errs)
		   hPutStrCIO stderr errTrailer
		   exitWithCIO $ ExitFailure 1

-- Process tasks
-- -------------

-- execute the compilation task
--
-- * if `Help' is present, emit the help message and ignore the rest
-- * if `Version' is present, do it first (and only once)
-- * actual compilation is only envoked if we have two extra arguments
--   (otherwise, it is just skipped)
--
execute :: [Flag] -> [FilePath] -> CST s ()
execute opts args | Help `elem` opts = help
		  | otherwise	     = 
  do
    let vs      = filter (== Version) opts
	opts'   = filter (/= Version) opts
    mapM_ processOpt (atMostOne vs ++ opts')
    when (length args == 2) $
      let [headerFile, bndFile] = args
      in
      process headerFile (stripSuffix bndFile)
	`fatalsHandledBy` 
	  \ioerr -> do
		      name <- getProgNameCIO
		      putStrCIO $
		        name ++ ": " ++ ioeGetErrorString ioerr ++ "\n"
		      exitWithCIO $ ExitFailure 1
  where
    atMostOne = (foldl (\_ x -> [x]) [])

-- emit help message
--
help :: CST s ()
help  = do
	  (version, copyright, disclaimer) <- getId
	  putStrCIO (usageInfo (header version copyright disclaimer) options)
	  putStrCIO trailer

-- process an option
--
-- * `Help' cannot occur 
--
processOpt                   :: Flag -> CST s ()
processOpt (CPPOpts cppopts)  = addCPPOpts cppopts
processOpt (CPP     cpp    )  = setCPP     cpp
processOpt (Dump    dt     )  = setDump    dt
processOpt (Keep           )  = setKeep
processOpt (Output  fname  )  = setOutput  fname
processOpt Version            = do
			          (version, _, _) <- getId 
			          putStrCIO (version ++ "\n")
processOpt (OldFFI  flag   )  = setOldFFI  flag
processOpt (Error   msg    )  = abort      msg

-- emit error message and raise an error
--
abort     :: String -> CST s ()
abort msg  = do
	       hPutStrLnCIO stderr msg
	       hPutStrCIO stderr errTrailer
	       fatal "Error in command line options"


-- set switches
-- ------------

-- set the options for the C proprocessor
--
-- * any header search path that is set with `-IDIR' is also added to
--   `hpathsSB'
--
addCPPOpts      :: String -> CST s ()
addCPPOpts opts  = 
  do
    let iopts = [opt |opt <- words opts, "-I" `isPrefixOf` opt, "-I-" /= opt]
    addHPaths . map (drop 2) $ iopts
    addOpts opts
  where
    addOpts opts  = setSwitch $ 
		      \sb -> sb {cppOptsSB = cppOptsSB sb ++ (' ':opts)}

-- set the program name of the C proprocessor
--
setCPP       :: FilePath -> CST s ()
setCPP fname  = setSwitch $ \sb -> sb {cppSB = fname}

-- add header file search paths
--
addHPaths       :: [FilePath] -> CST s ()
addHPaths paths  = setSwitch $ \sb -> sb {hpathsSB = paths ++ hpathsSB sb}

-- set the given dump option
--
setDump         :: DumpType -> CST s ()
setDump Trace    = setTraces $ \ts -> ts {tracePhasesSW  = True}
setDump GenBind  = setTraces $ \ts -> ts {traceGenBindSW = True}
setDump CHS      = setTraces $ \ts -> ts {dumpCHSSW	 = True}

-- set flag to keep the pre-processed header file
--
setKeep :: CST s ()
setKeep  = setSwitch $ \sb -> sb {keepSB = True}

-- set the output file name
--
setOutput       :: FilePath -> CST s ()
setOutput fname  = do
		     when (suffix fname /= hssuffix) $
		       raiseErrs ["Output file should end in .hs!\n"]
		     setSwitch $ \sb -> sb {outputSB = stripSuffix fname}

-- set flag wether or not to use the old pre-GHC-5.00 FFI without `Ptr a'
--
setOldFFI      :: Bool -> CST s ()
setOldFFI flag  = setSwitch $ \sb -> sb {oldFFI = flag}


-- compilation process
-- -------------------

process                    :: FilePath -> FilePath -> CST s ()
process headerFile bndFile  =
  do
    let preprocFile  = basename headerFile ++ isuffix
    hpaths          <- getSwitch hpathsSB
    realHeaderFile  <- headerFile `fileFindInCIO` hpaths
    --
    -- run C preprocessor over the header
    --
    cpp     <- getSwitch cppSB
    cppOpts <- getSwitch cppOptsSB
    let cmd  = unwords [cpp, cppOpts, realHeaderFile, ">" ++ preprocFile]
    tracePreproc cmd
    exitCode <- systemCIO cmd
    case exitCode of 
      ExitFailure _ -> fatal "Error during preprocessing"
      _		    -> nop
    --
    -- load and analyse the C header file
    --
    (cheader, warnmsgs) <- loadAttrC preprocFile
    putStrCIO warnmsgs
    --
    -- remove the pre-processed header
    --
    keep <- getSwitch keepSB
    unless keep $
      removeFileCIO preprocFile
    --
    -- load the Haskell binding module
    --
    (chsMod , warnmsgs) <- loadCHS bndFile
    putStrCIO warnmsgs
    traceCHSDump chsMod
    --
    -- expand binding hooks into plain Haskell
    --
    (hsMod  , warnmsgs) <- expandHooks cheader chsMod
    putStrCIO warnmsgs
    --
    -- output the result
    --
    outFName <- getSwitch outputSB
    let hsFile = if null outFName then basename bndFile else outFName
    dumpCHS hsFile hsMod True
  where
    tracePreproc cmd = putTraceStr tracePhasesSW $
		         "Invoking cpp as `" ++ cmd ++ "'...\n"
    traceCHSDump mod = do
			 flag <- traceSet dumpCHSSW
			 when flag $
			   (do
			      putStrCIO ("...dumping CHS to `" ++ chsName 
					 ++ "'...\n")
			      dumpCHS chsName mod False)

    chsName = basename bndFile ++ ".dump"