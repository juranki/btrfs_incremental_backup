from fabric.api import *
from hosts import *

env.user  = "core"

# SSH setup

@hosts(all_hosts)
def ssh_clean():
    run("if [ -f ~/.ssh/id_rsa ]; then rm ~/.ssh/id_rsa*; fi")
    run("if [ -f ~/.ssh/authorized_keys.d/core ]; then rm ~/.ssh/authorized_keys.d/core; fi")
    run("if [ -f ~/.ssh/known_hosts ]; then rm ~/.ssh/known_hosts; fi")
    run("if [ -f ~/.ssh/config ]; then rm ~/.ssh/config; fi")
    run("rm ~/.ssh/authorized_keys")
    run("update-ssh-keys")

@hosts(admin_host)
def mk_ssh_key():
    run("ssh-keygen -f ~/.ssh/id_rsa -P ''")
    get("~/.ssh/id_rsa.pub", ".")
    get("~/.ssh/id_rsa", ".")

@hosts(all_hosts)
def copy_auth_key():
    put("id_rsa", "~/.ssh/id_rsa", mode=0600)
    put("id_rsa.pub", "~/.ssh/id_rsa.pub", mode=0600)
    put("id_rsa.pub", "~/.ssh/authorized_keys.d/core", mode=0600)
    put("ssh.config", "~/.ssh/config", mode=0600)
    run("update-ssh-keys")

@runs_once
def ssh_setup():
    execute("mk_ssh_key")
    execute("copy_auth_key")

# REPLICATION

@hosts(all_hosts)
def replicate():
    sudo("/opt/bin/replication.sh")

@hosts(all_hosts)
def replication_setup():
    put("../replication.sh", "/tmp/replication.sh", mode=0755)
    put("../replication.service", "/tmp/replication.service", mode=0644)
    put("../replication.timer", "/tmp/replication.timer", mode=0644)

    sudo("if [ -f /opt/bin/replication.sh ]; then rm /opt/bin/replication.sh ; fi")
    sudo("rm -f /etc/systemd/system/replication.*")

    sudo("mv /tmp/replication.sh /opt/bin/")
    sudo("mv /tmp/replication.service /etc/systemd/system")
    sudo("mv /tmp/replication.timer /etc/systemd/system")

    sudo("/opt/bin/replication.sh -i")

    sudo("systemctl daemon-reload")
    sudo("systemctl restart replication.timer")
    sudo("systemctl enable replication.timer")


#POSTGRES

@hosts(pg_host)
def postgres_setup():
    put("../postgres.service", "/tmp/postgres.service", mode=0644)
    sudo("if [ -f /etc/systemd/system/postgres.service ]; then rm /etc/systemd/system/postgres.service; fi")
    sudo("mv /tmp/postgres.service /etc/systemd/system")
    sudo("systemctl daemon-reload")
    sudo("systemctl restart postgres.service")
    sudo("systemctl enable postgres.service")
