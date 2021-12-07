#!/bin/sh

##############################################
#
# Some global variables
# It like the dark side of the moon:
#
# There is no dark side in the moon, really.
# Matter of facts, it's all dark
# The only thing that makes it look light
# is the sun.
#
##############################################

VERSION=20211207
PROG=$0

JQ="`dirname $PROG`/jq.pl"       # Small perl script to handle JSON output, inspired by jq
ZPOOL="`dirname $PROG`/zpool.pl" # Small perl script to handle JSON output, inspired by jq

# Op5 / Nagios return codes
RC_OK=0
RC_WARNING=1
RC_CRITICAL=2
RC_UNKNOWN=3
RC_DEPENDENT=4

# Optional variables
DEBUG=0
PERF=0


#
# A function that creates a cookie to be used in subsequent API calls
# https://pve.proxmox.com/wiki/Proxmox_VE_API#Ticket_Cookie
#
# Requires USERNAME, PASSWORD and HOSTNAME variables
# Return cookie data on stdout
#
cookie() {
    DATA=`curl --silent --insecure --data "username=$USERNAME&password=$PASSWORD" $HOSTNAME/api2/json/access/ticket`
    #C=`echo $DATA | jq --raw-output '.data.ticket' | sed 's/^/PVEAuthCookie=/'`
    C=`echo $DATA | $JQ data ticket | sed 's/^/PVEAuthCookie=/'`
    if [ $DEBUG -ne 0 ]; then
    	/bin/rm -f /tmp/cookie.json && echo $DATA > /tmp/cookie.json
        /bin/rm -f /tmp/cookie.txt && echo $C > /tmp/cookie.txt
    fi
    echo $C
}

#
# The function that does it all, all for you.
#
# Requires URL as the first argument
# Returns the output of the call
#
doit() {
    URL=$1
    C=`cookie`
    curl -s --insecure --cookie "${C}" "${URL}" 
}

#
# Gets the zfs avail from a specified pool
#
# Requires HOSTNAME, CLUSTER and POOL variables
# Returns the available size in pool
#
zfs_avail() {
    RES=`doit $HOSTNAME/api2/json/nodes/$CLUSTER/disks/zfs`
    AVAIL=`echo $RES | $ZPOOL $POOL free`
    if [ $DEBUG -ne 0 ]; then
    	/bin/rm -f /tmp/zfs.json && echo $RES > /tmp/zfs.json
    	/bin/rm -f /tmp/zfs.avail && echo $AVAIL > /tmp/zfs.avail
    fi
    echo $AVAIL
}



#
# Requires HOSTNAME, CLUSTER and POOL variables
# Returns the health status of the pool ( if ok it's ONLINE )
#
zfs_online() {
    RES=`doit $HOSTNAME/api2/json/nodes/$CLUSTER/disks/zfs`
    ONLINE=`echo $RES | $ZPOOL $POOL health`
    if [ $DEBUG -ne 0 ]; then
    	/bin/rm -f /tmp/online.json && echo $RES > /tmp/online.json
    	/bin/rm -f /tmp/online.txt && echo $ONLINE > /tmp/online.txt
    fi
    echo $ONLINE
}

#
# Requires HOSTNAME and CLUSTER variables
# Returns free memoro on the host node
memory_free() {
    RES=`doit $HOSTNAME/api2/json/nodes/$CLUSTER/status`
    if [ $DEBUG -ne 0 ]; then
    	/bin/rm -f /tmp/memfree.json && echo $RES > /tmp/memfree.json
    fi
    #echo $RES | jq --raw-output '.data.memory.free'
    echo $RES | $JQ data memory free
}

#
# Check if free memory are within specifed constrains
# Requires CRITICAL, WARNING, HOSTNAME
#
# This function exits with a status code, responding to 
# the amount of free memory
#
check_memory_free() {
    FREE=`memory_free` 
    if [ $DEBUG != 0 ]; then
        echo "DEBUG check_memory_free: $FREE"
    fi
    if [ "${FREE}" = "" ]; then
        TEXT="CRITICAL Unable to get data from $HOSTNAME"
        RC=$RC_CRITICAL
    elif [ $FREE -lt ${CRITICAL} ]; then
        TEXT="CRITICAL Free memory $FREE is less then ${CRITICAL}"
        RC=$RC_CRITICAL
    elif [ $FREE -lt ${WARNING} ]; then
        TEXT="WARNING: Free memory $FREE is less then ${WARNING}"
        RC=$RC_WARNING
    else
        TEXT="OK: Free memory $FREE is OK"
        RC=$RC_OK
    fi

    PERFTEXT=""
    if [ ${PERF} -ne 0 ]; then
        PERFTEXT="| memfree=$FREE"
    fi

    echo $TEXT $PERFTEXT
    exit $RC
}

#
# Check if helath of a pool is "ONLINE"
# Requires HOSTNAME
#
# This function exits with a status code, responding to 
# if the pool is "ONLINE" or not
#
check_zfs_online() {
    ONLINE=`zfs_online`
    if [ $DEBUG != 0 ]; then
	    echo "DEBUG check_zfs_online: $ONLINE"
    fi
    if [ "${ONLINE}" = "" ]; then
        TEXT="CRITICAL: Unable to get data from $HOSTNAME: $ONLINE"
        RC=$RC_CRITICAL
    elif [ $ONLINE != "ONLINE" ]; then
        TEXT="CRITICAL: zpool $POOL is not online ($ONLINE)"
	PERFVALUE=0
        RC=$RC_CRITICAL
    else
	PERFVALUE=1
        TEXT="OK: zpool $POOL is online"
        RC=$RC_OK
    fi

    PERFTEXT=""
    if [ ${PERF} -ne 0 ]; then
        PERFTEXT="| online=$PERFVALUE"
    fi

    echo $TEXT $PERFTEXT
    exit $RC
}

#
# Check if free space are within specifed constrains
# Requires CRITICAL, WARNING, HOSTNAME and POOL
#
# This function exits with a status code, responding to 
# the amount of free space
#
check_zfs_avail() {
    FREE=`zfs_avail`
    if [ $DEBUG != 0 ]; then
	echo "DEBUG check_zfs_avail: $FREE"
    fi
    if [ "${FREE}" = "" ]; then
        TEXT="CRITICAL: Unable to get data from $HOSTNAME: $FREE"
        RC=$RC_CRITICAL
    elif [ $FREE -lt ${CRITICAL} ]; then
        TEXT="CRITICAL: Free zfs in $POOL is less then ${CRITICAL}"
        RC=$RC_CRITICAL
    elif [ $FREE -lt ${WARNING} ]; then
        TEXT="WARNING: Free zfs in $POOL is less then ${WARNING}"
        RC=$RC_WARNING
    else
        TEXT="OK: Free zfs in $POOL is OK"
        RC=$RC_OK
    fi

    PERFTEXT=""
    if [ ${PERF} -ne 0 ]; then
        PERFTEXT="| free=$FREE"
    fi

    echo $TEXT $PERFTEXT
    exit $RC
    
}

# 
# This function gets the running status of a qemu virtual machine
# Requires HOSTNAME, CLUSTER and QEMUNODE
# Returns running status
#
running_qemu() {
    RES=`doit ${HOSTNAME}/api2/json/nodes/${CLUSTER}/qemu/${QEMUNODE}/status/current`
    if [ $DEBUG -ne 0 ]; then
    	/bin/rm -f /tmp/qemu.json && echo $RES > /tmp/qemu.json
    fi
    #echo $RES | jq --raw-output  '.data.qmpstatus'
    echo $RES | $JQ data qmpstatus
}

# 
# This function gets the running status of a lxc container
# Requires HOSTNAME, CLUSTER and LXCNODE
# Returns running status
#
running_lxc() {
    RES=`doit ${HOSTNAME}/api2/json/nodes/${CLUSTER}/lxc/${LXCNODE}/status/current`
    if [ $DEBUG -ne 0 ]; then
    	/bin/rm -f /tmp/lxc.json && echo $RES > /tmp/lxc.json 
    fi
    #echo $RES | jq --raw-output  '.data.status'
    echo $RES | $JQ data status
}

#
# This function cheks if a qemu vm or lxc container is running
# Requires HOSTNAME, ( QEMUNODE or LXCNODE )
# This function exits with a status code, responding to if 
# the vm or container is in the running state
check_running() {
    RUNNING=""
    if [ "${QEMUNODE}" != "" ]; then
        NODE="${QEMUNODE}"
        RUNNING=`running_qemu ${NODE}`
    elif [ "${LXCNODE}" != "" ]; then
        NODE="${LXCNODE}"
        RUNNING=`running_lxc ${NODE}`
    else
        echo "UNKNOWN: Missing node to check, use -q(qemu) or -l(lxc)"
        exit $RC_UNKNOWN
    fi
    if [ $DEBUG != 0 ]; then
        echo "DEBUG RUNNING: $RUNNING"
    fi

    if [ "${RUNNING}" = "" ]; then
        TEXT="CRITICAL: Unable to get data from $HOSTNAME"
        RUNPERF=0
        RC=$RC_CRITICAL
    elif [ "${RUNNING}" != "running" ]; then
        TEXT="CRITICAL: $NODE is not running"
        RUNPERF=0
        RC=$RC_CRITICAL
    else
        TEXT="OK: $NODE is running"
        RUNPERF=1
        RC=$RC_OK
    fi

    PERFTEXT=""
    if [ ${PERF} -ne 0 ]; then
        PERFTEXT="| running=$RUNPERF"
    fi

    echo $TEXT $PERFTEXT
    exit $RC
}

# 
# Print som help on arguments to this fine script
#
show_help() {
    echo "Usage: $0 <args>"
    echo "  -c  Critical level, depending on check but 35000000000 is one"
    echo "  -C  Proxmox cluster name, example: proxmox"
    echo "  -d  Debug"
    echo "  -h  This help"
    echo "  -H  Proxmox hostname, example: https://192.168.0.1:8006"
    echo "  -k  Which check"
    echo "      running"
    echo "      memfree"
    echo "      zfsavail (Default to pool vmpool, use -z to change)"
    echo "      zfsonline (Default to pool vmpool, use -z to change)"
    echo "  -l  Lxc node ID, example: 1000"
    echo "  -p  Api password, secretpassword"
    echo "  -P  Include performance graphs"
    echo "  -q  Qemu node ID, example: 2000"
    echo "  -u  Api username, api@pve"
    echo "  -w  Warning level, depending on check but 6000000000 is one"
    echo "  -z  Zfs pool, example: rpool"
}

#
# Check arguments, and assign correct values to variables
#

while getopts "c:C:dhH:k:l:p:Pq:u:w:z:" options; do
    case "${options}" in
        c)
            CRITICAL=${OPTARG}
            ;;
        C)
            CLUSTER=${OPTARG}
            ;;
        d)
            DEBUG=1
            ;;
        h)
            show_help
            exit $RC_OK
            ;;
        H)
            HOSTNAME=${OPTARG}
            ;;
        k)
            CHECK=${OPTARG}
            ;;
        l)
            LXCNODE=${OPTARG}
            ;;
        p)
            PASSWORD=${OPTARG}
            ;;
        P)
            PERF=1
            ;;
        q)
            QEMUNODE=${OPTARG}
            ;;
        u)
            USERNAME=${OPTARG}
            ;;
        w)
            WARNING=${OPTARG}
            ;;
     	z)
	        POOL=${OPTARG}
	        ;;
    esac
done

#
# Check for required arguments
#

if [ "${USERNAME}" = "" ]; then
    echo "$PROG: Missing -u (USERNAME)"
    show_help
    exit $RC_CRITICAL
fi

if [ "${PASSWORD}" = "" ]; then
    echo "$PROG: Missing -p (PASSWORD)"
    show_help
    exit $RC_CRITICAL
fi

if [ "${HOSTNAME}" = "" ]; then
    echo "$PROG: Missing -H (HOSTNAME)"
    show_help
    exit $RC_CRITICAL
fi

#if [ "${WARNING}" = "" ]; then
#    echo "$PROG: Missing -w (WARNING)"
#    exit $RC_CRITICAL
#fi

#if [ "${CRITICAL}" = "" ]; then
#    echo "$PROG: Missing -c (CRITICAL)"
#    exit $RC_CRITICAL
#fi

if [ "${CHECK}" = "" ]; then
    echo "$PROG: Missing -k (CHECK)"
    show_help
    exit $RC_CRITICAL
fi

if [ "${HOSTNAME}" = "" ]; then
    echo "$PROG: Missing -H (HOSTNAME)"
    show_help
    exit $RC_CRITICAL
fi

if [ "${CLUSTER}" = "" ]; then
    CLUSTER=`echo $HOSTNAME | awk -F/ '{print $NF}' | awk -F. '{print $1}'`
fi

if [ "${POOL}" = "" ]; then
    POOL="vmpool"
fi

#
# Print som debug info if we are debugging
#

if [ $DEBUG -ne 0 ]; then
    echo "Username: $USERNAME"
    echo "Password: $PASSWORD"
    echo "Check: $CHECK"
    echo "Hostname: $HOSTNAME"
    echo "Cluster: $CLUSTER"
    echo "Pool: $POOL"
    echo "Warning: $WARNING"
    echo "Critical: $CRITICAL"
    echo "LXC Node: $LXCNODE"
    echo "QEMU Node: $QEMUNODE"
fi

#
# Which check do we want to execute
#
if [ "${CHECK}" = "running" ]; then
    check_running
elif [ "${CHECK}" = "memfree" ]; then
    check_memory_free
elif [ "${CHECK}" = "zfsavail" ]; then
    check_zfs_avail 
elif [ "${CHECK}" = "zfsonline" ]; then
    check_zfs_online 
fi

# This should not happen

echo "This should not happen"
exit $RC_UNKNOWN
