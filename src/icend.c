static const char icend_c[] =
"@(#)$Id: icend.c,v 1.1 2008/02/25 16:40:54 jw Exp $";
/********************************************************************
 *
 *	Copyright (C) 1985-2005  John E. Wulff
 *
 *  You may distribute under the terms of either the GNU General Public
 *  License or the Artistic License, as specified in the README file.
 *
 *  For more information about this program, or for information on how
 *  to contact the author, see the README file or <john@je-wulff.de>
 *
 *	icend.c
 *	parallel plc - dummy termination routine
 *
 *******************************************************************/

/********************************************************************
 *  The following initialisation function is one of two empty functions
 *  in the libict.a support library. The other is iCbegin().
 *  Either or both may be implemented in a literal block in iC source(s),
 *  in which case those function will be linked in preference.
 *******************************************************************/

/********************************************************************
 *  iCend() can be used to free allocated memory etc.
 *******************************************************************/

int
iCend(void)				/* default termination function */
{
    return 0;				/* does nothing */
} /* iCend */
