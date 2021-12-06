#!/bin/sh

CMDNAME="check_proxmox"
RC_OK=0
RC_WARNING=1
RC_CRITICAL=2
RC_UNKNOWN=3
RC_DEPENDENT=4
DEBUG=0
PERF=0


cookie() {
    DATA=`curl --silent --insecure --data "username=$USERNAME&password=$PASSWORD" $HOSTNAME/api2/json/access/ticket`
    C=`echo $DATA | jq --raw-output '.data.ticket' | sed 's/^/PVEAuthCookie=/'`
    echo $C
}

doit() {
    URL=$1
    C=`cookie`
    curl -s --insecure --cookie "${C}" "${URL}" 
}

memory_free() {
    RES=`doit $HOSTNAME/api2/json/nodes/$CLUSTER/status`
    echo $RES | jq --raw-output '.data.memory.free'
}

check_memory_free() {
    FREE=`memory_free` 
    if [ $DEBUG != 0 ]; then
        echo "DEBUG check_memory_free: $FREE"
    fi
    if [ "${FREE}" = "" ]; then
        TEXT="Unable to get data from $HOSTNAME"
        RC=$RC_CRITICAL
    elif [ $FREE -lt ${CRITICAL} ]; then
        TEXT="$CMDNAME: Free memory is less then ${CRITICAL}"
        RC=$RC_CRITICAL
    elif [ $FREE -lt ${WARNING} ]; then
        TEXT="$CMDNAME: Free memory is less then ${WARNING}"
        RC=$RC_WARNING
    else
        TEXT="$CMDNAME: Free memory is OK"
        RC=$RC_OK
    fi

    PERFTEXT=""
    if [ ${PERF} -ne 0 ]; then
        PERFTEXT="| memfree=$FREE"
    fi

    echo $TEXT $PERFTEXT
    exit $RC
}

running_qemu() {
    RES=`doit ${HOSTNAME}/api2/json/nodes/${CLUSTER}/qemu/${QEMUNODE}/status/current`
    echo $RES | jq --raw-output  '.data.qmpstatus'
}

running_lxc() {
    RES=`doit ${HOSTNAME}/api2/json/nodes/${CLUSTER}/lxc/${LXCNODE}/status/current`
    echo $RES | jq --raw-output  '.data.status'
}

check_running() {
    RUNNING=""
    if [ "${QEMUNODE}" != "" ]; then
        NODE="${QEMUNODE}"
        RUNNING=`running_qemu ${NODE}`
    elif [ "${LXCNODE}" != "" ]; then
        NODE="${LXCNODE}"
        RUNNING=`running_lxc ${NODE}`
    else
        echo "Missing node to check, use -q(qemu) or -l(lxc)"
        exit $RC_UNKNOWN
    fi
    if [ $DEBUG != 0 ]; then
        echo "DEBUG RUNNING: $RUNNING"
    fi

    if [ "${RUNNING}" = "" ]; then
        TEXT="Unable to get data from $HOSTNAME"
        RUNPERF=0
        RC=$RC_CRITICAL
    elif [ "${RUNNING}" != "running" ]; then
        TEXT="$CMDNAME: $NODE is not running"
        RUNPERF=0
        RC=$RC_CRITICAL
    else
        TEXT="$CMDNAME: $NODE is running"
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

show_help() {
    echo "Usage: $0 <args>"
    echo "  -u  Api username, api@pve"
    echo "  -p  Api password, secretpassword"
    echo "  -w  Warning level, depending on check but 6000000000 is one"
    echo "  -c  Critical level, depending on check but 35000000000 is one"
    echo "  -C  Proxmox cluster name, example: proxmox"
    echo "  -q  Qemu node ID, example: 2000"
    echo "  -l  Lxc node ID, example: 1000"
    echo "  -H  Proxmox hostname, example: https://192.168.0.1:8006"
    echo "  -h  This help"
    echo "  -P  Include performance graphs"
    echo "  -k  Which check"
    echo "      running"
    echo "      memfree"
    echo "      zfsavail"
}



while getopts "u:Pp:C:w:c:q:l:k:H:hd" options; do
    case "${options}" in
        d)
            DEBUG=1
            ;;
        u)
            USERNAME=${OPTARG}
            ;;
        p)
            PASSWORD=${OPTARG}
            ;;
        P)
            PERF=1
            ;;
        w)
            WARNING=${OPTARG}
            ;;
        c)
            CRITICAL=${OPTARG}
            ;;
        C)
            CLUSTER=${OPTARG}
            ;;
        q)
            QEMUNODE=${OPTARG}
            ;;
        l)
            LXCNODE=${OPTARG}
            ;;
        k)
            CHECK=${OPTARG}
            ;;
        H)
            HOSTNAME=${OPTARG}
            ;;
        h)
            show_help
            exit $RC_OK
            ;;
    esac
done

#
# Required arguments
#

if [ "${USERNAME}" = "" ]; then
    echo "$CMDNAME: Missing -u (USERNAME)"
    exit $RC_CRITICAL
fi

if [ "${PASSWORD}" = "" ]; then
    echo "$CMDNAME: Missing -p (PASSWORD)"
    exit $RC_CRITICAL
fi

if [ "${HOSTNAME}" = "" ]; then
    echo "$CMDNAME: Missing -H (HOSTNAME)"
    exit $RC_CRITICAL
fi

if [ "${WARNING}" = "" ]; then
    echo "$CMDNAME: Missing -w (WARNING)"
    exit $RC_CRITICAL
fi

if [ "${CRITICAL}" = "" ]; then
    echo "$CMDNAME: Missing -c (CRITICAL)"
    exit $RC_CRITICAL
fi

if [ "${CHECK}" = "" ]; then
    echo "$CMDNAME: Missing -k (CHECK)"
    exit $RC_CRITICAL
fi

if [ "${HOSTNAME}" = "" ]; then
    echo "$CMDNAME: Missing -H (HOSTNAME)"
    exit $RC_CRITICAL
fi

if [ "${CLUSTER}" = "" ]; then
    CLUSTER=`echo $HOSTNAME | awk -F/ '{print $NF}' | awk -F. '{print $1}'`
fi

if [ $DEBUG -ne 0 ]; then
    echo "Username: $USERNAME"
    echo "Password: $PASSWORD"
    echo "Hostname: $HOSTNAME"
    echo "Cluster: $CLUSTER"
    echo "Warning: $WARNING"
    echo "Critical: $CRITICAL"
    echo "Check: $CHECK"
    echo "LXC Node: $LXCNODE"
    echo "QEMU Node: $QEMUNODE"
fi

if [ "${CHECK}" = "running" ]; then
    check_running
elif [ "${CHECK}" = "memfree" ]; then
    check_memory_free
elif [ "${CHECK}" = "zfsavail" ]; then
    check_zfs_avail
fi
