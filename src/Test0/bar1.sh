#!/bin/sh

########################################################################
#
#	bar1.sh
#	This demo starts iCserver, 3 iCboxes and the control program
#	'bar1' which is generated by iCmake bar1.ic
#
#	iCbox IB4 is an analog input initialized to 1.
#	This sets the clocking speed of the running lights on QX0
#	to 50 ms.
#
#	By changing the input slider IB4 the clocking speed
#	on QX0 is set to IB4 * 50 ms.
#	A value of 0 on input IB4 lets you clock the running
#	lights manually via input IX0.0
#
#	Output QX1.0 indicates the direction of the running
#	lights on QX0 - just to show a bit of internal logic.
#
#	Stop the demo with ctrl-C
#
########################################################################

iCserver 'iCbox X0' 'iCbox X1' 'iCbox B4 1' bar1