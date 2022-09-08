#!/usr/bin/env sh
set -ex

# cd /

apk add util-linux
apk add openrc

# 创建隔离环境
if [ "$1" = "--enter" ]; then
    PWD_PATH=$(pwd)

    mount -t proc proc /rom/root/proc

    cd /rom/root
    mkdir -p parent
    pivot_root . parent

    mount --rbind /parent/dev /dev
    mount --rbind /parent/sys /sys
    mount --rbind /parent/mnt /mnt
    umount -l /parent && rm -rf /parent

    cd "$PWD_PATH"

    exec /sbin/init
elif [ "$1" = "--init" ]; then
    rm -rf /rom
    mkdir -p /rom/rom /rom/root /rom/over /rom/upper /rom/work
    mount --rbind / /rom/rom
    mount -t overlay overlay /rom/root -o lowerdir=/rom/over:/rom/rom,upperdir=/rom/upper,workdir=/rom/work
    exec /usr/bin/env -i unshare -muipf --mount-proc --propagation=unchanged -- "$0" --enter
else
    pid=$(ps -eo pid,args | awk '$2 ~ /^\/sbin\/init/ { print $1 }')
    if [ -z "$pid" ]; then
        nohup /usr/bin/env -i unshare -muipf --mount-proc --propagation=unchanged -- "$0" --enter >/dev/null 2>&1 &
        set +x
        times=0
        while [ $times -lt 10 ]; do
            pid=$(ps -eo pid,args | awk '$2 ~ /^\/sbin\/init/ { print $1 }')
            [ -n "$pid" ] && break
            times=$((times + 1))
            sleep 1
        done
        set -x
    fi
    exec nsenter -a -t "$pid" --wdns="$(pwd)" -- /bin/sh
fi
