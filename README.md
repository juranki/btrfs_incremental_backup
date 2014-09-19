Experiment with btrfs send/receive and CoreOS
-------------------------

Incremental backup script based on:

  - https://btrfs.wiki.kernel.org/index.php/Incremental_Backup and
  - http://marc.merlins.org/perso/btrfs/post_2014-03-22_Btrfs-Tips_-Doing-Fast-Incremental-Backups-With-Btrfs-Send-and-Receive.html

__etcd structure:__


```
core@core1 ~ $ etcdctl ls --recursive /replication
/replication/postgresql
/replication/postgresql/slaves
/replication/postgresql/slaves/10.10.10.10
/replication/postgresql/slaves/10.10.10.11
/replication/postgresql/slaves/10.10.10.12
/replication/postgresql/master

core@core1 ~ $ etcdctl get /replication/postgresql/slaves/10.10.10.12
/replication/snapshots/postgresql_20140919_145932

core@core1 ~ $ etcdctl get /replication/postgresql/master
10.10.10.10
```

__Filesystem structure:__

```
/replication/data        # subvolumes (only on master node)
/replication/snapshots   # read only snapshots
```

__Installation:__

 - _core_ user must be able to ssh from master to slaves without password.
 - put replication.sh to /opt/bin
 - set up replication config in etcd
   (eg. `/opt/bin/replication.sh -v [volname] -m [master-ip] -s [slave1-ip] -s [slave2-ip]`)
 - copy replication.service and replication.timer to `/etc/systemd/system`
 - enable and start replication timer
