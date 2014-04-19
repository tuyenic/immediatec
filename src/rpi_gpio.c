static const char rpi_gpio_c[] =
"$Id: rpi_gpio.c,v 1.1 2014/04/15 09:55:36 jw Exp $";
/********************************************************************
 *
 *	Copyright (C) 2014  John E. Wulff
 *
 *  You may distribute under the terms of either the GNU General Public
 *  License or the Artistic License, as specified in the README file.
 *
 *  For more information about this program, or for information on how
 *  to contact the author, see the README file
 *
 *	rpi_gpio.c
 *	communication to/from GPIO pins on the Raspberry Pi using
 *	the /sys/class/gpio interface to the GPIO system
 *
 *
 *  The following routines were partly extracted from gpio.c
 *  Copyright (c) 2012 Gordon Henderson
 *
 *  It seems tidier to use these routines directly to access the
 *  /sys/class/gpio device interface rather than execute 'gpio' from C
 *
 *  This version has been modified  by John E. Wulff	2014/03/25
 *  for the immediate C system to interface with a PiFace in
 *  accordance with the terms of the GNU Lesser General Public License
 *
 *******************************************************************/

#include	<sys/ioctl.h>
#include	<errno.h>
#include	<signal.h>
#include	<fcntl.h>
#include	<assert.h>
#include	"rpi_gpio.h"

/****************************************************************
 *
 *	gpio_fd_open	# open /sys/class/gpio/gpioN/value
 *	gpio		# RPi gpio pin number
 *
 ****************************************************************/

int
gpio_fd_open(unsigned int gpio)
{
    char	buf[32];

    snprintf(buf, 32, "/sys/class/gpio/gpio%d/value", gpio);
    return open(buf, O_RDONLY | O_NONBLOCK );
} /* gpio_fd_open */

/****************************************************************
 *
 *	gpio_read	# digital read of /sys/class/gpio/gpioN/value
 *	fd		# file number previously opened for pin gpio
 *
 ****************************************************************/

int
gpio_read(int fd)
{
    char	c;

    if (fd == -1) return -1;
    lseek(fd, 0L, SEEK_SET);
    read (fd, &c, 1);
    return (c == '1') ? 1 : (c == '0') ? 0 : -1;
} /* gpio_fd_open */

/********************************************************************
 *
 *	changeOwner:
 *
 *	Change the ownership of the file to the real userId of the calling
 *	program so we can access it.
 *
 *******************************************************************/

static void
changeOwner(const char * cmd, char * file)
{
    uid_t uid = getuid();
    uid_t gid = getgid();

    if (chown(file, uid, gid) != 0) {
	if (errno == ENOENT) {			/* Warn that it's not there */
	    fprintf(iC_errFP, "%s: Warning: File not present: %s\n", cmd, file);
	} else {
	    fprintf(iC_errFP, "%s: Unable to change ownership of %s: %s\n", cmd, file, strerror(errno));
	    iC_quit(SIGUSR1);
	}
    }
} /* changeOwner */

/********************************************************************
 *
 *	doEdge
 *	gpio		# RPi gpio pin number
 *	mode		# none, rising, falling or both
 *	fullProgname	# full name with path to change owner
 *
 *	Easy access to changing the edge trigger on a GPIO pin
 *	This uses the /sys/class/gpio device interface.
 *
 *******************************************************************/

void
doEdge(int gpio, const char * mode, const char * fullProgname)
{
    FILE *	fd;
    char	fName[128];

    assert(gpio >= 0 && gpio < 64);

    /* Export the pin and set direction to input */

    if ((fd = fopen("/sys/class/gpio/export", "w")) == NULL) {
	fprintf(iC_errFP, "%s: Unable to open GPIO export interface: %s\n", iC_progname, strerror(errno));
	iC_quit(SIGUSR1);
    }

    fprintf(fd, "%d\n", gpio);
    fclose(fd);
    sprintf(fName, "/sys/class/gpio/gpio%d/direction", gpio);
    if ((fd = fopen(fName, "w")) == NULL) {
	fprintf(iC_errFP, "%s: Unable to open GPIO direction interface for gpio %d: %s\n", iC_progname, gpio, strerror(errno));
	iC_quit(SIGUSR1);
    }

    fprintf(fd, "in\n");
    fclose(fd);

    /* Set the edge for interrupts */

    sprintf(fName, "/sys/class/gpio/gpio%d/edge", gpio);
    if ((fd = fopen(fName, "w")) == NULL) {
	fprintf(iC_errFP, "%s: Unable to open GPIO edge interface for gpio %d: %s\n", iC_progname, gpio, strerror(errno));
	iC_quit(SIGUSR1);
    }

    if (strcasecmp (mode, "none")    == 0 ||
	strcasecmp (mode, "rising")  == 0 ||
	strcasecmp (mode, "falling") == 0 ||
	strcasecmp (mode, "both")    == 0) {
	fprintf(fd, "%s\n", mode);
    } else {
	fprintf(iC_errFP, "%s: Invalid mode: %s. Should be none, rising, falling or both\n", iC_progname, mode, strerror(errno));
	iC_quit(SIGUSR1);
    }

    fclose(fd);

    /* Change ownership of the value and edge files, so the current user can actually use it! */

    sprintf(fName, "/sys/class/gpio/gpio%d/value", gpio);
    changeOwner(fullProgname, fName);

    sprintf(fName, "/sys/class/gpio/gpio%d/edge", gpio);
    changeOwner(fullProgname, fName);
} /* doEdge */

/********************************************************************
 *
 *	doUnexport
 *	gpio		# RPi gpio pin number
 *
 *	This uses the /sys/class/gpio device interface.
 *
 *******************************************************************/

void
doUnexport(int gpio)
{
    FILE *	fd;

    if ((fd = fopen("/sys/class/gpio/unexport", "w")) == NULL) {
	fprintf(iC_errFP, "%s: Unable to open GPIO unexport interface: %s\n", iC_progname, strerror(errno));
	iC_quit(SIGUSR1);
    }

    fprintf(fd, "%d\n", gpio);
    fclose(fd);
} /* doUnexport */