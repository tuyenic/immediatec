" Vim syntax file
" Language:	iC
" Maintainer:	John E. Wulff <wulff.johne@gmail.com>
" Last Change:	2007 Apr 11 - 2015 Apr 6 - 2017 Sept 19
" $Id: ic.vim 1.12 $
" for openSUSE ic.vim must be in /usr/share/vim/current/syntax
" NOTE: current -> vim70 for 10.2 and -> v71 for 11.0; vim74 for Leap 4.3
" local filetype.vim must be in ~/.vim (ic.vim does not work there)
" for Raspian copy ic.vim to /usr/share/vim/vim73/syntax/ic.vim

" For version 5.x: Clear all syntax items
" For version 6.x: Quit when a syntax file was already loaded
if version < 600
  syntax clear
elseif exists("b:current_syntax")
  finish
endif

" Read the C syntax to start with
if version < 600
  so <sfile>:p:h/c.vim
else
  runtime! syntax/c.vim
  unlet b:current_syntax
endif

" Error in Debian c.vim causes all lines after (d0 or similar to be a comment - go figure
let c_no_if0 = 1
" This stops #if 0 ... #endif working as a blue highlighted block comment - no great loss

" Accept %% for iCa, % for iC, # for C and line numbers for highlighting listings *.lst (iC vers 3)
syn region	cPreCondit	start="^[0-9\s]*\(%%\|%\|#\)\s*\(if\|ifdef\|ifndef\|elif\)\>" skip="\\$" end="$" end="//"me=s-1 contains=cComment,cCppString,cCharacter,cCppParen,cParenError,cNumbers,cCommentError,cSpaceError
syn match	cPreCondit	display "[0-9\s]*\(%%\|%\|#\)\s*\(else\|endif\)\>"
if !exists("c_no_if0")
  syn region	cCppOut		start="[0-9\s]*\(%%\|#\)\s*if\s\+0\+\>" end=".\@=\|$" contains=cCppOut2
  syn region	cCppOut2	contained start="0" end="[0-9\s]*\(%%\|%\|#\)\s*\(endif\>\|else\>\|elif\>\)" contains=cSpaceError,cCppSkip
  syn region	cCppSkip	contained start="[0-9\s]*\(%%\|%\|#\)\s*\(if\>\|ifdef\>\|ifndef\>\)" skip="\\$" end="[0-9\s]*\(%%\|%\|#\)\s*endif\>" contains=cSpaceError,cCppSkip
endif
syn region	cIncluded	display contained start=+"+ skip=+\\\\\|\\"+ end=+"+
syn match	cIncluded	display contained "<[^>]*>"
syn match	cInclude	display "[0-9\s]*\(%%\|%\|#\)\s*include\>\s*["<]" contains=cIncluded
"syn match cLineSkip	"\\$"
syn cluster	cPreProcGroup	contains=cPreCondit,cIncluded,cInclude,cDefine,cErrInParen,cErrInBracket,cUserLabel,cSpecial,cOctalZero,cCppOut,cCppOut2,cCppSkip,cFormat,cNumber,cFloat,cOctal,cOctalError,cNumbersCom,cString,cCommentSkip,cCommentString,cComment2String,@cCommentGroup,cCommentStartError,cParen,cBracket,cMulti
syn region	cDefine		start="[0-9\s]*\(%%\|%\|#\)\s*\(define\|undef\)\>" skip="\\$" end="$" end="//"me=s-1 contains=ALLBUT,@cPreProcGroup,@Spell
syn region	cPreProc	start="[0-9\s]*\(%%\|%\|#\)\s*\(pragma\>\|line\>\|warning\>\|warn\>\|error\>\)" skip="\\$" end="$" keepend contains=ALLBUT,@cPreProcGroup,@Spell

" iC extentions
syn keyword icStatement		this use no alias strict
syn keyword icStatement		iClock
syn keyword icType		bit clock timer iC_Gt Gate
syn match icIO			"\<\(I\|Q\|T\)X\([0-9][0-9]*\)\.\([0-7]\)\(_[0-9][0-9]*\)*\>"
syn match icIO			"\<\(I\|Q\)\(B\|W\|L\)\([0-9][0-9]*\)\(_[0-9][0-9]*\)*\>"
syn match icLineNumber		"^\d\d*"
syn match icType		"@"
syn match icSep			"%{"
syn match icSep			"%}"
syn match icSep			"^\*\*\* Warning\i*:"
syn match icSep			"^\/\/\* Warning\i*:"
syn match icError		"^\*\*\* Error\i*:"
syn match icError		"^\/\/\* Error\i*:"
syn match icError		"^\*\*\* .*syntax error"
syn match icError		"\m---?\M"
syn match icError		"? ---\&?"
syn keyword icStorageClass	assign
syn keyword icStructure		imm immC
syn keyword icBoolean		LO HI
syn match icConstant		"D\s*(\&D"
syn match icConstant		"SH\s*(\&SH"
syn keyword icConstant		DR_ DS_ DSR_ SHR_ SHSR_ CHANGE RISE SR SR_ SRR SRR_ CLOCK TIMER TIMER1 FORCE
syn keyword icConstant		SHR SHSR ST SRT SRX JK DR DS DSR FALL LATCH DLATCH EOI STDIN

" iCa extentions
syn keyword icRepeat		FOR IF ELSIF ELSE

" Default highlighting
if version >= 508 || !exists("did_ic_syntax_inits")
  if version < 508
    let did_ic_syntax_inits = 1
    command -nargs=+ HiLink hi link <args>
  else
    command -nargs=+ HiLink hi def link <args>
  endif
  HiLink icStatement		Statement
  HiLink icType			Type
  HiLink icStorageClass		StorageClass
  HiLink icStructure		Structure
  HiLink icNumber		Number
  HiLink icConstant		Macro
  HiLink icIO			Constant
  HiLink icBoolean		Boolean
  HiLink icLineNumber		Comment
  HiLink icSep			Todo
  HiLink icError		Error
  HiLink icRepeat		Repeat
  delcommand HiLink
endif

let b:current_syntax = "ic"

" vim: ts=8
