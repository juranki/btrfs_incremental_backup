#!/usr/bin/env bash

ETCD_ROOT=/replication
FS_ROOT=/replication
MY_IP=$( hostname -i | tr -d ' ' )
DATE="$(date '+%Y%m%d_%H%M%S')"
RETAIN_N=5


# make sure that required folders
# on filesystem and etcd exit
check_structure()
{
    if [ ! -d $FS_ROOT/vols ]; then install -d /replication/vols; fi
    if [ ! -d $FS_ROOT/snapshots ]; then install -d /replication/snapshots; fi
    if [ ! $(etcdctl ls / | grep replication) ]; then etcdctl mkdir /replication; fi
}


# send a snapshot or diff between snapshots
# to a slave
send_to_slave()
{
    local snap_path=$1
    local slave=$2
    local parts=(${slave//\// })
    local slave_ip=${parts[3]}
    local slave_snap=$( etcdctl get $slave )

    if [ "$slave_snap" == "" ]
    then
	btrfs send $snap_path | \
	    sudo -H -u core     \
	    ssh core@$slave_ip  \
	    sudo btrfs receive $ETCD_ROOT/snapshots
    else
	btrfs send -p $slave_snap $snap_path | \
	    sudo -H -u core     \
	    ssh core@$slave_ip  \
	    sudo btrfs receive $ETCD_ROOT/snapshots
    fi

    if [ "$?" == "0" ]
    then
	etcdctl set $slave $snap_path
    fi
}


# remove snapshots that are no longer needed
snapshot_cleanup()
{
    local snaps=()
    local n=0
    local vol_name=$1
    local snap=""

    for snap in $( ls "$FS_ROOT/snapshots" | grep "${vol_name}_" | head -n -$RETAIN_N )
    do
	snaps[$n]="$FS_ROOT/snapshots/$snap"
	n=$n+1
    done

    for slave in $( etcdctl ls $ETCD_ROOT/$vol_name/slaves )
    do
	snap=$( etcdctl get $slave )
	snaps=( "${snaps[@]/$snap}" )
    done

    for snap in ${snaps[*]}
    do
	btrfs sub delete $snap
    done
}


# run replication for a volume, if I'm master
replicate_vol()
{
    local ip=$( etcdctl get $1/master )
    local parts=(${line//\// })
    local vol_name=${parts[1]}
    local vol_path="$FS_ROOT/data/$vol_name"
    local snap_path="$FS_ROOT/snapshots/${vol_name}_$DATE"
    local slave=""

    # i'm master if ip matches
    if [ "$ip" == "$MY_IP" ]
    then
	if [ ! -d $vol_path ]; then btrfs sub create $vol_path; fi
	btrfs sub snap -r $vol_path $snap_path
	sync

	# add the new snapshot on slaves list to make sure that
	# it won't be removed if cleanup runs on another slave
	# after copy, but before updating current snapshot in etcd
	etcdctl set $1/slaves/$MY_IP $snap_path

	for slave in $( etcdctl ls $1/slaves )
	do
	    if [ "$slave" != "$1/slaves/$MY_IP" ]
	    then
		send_to_slave $snap_path $slave
	    fi
	done
    fi

    # give etcd a second to sync (BUG?)
    sleep 1

    snapshot_cleanup $vol_name
}


# READ ARGS
OPTIND=1
VOL=""
MASTER=""
SLAVES=()
N=0
while getopts "iv:m:s:" opt
do
    case "$opt" in
	i)
	    check_structure
	    exit 0
	    ;;
	v)
	    VOL=$OPTARG
	    ;;
	m)
	    MASTER=$OPTARG
	    ;;
	s)
	    SLAVES[$N]=$OPTARG
	    N=$N+1
	    ;;
    esac
done


# UPDATE CONFIG
check_structure
if [ "$VOL" != "" ]
then
    etcdctl mkdir $ETCD_ROOT/$VOL/slaves
    if [ "$MASTER" != "" ]
    then
	etcdctl set $ETCD_ROOT/$VOL/master $MASTER
    fi
    for item in ${SLAVES[*]}
    do
	etcdctl set $ETCD_ROOT/$VOL/slaves/$item ''
    done
fi


# RUN REPLICATION ACCORDING TO CONFIG
for line in $( etcdctl ls $ETCD_ROOT )
do
    replicate_vol $line
done
