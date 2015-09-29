static const char rpi_rev_c[] =
"$Id: rpi_rev.c,v 1.3 2015/09/29 06:55:10 jw Exp $";
/********************************************************************
 *
 *	Copyright (C) 2015  John E. Wulff
 *
 *  You may distribute under the terms of either the GNU General Public
 *  License or the Artistic License, as specified in the README file.
 *
 *  For more information about this program, or for information on how
 *  to contact the author, see the README file
 *
 *	rpi_rev.c
 *	adapted from raspberryalphaomega.org.uk by John E. Wulff 2015
 *
 *	Returns the following board revisions for differen Raspberry Pi models
 *		0	(8  0x08)	Rpi A
 *		1	(15 0x0e)	Rpi B	tested by JW
 *		2	(16 0x10)	Rpi B+	tested by JW
 *		2	(0xa21041)	Rpi 2B	tested by JW
 *
 *	according to http://elinux.org/RPi_HardwareHistory
 *
 *    Revision 	Release Date 	Model 	PCB Rev	Memory 	Notes
 *	Beta 	Q1 2012 	B  	 ? 	256MB 	Beta Board
 *	0002 	Q1 2012 	B 	1.0 	256MB 	
 *	0003 	Q3 2012 	B  	1.0 	256MB 	(ECN0001) Fuses mod and D14 removed
 *	0004 	Q3 2012 	B 	2.0 	256MB 	(Mfg by Sony)
 *	0005 	Q4 2012 	B 	2.0 	256MB 	(Mfg by Qisda)
 *	0006 	Q4 2012 	B 	2.0 	256MB 	(Mfg by Egoman)
 *	0007 	Q1 2013 	A 	2.0 	256MB 	(Mfg by Egoman)
 *	0008 	Q1 2013 	A 	2.0 	256MB 	(Mfg by Sony)
 *	0009 	Q1 2013 	A 	2.0 	256MB 	(Mfg by Qisda)
 *	000d 	Q4 2012 	B 	2.0 	512MB 	(Mfg by Egoman)
 *	000e 	Q4 2012 	B 	2.0 	512MB 	(Mfg by Sony)
 *	000f 	Q4 2012 	B 	2.0 	512MB 	(Mfg by Qisda)
 *	0010 	Q3 2014 	B+ 	1.0 	512MB 	(Mfg by Sony)
 *	0011 	Q2 2014  Compute Module	1.0 	512MB 	(Mfg by Sony)
 *	0012 	Q4 2014 	A+ 	1.0 	256MB 	(Mfg by Sony) 
 *	a21041 			2B 		1024MB
 *	If you see a "1000" at the front of the Revision, e.g. 10000002
 *	then it indicates[1] that your Raspberry Pi has been over-volted,
 *	and your board revision is simply the last 4 digits (i.e. 0002 in this example).
 *
 *	Other models need to be checked as they become available
 *
 *******************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/file.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <assert.h>
#include <errno.h>
#include "rpi_rev.h"
#include "icc.h"			/* declares iC_emalloc() */

#ifndef RASPBERRYPI
#error - must be compiled with RASPBERRYPI
#else	/* RASPBERRYPI */

/********************************************************************
 *	Validate gpio pins for different processors
 *******************************************************************/
static long long	gpioValid[] = {
    0x000000000bc6cf93LL,	/* proc == 0 for Raspberry Pi A  (rev = 0x8  or 8) */
    0x00000000fbc6cf9cLL,	/* proc == 1 for Raspberry Pi B  (rev = 0xe  or 15) */
    0x000080480ffffffcLL,	/* proc == 2 for Raspberry Pi B+ (rev = 0x10 or 16) */
    				/* 	  or for Raspberry Pi 2B (rev = 0xa21041) */
};

int
boardrev(void) {
    FILE*	f;
    int 	rev;
    char	buf[1024];
    char *	needle;
    int		proc;

    if ((f = fopen("/proc/cmdline", "r")) == NULL) {
	perror("rpi_rev: fopen(/proc/cmdline\")");
	exit(-1);
    }
    fread(buf, 1, 1023, f);
    fclose(f);
    if ((needle = strstr(buf, "boardrev")) == NULL ||
	sscanf(needle, "boardrev=0x%x", &rev) != 1) {
	fprintf(stderr, "rpi_rev: cannot find \"boardrev\" in:\n%s\n", buf);
	exit(-1);
    }
    switch (rev & 0xffff) {	/* ignore overvolting */
    /* Revision   Release Date Model  PCB Rev	Memory	Notes */
    case 0x02:	/* Q1 2012 	B 	1.0 	256MB	 */
    case 0x03:	/* Q3 2012 	B  	1.0 	256MB 	(ECN0001) Fuses mod and D14 removed */
    case 0x04:	/* Q3 2012 	B 	2.0 	256MB 	(Mfg by Sony) */
    case 0x05:	/* Q4 2012 	B 	2.0 	256MB 	(Mfg by Qisda) */
    case 0x06:	/* Q4 2012 	B 	2.0 	256MB 	(Mfg by Egoman) */
	proc = 1;	/* Rpi B */
	break;
    case 0x07:	/* Q1 2013 	A 	2.0 	256MB 	(Mfg by Egoman) */
    case 0x08:	/* Q1 2013 	A 	2.0 	256MB 	(Mfg by Sony) */
    case 0x09:	/* Q1 2013 	A 	2.0 	256MB 	(Mfg by Qisda) */
	proc = 0;	/* Rpi A */
	break;
    case 0x0d:	/* Q4 2012 	B 	2.0 	512MB 	(Mfg by Egoman) */
    case 0x0e:	/* Q4 2012 	B 	2.0 	512MB 	(Mfg by Sony) */
    case 0x0f:	/* Q4 2012 	B 	2.0 	512MB 	(Mfg by Qisda) */
	proc = 1;	/* Rpi B */
	break;
    case 0x10:	/* Q3 2014 	B+ 	1.0 	512MB 	(Mfg by Sony) */
	proc = 2;	/* Rpi B+ */
	break;
    case 0x11:	/* Q2 2014  Comp Module	1.0 	512MB 	(Mfg by Sony) */
	proc = 2;	/* Rpi Compute Module? */
	break;
    case 0x12:	/* Q4 2014 	A+ 	1.0 	256MB 	(Mfg by Sony)  */
    default:
	proc = 2;	/* Rpi 2B (a21041) same GPIO pins as B+ */
	break;
    }
    return proc;
} /* boardrev */

/********************************************************************
 *
 *	Determine proc and valid
 *
 *	Open or create and lock the auxiliary file ~/.iC/gpios.used,
 *	which contains the struct Used u - one 64 bit word u.used
 *					 - one 64 bit word u.oops
 *
 *	return proc, valid, u.used and u.oops in static struct ProcValidUsed gpios
 *
 *	For an RPi B+ processor it contains:
 *		gpios.proc	1			// returned by boardrev()
 *		gpios.valid	0x00000000fbc6cf9c	// GPIOs valid for this RPi
 *		gpios.u.used	0x0000000000000000	// GPIOs used in other apps
 *		gpios.u.oops	0x0000000000000000	// bit to block iCtherm
 *
 *	If -f (forceFlag) is set the gpios.u.used is cleared unconditionally
 *		gpios.u.oops must stay set for iCtherm (cleared with iCtherm -f).
 *	Else only GPIO's not used in other apps can be used in this app.
 *
 *******************************************************************/

static FILE *		gpiosFP;
static int		gpiosFN;
static ProcValidUsed	gpios;
static char *		gpiosName;

ProcValidUsed *
openLockGpios(int force)
{
    int		exists = 1;
    char *	home;

    gpios.proc = boardrev();
    assert(gpios.proc < sizeof gpioValid / sizeof gpioValid[0]);
    gpios.valid = gpioValid[gpios.proc];
    home = getenv("HOME");
    gpiosName = iC_emalloc(strlen(home)+16);	/* +1 for '\0' */
    sprintf(gpiosName, "%s/.iC/gpios.used", home);
    if (access(gpiosName, F_OK) < 0) {
	if (errno == ENOENT) {
	    exists = 0;
	    if ((gpiosFP = fopen(gpiosName, "w+")) == NULL) {
		perror("cannot create ~/.iC/gpios.used");
		return NULL;	/* error */
	    }
	    gpios.u.used  = 0LL;
	    gpios.u.oops  = 0LL;
	} else {
	    perror("cannot access ~/.iC/gpios.used");
	    return NULL;	/* error */
	}
    }
    if (exists && (gpiosFP = fopen(gpiosName, "r+")) == NULL) {
	perror("cannot fopen ~/.iC/gpios.used");
	return NULL;		/* error */
    }
    if ((gpiosFN = fileno(gpiosFP)) < 0) {
	perror("cannot fileno ~/.iC/gpios.used");
	return NULL;		/* error */
    }
    if (flock(gpiosFN, LOCK_EX) < 0) {	/* block until file is unlocked - lock the file */
	perror("cannot lock ~/.iC/gpios.used");
	return NULL;		/* error */
    }
    if (force || ! exists) {
	gpios.u.used  = 0LL;		/* keep u.oops forever once set */
    } else if (fread(&gpios.u, sizeof gpios.u, 1, gpiosFP) < 1) {
	fprintf(iC_errFP, "ERROR: openLockGpios: fread failed\n");
	return NULL;		/* error */
    }
    return &gpios;			/* current proc valid used and oops */
} /* openLockGpios */

/********************************************************************
 *
 *	Write unlock and close the auxiliary file ~/.iC/gpios.used
 *	Unlink (remove) ~/.iC/gpios.used if !gpios.u.used && !gpios.u.oops
 *
 *******************************************************************/

int
writeUnlockCloseGpios(void)
{
    if (fseek(gpiosFP, 0L, SEEK_SET) < 0) {	/* rewind to re-write the file */
	perror("cannot fseek ~/.iC/gpios.used");
	return -1;		/* error */
    }
    if (fwrite(&gpios.u, sizeof gpios.u, 1, gpiosFP) < 1) {	/* 16 bytes u.used and u.oops */
	return -1;		/* error */
    }
    if (fsync(gpiosFN) < 0) {			/* write all data to disk */
	perror("cannot fsync ~/.iC/gpios.used");
	return -1;		/* error */
    }
    if (flock(gpiosFN, LOCK_UN) < 0) {		/* remove the lock held by this process */
	perror("cannot unlock ~/.iC/gpios.used");
	return -1;		/* error */
    }
    if (fclose(gpiosFP) < 0) {
	perror("cannot close ~/.iC/gpios.used");
	return -1;		/* error */
    }
    if (!gpios.u.used && !gpios.u.oops && unlink(gpiosName) < 0) {
	perror("cannot unlink ~/.iC/gpios.used");
	return -1;		/* error */
    }
    return 0;
} /* writeUnlockCloseGpios */
#endif	/* RASPBERRYPI */
