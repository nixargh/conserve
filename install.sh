#!/bin/bash
#### INFO ######################################################################
# (*w) 
VERSION=3
#### SETTINGS ##################################################################
BIN='conserve'
LIBS='lib'
CONFDIR='/etc/conserve'
BINDIR='/usr/sbin'
LIBDIR='/usr/lib/conserve'
INFORM='inform.conf'
CRED='cred'
LOGROTATE='conserve.lr'
USER=`/usr/bin/env |grep -c USER=root`
#### PROGRAM ###################################################################
function copyconf {
	CONFIG=$1
	if test -e ./$CONFIG; then
		if test -e $CONFDIR/$CONFIG; then
			mv $CONFDIR/$CONFIG $CONFDIR/$CONFIG.bak
			echo "	$CONFDIR/$CONFIG moved to $CONFDIR/$CONFIG.bak"
		fi
		cp ./$CONFIG $CONFDIR
		echo "	./$CONFIG copied to $CONFDIR/"
		chmod 660 $CONFDIR/$CONFIG
		chown root:root $CONFDIR/$CONFIG
	fi
}

function install {
	echo -e "\033[1m Installing... \033[0m"
	if test ! -d $CONFDIR; then
		mkdir $CONFDIR
	fi
	chmod 770 $CONFDIR

	cp -f ./$BIN $BINDIR/conserve
	echo "	./$BIN copied to $BINDIR/conserve"
	chmod 755 $BINDIR/conserve
	chown root:root $BINDIR/conserve

	if test ! -d $LIBDIR; then
		mkdir $LIBDIR
	fi
	cp -f ./$LIBS/* $LIBDIR
	echo "	libs copied to $LIBDIR"
	chmod 644 $LIBDIR
	chown root:root $LIBDIR

	copyconf $INFORM
	copyconf $CRED
	CONFDIR='/etc/logrotate.d'
	copyconf $LOGROTATE
	echo -e "\033[1m OK. \033[0m"
}

if [ "$USER" != "0" ]; then
	if test -e $BINDIR/conserve; then
		echo -ne "\033[1m $BINDIR/conserve exist, replace it? [y|n]:  \033[0m"
		read -a ANSWER
		if [ $ANSWER == 'y' ];then
			install
		elif [ $ANSWER == 'n' ];then
			echo "Exiting."
			exit 0;
		else
			echo "Bad answer \"$ANSWER\". Exiting."
			exit 1;
		fi
	else
		install
		exit 0;
	fi
else
  echo -e "  \033[1m login as root first! \033[0m"
  exit 1;
fi
