#!/bin/bash
#CRON => */2 8-16 * * * /home/http_health_check.sh > /dev/null

RESTART_APACHE="/sbin/service httpd restart"
#RESTART_APACHE="/etc/init.d/apache2 restart"
PGREP_PATH="/usr/bin/pgrep"
SENDMAIL_PATH="/usr/sbin/sendmail"
LSOF_PATH="/usr/sbin/lsof"

HTTPD="httpd"
PORT="80"

URL="http://dev.playmore.ro/"
IN_PAGE_STRING="Dob"

FROM_EMAIL="vlad.tanasescu@dev.playmore.ro"
TO_EMAIL="t.mariovlad@gmail.com"
TO_EMAIL_ESCALATE="vlads@laleagane.ro"
MAIL_TMP_FILE="/tmp/http_health_check_mail.$$"
SUBJECT_EMAIL="HTTP check status on dev.playmore.ro"

LOG_FILE="/var/log/http_health_check.log"




## STORE THE CURRENT STATUS OF THE CHECKS
CHECK_STATUS='0'

# SEND MAIL FUNCTION
# param 1 = message to send
# param 2 = is it an error
mail_process() {
	if [ $? -ne 0 ] || [ $# -eq 2 ]
	then
		
		if [ "$2" ] && [ $2 -ne 0 ]
		then
			CHECK_STATUS='1'
			echo "FAIL_COUNT=$(($FAIL_COUNT+1))" >> $LOG_FILE
		fi
		
		if [ "$2" ]
		then
			mailbody="$1"
		else
			mailbody="HTTP server check failed while running [$1]"
			CHECK_STATUS='2'
		fi
		
		echo "From: $FROM_EMAIL" >> $MAIL_TMP_FILE
		if [ "$FAIL_COUNT" -gt "4" ]
		then
			echo "To: $TO_EMAIL_ESCALATE" >> $MAIL_TMP_FILE
		else
			echo "To: $TO_EMAIL" >> $MAIL_TMP_FILE
		fi
		
		echo "Subject: $SUBJECT_EMAIL" >> $MAIL_TMP_FILE
		echo "MESSAGE:" >> $MAIL_TMP_FILE
		echo $mailbody >> $MAIL_TMP_FILE
		
		# don't spam if the server has already sent that it has failed more than ~10 times
		if [ "$FAIL_COUNT" -lt "10" ] 
		then
			# in case we're sending multiple emails we should prevent mail servers from flagging us as spam by adding a delay
			sleep 2
			cat $MAIL_TMP_FILE | $SENDMAIL_PATH -t
			echo "mail sent"
			/bin/rm -f $MAIL_TMP_FILE
		fi
		
	fi
}

# get the fail count from previous checks
init_config() {
	if [ ! -f $LOG_FILE ]; then
		FAIL_COUNT='0'
	else
		source $LOG_FILE
	fi
}

# check if the process is started
check_pid() {
	# find httpd pid
	$PGREP_PATH ${HTTPD} > /dev/null
	if [ $? -ne 0 ] # if apache not running
		then
			if [ $# -eq 0 ]
			then
				mail_process "The HTTP server is not running (restarting)" 1
				$RESTART_APACHE
				check_pid 1
			else
				return 2
		fi
	else 
		echo "The HTTP server is running"
		CHECK_STATUS='0'
		return 0
	fi

	mail_process "restart apache"
	
	return $CHECK_STATUS
}

# check if apache is listening on the specified port
check_port() {
	if $LSOF_PATH -i :$PORT -sTCP:LISTEN | grep "${HTTPD}" > /dev/null
	  then 
		echo "The HTTP server is listening on port $PORT!"
		CHECK_STATUS='0'
		return 0
	  else
			if [ $# -eq 0 ]
			then
				mail_process "The HTTP server is not listening on port $PORT!" 1
				$RESTART_APACHE
				check_port 1
			else
				return 2
			fi
	fi

	mail_process "checking apache port"
	
	return $CHECK_STATUS
}

# check if the http response is 200 OK
check_http_response() {
	if curl -s --head ${URL} | grep "200 OK" > /dev/null
	  then 
		echo "The HTTP server on ${URL} is up (200 OK)!"
		CHECK_STATUS='0'
		return 0
	  else
			if [ $# -eq 0 ]
			then
				mail_process "The HTTP server on ${URL} is down (NOT 200 OK)!"
				# maybe we should also restart php-fpm if it exists, meh
				$RESTART_APACHE
				check_http_response 1
			else
				return 2
			fi
	fi
	
	mail_process "checking apache http response code"
	
	return $CHECK_STATUS
}

# check if the page contains the specified string
check_http_content() {
	if curl ${URL} -s -f | grep "${IN_PAGE_STRING}" > /dev/null
	then 
		echo "The HTTP server contains ${IN_PAGE_STRING}"
		CHECK_STATUS='0'
		return 0
	else
		if [ $# -eq 0 ]
		then
			mail_process "The site does not contain ${IN_PAGE_STRING}"
			# maybe we should also restart php-fpm if it exists, meh
			$RESTART_APACHE
			check_http_content 1
		else
			return 2
		fi
	fi
	
	mail_process "checking apache http content string"
	
	return $CHECK_STATUS
}

init_config

check_pid
ret=$?

if [ $ret -ne 0 ] ; then
	mail_process "The HTTP server failed to restart in check_pid ($ret)" 1	
	exit 2
fi

check_port
ret=$?
if [ $ret -ne 0 ] ; then
    mail_process "The HTTP server check failed even after the restart in check_port ($ret)" 1
	exit 2
fi

check_http_response
ret=$?
if [ $ret -ne 0 ] ; then
    mail_process "The HTTP server check failed even after the restart in check_http_response ($ret)" 1
	exit 2
fi

check_http_content
ret=$?
if [ $ret -ne 0 ] ; then
    mail_process "The HTTP server check failed even after the restart in check_http_content ($ret)" 1
	exit 2
fi

# looks like the server is ok now
if [ $FAIL_COUNT -ne 0 ]
then
	echo "FAIL_COUNT=0" >> $LOG_FILE
	mail_process "The HTTP server has recovered" 0
fi

exit 0
