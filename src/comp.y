%{ static const char comp_y[] =
"@(#)$Id: comp.y,v 1.85 2004/02/24 09:06:22 jw Exp $";
/********************************************************************
 *
 *	Copyright (C) 1985-2001  John E. Wulff
 *
 *  You may distribute under the terms of either the GNU General Public
 *  License or the Artistic License, as specified in the README file.
 *
 *  For more information about this program, or for information on how
 *  to contact the author, see the README file or <john@je-wulff.de>
 *
 *	comp.y
 *	grammar for icc compiler
 *
 *******************************************************************/

#include	<stdio.h>
#include	<stdlib.h>
#include	<unistd.h>
#include	<string.h>
#include	<ctype.h>
#include	<setjmp.h>
#include	<assert.h>

#include	"icg.h"
#include	"icc.h"
#include	"comp.h"

/* "comp.y	3.70	95/02/03 Copyright (c) 1985-1993 by John E. Wulff" */

static void	unget(int);		/* shares buffers with get() */
static long	getNumber(void);	/* shares buffers with get() */
static int	iClex(void);
int		ynerrs;			/* count of yyerror() calls */
		/* NOTE iCnerrs is reset for every call to yaccpar() */
static int	copyCfrag(char, char, char);	/* copy C action */
static unsigned char ccfrag;		/* flag for CCFRAG syntax */
static unsigned int stype;		/* to save TYPE in decl */
static Val	val1 = { 0, 0, 1, };	/* preset off 1 value for TIMER1 */
static Symbol	tSym = { "_tSym_", AND, GATE, };
#ifndef EFENCE
char		iCbuf[IMMBUFSIZE];	/* buffer to build imm statement */
char		iFunBuffer[IBUFSIZE];	/* buffer to build imm function symbols */
char *		iFunEnd = &iFunBuffer[IBUFSIZE];	/* pointer to end */
#else		/* malloc for EFENCE in main() */
char *		iCbuf;			/* buffer to build imm statement */
char *		iFunBuffer;		/* buffer to build imm function symbols */
char *		iFunEnd;		/* pointer to end */
#endif	/* EFENCE */
char *		iFunSymExt = 0;		/* pointer to imm function symbol Extension */
static char *	iFunSyText = 0;		/* pointer to function symbol text when active */
Sym		iRetSymbol;		/* .v is pointer to imm function return Symbol */
static char *	stmtp;			/* manipulated in iClex() only */
static void	clrBuf(void);
%}

%union {		/* stack type */
    Sym		sym;			/* symbol table pointer */
    Lis		list;			/* linked list elements */
    Val		val;			/* int numerical values */
    Str		str;			/* one character array */
    /* allows storing character as iClval.val.v (2nd byte is NULL) */
    /* then char array can be referenced as $1.v, single char as $1.v[0] */
}

%{
static void
clrBuf(void)
{
    stmtp = iCbuf;
#if YYDEBUG
    if ((debug & 0402) == 0402) {
	memset(iCbuf, '\0', IMMBUFSIZE);
    }
#endif
} /* clrBuf */

#if YYDEBUG
void
pu(int t, char * token, Lis * node)
{
    char *	t_first;
    int		len;

    switch (t) {
    case 0:
	if (node->v) {
	    fprintf(outFP, ">>>Sym	%s	%s :	", token, ((Sym*)node)->v->name);
	} else {
	    fprintf(outFP, ">>>Sym	%s	0 =	", token);
	}
	break;
    case 1:
	if (node->v) {
	    fprintf(outFP, ">>>Lis	%s	%s =	", token, node->v->le_sym->name);
	} else {
	    fprintf(outFP, ">>>Lis	%s	0 =	", token);
	}
	break;
    case 2:
	fprintf(outFP, ">>>Val	%s	%d =	", token, ((Val*)node)->v);
	break;
    case 3:
	fprintf(outFP, ">>>Str	%s	%2.2s =	", token, ((Str*)node)->v);
	break;
    }
    if ((t_first = node->f) != 0 && (len = node->l - t_first) != 0) {
	assert(t_first >= iCbuf && node->l < &iCbuf[IMMBUFSIZE]);
	fprintf(outFP, "%-*.*s\n", len, len, t_first);
    } else {
	fprintf(outFP, "\n");
    }
    fflush(outFP);
} /* pu */

static void
pd(const char * token, Symbol * ss, unsigned int s1, Symbol * s2)
{
    fprintf(outFP, ">>>%s\t%s\t[%c%c %c] [%c%c %c] => [%c%c %c]\n",
	token, s2->name,
	/* single character for type, . normal or - external, ftype */
	os[(s1 >>8)&TM], os[!!((s1 >>8)&EM)], fos[s1 & 0xff],
	os[s2->type&TM], os[!!(s2->type&EM)], fos[s2->ftype],
	os[ss->type&TM], os[!!(ss->type&EM)], fos[ss->ftype]);
    fflush(outFP);
} /* pd */

#endif
%}

	/************************************************************
	 *
	 * iC token types
	 *
	 ***********************************************************/

%token	<sym>	UNDEF AVARC AVAR LVARC LVAR AOUT LOUT BLATCH BFORCE DLATCH
%token	<sym>	BLTIN1 BLTIN2 BLTIN3 BLTINJ BLTINT CVAR CBLTIN TVAR TBLTIN TBLTI1
%token	<sym>	IF ELSE SWITCH EXTERN ASSIGN RETURN IMM VOID TYPE
%token	<sym>	IFUNCTION CFUNCTION TFUNCTION VFUNCTION
%token	<val>	NUMBER CCFRAG
%token	<str>	LEXERR COMMENTEND LHEAD
%type	<sym>	program statement funcStatement simpleStatement iFunDef iFunHead
%type	<sym>	returnStatement formalParameter lBlock variable valueVariable outVariable
%type	<sym>	decl extDecl asgn dasgn casgn dcasgn tasgn dtasgn
%type	<sym>	iFunTrigger vFunCall vFunCallHead iFunCallHead cFunCallHead tFunCallHead
%type	<list>	expr aexpr lexpr fexpr cexpr cfexpr texpr actexpr tfexpr ifini ffexpr
%type	<list>	cref ctref ctdref cCall cParams cPlist
%type	<list>	fParams fPlist funcBody iFunCall cFunCall tFunCall rParams rPlist
%type	<val>	cBlock declHead extDeclHead formalParaTypeDecl
%type	<str>	'{' '[' '(' '"' '\'' ')' ']' '}' /* C/C++ brackets */
%right	<str>	','		/* function seperator */
%right	<str>	'=' OPE
%right	<str>	'?' ':'		/* ? : */
%right	<str>	OO		/* || */
%right	<str>	AA 		/* && */
%right	<str>	'|'		/* logical or */
%right	<str>	'^'		/* logical exclusive or */
%right	<str>	'&'		/* logical and */
%right	<str>	CMP		/* compare operators == != < <= > >= */
%right	<str>	AOP PM '*'	/* arithmetic operators << >> / % + - * */
%nonassoc <str>	NOTL PPMM	/* unary operators ! ~ ++ -- (+ - & *) */
%right	<str>	PR 		/* structure operators -> . */
%%

	/************************************************************
	 *
	 * iC grammar
	 *
	 ***********************************************************/

program	: /* nothing */		{ $$.v = 0;  clrBuf(); }
	| program statement	{ $$   = $2; clrBuf(); }
	| program error ';'	{ $$.v = 0;  clrBuf(); iclock->type = ERR; yyerrok; }
	;

statement
	: ';'			{ $$.v = 0;  }		/* empty statement */
	| simpleStatement ';'	{ $$   = $1; }		/* immediate statement */
	| ffexpr		{ $$.v = op_asgn(0, &$1, GATE); } /* if or switch */
			    /* op_asgn(0,...) returns 0 for missing slave gate in ffexpr */
	| iFunDef		{ $$   = $1; }		/* immediate function definition */
	| lBlock		{ $$.v = 0;  }		/* literal block */
	;

funcStatement
	: ';'			{ $$.v = 0;  }		/* empty statement */
	| simpleStatement ';'	{ $$   = $1; }		/* immediate statement */
	| returnStatement ';'	{ $$   = $1;		/* function return statement */
	    collectStatement($1.v);
	}
	;

simpleStatement
	: extDecl		{ $$   = $1; }		/* external declaration */
	| decl			{ $$   = $1; }		/* immediate declararion */
	| asgn			{ $$   = $1; }		/* immediate value assignment */
	| dasgn			{ $$   = $1; }		/* declaration assignment */
	| casgn			{ $$   = $1;		/* clock assignment */
	    if (iFunSymExt) collectStatement($1.v); }
	| dcasgn		{ $$   = $1;		/* declararion clock assignment */
	    if (iFunSymExt) collectStatement($1.v); }
	| tasgn			{ $$   = $1;		/* timer assignment */
	    if (iFunSymExt) collectStatement($1.v); }
	| dtasgn		{ $$   = $1;		/* declararion timer assignment */
	    if (iFunSymExt) collectStatement($1.v); }
	| vFunCall		{ $$   = $1; }		/* void function call */
	;

variable
	: valueVariable		{ $$   = $1; }		/* value variable */
	| outVariable		{ $$   = $1; }		/* output variable */
	| CVAR			{ $$   = $1; }		/* clock variable */
	| TVAR			{ $$   = $1; }		/* timer variable */
	;

valueVariable
	: LVAR			{ $$   = $1; }		/* logical bit variable */
	| AVAR			{ $$   = $1; }		/* arithmetic variable */
	;

outVariable
	: LOUT			{ $$   = $1; }		/* output bit variable */
	| AOUT			{ $$   = $1; }		/* output arith. variable */
	;

	/************************************************************
	 *
	 * Extern type declarations - no assignment in the same source
	 *
	 *	extern imm bit   b1;	extern imm int   a1;
	 *	extern imm clock c1;	extern imm timer t1;
	 *
	 * The extern type declaration in iC declares that an immediate
	 * variable has been assigned in another module and may be used
	 * as an rvalue in immediate expressions in this module.
	 *
	 * Because of the single assignment rule, such an extern immediate
	 * variable may normally not be assigned in this module.
	 * To allow lists of extern immediate declarations of all variables
	 * in a common include file, a simple immediate type declaration
	 * after the extern immediate declaration (or after the #include
	 * statement containing the extern immeditate type declaration)
	 * declares that this variable will be assigned in the current
	 * module and must be assigned in this module. The type (bit, int,
	 * clock or timer) must match the type used previously in the
	 * extern declaration.
	 *
	 * An extern type declaration of a particular variable may not
	 * occurr after its simple declaration or its assignment.
	 *
	 * If a variable is declared extern in several sources which will
	 * later be linked and that variable is erroneously declared and
	 * assigned, either in immediate assignments or C assignments in
	 * more than one source module, a linker error will occurr.
	 * (Multiple definition of the variable in C code).
	 *
	 * See use of extern type declaration in a function definition
	 * under 'Immediate functions' below.
	 * In particulat iFunSyText is not set for an extDecl and thus the
	 * variables declared extern keep their unchanged global names.
	 *
	 * If an extDecl occurrs in a function definition, a check is made
	 * that the name does not clash with one of the local names in the
	 * function.
	 *
	 ***********************************************************/

extDecl	: extDeclHead UNDEF	{
		$$.v = $2.v;
		$$.v->ftype = $1.v & 0xff;
		$$.v->type = $1.v >> 8;		/* has EM set from extDeclHead */
#if YYDEBUG
		if ((debug & 0402) == 0402) {
		    Symbol t = *($2.v);
		    pd("extDecl", $$.v, $1.v, &t);
		}
#endif
	    }
	| extDeclHead variable	{
		char *	cp;

		if ($2.v->ftype != ($1.v & 0xff)) {
		    ierror("extern declaration does not match previous declaration:", $2.v->name);
		    $2.v->type = ERR;	/* cannot execute properly */
		}
		$$.v = $2.v;
		if (iFunSymExt && (cp = strchr($2.v->name, '$'))) {
		    warning("extern declaration of internal function variable - ignored:", cp+1);
		} else
		if (($2.v->type & EM) || $2.v->type == UDF) {	/* QXx.y QBz */
		    $$.v->ftype = $1.v & 0xff;
		    $$.v->type = $1.v >> 8;	/* has EM set from extDeclHead */
		} else
		if (iFunSymExt) {
		    ierror("extern declaration in function definition after assignment:", $2.v->name);
		    $$.v->type = ERR | EM;	/* stop use as a statement in function */
		} else
		if ($2.v->type != INPW && $2.v->type != INPX) {
		    warning("extern declaration after assignment - ignored:", $2.v->name);
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) {
		    Symbol t = *($2.v);
		    pd("extDecl", $$.v, $1.v, &t);
		}
#endif
	    }
	;

extDeclHead
	: EXTERN IMM TYPE	{
		int	ftyp;
		ftyp = $3.v->ftype;
		if (ftyp >= CLCKL) {		/* check that CLCKL TIMRL */
		    ftyp -= CLCKL - CLCK;	/* and CLCK and TIMR are adjacent */
		}
		$$.v = stype = $3.v->ftype | ((types[ftyp] | EM) << 8);
	    }
	| extDecl ','		{ $$.v = stype;	/* first TYPE */ }
	;

	/************************************************************
	 *
	 * Immediate type declaration - may be combined with dasgn
	 *
	 *	imm bit   b1;		imm int   a1;
	 *	imm clock c1;		imm timer t1;
	 *
	 * Multiple declarations of the same variable with the same
	 * immediate type are silently ignored. If correctly declared
	 * after an assignment a warning is still issued, except for
	 * input variables which are never assigned, rather predeclared.
	 *
	 ***********************************************************/

decl	: declHead UNDEF	{
#if YYDEBUG
		Symbol t = *($2.v);
#endif
		$$.f = $1.f; $$.l = $2.l;
		$$.v = $2.v;
		$$.v->ftype = $1.v & 0xff;	/* TYPE bit int clock timer */
		$$.v->type = $1.v >> 8;		/* UDF for all TYPEs */
		if (iFunSymExt) {
		    char *	cp;
		    Symbol *	sp;
		    cp = strchr($2.v->name, '$'); /* locate original extension */
		    assert(cp && isprint(cp[1])); /* extension must be at least 1 character */
		    if ((sp = lookup(++cp)) != 0 && (sp->type & EM)) {
			warning("function declaration of an extern variable - ignored:", cp);
		    }
		    collectStatement($2.v);
		    iFunSyText = 0;		/* no more function symbols */
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pd("decl", $$.v, $1.v, &t);
#endif
	    }
	| declHead variable	{
#if YYDEBUG
		Symbol t = *($2.v);
#endif
		$$.f = $1.f; $$.l = $2.l;
		if ($2.v->ftype != ($1.v & 0xff)) {
		    ierror("declaration does not match previous declaration:", $2.v->name);
		    $2.v->type = ERR;	/* cannot execute properly */
		}
		$$.v = $2.v;
		if (($2.v->type & EM) || $2.v->type == UDF) {
		    $$.v->ftype = $1.v & 0xff;	/* TYPE bit int clock timer */
		    $$.v->type = $1.v >> 8;	/* UDF for all TYPEs */
		} else if ($2.v->type != INPW && $2.v->type != INPX) {
		    warning("declaration after assignment - ignored:", $2.v->name);
		}
		iFunSyText = 0;			/* no more function symbols */
#if YYDEBUG
		if ((debug & 0402) == 0402) pd("decl", $$.v, $1.v, &t);
#endif
	    }
	;

declHead
	: IMM TYPE		{
		$$.f = $$.l = $2.l;		/* do not include in expression string */
		$$.v = stype = $2.v->ftype | UDF << 8;
		if (iFunSymExt) {
		    iFunSyText = iFunBuffer;	/* expecting a new function symbol */
		}
	    }
	| decl ','		{
		$$.f = $1.f; $$.l = $1.l;
		$$.v = stype;			/* first TYPE */
		if (iFunSymExt) {
		    iFunSyText = iFunBuffer;	/* expecting a new function symbol */
		}
	    }
	| dasgn ','		{
		$$.f = $1.f; $$.l = $1.l;
		$$.v = stype;			/* first TYPE */
		if (iFunSymExt) {
		    iFunSyText = iFunBuffer;	/* expecting a new function symbol */
		}
	    }
	;

	/************************************************************
	 *
	 * Assignment combined with a declaration
	 * an output can only be recognised by its name: Q[XBWL]%d
	 *
	 ***********************************************************/

dasgn	: decl '=' aexpr	{			/* dasgn is NOT an aexpr */
		unsigned char	y1[2];
		int		yn;
		int		ioTyp;
		$$.f = $1.f; $$.l = $3.l;
		if (sscanf($1.v->name, "Q%1[XBWL]%d", y1, &yn) == 2) {
		    ioTyp = (y1[0] == 'X') ? OUTX : OUTW;
		} else {
		    ioTyp = 0;				/* flags that no I/O is generated */
		}
		if (($$.v = assignExpression(&$1, &$3, ioTyp)) == 0) YYERROR;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(0, "dasgn", (Lis*)&$$);
#endif
	    }
	;

	/************************************************************
	 *
	 * Different forms of assignment
	 *
	 ***********************************************************/

asgn	: UNDEF '=' aexpr	{			/* asgn is an aexpr */
		$$.f = $1.f; $$.l = $3.l;
		$1.v->ftype = GATE;	/* implicitly declared as 'imm bit' */
		if (($$.v = assignExpression(&$1, &$3, 0)) == 0) YYERROR;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(0, "asgn", (Lis*)&$$);
#endif
	    }
	| LVAR '=' aexpr		{
		$$.f = $1.f; $$.l = $3.l;
		if (($$.v = assignExpression(&$1, &$3, 0)) == 0) YYERROR;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(0, "asgn", (Lis*)&$$);
#endif
	    }
	| AVAR '=' aexpr		{
		$$.f = $1.f; $$.l = $3.l;
		if (($$.v = assignExpression(&$1, &$3, 0)) == 0) YYERROR;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(0, "asgn", (Lis*)&$$);
#endif
	    }
	| LOUT '=' aexpr		{
		$$.f = $1.f; $$.l = $3.l;
		if (($$.v = assignExpression(&$1, &$3, OUTX)) == 0) YYERROR;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(0, "asgn", (Lis*)&$$);
#endif
	    }
	| AOUT '=' aexpr		{
		$$.f = $1.f; $$.l = $3.l;
		if (($$.v = assignExpression(&$1, &$3, OUTW)) == 0) YYERROR;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(0, "asgn", (Lis*)&$$);
#endif
	    }
	;

	/************************************************************
	 *
	 * Assignment as an expression - dasgn is NOT an aexpr
	 *
	 ***********************************************************/

aexpr	: expr			{
		$$ = $1;
		if ($$.v != 0) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
	    }
	| asgn			{
		$$.f = $1.f; $$.l = $1.l;
		$$.v = sy_push($1.v);
		$$.v->le_first = $$.f; $$.v->le_last = $$.l;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "aexpr", &$$);
#endif
	    }
	;

	/************************************************************
	 *
	 * Expressions - includes unclocked built in functions
	 *
	 ***********************************************************/

expr	: UNDEF			{
		$$.f = $1.f; $$.l = $1.l;
		$$.v = checkDecl($1.v);
		$1.v->ftype = GATE;
		$$.v->le_first = $$.f; $$.v->le_last = $$.l;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| NUMBER		{
		$$.f = $1.f; $$.l = $1.l;
		$$.v = 0;			/* no node, do not need value */
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| valueVariable		{		/* LVAR AVAR */
		$$.f = $1.f; $$.l = $1.l;
		$$.v = checkDecl($1.v);
		$$.v->le_first = $$.f; $$.v->le_last = $$.l;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| outVariable		{		/* LOUT AOUT */
		$$.f = $1.f; $$.l = $1.l;
		$$.v = sy_push($1.v);
		$$.v->le_first = $$.f; $$.v->le_last = $$.l;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| fexpr			{
		Symbol *	sp;

		if ($1.v == 0) YYERROR;			/* error in bltin() */
		sp = $1.v->le_sym;
		$$ = $1;
		if (sp->ftype != ftypes[sp->type & TM]) {
		    warning("not enough arguments for function", sp->name);
		}
		sp->ftype = sp->type == SH ? ARITH : GATE;
		$$.v->le_first = $$.f; $$.v->le_last = $$.l;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| cCall			{
		$$ = $1;
		if ($$.v) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
	    }
	| iFunCall			{
		$$ = $1;
		if ($$.v) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
	    }
	| '(' aexpr ')'		{
		$$.f = $1.f; $$.l = $3.l;
		if (($$.v = $2.v) != 0) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	/************************************************************
	 * L(aexpr,aexpr)
	 * LATCH(aexpr,aexpr)
	 *	L(..) LATCH(set,reset)
	 ***********************************************************/
	| BLATCH '(' lexpr ')'	{		/* L(set,reset) */
		Symbol *	nsp;
		List_e *	nlp;
		$$.f = $1.f; $$.l = $4.l;
		$$.v = op_push(sy_push($3.v->le_sym), LOGC, $3.v);
		$$.v->le_sym->type = LATCH;
		if (iFunSymExt) {
		    nsp = $$.v->le_sym;
#ifdef FEEDBACK
		    nlp = nsp->elist;		/* feedback list */
		    nsp->elist = sy_push(nsp);	/* feeds back to itself */
		    nsp->elist->le_next = nlp;
#else	/* FEEDBACK */
		    nlp = nsp->list;		/* feedback list */
		    nsp->list = sy_push(csp);
		    nsp->list->le_next = nlp;
#endif	/* FEEDBACK */
		}
		$$.v->le_first = $$.f; $$.v->le_last = $$.l;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	/************************************************************
	 * F(aexpr,aexpr,aexpr)
	 * FORCE(aexpr,aexpr,aexpr)
	 *	F(..) FORCE(expr,on,off)
	 ***********************************************************/
	| BFORCE '(' aexpr ',' lexpr ')'	{	/* F(expr,hi,lo) */
		$$.f = $1.f; $$.l = $6.l;
		if ($3.v == 0) { $$.v = 0; errBit(); YYERROR; }
		$$.v = op_push(op_force($3.v, GATE), LOGC, $5.v);
		$$.v->le_sym->type = LATCH;
		$$.v->le_first = $$.f; $$.v->le_last = $$.l;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| expr '|' expr		{		/* binary | */
		List_e *	lpL;
		List_e *	lpR;
		$$.f = $1.f; $$.l = $3.l;
		if (($1.v == 0 || $1.v->le_sym->ftype == ARITH) &&
		    ($3.v == 0 || $3.v->le_sym->ftype == ARITH)) {
		    $$.v = op_push($1.v, ARN, $3.v);	/* bitwise | */
		} else if ($1.v == 0 || $3.v == 0) {
		    errBit(); YYERROR;
		} else {
		    lpR = op_force($3.v, GATE);
		    lpL = op_force($1.v, GATE);
		    $$.v = op_push(lpL, OR, lpR);	/* logical | */
		}
		if ($$.v) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| expr '^' expr		{		/* binary ^ */
		List_e *	lpL;
		List_e *	lpR;
		$$.f = $1.f; $$.l = $3.l;
		if (($1.v == 0 || $1.v->le_sym->ftype == ARITH) &&
		    ($3.v == 0 || $3.v->le_sym->ftype == ARITH)) {
		    $$.v = op_push($1.v, ARN, $3.v);	/* bitwise ^ */
		} else if ($1.v == 0 || $3.v == 0) {
		    errBit(); YYERROR;
		} else {
		    lpR = op_force($3.v, GATE);
		    lpL = op_force($1.v, GATE);
		    $$.v = op_xor(lpL, lpR);		/* logical ^ */
		}
		if ($$.v) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| expr '&' expr		{		/* binary & */
		List_e *	lpL;
		List_e *	lpR;
		$$.f = $1.f; $$.l = $3.l;
		if (($1.v == 0 || $1.v->le_sym->ftype == ARITH) &&
		    ($3.v == 0 || $3.v->le_sym->ftype == ARITH)) {
		    $$.v = op_push($1.v, ARN, $3.v);	/* bitwise & */
		} else if ($1.v == 0 || $3.v == 0) {
		    errBit(); YYERROR;
		} else {
		    lpR = op_force($3.v, GATE);
		    lpL = op_force($1.v, GATE);
		    $$.v = op_push(lpL, AND, lpR);	/* logical & */
		}
		if ($$.v) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| expr CMP expr	{			/* == != < <= > >= */
		List_e *	lpL;
		List_e *	lpR;
		$$.f = $1.f; $$.l = $3.l;
		lpR = op_force($3.v, ARITH);
		lpL = op_force($1.v, ARITH);
		if (($$.v = op_push(lpL, ARN, lpR)) != 0) {
		    $$.v = op_force($$.v, GATE);	/* default output */
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| expr AOP expr		{		/* << >> / % */
		List_e *	lpL;
		List_e *	lpR;
		$$.f = $1.f; $$.l = $3.l;
		lpR = op_force($3.v, ARITH);
		lpL = op_force($1.v, ARITH);
		if (($$.v = op_push(lpL, ARN, lpR)) != 0) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| expr PM expr		{		/* binary + - */
		List_e *	lpL;
		List_e *	lpR;
		$$.f = $1.f; $$.l = $3.l;
		lpR = op_force($3.v, ARITH);
		lpL = op_force($1.v, ARITH);
		if (($$.v = op_push(lpL, ARN, lpR)) != 0) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| expr '*' expr		{		/* binary * */
		List_e *	lpL;
		List_e *	lpR;
		$$.f = $1.f; $$.l = $3.l;
		lpR = op_force($3.v, ARITH);
		lpL = op_force($1.v, ARITH);
		if (($$.v = op_push(lpL, ARN, lpR)) != 0) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }

	/************************************************************
	 *
	 * If both operands of a binary && or || operator are imm bit
	 * more precisely ftype GATE or UDFA (!ARITH) && type >ARN ||
	 * UDF or a reduced ARN variable (of type GATE), then the
	 * operation is compiled as a logical bit, rather than con-
	 * verting both imm bit (GATE) to ARITH, doing an arithmetic
	 * operation and then having default GATE again.
	 *
	 ***********************************************************/

	| expr AA expr	{			/* binary && */
		Symbol *	sp;
		int		typ;
		List_e *	lpL;
		List_e *	lpR;
		$$.f = $1.f; $$.l = $3.l;
		if ($1.v &&
		    (sp = $1.v->le_sym)->ftype != ARITH &&
		    ((typ = sp->type & TM) > ARN || typ == UDF || !sp->u_blist) &&
		    (sp = $3.v->le_sym)->ftype != ARITH &&
		    ((typ = sp->type & TM) > ARN || typ == UDF || !sp->u_blist)) {
		    lpR = op_force($3.v, GATE);
		    lpL = op_force($1.v, GATE);
		    $$.v = op_push(lpL, AND, lpR);	/* logical & */
		} else {
		    lpR = op_force($3.v, ARITH);
		    lpL = op_force($1.v, ARITH);
		    $$.v = op_push(lpL, ARN, lpR);	/* arithmetic && */
		    $$.v = op_force($$.v, GATE);	/* default GATE output */
		}
		if ($$.v) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| expr OO expr	{			/* binary || */
		Symbol *	sp;
		int		typ;
		List_e *	lpL;
		List_e *	lpR;
		$$.f = $1.f; $$.l = $3.l;
		if ($1.v &&
		    (sp = $1.v->le_sym)->ftype != ARITH &&
		    ((typ = sp->type & TM) > ARN || typ == UDF || !sp->u_blist) &&
		    (sp = $3.v->le_sym)->ftype != ARITH &&
		    ((typ = sp->type & TM) > ARN || typ == UDF || !sp->u_blist)) {
		    lpR = op_force($3.v, GATE);
		    lpL = op_force($1.v, GATE);
		    $$.v = op_push(lpL, OR, lpR);	/* logical | */
		} else {
		    lpR = op_force($3.v, ARITH);
		    lpL = op_force($1.v, ARITH);
		    $$.v = op_push(lpL, ARN, lpR);	/* arithmetic || */
		    $$.v = op_force($$.v, GATE);	/* default GATE output */
		}
		if ($$.v) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| expr '?' expr ':' expr	{	/* ? : */
		List_e *	lpL;
		List_e *	lpR;
		$$.f = $1.f; $$.l = $5.l;
		lpR = op_force($5.v, ARITH);
		lpL = op_force($3.v, ARITH);
		lpR = op_push(lpL, ARN, lpR);
		lpL = op_force($1.v, ARITH);
		if (($$.v = op_push(lpL, ARN, lpR)) != 0) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| NOTL expr 		{		/* unary ~ or ! */
		Symbol *	sp;
		$$.f = $1.f; $$.l = $2.l;
		if ($2.v) {
		    int typ;
		    if ((sp = $2.v->le_sym)->ftype != ARITH &&
			(((typ = sp->type & TM) != ARNC && typ != ARN &&
			typ != SH) || sp->u_blist == 0)) {
						/* logical negation */
			$$.v = op_not(op_force($2.v, GATE));
		    } else {
						/* bitwise negation */
			$$.v = op_push(0, ARN, op_force($2.v, ARITH));
		    }
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		} else {
		    $$.v = 0;			/* constant negation */
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	| PM expr %prec NOTL	{		/* unary + or - */
		$$.f = $1.f; $$.l = $2.l;
		if (($$.v = op_push(0, ARN, op_force($2.v, ARITH))) != 0) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "expr", &$$);
#endif
	    }
	;

lexpr	: aexpr ',' aexpr		{
		List_e *	lpL;
		List_e *	lpR;
		$$.f = $1.f; $$.l = $3.l;
		if ($1.v == 0) { $$.v = $3.v; errBit(); YYERROR; }
		if ($3.v == 0) { $$.v = $1.v; errBit(); YYERROR; }
		lpR = op_not(op_force($3.v, GATE));
		lpL = op_force($1.v, GATE);
		if (($$.v = op_push(lpL, LOGC, lpR)) != 0) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "lexpr", &$$);
#endif
	    }
	;

	/************************************************************
	 *
	 * Literal block %{ ......... %}
	 *
	 * A literal block may be used anywhere before, between or after
	 * statements in an iC program. The contents of the literal block
	 * will be copied to the generated C file before any expressions
	 * generated by immediate statements.
	 *
	 * The characters %# occurring at the start of a line in a literal
	 * block will be converted to a plain #. This allows the use of
	 * C-preprocessor statements in literal blocks which will be
	 * resolved after the iC compilation. They must be written as
	 * %#include
	 * %#define
	 * %#ifdef etc
	 *
	 ***********************************************************/

lBlock	: LHEAD			{ ccfrag = '%'; }	/* %{ literal block %} */
	  CCFRAG '}'		{ $$.v = 0; }
	;

	/************************************************************
	 *
	 * C block { ......... }
	 *
	 * A C block is used in if, if else and switch immediate expressions
	 *
	 * The characters %# occurring at the start of a line in a C block
	 * will be converted to a plain #. See literal block above.
	 *
	 ***********************************************************/

cBlock	: '{'			{ ccfrag = '{'; }	/* ccfrag must be set */
	  CCFRAG '}'		{ $$ = $3; }		/* count dummy yacc token */
	;

	/************************************************************
	 *
	 * Clock and Timer parameters
	 *
	 * default clock is iClock if last clock parameter in list
	 *
	 * timer parameters must specify a delay, which is either
	 * NUMBER, an Alias for a NUMBER or an immediate expression
	 * which is forced to ftype ARITH
	 *
	 * default timer delay is 1 if last clock parameter in list
	 *
	 ***********************************************************/

	/************************************************************
	 *  [,(cexpr|texpr[,aexpr])]
	 ***********************************************************/
cref	: /* nothing */		{ $$.v = sy_push(iclock); }
	| ','			{ $$.v = sy_push(iclock); }
	| ',' ctref		{ $$ = $2; }		/* clock or timer */
	;

	/************************************************************
	 *  (cexpr|texpr[,aexpr])
	 ***********************************************************/
ctref	: ctdref		{ $$ = $1; }		/* clock or timer with delay */
	| ctdref ','		{ $$ = $1; }
	| texpr			{			/* timer */
		$$.f = $1.f; $$.l = $1.l;
		$$.v = delayOne($1.v);			/* with implicit delay of 1 */
	    }
	| texpr ','		{
		$$.f = $1.f; $$.l = $2.l;
		$$.v = delayOne($1.v);			/* with implicit delay of 1 */
	    }
	;

	/************************************************************
	 *  (cexpr|texpr,aexpr)
	 ***********************************************************/
ctdref	: cexpr			{ $$ = $1; }		/* clock */
	| texpr ',' aexpr	{			/* timer with delay expression */
		$$ = $1; $$.l = $3.l;
		if ($3.v == 0) {
		    if (const_push(&$3)) { errInt(); YYERROR; }
		}
		$3.v = op_force($3.v, ARITH);
		$3.v->le_val = (unsigned) -1;		/* mark link as timer value */
		$$.v = op_push($1.v, TIM, $3.v);
	    }
	;

	/************************************************************
	 *
	 * Built in iC functions
	 *
	 * These built in functions follow C syntax
	 *
	 * the actual function names are defined in file init.c
	 *
	 ***********************************************************/

	/************************************************************
	 * D(aexpr[,(cexpr|texpr[,aexpr])])
	 * SH(aexpr[,(cexpr|texpr[,aexpr])])
	 * CHANGE(aexpr[,(cexpr|texpr[,aexpr])])
	 * RISE(aexpr[,(cexpr|texpr[,aexpr])])
	 *	D(..) SH(..) CHANGE(..) RISE(expr)
	 *	D(..) SH(..) CHANGE(..) RISE(expr,clk)
	 *	D(..) SH(..) CHANGE(..) RISE(expr,tim)
	 *	D(..) SH(..) CHANGE(..) RISE(expr,tim,delay)
	 ***********************************************************/
fexpr	: BLTIN1 '(' aexpr cref ')' {			/* D(expr); SH etc */
		$$.f = $1.f; $$.l = $5.l;
		$$.v = bltin(&$1, &$3, &$4, 0, 0, 0, 0, 0, 0);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	/************************************************************
	 * DL(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 * DLATCH(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 *	DL(..) DLATCH(set,reset)
	 *	DL(..) DLATCH(set,reset,clkSetReset)
	 *	DL(..) DLATCH(set,reset,timSetReset)
	 *	DL(..) DLATCH(set,reset,timSetReset,delaySetReset)
	 ***********************************************************/
	| DLATCH '(' lexpr cref ')'	{		/* DL(set,reset) */
		Lis		li1 = $3;
		List_e *	lp1;
		$$.f = $1.f; $$.l = $5.l;
		lp1 = op_push(sy_push($3.v->le_sym), LOGC, $3.v);
		lp1->le_sym->type = LATCH;
		lp1 = op_push(sy_push($1.v), LATCH, lp1);
		/* DLATCH output is transferred as feed back in op_asgn */
		$$.v = bltin(&$1, &li1, &$4, 0, 0, 0, 0, 0, 0);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	/************************************************************
	 * SR(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 *	SR(set,reset)
	 *	SR(set,reset,clkSetReset)
	 *	SR(set,reset,timSetReset)
	 *	SR(set,reset,timSetReset,delaySetReset)
	 * DR(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 * SHR(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 *	DR(..) SHR(expr,reset)
	 *	DR(..) SHR(expr,reset,clkExprReset)
	 *	DR(..) SHR(expr,reset,timExprReset)
	 *	DR(..) SHR(expr,reset,timExprReset,delayExprReset)
	 ***********************************************************/
	| BLTIN2 '(' aexpr ',' aexpr cref ')' {		/* SR(set,reset); DR(expr,reset) */
		$$.f = $1.f; $$.l = $7.l;
		$$.v = bltin(&$1, &$3, 0, 0, 0, &$5, &$6, 0, 0);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	/************************************************************
	 * SR(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 *	SR(set,clkSet,         reset)
	 *	SR(set,clkSet,         reset,clkReset)
	 *	SR(set,clkSet,         reset,timReset)
	 *	SR(set,clkSet,         reset,timReset,delayReset)
	 *	SR(set,timSet,delaySet,reset)
	 *	SR(set,timSet,delaySet,reset,clkReset)
	 *	SR(set,timSet,delaySet,reset,timReset)
	 *	SR(set,timSet,delaySet,reset,timReset,delayReset)
	 * DR(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 * SHR(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 *	DR(..) SHR(expr,clkExpr,          reset)
	 *	DR(..) SHR(expr,clkExpr,          reset,clkReset)
	 *	DR(..) SHR(expr,clkExpr,          reset,timReset)
	 *	DR(..) SHR(expr,clkExpr,          reset,timReset,delayReset)
	 *	DR(..) SHR(expr,timExpr,delayExpr,reset)
	 *	DR(..) SHR(expr,timExpr,delayExpr,reset,clkReset)
	 *	DR(..) SHR(expr,timExpr,delayExpr,reset,timReset)
	 *	DR(..) SHR(expr,timExpr,delayExpr,reset,timReset,delayReset)
	 ***********************************************************/
	| BLTIN2 '(' aexpr ',' ctdref ',' aexpr cref ')' {
		$$.f = $1.f; $$.l = $9.l;
		$$.v = bltin(&$1, &$3, &$5, 0, 0, &$7, &$8, 0, 0);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	/************************************************************
	 * DSR(aexpr[,(cexpr|texpr[,aexpr])])
	 * SHSR(aexpr[,(cexpr|texpr[,aexpr])])
	 *	DSR(..) SHSR(expr)
	 *	DSR(..) SHSR(expr,clk)
	 *	DSR(..) SHSR(expr,tim)
	 *	DSR(..) SHSR(expr,tim,delay)
	 ***********************************************************/
	| BLTIN3 '(' aexpr cref ')' {			/* DSR(expr); SHSR(expr) */
		$$.f = $1.f; $$.l = $5.l;
		$$.v = bltin(&$1, &$3, &$4, 0, 0, 0, 0, 0, 0);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	/************************************************************
	 * DSR(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 * SHSR(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 *	DSR(..) SHSR(expr,reset)
	 *	DSR(..) SHSR(expr,reset,clkExprReset)
	 *	DSR(..) SHSR(expr,reset,timExprReset)
	 *	DSR(..) SHSR(expr,reset,timExprReset,delayExprReset)
	 ***********************************************************/
	| BLTIN3 '(' aexpr ',' aexpr cref ')' {
		$$.f = $1.f; $$.l = $7.l;
		$$.v = bltin(&$1, &$3, 0, 0, 0, &$5, &$6, 0, 0);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	/************************************************************
	 * DSR(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 * SHSR(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 *	DSR(..) SHSR(expr,clkExpr,          reset)
	 *	DSR(..) SHSR(expr,clkExpr,          reset,clkReset)
	 *	DSR(..) SHSR(expr,clkExpr,          reset,timReset)
	 *	DSR(..) SHSR(expr,clkExpr,          reset,timReset,delayReset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,reset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,reset,clkReset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,reset,timReset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,reset,timReset,delayReset)
	 ***********************************************************/
	| BLTIN3 '(' aexpr ',' ctdref ',' aexpr cref ')' {
		$$.f = $1.f; $$.l = $9.l;
		$$.v = bltin(&$1, &$3, &$5, 0, 0, &$7, &$8, 0, 0);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	/************************************************************
	 * DSR(aexpr,aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 * SHSR(aexpr,aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 *	DSR(..) SHSR(expr,set,reset)
	 *	DSR(..) SHSR(expr,set,reset,clkExprReset)
	 *	DSR(..) SHSR(expr,set,reset,timExprReset)
	 *	DSR(..) SHSR(expr,set,reset,timExprReset,delayExprReset)
	 ***********************************************************/
	| BLTIN3 '(' aexpr ',' aexpr ',' aexpr cref ')' {
		$$.f = $1.f; $$.l = $9.l;
		$$.v = bltin(&$1, &$3, 0, &$5, 0, &$7, &$8, 0, 0);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	/************************************************************
	 * DSR(aexpr,aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 * SHSR(aexpr,aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 *	DSR(..) SHSR(expr,set,clkSet,         reset)
	 *	DSR(..) SHSR(expr,set,timSet,delaySet,reset)
	 *	DSR(..) SHSR(expr,set,clkSet,         reset,clkReset)
	 *	DSR(..) SHSR(expr,set,timSet,delaySet,reset,clkReset)
	 *	DSR(..) SHSR(expr,set,clkSet,         reset,timReset)
	 *	DSR(..) SHSR(expr,set,timSet,delaySet,reset,timReset)
	 *	DSR(..) SHSR(expr,set,clkSet,         reset,timReset,delayReset)
	 *	DSR(..) SHSR(expr,set,timSet,delaySet,reset,timReset,delayReset)
	 * These cases have been left out deliberately, beause it is
	 * not clear wether the default clock for 'expr' should be taken
	 * from the set clock or the reset clock - causes syntax errors.
	 * Therefore the user is forced to chose a clock for 'expr'.
	 * The following code would do the job - has been tested - JW 020630
	 * The clock for 'expr' is cloned from the reset clock.
	| BLTIN3 '(' aexpr ',' aexpr ',' ctdref ',' aexpr cref ')' {
		$$.f = $1.f; $$.l = $11.l;
		$$.v = bltin(&$1, &$3, 0, &$5, &$7, &$9, &$10, 0, 0);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	 ***********************************************************/
	/************************************************************
	 * DSR(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 * SHSR(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 *	DSR(..) SHSR(expr,clkExpr,          set,reset)
	 *	DSR(..) SHSR(expr,clkExpr,          set,reset,clkSetReset)
	 *	DSR(..) SHSR(expr,clkExpr,          set,reset,timSetReset)
	 *	DSR(..) SHSR(expr,clkExpr,          set,reset,timSetReset,delaySetReset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,set,reset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,set,reset,clkSetReset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,set,reset,timSetReset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,set,reset,timSetReset,delaySetReset)
	 ***********************************************************/
	| BLTIN3 '(' aexpr ',' ctdref ',' aexpr ',' aexpr cref ')' {
		$$.f = $1.f; $$.l = $11.l;
		$$.v = bltin(&$1, &$3, &$5, &$7, 0, &$9, &$10, 0, 0);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	/************************************************************
	 * DSR(aexpr,(cexpr|texpr,aexpr),aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 * SHSR(aexpr,(cexpr|texpr,aexpr),aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 *	DSR(..) SHSR(expr,clkExpr,          set,clkSet,         reset)
	 *	DSR(..) SHSR(expr,clkExpr,          set,timSet,delaySet,reset)
	 *	DSR(..) SHSR(expr,clkExpr,          set,clkSet,         reset,clkReset)
	 *	DSR(..) SHSR(expr,clkExpr,          set,timSet,delaySet,reset,clkReset)
	 *	DSR(..) SHSR(expr,clkExpr,          set,clkSet,         reset,timReset)
	 *	DSR(..) SHSR(expr,clkExpr,          set,timSet,delaySet,reset,timReset)
	 *	DSR(..) SHSR(expr,clkExpr,          set,clkSet,         reset,timReset,delayReset)
	 *	DSR(..) SHSR(expr,clkExpr,          set,timSet,delaySet,reset,timReset,delayReset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,set,clkSet,         reset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,set,timSet,delaySet,reset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,set,clkSet,         reset,clkReset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,set,timSet,delaySet,reset,clkReset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,set,clkSet,         reset,timReset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,set,timSet,delaySet,reset,timReset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,set,clkSet,         reset,timReset,delayReset)
	 *	DSR(..) SHSR(expr,timExpr,delayExpr,set,timSet,delaySet,reset,timReset,delayReset)
	 ***********************************************************/
	| BLTIN3 '(' aexpr ',' ctdref ',' aexpr ',' ctdref ',' aexpr cref ')' {
		$$.f = $1.f; $$.l = $13.l;
		$$.v = bltin(&$1, &$3, &$5, &$7, &$9, &$11, &$12, 0, 0);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	/************************************************************
	 * JK(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 *	JK(set,reset)
	 *	JK(set,reset,clkSetReset)
	 *	JK(set,reset,timSetReset)
	 *	JK(set,reset,timSetReset,delaySetReset)
	 ***********************************************************/
	| BLTINJ '(' aexpr ',' aexpr cref ')' {		/* JK(set,reset) */
		Lis		liS = $3;	/* later = 0 ZZZ */
		Lis		liR = $5;
		List_e *	lpS;
		List_e *	lpR;
		Symbol *	nsp;
		List_e *	nlp;
		$$.f = $1.f; $$.l = $7.l;
		liS.v = op_not(sy_push(&tSym));		/* temporary Gate */
		if ((liS.v = op_push(liS.v, AND, op_force($3.v, GATE))) != 0) {
		    liS.v->le_first = liS.f = 0; liS.v->le_last = liS.l = 0;
		}
		liR.v = sy_push(&tSym);			/* temporary Gate */
		if ((liR.v = op_push(liR.v, AND, op_force($5.v, GATE))) != 0) {
		    liR.v->le_first = liR.f = 0; liR.v->le_last = liR.l = 0;
		}
		$$.v = bltin(&$1, &liS, 0, 0, 0, &liR, &$6, 0, 0);
		lpS = liS.v->le_sym->u_blist;
		while (lpS && lpS->le_sym != &tSym) {
		    lpS = lpS->le_next;
		}
		assert(lpS);
		lpR = liR.v->le_sym->u_blist;
		while (lpR && lpR->le_sym != &tSym) {
		    lpR = lpR->le_next;
		}
		assert(lpR);
		nsp = lpS->le_sym = lpR->le_sym = $$.v->le_sym;	/* JK feedback links */
		if (iFunSymExt) {
#ifdef FEEDBACK
		    nlp = nsp->elist;		/* feedback list */
		    nsp->elist = sy_push(liS.v->le_sym);
		    nsp->elist->le_next = sy_push(liR.v->le_sym);
		    nsp->elist->le_next->le_next = nlp;
#else	/* FEEDBACK */
		    nlp = nsp->list;		/* feedback list */
		    nsp->list = sy_push(liS.v->le_sym);
		    nsp->list->le_next = sy_push(liR.v->le_sym);
		    nsp->list->le_next->le_next = nlp;
#endif	/* FEEDBACK */
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	/************************************************************
	 * JK(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 *	JK(set,clkSet,         reset)
	 *	JK(set,clkSet,         reset,clkReset)
	 *	JK(set,clkSet,         reset,timReset)
	 *	JK(set,clkSet,         reset,timReset,delayReset)
	 *	JK(set,timSet,delaySet,reset)
	 *	JK(set,timSet,delaySet,reset,clkReset)
	 *	JK(set,timSet,delaySet,reset,timReset)
	 *	JK(set,timSet,delaySet,reset,timReset,delayReset)
	 ***********************************************************/
	| BLTINJ '(' aexpr ',' ctdref ',' aexpr cref ')' {
		Lis		liS = $3;	/* later = 0 ZZZ */
		Lis		liR = $7;
		List_e *	lpS;
		List_e *	lpR;
		Symbol *	nsp;
		List_e *	nlp;
		$$.f = $1.f; $$.l = $9.l;
		liS.v = op_not(sy_push(&tSym));		/* temporary Gate */
		if ((liS.v = op_push(liS.v, AND, op_force($3.v, GATE))) != 0) {
		    liS.v->le_first = liS.f = 0; liS.v->le_last = liS.l = 0;
		}
		liR.v = sy_push(&tSym);			/* temporary Gate */
		if ((liR.v = op_push(liR.v, AND, op_force($7.v, GATE))) != 0) {
		    liR.v->le_first = liR.f = 0; liR.v->le_last = liR.l = 0;
		}
		$$.v = bltin(&$1, &liS, &$5, 0, 0, &liR, &$8, 0, 0);
		lpS = liS.v->le_sym->u_blist;
		while (lpS && lpS->le_sym != &tSym) {
		    lpS = lpS->le_next;
		}
		assert(lpS);
		lpR = liR.v->le_sym->u_blist;
		while (lpR && lpR->le_sym != &tSym) {
		    lpR = lpR->le_next;
		}
		assert(lpR);
		nsp = lpS->le_sym = lpR->le_sym = $$.v->le_sym;	/* JK feedback links */
		if (iFunSymExt) {
#ifdef FEEDBACK
		    nlp = nsp->elist;		/* feedback list */
		    nsp->elist = sy_push(liS.v->le_sym);
		    nsp->elist->le_next = sy_push(liR.v->le_sym);
		    nsp->elist->le_next->le_next = nlp;
#else	/* FEEDBACK */
		    nlp = nsp->list;		/* feedback list */
		    nsp->list = sy_push(liS.v->le_sym);
		    nsp->list->le_next = sy_push(liR.v->le_sym);
		    nsp->list->le_next->le_next = nlp;
#endif	/* FEEDBACK */
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);
#endif
	    }
	/************************************************************
	 * SRT(aexpr[,(cexpr|texpr[,aexpr])])
	 *	SRT(set)
	 *	SRT(set,clk)
	 *	SRT(set,tim)
	 *	SRT(set,tim,delay)
	 ***********************************************************/
	| BLTINT '(' aexpr cref ')'	{			/* SRT(set,reset,tim,delay) */
		$$.f = $1.f; $$.l = $5.l;
		$$.v = bltin(&$1, &$3, 0, 0, 0, 0, 0, &$4, 0); /* monoflop without reset */
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);	/* set clocked by iClock */
#endif
	    }
	/************************************************************
	 * SRT(aexpr,(cexpr|texpr,aexpr),(cexpr|texpr[,aexpr]))
	 *	SRT(set,clkSet,         clk)
	 *	SRT(set,timSet,delaySet,clk)
	 *	SRT(set,clkSet,         tim)
	 *	SRT(set,timSet,delaySet,tim)
	 *	SRT(set,clkSet,         tim,delay)
	 *	SRT(set,timSet,delaySet,tim,delay)
	 ***********************************************************/
	| BLTINT '(' aexpr ',' ctdref ',' ctref ')'	{
		$$.f = $1.f; $$.l = $8.l;
		$$.v = bltin(&$1, &$3, &$5, 0, 0, 0, 0, &$7, 0); /* monoflop without reset */
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);	/* set clocked by ext clock or timer */
#endif
	    }
	/************************************************************
	 * SRT(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 *	SRT(set,reset)
	 *	SRT(set,reset,clk)
	 *	SRT(set,reset,tim)
	 *	SRT(set,reset,tim,delay)
	 ***********************************************************/
	| BLTINT '(' aexpr ',' aexpr cref ')'	{
		$$.f = $1.f; $$.l = $7.l;
		$$.v = bltin(&$1, &$3, 0, 0, 0, &$5, 0, &$6, 0); /* monoflop with reset */
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);	/* set and reset clocked by iClock */
#endif
	    }
	/************************************************************
	 * SRT(aexpr,aexpr,(cexpr|texpr,aexpr),(cexpr|texpr[,aexpr]))
	 *	SRT(set,reset,clkSetReset,              clk)
	 *	SRT(set,reset,timSetReset,delaySetReset,clk)
	 *	SRT(set,reset,clkSetReset,              tim)
	 *	SRT(set,reset,timSetReset,delaySetReset,tim)
	 *	SRT(set,reset,clkSetReset,              tim,delay)
	 *	SRT(set,reset,timSetReset,delaySetReset,tim,delay)
	 ***********************************************************/
	| BLTINT '(' aexpr ',' aexpr ',' ctdref ',' ctref ')'	{
		$$.f = $1.f; $$.l = $10.l;
		$$.v = bltin(&$1, &$3, 0, 0, 0, &$5, &$7, &$9, 0); /* monoflop with reset */
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);	/* set and reset clocked by same clock or timer */
#endif
	    }
	/************************************************************
	 * SRT(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 *	SRT(set,clkSet,         reset)
	 *	SRT(set,timSet,delaySet,reset)
	 *	SRT(set,clkSet,         reset,clk)
	 *	SRT(set,timSet,delaySet,reset,clk)
	 *	SRT(set,clkSet,         reset,tim)
	 *	SRT(set,timSet,delaySet,reset,tim)
	 *	SRT(set,clkSet,         reset,tim,delay)
	 *	SRT(set,timSet,delaySet,reset,tim,delay)
	 ***********************************************************/
	| BLTINT '(' aexpr ',' ctdref ',' aexpr cref ')'	{
		Lis	lis1;
		$$.f = $1.f; $$.l = $9.l;
		lis1.v = sy_push(iclock);		/* to avoid shift reduce conflict */
		$$.v = bltin(&$1, &$3, &$5, 0, 0, &$7, &lis1, &$8, 0); /* monoflop with reset */
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);	/* set clocked by ext clock or timer */
#endif
	    }						/* reset clocked by iClock */
	/************************************************************
	 * SRT(aexpr,(cexpr|texpr,aexpr),aexpr,(cexpr|texpr,aexpr),(cexpr|texpr[,aexpr]))
	 *	SRT(set,clkSet,         reset,clkReset,           clk)
	 *	SRT(set,timSet,delaySet,reset,clkReset,           clk)
	 *	SRT(set,clkSet,         reset,clkReset,           tim)
	 *	SRT(set,timSet,delaySet,reset,clkReset,           tim)
	 *	SRT(set,clkSet,         reset,clkReset,           tim,delay)
	 *	SRT(set,timSet,delaySet,reset,clkReset,           tim,delay)
	 *	SRT(set,clkSet,         reset,timReset,delayReset,clk)
	 *	SRT(set,timSet,delaySet,reset,timReset,delayReset,clk)
	 *	SRT(set,clkSet,         reset,timReset,delayReset,tim)
	 *	SRT(set,timSet,delaySet,reset,timReset,delayReset,tim)
	 *	SRT(set,clkSet,         reset,timReset,delayReset,tim,delay)
	 *	SRT(set,timSet,delaySet,reset,timReset,delayReset,tim,delay)
	 ***********************************************************/
	| BLTINT '(' aexpr ',' ctdref ',' aexpr ',' ctdref ',' ctref ')'	{
		$$.f = $1.f; $$.l = $12.l;
		$$.v = bltin(&$1, &$3, &$5, 0, 0, &$7, &$9, &$11, 0); /* monoflop with reset */
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fexpr", &$$);	/* set clocked by ext clock or timer */
#endif
	    }						/* reset clocked by different clock or timer */
	;

	/************************************************************
	 *
	 * if, if else and switch immediate expressions
	 *
	 * no assignment allowed for ffexpr - they stand alone
	 *
	 ***********************************************************/

ifini	: IF '(' aexpr cref ')'		{		/* if (expr) { x++; } */
		fprintf(T1FP, cexeString[outFlag], ++c_number);
		fprintf(T1FP, "    if (_cexe_gf->gt_val < 0)\n");
	    }
				cBlock	{		/* { x++; } */
		$$.v = bltin(&$1, &$3, &$4, 0, 0, 0, 0, 0, &$7);
	    }
	;

	/************************************************************
	 * if (aexpr[,(cexpr|texpr[,aexpr])]) { C code }
	 *	if (expr)	    { C code }
	 *	if (expr,clk)	    { C code }
	 *	if (expr,tim)	    { C code }
	 *	if (expr,tim,delay) { C code }
	 ***********************************************************/
ffexpr	: ifini				{		/* if (expr) { x++; } */
		fprintf(T1FP, "    return 0;\n%s", outFlag ? "}\n\n" : "\n");
	    }
	/************************************************************
	 * if (aexpr[,(cexpr|texpr[,aexpr])]) { C code } else { C code }
	 *	if (expr)	    { C code } else { C code }
	 *	if (expr,clk)	    { C code } else { C code }
	 *	if (expr,tim)	    { C code } else { C code }
	 *	if (expr,tim,delay) { C code } else { C code }
	 ***********************************************************/
	| ifini ELSE			{		/* { x++; } else */
		Symbol *	sp;
		List_e *	lp;
		sp = $1.v->le_sym;		/* slave, deleted later */
		assert(sp);
		lp = sp->u_blist;
		assert(lp);
		sp = lp->le_sym;		/* master - currently ftype F_CF */
		assert(sp);
		sp->ftype = $2.v->ftype;	/* make it ftype F_CE from ELSE */
		fprintf(T1FP, "    else\n");
	    }
		     cBlock		{		/* { x--; } */
		fprintf(T1FP, "    return 0;\n%s", outFlag ? "}\n\n" : "\n");
	    }
	/************************************************************
	 * switch (aexpr[,(cexpr|texpr[,aexpr])]) { C switch code }
	 *	switch (expr)		{ C switch code }
	 *	switch (expr,clk)	{ C switch code }
	 *	switch (expr,tim)	{ C switch code }
	 *	switch (expr,tim,delay) { C switch code }
	 ***********************************************************/
	| SWITCH '(' aexpr cref ')'		{	/* switch (expr) { case ...; } */
		fprintf(T1FP, cexeString[outFlag], ++c_number);
		fprintf(T1FP, "    switch (_cexe_gf->gt_new)\n");
	    }
				    cBlock	{	/* { x++; } */
		$$.v = bltin(&$1, &$3, &$4, 0, 0, 0, 0, 0, &$7);
		fprintf(T1FP, "    return 0;\n%s", outFlag ? "}\n\n" : "\n");
	    }
	;

	/************************************************************
	 *
	 * Clock built in expression
	 *
	 ***********************************************************/

dcasgn	: decl '=' cexpr	{			/* dcasgn is NOT an cexpr */
		if ($1.v->ftype != CLCKL) {
		    ierror("assigning clock to variable declared differently:", $1.v->name);
		    $1.v->type = ERR;	/* cannot execute properly */
		} else if ($1.v->type != UDF && $1.v->type != CLK) {
		    ierror("assigning clock to variable assigned differently:", $1.v->name);
		    $1.v->type = ERR;	/* cannot execute properly */
		}
		$$.v = op_asgn(&$1, &$3, CLCKL);
	    }
	;

casgn	: UNDEF '=' cexpr	{ $$.v = op_asgn(&$1, &$3, CLCKL); }
	| CVAR '=' cexpr	{
		if ($1.v->type != UDF) {
		    ierror("multiple assignment clock:", $1.v->name);
		    $1.v->type = ERR;	/* cannot execute properly */
		}
		$$.v = op_asgn(&$1, &$3, CLCKL);
	    }
	;

cexpr	: CVAR			{ $$.v = checkDecl($1.v); }
	| casgn			{ $$.v = sy_push($1.v); }
	| cfexpr		{
		Symbol *	sp = $1.v->le_sym;
		assert(sp);
		if (sp->ftype != ftypes[sp->type & TM]) {
		    warning("not enough arguments for function", sp->name);
		}
		sp->ftype = CLCKL;	/* clock list head */
		$$ = $1;
	    }
	| cFunCall		{
		Symbol *	sp;
		assert($1.v);			/* ZZZ analyse and fix */
		sp = $1.v->le_sym;
		assert(sp);
		if (sp->ftype != CLCKL) {
		    ierror("called function does not return type clock:", sp->name);
		    sp->type = ERR;	/* cannot execute properly */
		}
		$$ = $1;
	    }
	| '(' cexpr ')'		{ $$ = $2; }
	;

	/************************************************************
	 * C(aexpr[,(cexpr|texpr[,aexpr])])
	 * CLOCK(aexpr[,(cexpr|texpr[,aexpr])])
	 *	C(..) CLOCK(set1)
	 *	C(..) CLOCK(set1,clkSet1)
	 *	C(..) CLOCK(set1,timSet1)
	 *	C(..) CLOCK(set1,timSet1,delaySet1)
	 ***********************************************************/
cfexpr	: CBLTIN '(' aexpr cref ')'	{
		$$.v = bltin(&$1, &$3, &$4, 0, 0, 0, 0, 0, 0);
	    }
	/************************************************************
	 * C(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 * CLOCK(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 *	C(..) CLOCK(set1,set2)
	 *	C(..) CLOCK(set1,set2,clkSet1Set2)
	 *	C(..) CLOCK(set1,set2,timSet1Set2)
	 *	C(..) CLOCK(set1,set2,timSet1Set2,delaySet1Set2)
	 ***********************************************************/
	| CBLTIN '(' aexpr ',' aexpr cref ')'	{
		$$.v = bltin(&$1, &$3, 0, 0, 0, &$5, &$6, 0, 0);
	    }
	/************************************************************
	 * C(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 * CLOCK(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 *	C(..) CLOCK(set1,clkSet1,          set2)
	 *	C(..) CLOCK(set1,clkSet1,          set2,clkSet2)
	 *	C(..) CLOCK(set1,clkSet1,          set2,timSet2)
	 *	C(..) CLOCK(set1,clkSet1,          set2,timSet2,delaySet2)
	 *	C(..) CLOCK(set1,timSet1,delaySet1,set2)
	 *	C(..) CLOCK(set1,timSet1,delaySet1,set2,clkSet2)
	 *	C(..) CLOCK(set1,timSet1,delaySet1,set2,timSet2)
	 *	C(..) CLOCK(set1,timSet1,delaySet1,set2,timSet2,delaySet2)
	 ***********************************************************/
	| CBLTIN '(' aexpr ',' ctdref ',' aexpr cref ')'	{
		$$.v = bltin(&$1, &$3, &$5, 0, 0, &$7, &$8, 0, 0);
	    }
	;

	/************************************************************
	 *
	 * Timer built in expression
	 *
	 ***********************************************************/

dtasgn	: decl '=' texpr	{			/* dtasgn is NOT an texpr */
		if ($1.v->ftype != TIMRL) {
		    ierror("assigning timer to variable declared differently:", $1.v->name);
		    $1.v->type = ERR;	/* cannot execute properly */
		} else if ($1.v->type != UDF && $1.v->type != TIM) {
		    ierror("assigning timer to variable assigned differently:", $1.v->name);
		    $1.v->type = ERR;	/* cannot execute properly */
		}
		$$.v = op_asgn(&$1, &$3, TIMRL);
	    }
	;

tasgn	: UNDEF '=' texpr	{ $$.v = op_asgn(&$1, &$3, TIMRL); }
	| TVAR '=' texpr	{
		if ($1.v->type != UDF) {
		    ierror("multiple assignment timer:", $1.v->name);
		    $1.v->type = ERR;	/* cannot execute properly */
		}
		$$.v = op_asgn(&$1, &$3, TIMRL);
	    }
	;

texpr	: TVAR			{ $$.v = checkDecl($1.v); }
	| tasgn			{ $$.v = sy_push($1.v); }
	| tfexpr		{
		Symbol *	sp = $1.v->le_sym;
		assert(sp);
		if (sp->ftype != ftypes[sp->type & TM]) {
		    warning("not enough arguments for function", sp->name);
		}
		sp->ftype = TIMRL;	/* timer list head */
		$$ = $1;
	    }
	| tFunCall		{
		Symbol *	sp;
		assert($1.v);			/* ZZZ analyse and fix */
		sp = $1.v->le_sym;
		assert(sp);
		if (sp->ftype != TIMRL) {
		    ierror("called function does not return type timer:", sp->name);
		    sp->type = ERR;	/* cannot execute properly */
		}
		$$ = $1;
	    }
	| '(' texpr ')'		{ $$ = $2; }
	;

	/************************************************************
	 *
	 * Timers (TIMER or T) have a preset off delay of 0.
	 * Such timers will clock with iClock on the falling edge of
	 * the master gate. They will clock with iClock on the rising
	 * edge if the on delay is 0.
	 *
	 ***********************************************************/

tfexpr	: TBLTIN '(' aexpr cref ')'	{
		$$.v = bltin(&$1, &$3, &$4, 0, 0, 0, 0, 0, 0);
	    }
	/************************************************************
	 * T(aexpr[,(cexpr|texpr[,aexpr])])
	 * TIMER(aexpr[,(cexpr|texpr[,aexpr])])
	 *	T(..) TIMER(set1)
	 *	T(..) TIMER(set1,clkSet1)
	 *	T(..) TIMER(set1,timSet1)
	 *	T(..) TIMER(set1,timSet1,delaySet1)
	 ***********************************************************/
	| TBLTIN '(' aexpr ',' aexpr cref ')'	{
		$$.v = bltin(&$1, &$3, 0, 0, 0, &$5, &$6, 0, 0);
	    }
	/************************************************************
	 * T(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 * TIMER(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 *	T(..) TIMER(set1,set2)
	 *	T(..) TIMER(set1,set2,clkSet1Set2)
	 *	T(..) TIMER(set1,set2,timSet1Set2)
	 *	T(..) TIMER(set1,set2,timSet1Set2,delaySet1Set2)
	 ***********************************************************/
	| TBLTIN '(' aexpr ',' ctdref ',' aexpr cref ')'	{
		$$.v = bltin(&$1, &$3, &$5, 0, 0, &$7, &$8, 0, 0);
	    }
	/************************************************************
	 * T(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 * TIMER(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 *	T(..) TIMER(set1,clkSet1,          set2)
	 *	T(..) TIMER(set1,clkSet1,          set2,clkSet2)
	 *	T(..) TIMER(set1,clkSet1,          set2,timSet2)
	 *	T(..) TIMER(set1,clkSet1,          set2,timSet2,delaySet2)
	 *	T(..) TIMER(set1,timSet1,delaySet1,set2)
	 *	T(..) TIMER(set1,timSet1,delaySet1,set2,clkSet2)
	 *	T(..) TIMER(set1,timSet1,delaySet1,set2,timSet2)
	 *	T(..) TIMER(set1,timSet1,delaySet1,set2,timSet2,delaySet2)
	 ***********************************************************/

	/************************************************************
	 *
	 * Alternate timers (TIMER1 or T1) have a preset off delay of 1.
	 * Such timers will clock with the next timer pulse on the
	 * falling edge of the master gate. They will clock with the
	 * next timer pulse on the rising edge if the on delay is 0.
	 *
	 ***********************************************************/

	/************************************************************
	 * T1(aexpr[,(cexpr|texpr[,aexpr])])
	 * TIMER1(aexpr[,(cexpr|texpr[,aexpr])])
	 *	T1(..) TIMER1(set1)
	 *	T1(..) TIMER1(set1,clkSet1)
	 *	T1(..) TIMER1(set1,timSet1)
	 *	T1(..) TIMER1(set1,timSet1,delaySet1)
	 ***********************************************************/
	| TBLTI1 '(' aexpr cref ')'	{
		$$.v = bltin(&$1, &$3, &$4, 0, 0, 0, 0, 0, &val1);
	    }
	/************************************************************
	 * T1(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 * TIMER1(aexpr,aexpr[,(cexpr|texpr[,aexpr])])
	 *	T1(..) TIMER1(set1,set2)
	 *	T1(..) TIMER1(set1,set2,clkSet1Set2)
	 *	T1(..) TIMER1(set1,set2,timSet1Set2)
	 *	T1(..) TIMER1(set1,set2,timSet1Set2,delaySet1Set2)
	 ***********************************************************/
	| TBLTI1 '(' aexpr ',' aexpr cref ')'	{
		$$.v = bltin(&$1, &$3, 0, 0, 0, &$5, &$6, 0, &val1);
	    }
	/************************************************************
	 * T1(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 * TIMER1(aexpr,(cexpr|texpr,aexpr),aexpr[,(cexpr|texpr[,aexpr])])
	 *	T1(..) TIMER1(set1,clkSet1,          set2)
	 *	T1(..) TIMER1(set1,clkSet1,          set2,clkSet2)
	 *	T1(..) TIMER1(set1,clkSet1,          set2,timSet2)
	 *	T1(..) TIMER1(set1,clkSet1,          set2,timSet2,delaySet2)
	 *	T1(..) TIMER1(set1,timSet1,delaySet1,set2)
	 *	T1(..) TIMER1(set1,timSet1,delaySet1,set2,clkSet2)
	 *	T1(..) TIMER1(set1,timSet1,delaySet1,set2,timSet2)
	 *	T1(..) TIMER1(set1,timSet1,delaySet1,set2,timSet2,delaySet2)
	 ***********************************************************/
	| TBLTI1 '(' aexpr ',' ctdref ',' aexpr cref ')'	{
		$$.v = bltin(&$1, &$3, &$5, 0, 0, &$7, &$8, 0, &val1);
	    }
	;

	/************************************************************
	 *
	 * Embedded C function  or macro calls.
	 * These functions or macros may be declared implicitly via a
	 * #include or #define in a preceding literal block or declared
	 * and or defined in a literal block.
	 *
	 * Such functions must have at least 1 parameter which is
	 * immediate to trigger execution of the function. Any changes
	 * in non-immediate parameters will not trigger execution and
	 * should be handled with care.
	 *
	 * All bit expressions in parameters will be converted to imm int.
	 *
	 * The return value of all functions must be int. If a function
	 * is to be used with a different return value, define a wrapper
	 * function in a literal block.
	 *
	 ***********************************************************/

cCall	: UNDEF '(' cParams ')'	{
		$$.f = $1.f; $$.l = $4.l;
	    				/* CHECK if iCbuf changes now _() is missing */
		if (lookup($1.v->name)) {	/* may be unlinked in same expr */
		    unlink_sym($1.v);		/* unlink Symbol from symbol table */
		    free($1.v->name);
		    free($1.v);		/* TODO may be better to keep in ST with type ??? */
		}
		$$.v = $3.v;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "cFunct", &$$);
#endif
	    }
	;

cParams	: /* nothing */		{ $$.v = 0; }
	| cPlist		{ $$   = $1; }
	;

cPlist	: aexpr			{
		$$.f = $1.f; $$.l = $1.l;
		if (($$.v = op_push(0, ARN, op_force($1.v, ARITH))) != 0) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "cPlist", &$$);
#endif
	    }
	| cPlist ',' aexpr	{
		$$.f = $1.f; $$.l = $3.l;
		if (($$.v = op_push($1.v, ARN, op_force($3.v, ARITH))) != 0) {
		    $$.v->le_first = $$.f; $$.v->le_last = $$.l;
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "cPlist", &$$);
#endif
	    }
	;

	/************************************************************
	 *
	 *	Immediate functions
	 *
	 * A new immediate function definition name is an UNDEF.
	 * Alternatively an existing immediate function is an IFUNCTION
	 * etc, whose data objects are deleted to allow redefinition.
	 ***********************************************************/

iFunTrigger
	: UNDEF				{ $$ = $1; }
	| IFUNCTION			{ $$ = $1; $$.v = clearFunDef($1.v); }
	| CFUNCTION			{ $$ = $1; $$.v = clearFunDef($1.v); }
	| TFUNCTION			{ $$ = $1; $$.v = clearFunDef($1.v); }
	| VFUNCTION			{ $$ = $1; $$.v = clearFunDef($1.v); }
	;

	/************************************************************
	 * Immediate function with immediate return value
	 * Definition:
	 *	imm bit   bf1(bit p1, int p2, clock c1, timer t1, int delay) {...}
	 *	imm int   if1(assign bit a1, assign int a2, bit p1, int p2)  {...}
	 *	imm clock cf1(bit p1, clock c1) {...}
	 *	imm timer tf1(bit p1, clock c1) {...}
	 ***********************************************************/

iFunHead
	: declHead iFunTrigger '('	{
		$$.f = $1.f; $$.l = $3.l;
		$$.v = functionHead($1.v, $2.v, 1);	/* function head Symbol */
	    }

	/************************************************************
	 * Void immediate function
	 * Definition:
	 *	imm void  vf1(assign bit a1, assign int a2, bit p1, int p2) {...}
	 ***********************************************************/

	| IMM VOID iFunTrigger '('	{
		$$.f = $1.f; $$.l = $4.l;
		$$.v = functionHead($2.v->ftype, $3.v, 0); /* function head Symbol */
	    }
	;

	/************************************************************
	 * Finalise function definition
	 ***********************************************************/

iFunDef	: iFunHead fParams ')' '{' funcBody '}'	{
		$$.f = $1.f; $$.l = $6.l;
		$$.v = functionDefinition($1.v, $2.v);
	    }
	;

	/************************************************************
	 * collect statements in the function body
	 * is now done for individual statements and assignments
	 ***********************************************************/

funcBody
	: /* nothing */			{ $$.v = 0; clrBuf(); }
	| funcBody funcStatement	{
		$$.f = $1.f; $$.l = $2.l;
		$$.v = 0;			/* $$.v is not required */
		clrBuf();
	    }
	| funcBody error ';'	{ $$.v = 0; clrBuf(); iclock->type = ERR; yyerrok; }
	;

	/************************************************************
	 * Value function return statement
	 ***********************************************************/

returnStatement
	: RETURN actexpr		{
		$$.f = $2.f; $$.l = $2.l;	/* TODO $$.f should be func$ */
		if ($2.v == 0) { $$.v = 0; errBit(); YYERROR; }
		$$.v = returnStatement(&$2);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(0, "return", (Lis*)&$$);
#endif
	    }
	;

actexpr	: aexpr				{ $$ = $1; }
	| cexpr				{ $$ = $1; }
	| texpr				{ $$ = $1; }
	;

	/************************************************************
	 * formal parameter list for immediate function definitions
	 ***********************************************************/

fParams	: /* nothing */			{ $$.v =  0; }
	| fPlist			{ $$   = $1; }
	| fPlist ','			{ $$   = $1; }
	;

fPlist	: formalParameter		{
		$$.f = $1.f; $$.l = $1.l;
		$$.v = sy_push($1.v);		/* first link in parameter list */
		$$.v->le_first = $1.f;
		$$.v->le_last = $1.l;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fPlist", &$$);
#endif
	    }
	| fPlist ',' formalParameter	{
		List_e *	lp;

		$$.f = $1.f; $$.l = $3.l;
		lp = $$.v;
		while (lp->le_next) {
		    lp = lp->le_next;
		}
		lp = lp->le_next = sy_push($3.v); /* link to end of parameter list */
		lp->le_first = $3.f;
		lp->le_last = $3.l;
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "fPlist", &$$);
#endif
	    }
	;

	/************************************************************
	 * individual formal parameter
	 ***********************************************************/

formalParameter
	: ASSIGN formalParaTypeDecl UNDEF	{
		$$ = $3;			/* formal assign parameter Symbol */
		$$.v->ftype = $2.v & 0xff;	/* TYPE bit int clock timer */
		$$.v->type = $2.v >> 8;		/* UDF for all TYPEs */
		iFunSyText = 0;			/* no more function symbols */
	    }
	| formalParaTypeDecl UNDEF	{
		int	ft;

		$$ = $2;			/* formal value parameter Symbol */
		$$.v->ftype = ft = $1.v & 0xff;	/* TYPE bit int clock timer */
		if (ft >= CLCKL) {		/* check that CLCKL TIMRL */
		    ft -= CLCKL - CLCK;		/* and CLCK and TIMR are adjacent */
		}
		$$.v->type = types[ft];
		iFunSyText = 0;			/* no more function symbols */
	    }
	;

formalParaTypeDecl
	: TYPE				{
		$$.f = $$.l = $1.l;		/* do not include in expression string */
		$$.v = $1.v->ftype;
		iFunSyText = iFunBuffer;	/* expecting a new function symbol */
	    }
	| IMM TYPE			{
		$$.f = $$.l = $2.l;		/* do not include in expression string */
		$$.v = $2.v->ftype;		/* IMM is optional */
		iFunSyText = iFunBuffer;	/* expecting a new function symbol */
	    }
	;

	/************************************************************
	 * immediate function with immediate return value bit and int
	 * Call:
	 *	imm bit b1, b2; imm int i1, i2, delay; imm clock clk; imm timer tim;
	 *	b1  = bf1(b2, i1, clk, tim, delay);
	 *	i1  = if1(b2, i2, b1 & IX0.0, delay * 10);
	 * Mixed Call:
	 *	QX0.0  = bf1(b1 | b2, if1(...) + 5, cf1(...), tf1(...), 2);
	 ***********************************************************/

iFunCallHead
	: IFUNCTION '('			{
		$$.f = $1.f; $$.l = $2.l;
		$$.v = pushFunCall($1.v);	/* save globals for nested function calls */
	    }
	;

iFunCall: iFunCallHead rParams ')'	{
		$$.f = $1.f; $$.l = $3.l;
		$$.v = cloneFunction($1.v, $2.v);	/* clone function from call head */
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "iFunC", &$$);
#endif
	    }
	;

	/************************************************************
	 * immediate function with immediate return value clock
	 * Call:
	 *	clk = cf1(b1, iClock);
	 ***********************************************************/

cFunCallHead
	: CFUNCTION '('			{
		$$.f = $1.f; $$.l = $2.l;
		$$.v = pushFunCall($1.v);	/* save globals for nested function calls */
	    }
	;

cFunCall: cFunCallHead rParams ')'	{
		$$.f = $1.f; $$.l = $3.l;
		$$.v = cloneFunction($1.v, $2.v);	/* clone function from call head */
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "cFunC", &$$);
#endif
	    }
	;

	/************************************************************
	 * immediate function with immediate return value timer
	 * Call:
	 *	tim = tf1(b2, clk);
	 ***********************************************************/

tFunCallHead
	: TFUNCTION '('			{
		$$.f = $1.f; $$.l = $2.l;
		$$.v = pushFunCall($1.v);	/* save globals for nested function calls */
	    }
	;

tFunCall: tFunCallHead rParams ')'	{
		$$.f = $1.f; $$.l = $3.l;
		$$.v = cloneFunction($1.v, $2.v);	/* clone function from call head */
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "tFunC", &$$);
#endif
	    }
	;

	/************************************************************
	 * void immediate function
	 * Call:
	 *	imm bit b1, b3; imm int i3, delay;
	 *	vf1(b3, i3, b1 & IX0.0, delay * 10);
	 ***********************************************************/

vFunCallHead
	: VFUNCTION '('			{
		$$.f = $1.f; $$.l = $2.l;
		$$.v = pushFunCall($1.v);	/* save globals for nested function calls */
	    }
	;

vFunCall: vFunCallHead rParams ')'	{
		$$.f = $1.f; $$.l = $3.l;
		cloneFunction($1.v, $2.v);	/* clone function from call head */
		$$.v = 0;			/* $$.v is Sym - not compatible */
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(0, "vFunC", (Lis*)&$$);
#endif
	    }
	;

	/************************************************************
	 * real parameter list for immediate function calls
	 ***********************************************************/

rParams	: /* nothing */			{ $$.v =  0; }
	| rPlist			{ $$   = $1; }
	| rPlist ','			{ $$   = $1; $$.l = $2.l; }
	;

rPlist	: actexpr			{
		$$.f = $1.f; $$.l = $1.l;
		if ($1.v == 0) {
		    if (const_push(&$1)) { errInt(); YYERROR; }
		}
		$$.v = handleRealParameter(0, $1.v);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "rPlist", &$$);
#endif
	    }
	| rPlist ',' actexpr		{
		$$.f = $1.f; $$.l = $3.l;
		if ($3.v == 0) {		/* must extract value from aexpr */
		    if (const_push(&$3)) { errInt(); YYERROR; }
		}
		$$.v = handleRealParameter($1.v, $3.v);
#if YYDEBUG
		if ((debug & 0402) == 0402) pu(1, "rPlist", &$$);
#endif
	    }
	;

	/************************************************************
	 *
	 * end of iC grammar
	 *
	 ***********************************************************/

%%

#ifdef NEWSTYLE
#define CBUFSZ 166			/* listing just fits on 132  cols */
#define YTOKSZ 166
#else
#define CBUFSZ 125			/* listing just fits on 132  cols */
#define YTOKSZ 66
#endif
static char	chbuf[CBUFSZ];		/* used in get() errline() andd yyerror() */
static char	prevNM[BUFS];
static char *	getp = NULL;		/* used in get() unget() andd yyerror() */
static char	iCtext[YTOKSZ];		/* lex token */
static int	iCleng;			/* length */
static int	lineflag;
static int	iniDebug;
static char const * iniPtr;
static char *	errFilename;
static int	errFlag = 0;
static int	errRet = 0;
static int	eofLineno = 0;
static int	savedLineno = 0;
static int	errline = 0;

/********************************************************************
 *	lexflag is bitmapped and controls the input for lexers
 *******************************************************************/
int		lexflag = 0;
int		lineno = 0;		/* count first line on entry to get() */

int		c_number = 0;		/* case number for cexe.c */
int		outFlag = 0;		/* global flag for compiled output */
jmp_buf		begin;
int		lex_typ[] = { DEF_TYP };/* tokens corresponding to type */
int		lex_act[] = { DEF_ACT };/* tokens corresponding to ftype */

/********************************************************************
 *
 *	Compile an iC language source file whose name is in 'inpPath'
 *	if inpPath is a null pointer use standard input (stdin)
 *	a copy of the source file name (or stdin) is kept in inpNM for
 *	error messages. This name and the variable 'lineno' are
 *	modified by a #line 1 "file.ic" pre-processor directive.
 *
 *	listing text is directed to 'lstNM' (default stdout)
 *	error   text is directed to 'errNM' (default stderr)
 *
 *	a prototype for C function execution is read and extended
 *	with the C fragments possibly contained in the iC program
 *
 *******************************************************************/

int
compile(
    char *	inpPath,		/* input file path */
    char *	lstNM,			/* list file name */
    char *	errNM,			/* error file name */
    char *	outNM)			/* C output file name */
{
    char	execBuf[BUFS];
    int		fd;
    int		r = 1;

    lineno = 0;
#if YYDEBUG
    if ((debug & 0402) != 0402)
#endif
    lexflag = C_FIRST;			/* supress initial pre-processor lines */
    lineflag = 1;			/* previous line was complete */

    if (lstNM && (outFP = fopen(lstNM, "w+")) == NULL) {
	return Lindex;
    }
    errFilename = errNM;		/* open on first error */
    init();				/* initialise symbol table - allows ierror() */
    if (inpPath) {
	strncpy(inpNM, inpPath, BUFS);
	/* pre-compile if iC files contains any #include, #define #if etc */
	snprintf(execBuf, BUFS, "grep -q '^[ \t]*#' %s", inpPath);
	r = system(execBuf);		/* test with grep if #include in input */
	if (r == 0) {
	    /* pass the input file through the C pre-compiler to resolve #includes */
	    if ((fd = mkstemp(T0FN)) < 0 || close(fd) < 0 || unlink(T0FN) < 0) {
		ierror("compile: cannot make or unlink:", T0FN);
		perror("unlink");
		return T0index;		/* error unlinking temporary file */
	    }
	    /* Cygnus does not understand cc - use gcc - pass comments with -C */
	    snprintf(execBuf, BUFS, "gcc -E -C -x c %s -o %s", inpPath, T0FN);
#if YYDEBUG
	    if ((debug & 0402) == 0402) fprintf(outFP, "####### compile: %s; $? = %d\n", execBuf, r>>8);
#endif
	    r = system(execBuf);	/* Pre-compile iC file */
	    if (r != 0) {
		ierror("compile: cannot run:", execBuf);
		return T0index;
	    }
	    if ((T0FP = fopen(T0FN, "r")) == NULL) {
		return T0index;		/* error opening intermediate file */
	    }
	} else if ((T0FP = fopen(inpNM, "r")) == NULL) {
	    return Iindex;		/* error opening input file */
	}
    }
    strncpy(prevNM, inpNM, BUFS);
    outFlag = outNM != 0;		/* global flag for compiled output */
    if (debug & 046) {			/* begin source listing */
	fprintf(outFP, "******* %-15s ************************\n", inpNM);
    }
    if ((debug & 020000) == 0) {		/* suppres internal functions to test old code */
	iniPtr = initialFunctions;		/* read system function definitions first */
	iniDebug = debug;			/* save debug flag */
	if ((debug & 010400) != 010400) debug &= ~ 047; /* suppress logic expansion for ini code */
    }
    setjmp(begin);
    for (initcode(); iCparse(); initcode()) {
	;
    }
    if (r == 0 && !(debug & 04000)) {
	unlink(T0FN);
    }
    if (inpPath) fclose(T0FP);
    return errRet;
} /* compile */

/********************************************************************
 *
 *	Get routine for iC and C grammars
 *
 *******************************************************************/

int
get(FILE* fp)
{
    int		c;
    int		temp1;
    int		prevflag;
    size_t	iniLen;
    char	tempBuf[2];

    while (getp == 0 || (c = *getp++) == 0) {
	if (iniPtr) {
	    iniLen = strcspn(iniPtr, "\n");
	    if (iniPtr[iniLen] == '\n') {
		iniLen++;
	    }
	    else if (iniLen == 0) {
		debug = iniDebug;		/* restore logic expansion */
		iniPtr = getp = 0;		/* iC system function definitions read */
		clrBuf();			/* clear iCbuf after initial functions */
		continue;
	    }
	    assert(iniLen < CBUFSZ);
	    getp = strncpy(chbuf, iniPtr, iniLen); /* copy with terminating \n */
	    chbuf[iniLen] = '\0';
	    iniPtr += iniLen;
	} else {
	    if ((prevflag = lineflag) != 0) {
		lineno++;			/* count previous line */
	    }
	    /************************************************************
	     *  getp has reached end of previous chbuf filling
	     *  fill chbuf with a new line
	     *  NOTE: getp === NULL at start of file (chbuf has EOF line)
	     ************************************************************/
	    if ((getp = fgets(chbuf, CBUFSZ, fp)) == NULL) {
		if ((lexflag & C_PARSE) == 0) {
		    eofLineno = lineno;
		} else {
		    lineno = eofLineno;
		}
		errline = lineno;		/* no listing line at EOF */
		return (EOF);
	    }
	    lineflag = chbuf[strlen(chbuf)-1] == '\n' ? 1 : 0;	/* this line terminated with \n */
	}

	/********************************************************
	 *  handle different preprocessor lines
	 *  identify leading '#' for efficiency
	 *  Note: white space in scanf format matches any amount of
	 *        white space including none (have used single blank)
	 *  NOTE: chbuf[] must be large enough to hold a complete
	 *        pre-processor line for the following sscanf()s
	 ********************************************************/
	if (prevflag && sscanf(chbuf, " %1s", tempBuf) == 1 && *tempBuf == '#') {
	    if ((lexflag & C_PARSE) && strncmp(chbuf, "##", 2) == 0) {
		lexflag |= C_BLOCK;		/* block source listing for lex */
		lineno = savedLineno;
	    }
	    /********************************************************
	     *  handle C-pre-processor # 1 "/usr/include/stdio.h"
	     ********************************************************/
	    if (sscanf(chbuf, " # %d \"%[-/A-Za-z_.0-9<>]\"", &temp1, inpNM) == 2) {
		lineno = temp1 - 1;		/* handled in iC and C-code */
		lexflag |= C_LINE;
		if ((lexflag & C_PARSE) == 0) {
		    if (strcmp(inpNM, prevNM) && strchr(inpNM, '<') == 0) {
			lexflag &= ~C_FIRST;	/* report # 1 if file has changed */
		    }
		    getp = NULL;		/* bypass this line in iC */
		}
	    } else
	    /********************************************************
	     *  there should be no other # lines remaining in iC file
	     ********************************************************/
	    if ((lexflag & C_PARSE) == 0) {
		/* TODO process pre-processor lines in iC compilation */
		/* handle only local includes - not full C-precompiler features */
		ierror("get: stray # line in iC ???", NULL);
		getp = NULL;			/* bypass this line in iC */
	    } else
	    /********************************************************
	     *  C-compile
	     *  handle pre-processor #line 1 "file.ic"
	     ********************************************************/
	    if (sscanf(chbuf, " # line %d \"%[-/A-Za-z_.0-9<>]\"", &temp1, inpNM) == 2) {
		savedLineno = lineno;
		lineno = temp1 - 1;
		if ((debug & 042) && lexflag & C_FIRST) {
		    fprintf(outFP, "******* C CODE          ************************\n");
		}
		if (strcmp(inpNM, prevNM)) {
		    lexflag &= ~C_BLOCK;	/* output #line for changed filename */
		} else if (debug & 042) {
		    fprintf(outFP, "\n");	/* seperate blocks in lex listing */
		}
		lexflag |= C_LINE|C_LINE1;	/* only in C-compile */
		strncpy(prevNM, inpNM, BUFS);
	    }
	}
	if ((debug & 040) && ((lexflag & C_BLOCK) == 0	/* iC listing */
#if YYDEBUG
							|| ((debug & 0402) == 0402)
#endif
						    )) {
	    /********************************************************
	     *  output source listing line in debugging output
	     *  before any tokens are handed to the parser
	     *  then messages appear neatly after the listing line
	     ********************************************************/
	    if ((lexflag & C_LINE) == 0) {
		fprintf(outFP, "%03d\t%s", lineno, chbuf);
		iFlag = 1;				/* may need correction by pplstfix */
	    } else if ((lexflag & (C_PARSE|C_FIRST)) != C_FIRST) {
		fprintf(outFP, "\t%s", chbuf);		/* # line or # 123 "name" */
	    }
	    if (lineflag == 0) putc('\n', outFP);	/* current line not complete */
	}
	if ((lexflag & C_PARSE) == 0 && lineno > 0) {
	    lexflag &= ~C_FIRST;
	} else if (lexflag & C_LINE1) {
	    lexflag &= ~(C_FIRST|C_BLOCK|C_LINE1);	/* output source listing for lex */
	}
	lexflag &= ~C_LINE;
    }
    /****************************************************************
     *  return 1 character at a time from chbuf and return it
     *  transfer it to the token buffer iCtext and count iCleng if not lex
     ****************************************************************/
    if ((lexflag & C_PARSE) == 0) {
	iCtext[iCleng++] = c;			/* iC compile via iCparse() */
	if (iCleng >= sizeof(iCtext)) iCleng--;
	iCtext[iCleng] = '\0';
    }
    return c;
} /* get */

/********************************************************************
 *
 *	Unget for iC grammar only
 *
 *******************************************************************/

static void
unget(int c)
{
    if (c != EOF) {
	if(getp <= chbuf) {
	    execerror("unget: ???", NULL, __FILE__, __LINE__);
	}
	*--getp = c;		/* use always insures 1 free place */
	iCtext[--iCleng] = '\0';
    }
} /* unget */

/********************************************************************
 *
 *	Get a number, which may be decimal, octal or hexadecimal
 *
 *	Convert from getp in chbuf - termination will be at least at
 *	newline supplied by fgets() or final '\0'. Usually it is
 *	erlier and that part is copied into iCtext with get().
 *
 *******************************************************************/

static long
getNumber(void)
{
    long	value;
    char *	cp;
    char *	ep;

    value = strtol(getp, &ep, 0);		/* convert to long */
    assert (ep <= &chbuf[CBUFSZ]);
    for (cp = getp; cp < ep; cp++) {
	get(T0FP);				/* transfer to iCtext */
    }
#if YYDEBUG
    if ((debug & 0402) == 0402) {
	fprintf(outFP, "getNumber: '%s' converted to %ld\n", iCtext, value);
	fflush(outFP);
    }
#endif
    return value;
} /* getNumber */

/********************************************************************
 *
 *	Lexer for iC grammar
 *
 *******************************************************************/

char *	cexeString[] = {
    "    case %d:\n",
#if INT_MAX == 32767 && defined (LONG16)
    "static long _c_%d(Gate * _cexe_gf) {\n",
#else
    "static int _c_%d(Gate * _cexe_gf) {\n",
#endif
};

static int
iClex(void)
{
    int		c;
    int		c1;

    if (ccfrag) {
	if (ccfrag == '%') {
	    fprintf(T1FP, "%%{\n");	/* output "%{\n" now */
	}
	fprintf(T1FP, "#line %d \"%s\"\n", lineno, inpNM);
	unget('{');
	if (copyCfrag('{', ccfrag == '%' ? '%' : ';', '}') == 0) {
	    ccfrag = 0;
	    return 0;	/* EOF in copy C block or statement */
	}
	iClval.val.v = c_number;	/* return case # */
	ccfrag = 0;
	c = CCFRAG;
	goto retfl;
    }
    iCleng = 0;
    while ((c = get(T0FP)) !=  EOF) {
	Symbol *	symp;
	Symbol *	sp;
	List_e *	lp;
	int		len;
	int		rest;
	char		tempBuf[TSIZE];			/* make long enough for format below */

	if (c == ' ' || c == '\t' || c == '\n') {
	    iCleng = 0;
	    continue;					/* ignore white space */
	}
	if (isdigit(c)) {
	    unget(c);					/* must be at least a single 0 */
	    iClval.val.v = getNumber();			/* decimal octal or hex */
	    c = NUMBER;					/* value in iClval.val.v */
	    goto retfl;
	} else if (isalpha(c) || c == '_') {
	    unsigned char	wplus = 0;
	    unsigned int	qtoken = 0;
	    unsigned long	qmask = 0;		/* mask to id bit, byte, word or long */
	    unsigned long	iomask = 0;		/* output Q is 0x0f, input I is 0xf0 */
	    unsigned char	typ = UDF;
	    unsigned char	ftyp = UDFA;
	    int			ixd = IXD;
	    unsigned char	y0[2];
	    unsigned char	y1[2];
	    int			yn;
	    int			yt;
	    unsigned char	y2[2];

	    while ((c = get(T0FP)) != EOF && (isalnum(c) || c == '$' || c == '_'));
	    if (sscanf(iCtext, "%1[IQT]%1[XBWL]%d", y0, y1, &yn) == 3) {
		if (y1[0] == 'B') {
		    wplus = 1;
		    qmask = 0x02;			/* QB or IB */
		    iomask = 0x0f;
		    goto foundQIT;
		} else if (y1[0] == 'W') {
		    wplus = 1;
		    qmask = 0x0404;			/* QW or IW */
		    iomask = 0x0f0f;
		    goto foundQIT;
		} else if (y1[0] == 'L') {
#if INT_MAX != 32767 || defined (LONG16)
		    wplus = 1;
		    qmask = 0x08080808;			/* QL or IL */
		    iomask = 0x0f0f0f0f;
		    goto foundQIT;
#else
		    ierror("32 bit I/O not supported in 16 bit environment:", iCtext);
#endif
		} else if (c == '.') {
		    int c1, i1;				/* QXn. or IXn. */
		    if (isdigit(c1 = c = get(T0FP))) {	/* can only be QX%d. */
			for (i1 = 0; isdigit(c = get(T0FP)); i1++);
			if (c1 >= '8' || i1 > 0) {
			    ierror("I/O bit address must be less than 8:", iCtext);
			} else {
			    qmask = 0x01;		/* QX, IX or TX */
			    iomask = 0x0f;
			}
		    foundQIT:
			ftyp = GATE - wplus;		/* GATE or ARITH */
			if (y0[0] == 'Q') {
			    qtoken = lex_act[OUTX - wplus]; /* LOUT or AOUT */
			} else {
			    typ = INPX - wplus;		/* INPX or INPW */
			    if (y0[0] != 'T') {
				qmask <<= 4;		/* IX, IB, IW or IL */
				iomask <<= 4;		/* input I */
			    } else {
				qmask = iomask = 0;	/* TX (TB or TW) */
				ixd = y1[0] == 'X' ? 1 : 0;	/* TX0.7 is max */
			    }
			}
		    } else {
			unget(c);		/* the non digit, not '.' */
		    }
		} else if (sscanf(iCtext, "%1[IQT]%1[XBWL]%d_%d%1[A-Z_a-z]",
		    y0, y1, &yn, &yt, y2) == 4) {
		    ierror("I/O like names with _ instead of . clash with internal representation", iCtext);
						/* QX%d_%d not allowed */
		}				/* QX%d_%dABC is OK - not I/O */

		if (yn >= ixd) {
		    snprintf(tempBuf, TSIZE, "I/O byte address must be less than %d:",
			ixd);
		    ierror(tempBuf, iCtext);	/* hard error if outside range */
		} else			/* test rest if yn < ixd (array bounds) */
		if (wplus && y1[0] == 'W' && (yn & 0x01) != 0) {
		    ierror("WORD I/O must have even byte address:", iCtext);
		} else			/* test rest if yn < ixd (array bounds) */
		if (wplus && y1[0] == 'L' && (yn & 0x03) != 0) {
		    ierror("LONG I/O address must be on 4 byte boundary:", iCtext);
		} else			/* and yn is on correct byte boundary */
		if (qmask & 0x88888888) {
		    if (*(unsigned long*)&QX_[yn] & ~qmask & iomask) {
			ierror("I/O addresses more than 1 of bit, byte or word:",
			    iCtext);		/* mixed mode warning */
		    }
		    *(unsigned long*)&QX_[yn] |= qmask; /* note long I/O */
		} else
		if (qmask & 0x4444) {
		    if (*(unsigned short*)&QX_[yn] & ~qmask & iomask) {
			ierror("I/O addresses more than 1 of bit, byte or word:",
			    iCtext);		/* mixed mode warning */
		    }
		    *(unsigned short*)&QX_[yn] |= qmask; /* note word I/O */
		} else
		if (qmask) {
		    if (QX_[yn] & ~qmask & iomask) {
			ierror("I/O addresses more than 1 of bit, byte or word:",
			    iCtext);		/* mixed mode warning */
		    }
		    QX_[yn] |= qmask;		/* note bit or byte I/O */
		}
	    } else if (sscanf(iCtext, "_%d%1[A-Z_a-z_]", &yn, y2) == 1) {
		ierror("Variables _<number> clash with internal number representation", iCtext);
	    }
	    unget(c);
	    symp = 0;
	    if (iFunSymExt && ! qtoken) {	/* in function definition */
		if (iRetSymbol.v && strcmp(iCtext, "this") == 0) {
		    symp = iRetSymbol.v;	/* function return Symbol */
		} else {
		    strncpy(iFunSymExt, iCtext, iFunEnd - iFunSymExt);
		    if ((symp = lookup(iFunBuffer)) == 0 && iFunSyText) {
			symp = install(iFunBuffer, typ, ftyp); /* parameter or declaration */
		    }
		    *iFunSymExt = '\0';
		}
	    }
	    if (symp == 0) {
		if ((symp = lookup(iCtext)) == 0) {
		    symp = install(iCtext, typ, ftyp); /* usually UDF UDFA */
		} else if (typ == ERR) {
		    symp->type = ERR;		/* mark ERROR in QX%d_%d */
		}
	    }
#if YYDEBUG
	    if ((debug & 0402) == 0402) {
		fprintf(outFP, "iClex: %s %s %s\n",
		    symp->name, full_type[symp->type&TM], full_ftype[symp->ftype]);
		fflush(outFP);
	    }
#endif
	    iClval.sym.v = symp;		/* return actual symbol */
	    while ( (typ = symp->type) == ALIAS &&
		    (lp = symp->list) != 0 &&
		    (sp = lp->le_sym) != 0) {
		symp = sp;			/* with token of original */
	    }
	    typ &= ~EM;
	    if (typ > IFUNCT) {
		c = LEXERR;
	    } else
	    if (typ == IFUNCT) {
		if ((ftyp = symp->ftype) == UDFA) {
		    c = VFUNCTION;
		} else if (ftyp == ARITH || ftyp == GATE) {
		    c = IFUNCTION;
		} else if (ftyp == CLCKL) {
		    c = CFUNCTION;
		} else if (ftyp == TIMRL) {
		    c = TFUNCTION;
		} else {
		    c = LEXERR;
		}
	    } else
	    if (typ >= KEYW) {
		c = symp->u_val;		/* reserved word or C-type */
	    } else
	    if (qtoken) {
		c = qtoken;			/* LOUT or AOUT */
	    } else
	    if (typ == ARNC || typ == LOGC) {
		c = lex_typ[typ];
	    } else {
		c = lex_act[symp->ftype];	/* alpha_numeric symbol */
	    }
	    if (symp->ftype == OUTW && (lp = symp->list) != 0) {
		symp = lp->le_sym;		/* original via backptr */
	    }
	    iClval.sym.f = stmtp;	/* original name for expressions */
	    				/* CHECK if iCbuf changes now _() is missing */
	    if ((len = snprintf(stmtp, rest = &iCbuf[IMMBUFSIZE] - stmtp,
				"%s", symp->name)) < 0 || len >= rest) {
		iCbuf[IMMBUFSIZE-1] = '\0';
		len = rest - 1;			/* text + NUL which fits */
		ierror("statement too long at: ", symp->name);
	    }
	    iClval.sym.l = stmtp += len;
	} else {
	    if ((c1 = get(T0FP)) == EOF) goto found;	/* nothing after EOF */
	    switch (c) {
	    case '!':
		if (c1 == '=') {
		    c = CMP; goto found;		/* != */
		}
	    case '~':
		c = NOTL;				/* ! or ~ */
		break;
	    case '%':
		if (c1 == '{') {			/*    >>> '}' */
		    c = LHEAD; goto found;		/* %{ >>> %} */
		} else if (c1 == '=') {
		    c = OPE; goto found;		/* %= */
		}
		c = AOP;				/* % */
		break;
	    case '&':
		if (c1 == '&') {
		    c = AA; goto found;			/* && */
		} else if (c1 == '=') {
		    c = OPE; goto found;		/* &= */
		}
		break;
	    case '*':
		if (c1 == '/') {
		    c = COMMENTEND;	/* dangling end of a comment */
		    goto found;
		} else if (c1 == '=') {
		    c = OPE; goto found;		/* *= */
		}
		break;
	    case '+':
		if (c1 == '+') {
		    c = PPMM; goto found;		/* ++ */
		} else if (c1 == '=') {
		    c = OPE; goto found;		/* += */
		}
		c = PM;					/* + */
		break;				/* + binary or unary */
	    case '-':
		if (c1 == '-') {
		    c = PPMM; goto found;		/* -- */
		} else if (c1 == '=') {
		    c = OPE; goto found;		/* -= */
		} else if (c1 == '>') {
		    c = PR; goto found;			/* -> */
		}
		c = PM;					/* - */
		break;				/* - binary or unary */
	    case '/':
		if (c1 == '/') {
		    do {		/* start C++ style comment */
			if ((c1 = get(T0FP)) == EOF) return 0;
		    } while (c1 != '\n');
		} else if (c1 == '*') {
		    do {		/* start C style comment */
			while (c1 != '*') {
			    if ((c1 = get(T0FP)) == EOF) return 0;
			}
		    } while ((c1 = get(T0FP)) != '/');
		} else if (c1 == '=') {
		    c = OPE; goto found;		/* /= */
		} else {
		    c = AOP;				/* / */
		    break;
		}
		iCleng = 0;			/* end of comment */
		continue;
	    case '<':
		if (c1 == '<') {
		    if ((c1 = get(T0FP)) == '=') {
			c = OPE; goto found;		/* <<= */
		    }
		    c = AOP;				/* << */
		    break;
		}
		if (c1 != '=') {
		    unget(c1);
		}
		c = CMP; goto found;			/* < or <= */
	    case '=':
		if (c1 == '=') {
		    c = CMP; goto found;		/* == */
		}
		*iCtext = '#';	/* to recognise <= => transmogrify = */
		break;
	    case '>':
		if (c1 == '>') {
		    if ((c1 = get(T0FP)) == '=') {
			c = OPE; goto found;		/* >>= */
		    }
		    c = AOP;				/* >> */
		    break;
		}
		if (c1 != '=') {
		    unget(c1);
		}
		c = CMP; goto found;			/* > or >= */
	    case '^':
		if (c1 == '=') {
		    c = OPE; goto found;		/* ^= */
		}
		break;
	    case '|':
		if (c1 == '|') {
		    c = OO; goto found;			/* || */
		} else if (c1 == '=') {
		    c = OPE; goto found;		/* |= */
		}
		break;
	    case '.':
		c = PR;					/* . */
		break;
	    }
	    unget(c1);
	found:
	    iClval.val.v = c;		/* return to yacc as is */
	retfl:
	    iClval.val.f = stmtp;	/* all sources are iClval.val */
	    if ((c == PM || c == PPMM) &&
		stmtp > iCbuf && *(stmtp-1) == *iCtext) {
		*stmtp++ = ' ';		/* space between + + and - - */
					/* 1 byte will always fit */
	    }
	    rest = &iCbuf[IMMBUFSIZE] - stmtp;
	    len = strlen(iCtext);
	    if (len >= rest) {
		iCbuf[IMMBUFSIZE-1] = '\0';
		len = rest -1;
		ierror("statement too long at: ", iCtext);
	    }
	    iClval.val.l = stmtp = strncpy(stmtp, iCtext, len) + len;
	}
	return c;			/* return token to yacc */
    }
    return 0;				/* EOF */
} /* iClex */

/********************************************************************
 *
 *	Output an error in source listing and error output
 *	The error file errFP is opened with the first error
 *
 *******************************************************************/

static void
errLine(void)			/* error file not openend if no errors */
{
    if (errFlag == 0) {
	if (errFilename && errFP == stderr) {
	    if ((errFP = fopen(errFilename, "w+")) == NULL) {
		errFilename = 0;	/* cannot open errFilename */
		errFP = stderr;		/* just output to stderr */
		errRet = Eindex;	/* error return for compile() */
	    } else {
		errFlag = 1;		/* there is an error file */
	    }
	}
	if (outFP != stdout) {
	    errFlag = 1;		/* errors to errFilename or stderr */
	    if (!(debug & 046)) {	/* no source listing in debugging output */
		fprintf(outFP, "******* %-15s ************************\n", inpNM);
	    }
	}
	if (errFlag) fprintf(errFP, "******* %-15s ************************\n", inpNM);
    }
    if (lineno != errline) {
	errline = lineno;		/* dont print line twice */
	if (!(debug & 040) || (lexflag & C_BLOCK)) {	/* no source listing in debugging output */
	    fprintf(outFP, "%03d\t%s", lineno, chbuf);
	    if (lineflag == 0) putc('\n', outFP);	/* current line not complete */
	}
	if (errFlag) {
	    fprintf(errFP, "%03d\t%s", lineno, chbuf);
	    if (lineflag == 0)  putc('\n', errFP);	/* current line not complete */
	}
    }
} /* errLine */

/********************************************************************
 *
 *	Common code for error messages
 *
 *******************************************************************/

void
errmess(				/* actual error message */
    char *	str0,
    char *	str1,
    char *	str2)
{
    errLine();				/* do not change - used as search key in iClive */
    fprintf(outFP, "*** %s: %s", str0, str1);
    if (errFlag) fprintf(errFP, "*** %s: %s", str0, str1);
    if (str2) {
	fprintf(outFP, " %s", str2);
	if (errFlag) fprintf(errFP, " %s", str2);
    } else {
	putc('.', outFP);
	if (errFlag) putc('.', errFP);
    }
#ifdef NEWSTYLE
    fprintf(outFP, " '%s'\n", inpNM);
    if (errFlag) fprintf(errFP, " '%s'\n", inpNM);
#else
    fprintf(outFP, " File %s, line %d\n", inpNM, lineno);
    if (errFlag) fprintf(errFP, " File %s, line %d\n", inpNM, lineno);
#endif
} /* errmess */

/********************************************************************
 *
 *	Error message
 *	sets iClock type to ERR to prevent execution of generated code
 *
 *******************************************************************/

void
ierror(					/* print error message */
    char *	str1,
    char *	str2)
{
    iclock->type = ERR;			/* prevent execution */
    errmess("Error", str1, str2);
} /* ierror */

/********************************************************************
 *
 *	Warning message
 *
 *******************************************************************/

void
warning(				/* print warning message */
    char *	str1,
    char *	str2)
{
    errmess("Warning", str1, str2);
} /* warning */

/********************************************************************
 *
 *	Common error messages
 *
 *******************************************************************/

void
errBit(void)
{
    ierror("no constant allowed in bit expression", NULL);
} /* errBit */

void
errInt(void)
{
    ierror("no imm variable to trigger arithmetic expression", NULL);
} /* errInt */

/********************************************************************
 *
 *	Recovery from run-time errors
 *
 *******************************************************************/

void
execerror(			/* recover from run-time error */
    char *	str1,
    char *	str2,
    char *	file,
    int		line)
{
    errmess("Execerror", str1, str2);
    fprintf(outFP, "in source file: %s line %d\n", file, line);
    fflush(outFP);
    if (errFlag) {
	fprintf(errFP, "in source file: %s line %d\n", file, line);
	fflush(errFP);
    }
    fseek(T0FP, 0L, 2);	/* flush rest of file */
    longjmp(begin, 0);
} /* execerror */

/********************************************************************
 *
 *	Called from yacc parser on error (mostly syntax error)
 *
 *******************************************************************/

void
yyerror(char *	s)
{
    char *	cp = chbuf;
    int		n, n1;
    char	erbuf[TSIZE];

    errLine();
    fprintf(outFP, "*** ");	/* do not change - used as search key in iClive */
    if (errFlag) fprintf(errFP, "*** ");
    if ((lexflag & C_PARSE) == 0) {
	n = getp - chbuf - iCleng;
    } else {
	n = column - c_leng;
    }
    for (n1 = 0; n > 0; n--, cp++) {
	n1++;
	if (*cp == '\t') {
	    while (n1 % 8) {
		n1++;
	    }
	}
    }
    ynerrs++;
#ifdef NEWSTYLE
    n = snprintf(erbuf, TSIZE, "%s '%s'", s, inpNM);
#else
    n = snprintf(erbuf, TSIZE, "%s %d in %s", s, ynerrs, inpNM);
#endif
    if (n1 < n + 5) {
	n1 += 4;
	while (n1--) {
	    putc('-', outFP);
	    if (errFlag) putc('-', errFP);
	}
	fprintf(outFP, "^ %s\n", erbuf);
	if (errFlag) fprintf(errFP, "^ %s\n", erbuf);
    } else {
	fprintf(outFP, "%s ", erbuf);
	if (errFlag) fprintf(errFP, "%s ", erbuf);
	n1 -= n - 3;
	while (n1--) {
	    putc('-', outFP);
	    if (errFlag) putc('-', errFP);
	}
	fprintf(outFP, "^\n");
	if (errFlag) fprintf(errFP, "^\n");
    }
} /* yyerror */

/********************************************************************
 *
 *	Copy a C fragment to T1FP for an lBlock and a cBlock
 *	when yacc token CCFRAG is recognised in iClex()
 *
 *******************************************************************/

static int
copyCfrag(char s, char m, char e)
	/* copy C action to the next ; , or closing brace or bracket */
{
    int		brace;
    int		c;
    int		match;

    for (brace = 0; (c = get(T0FP)) != EOF; ) {
	if (c == s) {			/* '{' or '(' */
	    if (brace++ == 0 && m == '%') {	/* don't output "%{\w" */
		while ((c = get(T0FP)) == ' ' || c == '\t');
		unget(c);
		continue;
	    }
	} else if (c == m) {		/* ';' or '%' or ',' */
	    if (brace <= 0) {
		unget(c);		/* use for next token */
		return m;		/* no longer used */
	    } else if (brace == 1 && c == '%') {
		if ((c = get(T0FP)) == '}') {
		    fprintf(T1FP, "\n%%##\n\n%%}\n");	/* #line lineno "outNM"\n%} */
		    unget(c);
		    return m;
		}
		unget(c);
		c = '%';
	    }
	} else if (c == e) {		/* ')' or '}' */
	    if (--brace <= 0) {
		/* ZZZ fix lineno and name */
		if (brace == 0 && c == '}') {
		    putc(c, T1FP);	/* output '}' */
		}
		fprintf(T1FP, "\n%%##\n");	/* #line lineno "outNM" */
		unget(c);		/* should not return without '}' */
		return e;
	    }
	} else switch (c) {

	case '/':			/* look for comments */
	    putc(c, T1FP);
	    if ((c = get(T0FP)) == '/') {
		do {			/* start C++ style comment */
		    putc(c, T1FP);
		    if ((c = get(T0FP)) == EOF) goto eof_error;
		} while (c != '\n');
	    } else if (c == '*') {
		do {			/* start C style comment */
		    putc(c, T1FP);
		    while (c != '*') {
			if ((c = get(T0FP)) == EOF) goto eof_error;
			putc(c, T1FP);
		    }
		} while ((c = get(T0FP)) != '/');
	    } else {
		unget(c);
	    }
	    break;

	case '\'':			/* character constant */
	    match = '\'';
	    goto string;

	case '"':			/* character string */
	    match = '"';

	string:
	    putc(c, T1FP);
	    while ((c = get(T0FP)) != match) {
		if (c == '\\') {
		    putc(c, T1FP);
		    if ((c = get(T0FP)) == EOF) goto eof_error;
		} else if (c == '\n') {
		    iCleng = 1;		/* error pointer at newline */
		    yyerror("C code: newline in \" \" or ' ', error");
		} else if (c == EOF)  goto eof_error;
		putc(c, T1FP);
	    }
	    break;
	}
	putc(c, T1FP);			/* output to T1FN */
    }
eof_error:
    iCleng = 1;				/* error pointer at EOF */
    yyerror("C code: EOF, error");
    return 0;				/* EOF */
} /* copyCfrag */
