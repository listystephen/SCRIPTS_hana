#!/bin/bash

# Author: Harsh Jha <harsh.jha@sap.com>
# Description: Extract the metadata of HANA system
# Description: Get the status

function sapserv
#to check if its a HDB host
{
        STAT="OK"
        if [ -f /usr/sap/sapservices ];
        then
                sapservicesdata=`cat /usr/sap/sapservices|grep HDB|grep -v "#" |cut -d';' -f1  |awk -F'=' {'print $2'}|cut -d ':' -f1`
                                                                            #to get the entries of sapservices file
                if [[ -z $sapservicesdata ]];                               #to check if sapservicesdata is null
                then
                        echo "OK: Not an HDB Host"
                        exit 0
                else

                        while read -r sapservicesinstance
                        do
#                               value_assign
                                mergestatus
                        done < <(echo $sapservicesdata| cut -d ' ' --output-delimiter=$'\n' -f 1- ) # tr -s " " "\n")
        fi
        else
                echo "OK: Not an HDB Host"
                exit 0
        fi
}

function value_assign
#to get the SID and the instance number
{
        instance_directory=`echo $sapservicesinstance|rev|cut -d/ -f2-|rev` #to get the Hana instance path
        sid=`echo $sapservicesinstance|cut -d '/' -f4`                      #to fetch the SID from the path
        instance_number=`echo $instance_directory|sed 's/.*\(..\)$/\1/'`    #to fetch the instance number
        lower_sid=`echo $sid| awk '{ print tolower($1) }'`                  #to convert the SID to lo lowercase
#       echo $instance_directory $sid $instance_number
        DBUSER=$lower_sid"adm"                                              #to get the sidadm user
#       hdb_version
}

function hdb_version
#to check the HDB version
{

        if [[ -z $instance_directory ]];
        then
                echo "OK: Not an HDB Host"
                exit 0
        else
                                                                            #to get the full Hana release version
                hdb_version=`su - $DBUSER -c "source $instance_directory/HDBSettings.csh 2>/dev/null  ;$instance_directory/HDB version"  2>/dev/null|grep version:|awk '{print$2}'`
                RC=$?
                hdb_main_version=`echo $hdb_version |awk -F'.' '{print $1}'` #to fetch only the Hana version
                hdb_sp_version=`echo $hdb_version|awk -F'.' '{print $3}'|cut -c 1-2` #to get the patch version

                if [ $RC -eq 0 ] && ! [ -z $hdb_version ]; then
                        version_flag=0
                else
                        echo "NOT OK: Not able to find HDB Version"
                        STAT="Not OK"
                        exit 1
                fi
        fi
}

function XSA
#to check the presence of XSA
{
        xsdata=`su - $DBUSER -c "source $instance_directory/HDBSettings.csh 2>/dev/null ; sapcontrol -nr $instance_number -function GetSystemInstanceList " 2>/dev/null`
        RC5=$?

        if [ $RC5 -eq 1 ]; then
        STAT1="ERROR:XSA presence cannot be determined"
        STAT="Not OK"
                xsacheckflag=1
        else
                                                                                #to check the presence of xs worker in systeminstancelist output
        xsdata1=`su - $DBUSER -c "source $instance_directory/HDBSettings.csh 2>/dev/null ; sapcontrol -nr $instance_number -function GetSystemInstanceList  | grep -i HDB_XS_WORKER " 2>/dev/null`
        RC6=$?

                if [ $RC6 -eq 0 ] ; then
                        STAT1="PRESENT"
                else
                        STAT1="NOT PRESENT"
                fi

                xsacheckflag=0
        fi
}

function DT
#to chech the presence of DT
{

        if [ ! -f $instance_directory/exe/python_support/landscapeHostConfiguration.py ] ; then

                STAT="Not OK"
                STAT2="Presence cannot be determined"
                dtcheckflag=1
        else
                                                                                #to check the presence of extended_storage keyword in landscapeconfig python file
                dtdata=`su - $DBUSER -c "source $instance_directory/HDBSettings.csh 2>/dev/null; python $instance_directory/exe/python_support/landscapeHostConfiguration.py | grep -i extended_storage " 2>/dev/null`
                RC8=$?

                        if [ $RC8 -eq 4 ] ; then

                                STAT2="PRESENT"
                                dtcheckflag=0
                        elif [ $RC8 -eq 2 ]  ; then

                              STAT="Not OK"
                              STAT2="Presence cannot be determined"
                                dtcheckflag=1

                        elif [ $RC8 -eq 1 ] ; then
                                dtdata1=`su - $DBUSER -c "source $instance_directory/HDBSettings.csh 2>/dev/null; python $instance_directory/exe/python_support/landscapeHostConfiguration.py | grep -i err  "  2>&1 1>/dev/null |grep -v stty`

                                if [ -z "$dtdata1" ] ; then
                                        dtcheckflag=0
                                        STAT2="NOT PRESENT"
                                else
                                        STAT2="Presence cannot be determined"
                                        STAT="Not OK"
                                        dtcheckflag=1
                                fi

                        else

                              STAT2="NOT PRESENT"

                                dtcheckflag=0
                        fi

      fi

      }
function db_status
{
#fetches the color status of system from getsysteminstancelist command
        HDBStatus=`su - $DBUSER -c "source $instance_directory/HDBSettings.csh 2>/dev/null ; sapcontrol -nr $instance_number -function GetSystemInstanceList" 2>/dev/null | egrep -w "HDB_WORKER|HDB" | awk '{print $7}'`
        if [ "$HDBStatus" == "GREEN" ] ; then
                STAT3="0"
                STAT="OK"
                #return 0
        elif [ "$HDBStatus" == "RED" ] ; then
                STAT3="1"
                STAT="Not OK"
                return 2
        elif [ "$HDBStatus" == "YELLOW" ] ; then
                STAT3="1"
                STAT="Not OK"
                return 2
        elif [ "$HDBStatus" == "GRAY" ] ; then
                STAT3="1"
                STAT="Not OK"
                return 2
        else
                echo " DB status cannot be determined "
                STAT3="2"
                return 1
        fi
}

function db_connectivity_check
{
#checking for connectivity via SYSTEM KEY
dbconn=`su - $DBUSER -c "source $instance_directory/HDBSettings.csh 2>/dev/null; hdbsql -U SYSTEM \"\\s\"" 2>/dev/null`
RC9=$?
        if [ $RC9 -eq 0 ] ; then
                STAT4=0
        elif [ $RC9 -eq 43 ] ; then
                STAT4=1
              STAT="Not OK"
        elif [ $RC9 -eq 136 ] || [ $RC9 -eq 10 ] ; then
#checking connectivity via DEFAULT KEY
                dbconn1=`su - $DBUSER -c "source $instance_directory/HDBSettings.csh 2>/dev/null; hdbsql -U DEFAULT \"\\s\"" 2>/dev/null`
                RC10=$?
                        if [ $RC10 -eq 0 ] ; then

                                STAT4=0
                        elif [ $RC10 -eq 136 ] ; then
#                                echo "DB connectivity cannot be determined"
                                STAT4=2
                                STAT="Not OK"
                                STAT5="Invalid KEY"
                        elif [ $RC10 -eq 10 ] ; then
#                                echo "DB connectivity cannot be determined"
                                STAT4=2
                                STAT="Not OK"
                                STAT5="Authentication Problem"

                        else
                                STAT4=2
                                STAT="Not OK"
                                STAT5="DB connectivity cannot be determined"

                        fi
        else
                STAT4=2
                STAT="Not OK"
                STAT5="DB connectivity cannot be determined"
        fi
}
function rccheck
{
#finding DB status based on STAT3 and STAT4 values fetched from above

        if [ $STAT3 -eq "0" ] && [ $STAT4 -eq 0 ] ;
        then
                STAT5="Connectable"
                RC=0

                if [ $dtcheckflag -eq 1 ] || [ $xsacheckflag -eq 1 ]; then
                        RC=1
                fi

        elif [ $STAT3 -eq "0" ] && [ $STAT4 -eq 1 ] ;
        then
                STAT5="Available but not connectable"
                RC=2
#                       return 2
        elif [ $STAT3 -eq "1" ] && [ $STAT4 -eq 1 ] ;
        then
                STAT5="DB is down"
                RC=2
#                       return 2
        elif [ $STAT3 -eq "1" ] && [ $STAT4 -eq 0 ] ;
        then
                STAT5="DB is down"
                RC=2
#                       return 2
        else
                if [ $STAT3 -eq "2" ]; then
                        STAT5="DB State can not be checked"
                        RC=1
                elif [ $STAT4 -eq 2 ]; then
                        RC=1
                fi
#                       return 1
        fi
}

function output
{
#output display
DB="HDB"
        echo "$STAT: DBTYPE:$DB SID:$sid VERSION:$hdb_main_version PATCH:$hdb_sp_version STATUS:$STAT5 XSA:$STAT1 DT:$STAT2 ;"
        return $RC
}

function mergestatus
{
value_assign
hdb_version
XSA
DT
db_status
db_connectivity_check
rccheck
output

}
function main
{
#function calls
sapserv
}

main
