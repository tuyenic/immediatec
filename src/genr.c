static const char genr_c[] =
"@(#)$Id: genr.c,v 1.55 2003/12/22 18:19:32 jw Exp $";
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
 *	genr.c
 *	generator functions for icc compiler
 *
 *******************************************************************/

#ifdef _WINDOWS
#include	<windows.h>
#endif
#include	<stdio.h>
#ifndef _WINDOWS 
#include	<stdlib.h>
#endif
#include	<string.h>
#include	<assert.h>
#include	"icg.h"
#include	"icc.h"
#include	"comp.h"
#include	"comp_tab.h"

#define v(lp)	(lp->le_val) ? '~' : ' ', lp->le_sym->name
#define w(lp)	(lp->le_val) ? '~' : ' '

static Symbol *	templist;	/* temp list of un-named symbols */
static short	ttn;		/* for generating temp f object name */
#if YYDEBUG
static short	tn;
#endif
char		eBuf[1024];	/* temporary expression text buffer */

/********************************************************************
 *
 *	initialize for code generation
 *
 *******************************************************************/

void
initcode(void)			/* initialize for code generation */
{
    templist = 0;
#if YYDEBUG
    tn = 0;
#endif
} /* init_code */

/********************************************************************
 *
 *	create List element for variable
 *
 *******************************************************************/

List_e *
sy_push(Symbol * var)	/* create List element for variable */
{
    List_e *	lp;

    lp = (List_e *) emalloc(sizeof(List_e));
    lp->le_sym = var;	/* point to variables Symbol entry */
#if YYDEBUG
    if ((debug & 0402) == 0402) {
	fprintf(outFP, "++%s\n", var->name);
	fflush(outFP);
    }
#endif
    return (lp);	/* return pointer to List_e to yacc */
} /* sy_push */

/********************************************************************
 *
 *	delete List element left over
 *
 *******************************************************************/

Symbol *
sy_pop(List_e * lp)	/* delete List element left over */
{
    Symbol *	sp;

    sp = lp->le_sym;	/* point to variables Symbol entry */
    free(lp);
#if YYDEBUG
    if ((debug & 0402) == 0402) {
	fprintf(outFP, "  %s--\n", sp->name);
	fflush(outFP);
    }
#endif
    return (sp);	/* return pointer to Symbol to yacc */
} /* sy_pop */

/********************************************************************
 *
 *	force linked Symbol to correct ftype
 *
 *******************************************************************/

List_e *
op_force(		/* force linked Symbol to correct ftype */
    List_e *		lp,
    unsigned char	ftyp)
{
    Symbol *		sp;
    List_e *		lp1;

    if (lp && (sp = lp->le_sym)->ftype != ftyp) {
	if (sp->u.blist == 0 ||			/* not a $ symbol or */
	    (sp->type & TM) >= MAX_GT ||	/* SH, FF, EF, VF, SW, CF or */
	    sp->u.blist->le_sym == sp && sp->type == LATCH) { /* L(r,s) */
	    lp1 = op_push(0, types[sp->ftype], lp);
	    lp1->le_first = lp->le_first;
	    lp1->le_last = lp->le_last;
	    lp = lp1;	/* create a new $ symbol linked to old */
	    sp = lp->le_sym;
	}
#if YYDEBUG
	if ((debug & 0402) == 0402) {
	    fprintf(outFP, "\tforce %s from %s to %s\n",
		sp->name, full_ftype[sp->ftype], full_ftype[ftyp]);
	    fflush(outFP);
	}
#endif
	sp->ftype = ftyp;	/* convert old or new to ftyp */
    }
    return (lp);	/* return 0 or link to old or new Symbol */
} /* op_force */

/********************************************************************
 *
 *	reduce List_e stack to links
 *
 *******************************************************************/

List_e *
op_push(			/* reduce List_e stack to links */
    List_e *		left,
    unsigned char	op,
    List_e *		right)
{
    List_e *		rlp;
    Symbol *		sp;	/* current temporary Symbol */
    char 		temp[8];
    Symbol *		lsp;
    Symbol *		tsp;
    List_e *		lp;
    int			typ;

    if (right == 0) {
	if ((right = left) == 0) return 0;	/* nothing to push */
	left = 0;
    }
    rlp = right;
    sp = rlp->le_sym;
    typ = sp->type & TM;
    if (left && op > OR && op < MAX_LV && op != typ) {
	warning("function types incompatible", NS);
    }
    if (sp->u.blist == 0 || op != typ) {
	/* right not a $ symbol or new operator - force new level */
	sp = (Symbol *) emalloc(sizeof(Symbol));
	sp->name = NS;		/* no name at present */
#if YYDEBUG
	if ((debug & 0402) == 0402) {	/* DEBUG name */
	    sprintf(temp, "$%d", ++tn);
	    sp->name = emalloc(strlen(temp)+1);	/* +1 for '\0' */
	    strcpy(sp->name, temp);
	}
#endif
	sp->type = op != UDF ? op : AND; /* operator OR or AND (default) */
	sp->ftype = rlp->le_sym->ftype;	 /* used in op_xor() with op UDF */
	sp->next = templist;	/* put at front of templist */
	templist = sp;
	rlp->le_next = 0;	/* sp->u.blist is 0 for new sp */
	sp->u.blist = rlp;	/* link right of expression */
	rlp = sy_push(sp);	/* push new list element on stack */
    }
    if (left) {
	lsp = left->le_sym;	/* test works correctly with ftype - handles ALIAS */
	if (lsp->ftype >= MIN_ACT && lsp->ftype < MAX_ACT) {
	    if (sp->ftype < S_FF) {
		sp->ftype = 0;	/* OK for any value of GATE */
	    }
	    sp->ftype |= lsp->ftype;	/* modify S_FF ==> D_FF */
	}
	if ((typ = lsp->type & TM) < MAX_LS) {
	    if ((lp = lsp->u.blist) == 0 ||	/* left not a $ symbol */
		sp == lsp ||			/* or right == left */
		typ != op &&			/* or new operator */
			/* ZZZ watch this when typ is ALIAS or UDF */
		typ != TIM ||			/* but left is not a timer */
		typ == op &&			/* or old operator */
		right->le_val == (unsigned) -1)	/* and right is a delay for timer */
	    {
		left->le_next = sp->u.blist;	/* extend expression */
		sp->u.blist = left;		/* link left of expr */
#if YYDEBUG
		if ((debug & 0402) == 0402) {
		    fprintf(outFP, "\t%c%s %c %c%s\n",
			v(left), os[op], v(right));
		    fflush(outFP);
		}
#endif
	    } else {	/* left is a $ symbol and ... - merge left into right */
		while (lp->le_next) {
		    lp = lp->le_next;
		}
		lp->le_next = sp->u.blist;	/* move connect list */
		sp->u.blist = lsp->u.blist;	/* in the right order */
		if (templist != lsp) {
		    tsp = templist;			/* scan templist */
		    while (tsp->next != lsp) {
			tsp = tsp->next;
			if (tsp == 0) {
			    execerror("left temp not found ???\n", NS, __FILE__, __LINE__);
			}
		    }
		    tsp->next = lsp->next;		/* unlink lsp from templist */
		} else {
		    templist = lsp->next;		/* unlink first object */
		}
#if YYDEBUG
		if ((debug & 0402) == 0402) {
		    fprintf(outFP, "\t%c%s %c %c%s\n",
			v(left), os[op], v(right));
		    fflush(outFP);
		}
		sy_pop(left);			/* left Link_e */
		if ((debug & 0402) == 0402) {
		    free(lsp->name);		/* free name space */
		}
		free(lsp);			/* left Symbol */
#else
		free(sy_pop(left));		/* left Link and Symbol */
#endif
	    }
	} else {				/* discard left BLT, CLT */
	    sy_pop(left);			/* Link_e only */
	}
#if YYDEBUG
    } else if ((debug & 0402) == 0402) {		/* fexpr : sexpr { left is 0 } */
	fprintf(outFP, "\t(0) %c %c%s\n", os[op], v(right));
	fflush(outFP);
#endif
    }
    return (rlp);
} /* op_push */

/********************************************************************
 *
 *	numeric constant push
 *
 *******************************************************************/

int
const_push(Lis * expr)
{
    char *	cp = expr->f;
    char *	ep = expr->l;
    int		bc = 30;
    char	buf[30];
    char *	bp = buf;
    Symbol *	symp;
    while (cp < ep) {
	if (--bc == 0 || !isdigit(*bp++ = *cp++)) {
	    return 1;			/* error - too big or not a digit */
	}
    }
    *bp = 0;		/* terminate - there is room in buf */
    if ((symp = lookup(buf)) == 0) {
	symp = install(buf, NCONST, ARITH);	/* becomes NVAR */
    }
    expr->v = sy_push(symp);
    return 0;				/* correct - no error */
} /* const_push */

/********************************************************************
 *
 *	special exclusive or push
 *
 *******************************************************************/

List_e *
op_xor(				/* special exclusive or push */
    List_e *	left,
    List_e *	right)
{
    List_e *	inv_left;
    List_e *	inv_right;
    List_e*	lp1;
    List_e*	lp2;

    inv_left = sy_push(left->le_sym);	/* duplicate arg list entries */
    inv_right = sy_push(right->le_sym);
    inv_left->le_val = left->le_val ^ NOT;	/* invert */
    inv_right->le_val = right->le_val ^ NOT;	/* invert */
    /*
     * left ^ right === (left & ~right) | (~left & right)
     * the op "UDF" forces a new level in op_push
     * it is then changed to AND 
     * thus a new level is forced even if left or right is AND
     */
    lp2 = op_push(inv_left, UDF, right);	/* ~left & right */
    lp1 = op_push(left, UDF, inv_right);	/* left & ~right */
    lp2->le_first = lp1->le_first = inv_left->le_first = left->le_first;
    inv_left->le_last = left->le_last;
    inv_right->le_first = right->le_first;
    lp2->le_last = lp1->le_last = inv_right->le_last = right->le_last;
    return op_push(lp1, OR, lp2);		/* left ^ right */
} /* op_xor */
 
/********************************************************************
 *
 *	logical negation
 *
 *******************************************************************/

List_e *
op_not(List_e * right)		/* logical negation */
{
    Symbol *	sp;
    List_e *	lp;
    Symbol *	ssp;
    List_e *	llp;

    if (!(lp = (sp = right->le_sym)->u.blist)) {
	right->le_val ^= NOT;		/* negate logical value */
    } else {
	switch (sp->type) {			/* $ symbol */
	case AND:
	case OR:
	case EXT_AND:
	case EXT_OR:
	    sp->type ^= (AND ^ OR);		/* de Morgans rule */
	case LATCH:
	    while (lp) {
		if (lp->le_sym != sp) {		/* ignore latch feedback */
		    lp->le_val ^= NOT;
		}
		lp = lp->le_next;
	    }
	    break;
	case ARNC:
	case ARN:
	case LOGC:
	case SH:
	case FF:
	case VF:
	case EF:
	case SW:
	case CF:
	case EXT_ARN:
	    right->le_val ^= NOT;	/* negate logical value */
	    				/* forces creation of alias */
	    break;			/* if assigned immediately */
	case INPW:
	case INPX:
	    execerror("INPUT has other inputs in op_not() ???", sp->name, __FILE__, __LINE__);
	    break;
	default:
	    execerror("negation of non-logical value attempted", sp->name, __FILE__, __LINE__);
	    break;
	}
    }
#if YYDEBUG
    if ((debug & 0402) == 0402) {
	fprintf(outFP, "    ~%s\n", right->le_sym->name);
	fflush(outFP);
    }
#endif
    return (right);
} /* op_not */

/********************************************************************
 *
 *	asign List_e stack to links
 *
 *	Sym sv contains Symbol *v and char *f and *l to source
 *	Lis lr contains List_e *v and char *f and *l to source
 *	unsigned char ft is the ftype which right must be forced to
 *
 *******************************************************************/

Symbol *
op_asgn(				/* asign List_e stack to links */
    Sym *		sv,		/* may be 0 for ffexpr */
    Lis *		rl,
    unsigned char	ft)
{
    Symbol *	var;
    Symbol *	sp;
    List_e *	lp;
    Symbol *	gp;
    Symbol *	rsp;
    List_e *	tlp;
    List_e *	right;
    char	temp[100];
    short	atn;
    short	sflag;
    Symbol *	sr;
    char *	t_last = 0;
    char *	t_first = 0;
    int		typ;

    right = op_force(rl->v, ft);	/* force Symbol on right to ftype ft */
    if (sv == 0) {
	/* null var - generate a temporary Symbol of type UNDEF */
	var = (Symbol *) emalloc(sizeof(Symbol));
	sprintf(temp, "_f%d", ++ttn);
	var->name = emalloc(strlen(temp)+1);	/* +1 for '\0' */
	strcpy(var->name, temp);	/* name needed for derived Sy's */
	sflag = 0;			/* don't output name */
    } else {
	var = sv->v;			/* Symbol * var */
	sflag = 1;			/* print output name */
    }
#if YYDEBUG
    if ((debug & 0402) == 0402) {
	fprintf(outFP, "\t  %s = %c%s\n", var->name, v(right));
	fflush(outFP);
    }
#endif
    rsp = right->le_sym;
    if ((typ = var->type & TM) >= AND && typ != rsp->type & TM) {
	if (typ != ERR) {
	    ierror("type mismatch in multiple assignment:", var->name);
	    var->type = ERR;		/* reduce anyway to clear list */
	}
    } else {
	var->type = rsp->type & TM;
	if (var->ftype < MIN_ACT) {
	    var->ftype = rsp->ftype;
	}
    }
    if (rsp->type == NCONST || rsp->u.blist == 0) {		/* right must be a $ symbol */
	if (var->type != ERR) {
	    var->type = ALIAS;		/* alias found */
	}
	/***********************************************************
	 *  Change right to point to source of ALIAS, adjusting
	 *  negation correctly. An ALIAS must have a gate it points
	 *  to via list.
	 ***********************************************************/
	while (rsp->type == ALIAS) {	/* scan down list of aliases */
	    if (var == rsp) {
		var->type = ERR;	/* error found */
		ierror("circular list of aliases:", var->name);
		break;			/* circular list of aliases */
	    }
	    right->le_val ^= rsp->list->le_val;
	    if (!(rsp = rsp->list->le_sym)) {
		execerror("ALIAS points to nothing ???",
		right->le_sym->name, __FILE__, __LINE__);
	    }
	    right->le_sym = rsp;
	}
	/***********************************************************
	 *  If there are gates driven by var, which is an ALIAS,
	 *  the output list must be scanned and negations carried out.
	 *  Link rsp's output list to end of scanned list and
	 *  link var's list to rsp and point var to right->rsp.
	 *  This means that future use of the ALIAS will be resolved.
	 ***********************************************************/
	if ((lp = tlp = var->list) != 0) {	/* start of left list */
	    while (lp->le_next) {
		lp->le_val ^= right->le_val;
		lp = lp->le_next;	/* scan to end of left list */
	    }
	    lp->le_val ^= right->le_val;
	    lp->le_next = rsp->list;	/* link right to end of left */
	    rsp->list = tlp;		/* link full list to right */
	}
	var->list = right;		/* alias points to original */
	if (debug & 04) {
	    iFlag = 1;
	    fprintf(outFP, "\n\t%s\t%c ---%c\t%s\n\n", rsp->name,
		((typ = rsp->type & TM) >= MAX_LV) ? os[typ] : w(right),
		os[var->type & TM], var->name);
	}
	if (sv == 0) {
	    execerror("ALIAS points to temp ???", var->name, __FILE__, __LINE__);
	} else {
	    t_first = sv->f; t_last = sv->l;	/* full text of var */
	    while (t_first && t_first < t_last) {
		*t_first++ = '#';		/* mark left var, leave ALIAS */
	    }
	}
	return (var);			/* needs no reduction */
    }

    if (rsp != (sp = templist)) {
	if (sp == 0) goto FailTemplist;
	while (rsp != sp->next) {
	    if ((sp = sp->next) == 0) {			/* DEBUG */
	      FailTemplist:
		execerror("right->le_sym not found in templist ???",
		    right->le_sym->name, __FILE__, __LINE__);
	    }
	}
	sp->next = rsp->next;	/* link tail to head in front of rsp */
	rsp->next = templist;	/* link head to rsp */
	templist = rsp;		/* now rsp is head of templist */
    }
    if (((typ = rsp->type & TM) == CLK || typ == TIM) && var->ftype != rsp->ftype) {
	warning("clock or timer assignment from wrong ftype:", var->name);
    }

    sr = rsp->u.blist->le_sym;		/* gate linked to var */
    if (right->le_val == NOT ^ NOT) {
	var->u.blist = rsp->u.blist;	/* move blist from rsp to var */
	templist = rsp->next;		/* bypass rsp */
    } else {
	/* make var an ALIAS because of FF negation */
	rsp->ftype = GATE;		/* may be odd value from gen */
	var->type = ALIAS;		/* make var negated ALIAS */
	var->u.blist = right;		/* link var to right */
    }

    atn = 0;
    sp = var;				/* start reduction with var */
    t_first = rl->f; t_last = rl->l;	/* full text of expression */
#if YYDEBUG
    if ((debug & 0402) == 0402) fprintf(outFP, "resolve \"%s\" to \"%s\"\n", t_first, t_last);
#endif
    do {				/* marked symbol */
	int	gt_input;
	char *	ep = eBuf;		/* temporary expression buffer */
	if (debug & 04) {
	    fprintf(outFP, "\n");
	}
	gt_input = 0;			/* output scan for 1 gate */
	while ((lp = sp->u.blist) != 0) {
	    sp->u.blist = lp->le_next;
	    if ((gp = lp->le_sym) == rsp && var->type != ALIAS) {
		gp = var;		/* link points to right */
	    }
	    while (gp->type == ALIAS) {
		lp->le_val ^= gp->list->le_val;	/* negate if necessary */
		gp = gp->list->le_sym;		/* point to original */
	    }
	    if (sp == gp && sp->ftype >= MIN_ACT) {
		if (sp->type == LATCH && sp->ftype == D_FF) {
		    gp = sp->list->le_sym;	/* feedback via D output */
		} else if (gt_input) {
		    warning("input equals output at function gate:", sp->name);
		} else {
		    /****************************************************
		     * no logical inputs yet: can split function and logic
		     *
		     *	O1 = CLOCK(L(I1, I2));
		     *			clock	: ---%	O1_1	C ---:	O1
		     *	O1_2	  ---%	O1_2	  ---|	O1_1
		     *	I1	  ---%	O1_2
		     *	I2	~ ---%	O1_2	<--- new gp
		     ***************************************************/
		    gp = (Symbol *) emalloc(sizeof(Symbol));
		    gp->name = NS;		/* no name at present */
#if YYDEBUG
		    if ((debug & 0402) == 0402) {	/* DEBUG name */
			sprintf(temp, "$%d", ++tn);
			gp->name = emalloc(strlen(temp)+1);
			strcpy(gp->name, temp);
		    }
#endif
		    gp->type = sp->type;
		    gp->ftype = GATE;
		    sp->type = OR;		/* OR default for 1 input */
		    gp->next = templist;	/* put at front of list */
		    templist = gp;
		    gp->u.blist = tlp = sy_push(gp);	/* link self */
		    tlp->le_next = sp->u.blist;	/* rest of inputs on sp */
		    sp->u.blist = 0;
		}
	    }
	    if (sp->type == ALIAS) {
		/* var was made an ALIAS because of FF negation */
		gp->list = tlp = sp->list;	/* start of left list */
		while (tlp) {
		    tlp->le_val ^= lp->le_val;	/* negate if necesary */
		    tlp = tlp->le_next;		/* scan to end of list */
		}
		sp->list = lp;		/* link ALIAS to right */
	    } else {
		/* link Symbols to the end of gp->list to maintain order */
		lp->le_next = 0;
					/* && gp->u.blist ZZZ */
		if (gp->ftype == ARITH &&
		    sp->ftype != OUTW &&
		    lp->le_val != (unsigned) -1) {
		    lp->le_val = c_number + 1;	/* arith case # */
		}
		if ((tlp = gp->list) == 0) {
		    gp->list = lp;	/* this is the first Symbol */
		} else {
		    /* loop to find duplicate link (possibly inverted) */
		  loop:		/* special loop with test in middle */
		    if (tlp->le_sym == sp) {
			if (gp->ftype == OUTW || gp->ftype == OUTX) {
			    warning("input equals output at output gate:", gp->name);
			} else if (tlp->le_val == lp->le_val) {
			    sy_pop(lp);	/* ignore duplicate link */
			    continue;	/* output scan for 1 gate */
			} else if (gp->ftype != ARITH) {
			    warning("gate has input and inverse:", gp->name);
			}
		    }
		    if (tlp->le_next) {
			tlp = tlp->le_next;	/* find last Symbol */
			goto loop;
		    }
		    tlp->le_next = lp;	/* put new Symbol after last */
		}
		lp->le_sym = sp;	/* completely symmetrical */
		if ((gp->type & TM) < MAX_LV) {
		    gt_input++;		/* count the gate inputs */
		}
	    }
	    if (! gp->name
#if YYDEBUG
		|| *(gp->name) == '$'
#endif
	    ) {			/* not marked symbol */
#if YYDEBUG
		if ((debug & 0402) == 0402) {
		    if (debug & 04) {
			fprintf(outFP, "%s =", gp->name);
		    } else {
			fprintf(outFP, "\t  %s cleared\n", gp->name);
		    }
		    free(gp->name);		/* free name space */
		}
#endif
		sprintf(temp, "%s_%d", var->name, ++atn);
		gp->name = emalloc(strlen(temp)+1);	/* +1 for '\0' */
		strcpy(gp->name, temp);	/* mark Symbol */
	    }
	    if (debug & 04) {
		if ((typ = gp->type & TM) >= MAX_LV) {
		    fprintf(outFP, "\t%s\t%c ---%c", gp->name, os[typ],
			os[sp->type & TM]);
		} else if (gp->ftype < MAX_AR && lp->le_val == (unsigned) -1) {
		    /* reference to a timer value - no link */
		    fprintf(outFP, "\t%s\t%c<---%c", gp->name, fos[gp->ftype],
			os[sp->type & TM]);
		} else if (gp->ftype != GATE) {
		    fprintf(outFP, "\t%s\t%c ---%c", gp->name, fos[gp->ftype],
			os[sp->type & TM]);
		} else {
		    if (sp->type == ALIAS) iFlag = 1;
		    fprintf(outFP, "\t%s\t%c ---%c", gp->name, w(lp),
			os[sp->type & TM]);
		}
		if (sflag) {
		    fprintf(outFP, "\t%s", sp->name);
		    if (sp->ftype != GATE) {
			fprintf(outFP, "\t%c", fos[sp->ftype]);
		    }
		}
		if (gp->ftype == F_SW || gp->ftype == F_CF || gp->ftype == F_CE ||
		    (gp->ftype == TIMR && lp->le_val > 0)) {
		    /*
		     * case number of "if" or "switch" C fragment
		     * or timer preset off value
		     */
		    fprintf(outFP, " (%d)", lp->le_val);
		}
	    }
	    if (gp->ftype == ARITH && (sp->type & TM) == ARN && lp->le_val != (unsigned) -1 &&
		(gp->u.blist || gp->type == NCONST)) {
		char	buffer[BUFS];	/* buffer for modified names */
		char	iqt[2];		/* char buffers - space for 0 terminator */
		char	xbwl[2];
		int	byte;
		int	bit;
		char	tail[8];	/* compiler generated suffix _123456 max */

		if (debug & 04) {
		    /* only logic gate or SH can be aux expression */
		    if (sflag) {
			if (sp->ftype == GATE) {
			    putc('\t', outFP);
			}
			putc('\t', outFP);
		    } else {
			fprintf(outFP, "\t\t\t");
		    }
		}
		while (t_first && t_first < lp->le_first) {	/* end of arith */
		    if (*t_first != '#') {	/* transmogrified '=' */
			if (debug & 04) putc(*t_first, outFP);
			*ep++ = *t_first;
		    }
		    t_first++;
		}
		if (debug & 04) fprintf(outFP, "%s", gp->name);
		/* modify numbers, IXx.x and QXx.x names for compiled output only */
	    				/* CHECK if ep changes now _() is missing */
		IEC1131(gp->name, buffer, BUFS, iqt, xbwl, &byte, &bit, tail);
		ep += sprintf(ep, "%s", buffer);
		t_first = lp->le_last;	/* skip logic expr's */
	    }
	    if (debug & 04) {
		fprintf(outFP, "\n");
		sflag = debug & 0200;
	    }
	    if (sp == gp && (sp->type != LATCH || lp->le_val != NOT ^ NOT)) {
		warning("input equals output at gate:", sp->name);
	    }
	}					/* end output scan for 1 gate */
	if ((sp->type & TM) == ARN) {
	    if (debug & 04) fprintf(outFP, "\t\t\t\t\t");
	    while (t_first && t_first < t_last) {
		if (*t_first != '#') {	/* transmogrified '=' */
		    if (debug & 04) putc(*t_first, outFP);
		    *ep++ = *t_first;
		}
		t_first++;
	    }
	    *ep++ = 0;
						/* start case or function */
	    if (sp->ftype != OUTW) {	/* output cexe function */
		fprintf(T1FP, cexeString[outFlag], ++c_number);
		fprintf(T1FP, "#line %d \"%s\"\n", lineno, inpNM);
		fprintf(T1FP, "	return %s;\n", eBuf);
		fprintf(T1FP, "%%##\n%s", outFlag ? "}\n\n" : "\n");
		if (debug & 04) fprintf(outFP, "; (%d)\n", c_number);
	    }
	}
	sflag = 1;			/* print output name */
	if (gt_input > PPGATESIZE) {
	    sp->type = ERR;		/* cannot execute properly */
	    ierror("too many inputs on gate:", sp->name);
	}
	if ((gp = sp = templist) != 0) {
	    if (sp->name
#if YYDEBUG
		&& *(sp->name) != '$'
#endif
	    ) {				/* marked symbol is first */
		templist = sp->next;	/* by_pass marked symbol */
	    } else {
		while ((sp = sp->next) != 0 && (!sp->name
#if YYDEBUG
		    || *(sp->name) == '$'
#endif
		)) {
		    gp = sp;		/* look for marked symbol */
		}
		if (sp) {
		    gp->next = sp->next;/* by_pass marked symbol */
		}
	    }
	    if (sp) {
		(void) place_sym(sp);	/* place sp in the symbol table */
		if ((sp->type & TM) == ARN) {
		    assert(sp->list);
		    t_first = sp->list->le_first;
		    t_last = sp->list->le_last;
		    assert(t_first && t_last);
		}
	    }
	}
    } while (sp);			/* 1 symbol resolved */

    /*
     * right Symbol must remain intact until after reduction, because
     * there may be a reference to it which is tested in if(gp == rsp).
     * When rsp is freed before reduction, rsp may point to a newly
     * generated Symbol, which is not a reference to right Symbol.
     * Therefore free here.
     */

    if (right->le_val == NOT ^ NOT) {
	sy_pop(right);			/* right Symbol and List_e */
#if YYDEBUG
	if ((debug & 0402) == 0402) {
	    free(rsp->name);		/* free name space of $x */
	}
#endif
	free(rsp);			/* free right Symbol */
    }
    if (debug & 04) {
	fprintf(outFP, "\n");
    }

    /*
     * A Symbol is marked by storing a pointer value in ->name
     * which points to a string which does not start with $.
     * Only marked symbols are reduced.
     * Any remaining new Symbols on 'templist' must belong to an outer
     * assignment which will be reduced later.
     */

    t_first = rl->f; t_last = rl->l;	/* full text of expression */
    while (t_first && t_first < t_last) {
	*t_first++ = '#';		/* mark embedded assignments */
    }
    if (sv == 0) {
	lp = sr->list;			/* link action to temp */
	if (lp->le_sym != var || lp->le_next) {
	    execerror("error in unlinking temp:", var->name, __FILE__, __LINE__);
	}
	lp->le_sym = 0;			/* erase reference to temp */
#if YYDEBUG
	if ((debug & 0402) == 0402) {
	    fprintf(outFP, "\t  %s deleted\n\n", var->name);
	    fflush(outFP);
	}
#endif
	free(var->name);		/* free name space */
	free(var);			/* temporary Symbol */
	return 0;
    }
    return (sv->v);
} /* op_asgn */

/********************************************************************
 *
 *	Asign to QBx or QWx	when ft == ARITH
 *	Asign to QXx.y		when ft == GATE
 *
 *	Outputs are ordinary nodes of type ARITH or GATE which may
 *	be used as values anywhere, even before they are assigned.
 *
 *	When the right expression of the assignment is a direct Symbol
 *	that Symbol drives the output gate. This assignment generates
 *	an ALIAS in the usual way. This ALIAS may contain a logic
 *	inversion.
 *
 *	The actual output action is handled by an auxiliary node of
 *	ftype OUTW or OUTX, which is linked to the output value node,
 *	carrying the name of the output. This auxiliary node is never
 *	and can never be used as an input value.
 *
 *	The use of output values before assignment is necessary in iC,
 *	to allow the implementation of feedback in single clocked
 *	expressions. eg: the following output word of 1 second counts
 *
 *		QW1 = SH(QW1 + 1, clock1Second);
 *
 *	The same could of course be realised by using a counter
 *	variable and assigning the output independently. But this way
 *	the compiler does the job - which is what it should do.
 *
 *	With this implementation, the fact that outputs are not full
 *	logic or arithmetic values is completely hidden from the user,
 *	which removes unnecessary errors in user code.
 *
 *******************************************************************/

/********************************************************************
 *
 *	Return operator to use in built in iC functions
 *
 *	this logic ensures that type is taken over if possible to
 *	allow a gate to become an action gate without unnecessary
 *	forcing of levels.
 *
 *	only if a gate is undefined or drives an output use a type
 *	derived from the ftype.
 *
 *	Master gates lead to either ARN or OR
 *
 *******************************************************************/

static unsigned char
bTyp(List_e * lp)
{
    Symbol *		symp;
    unsigned char	tp;
    unsigned char	ft;

    symp = lp->le_sym;
    while (symp->type == ALIAS) {
	symp = symp->list->le_sym;	/* with token of original */
    }
    tp = symp->type & TM;
    return tp >= MAX_GT ? (tp == SH || tp == INPW ? ARN : OR)
			: tp == UDF ||
			  symp->u.blist == 0 || 		  
    symp->list &&
    ((ft = symp->list->le_sym->ftype) == OUTX || ft == OUTW) ? types[symp->ftype]
							     : tp;
} /* bTyp */

/********************************************************************
 *
 *	Push one parameter with its clock for a built in iC function
 *
 *******************************************************************/

static List_e *
para_push(
    Sym* fname,
    Lis* aex, Lis* crx,
    Lis* cr3,
    List_e* lp3,
    unsigned char ft,				/* 0 or S_FF or R_FF */
    List_e** alp1)
{
    List_e *	lp1;
    List_e *	lp2;
    List_e *	lpc;

    /* lpc is either own clock crx->v or clock cloned from cr3->v or iClock */
    lp1 = 0;
    lpc = crx ? crx->v				/* individul clock or timer crx */
	      : cr3 ? sy_push((lp1 = cr3->v->le_sym->u.blist) ? lp1->le_sym
							      : cr3->v->le_sym)
						/* or clone last clock or timer cr3 */
		    : sy_push(iclock);		/* or clone default clock iClock */
    if (lp1 && lp1->le_sym->ftype == TIMRL) {
	lp1 = lp1->le_next;			/* type TIM, TIM|TM+1, UDF or ALIAS */
	assert(lp1);				/* clone associated timer value */
	assert(lp1->le_val == (unsigned) -1);
	lpc = op_push(lpc, TIM, sy_push(lp1->le_sym));
	lp2 = lpc->le_sym->u.blist;
	assert(lp2 && lp2->le_next);
	lp2 = lp2->le_next;
	lp2->le_val = (unsigned) -1;		/* mark link as timer value */
	lp2->le_first = lp1->le_first;		/* copy expr text */
	lp2->le_last  = lp1->le_last;		/* copy expr termination */
    }
    lp1 = op_push(sy_push(fname->v), bTyp(aex->v), aex->v);
    lp1->le_first = aex->f; lp1->le_last = aex->l;
    if (ft) {
	if (lp1->le_sym->ftype == D_FF ||	/* force ft for set or reset */
	    lp1->le_sym->ftype == S_FF) {
	    lp1->le_sym->ftype = ft;		/* right ftype for SR, DSR, DR */
	} else if (lp1->le_sym->ftype == D_SH ||
	    lp1->le_sym->ftype == S_SH) {
	    lp1->le_sym->ftype = S_SH + ft - S_FF;/* right ftype for SHSR, SHR */
	}
    }
    *alp1 = op_push(lpc, lp1->le_sym->type & TM, lp1);	/* return lp1 for pVal */
    lp2 = op_push((List_e *)0, types[lp1->le_sym->ftype], lp1);
    return lp3 ? op_push(lp3, types[lp3->le_sym->ftype], lp2) : lp2;
}
/********************************************************************
 *
 *	Common code to generate built in iC functions
 *
 *******************************************************************/

List_e *
bltin(
    Sym* fname,					/* function name and ftype */
    Lis* ae1, Lis* cr1,				/* expression */
    Lis* ae2, Lis* cr2,				/* optional set */
    Lis* ae3, Lis* cr3,				/* optional reset */
    Lis* crm,					/* optional mono-flop clock */
    Val* pVal)					/* optional cblock# or off-delay */
{
    List_e *	lp1;
    List_e *	lp2;
    List_e *	lp3;

    if (ae1 == 0 || ae1->v == 0) {
	warning("first parameter missing. builtin: ", fname->v->name);
	return 0;				/* YYERROR in fexpr */
    }
    lp3 = para_push(fname, ae1, cr1, cr3, 0, 0, &lp1);	/* lp1 needed for pVal */

    if (ae2) {
	if (ae2->v == 0) {
	    warning("second parameter missing. builtin: ", fname->v->name);
	    return 0;				/* YYERROR in fexpr */
	}
	lp3 = para_push(fname, ae2, cr2, cr3, lp3, S_FF, &lp2);
    }

    if (ae3) {
	if (ae3->v == 0) {
	    warning("third parameter missing. builtin: ", fname->v->name);
	    return 0;				/* YYERROR in fexpr */
	}
	lp3 = para_push(fname, ae3, cr3, 0, lp3, R_FF, &lp2);	/* 0 stops cloning */
    }

    if (crm) {
	/* extra Master for mono-flop is reset fed back from own output */
	lp1 = sy_push(ae1->v->le_sym);		/* use dummy ae1 fill link */
	lp2 = op_push(sy_push(fname->v), UDF, lp1);
	if (lp2->le_sym->ftype == S_FF) {
	    lp2->le_sym->ftype = R_FF;		/* next ftype for SR flip flop*/
	}
	lp2 = op_push(crm->v, lp2->le_sym->type & TM, lp2);
	lp2 = op_push((List_e *)0, types[lp2->le_sym->ftype], lp2);
	lp3 = op_push(lp3, types[lp3->le_sym->ftype], lp2);

	lp1->le_sym = lp3->le_sym;		/* fix link from own */
    }

    if (pVal) {
	/* cblock number for ffexpr or preset off delay for timer */
	lp1->le_val = pVal->v;			/* unsigned int value for case # */
    }
    return lp3;
} /* bltin */
