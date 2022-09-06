#!/bin/sh

set -ex

cd "$(dirname "$0")"

#########################
#        Utils        #
#########################

wait() {
    while true; do
        pid="$(ps -o pid,args | awk '$2 ~ /^\/sbin\/init/ { print $1 }')"
        [ -n "$pid" ] && break
        sleep 0.1
    done
    nsenter --pid --mount --target="$pid" -- "$@"
}

if [ "$1" = "wait" ]; then
    shift
    wait "$@"
    exit

fi

#########################
#        Install        #
#########################

type /usr/bin/openrc >/dev/null && return

apk add openrc

##############################################################################################
# openrc 依靠 inittab
# WSL中初始进程 "/init" 无法启动 inittab，需要重新执行 "/sbin/init"
# "/sbin/init" 必须做为初始进程 (PID 1) 运行，使用 namespace 技术
# 依赖 util-linux 软件包中的 (nsenter,nsenter) 命令实现 namespace

apk add util-linux

mkdir -p /etc/wsl

cat <<"EOF" | tee /etc/wsl/wsl-init
#!/bin/sh
if [ $$ -ne "1" ]; then
    {
        flock -n 5
        [ $? -eq 1 ] && exit
        echo $$ >/var/run/wsl-init.pid
        exec /usr/bin/env -i /usr/bin/unshare --pid --mount-proc --fork --propagation unchanged -- ${0}
        exit
    } 5<>/var/run/wsl-init.lock
fi
exec /sbin/init
EOF
chmod +x /etc/wsl/wsl-init

# wel.conf  boot.command
cat <<EOF | tee /etc/wsl.conf
[boot]
command = /etc/wsl/wsl-init
EOF

##############################################################################################
# shell 会话自动进入 namespace

cat <<"EOF" | tee /etc/wsl/wsl-nsenter-core
#!/bin/sh
exec /usr/bin/env -i /usr/bin/nsenter --pid --mount --target="$1" --wdns="$(pwd)" -- /bin/su "${2:-root}"
EOF
chmod +x /etc/wsl/wsl-nsenter-core

apk add sudo
echo "ALL ALL=(root) NOPASSWD: /etc/wsl/wsl-nsenter-core" >/etc/sudoers.d/wsl-nsenter

cat <<"EOF" | tee /etc/wsl/wsl-nsenter
#!/bin/sh
if [ -r /var/run/wsl-init.pid ]; then
    parent="$(cat /var/run/wsl-init.pid)"
    pid="$(ps -o pid,ppid,args | awk '$2 == "'"${parent}"'" && $3 ~ /^\/sbin\/init/ { print $1 }')"
    if [ -n "$pid" ] && [ "$pid" -ne 1 ]; then
        if [ "$USER" == "root" ]; then
            exec /etc/wsl/wsl-nsenter-core "$pid"
        elif type -t /usr/bin/sudo >/dev/null; then        
            [ -f "$HOME/.wsl-nsenter.env" ] && rm "$HOME/.wsl-nsenter.env"
            export > "$HOME/.wsl-nsenter.env"
            exec sudo /etc/wsl/wsl-nsenter-core "$pid" "$USER"
        fi
    fi
fi
if [ -f "$HOME/.wsl-nsenter.env" ]; then
  set -a
  source "$HOME/.wsl-nsenter.env"
  set +a
  rm "$HOME/.wsl-nsenter.env"
fi
EOF
chmod +x /etc/wsl/wsl-nsenter
ln -sf /etc/wsl/wsl-nsenter /etc/profile.d/00-wsl-nsenter.sh

##############################################################################################
# 马上生效
# 依赖 busybox\coreutils 软件包中的 (nohup) 命令和 & 实现后台运行
/etc/wsl/wsl-init >/dev/null 2>&1 &
