module BaseVersion (version, copyright, disclaimer)
where

-- version number is major.minor.patchlvl; don't change the format of the
-- `versnum' line as it is `grep'ed for by a Makefile
--
idstr      = "$Id: BaseVersion.hs,v 1.32 2001/04/29 12:23:46 chak Exp $"
name       = "Compiler Toolkit"
versnum    = "0.22.3"
date	   = "21 Apr 2001"
version    = name ++ ", version " ++ versnum ++ ", " ++ date
copyright  = "Copyright (c) [1995..2001] Manuel M. T. Chakravarty"
disclaimer = "This software is distributed under the \
	     \terms of the GNU Public Licence.\n\
	     \NO WARRANTY WHATSOEVER IS PROVIDED. \
	     \See the details in the documentation."