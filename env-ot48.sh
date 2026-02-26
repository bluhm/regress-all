export MANAGEMENT_IF=vio2
export SKIP_IF=vio2
export NETLINK_LINE=5
export LINUX_IF=enp7s0
export LINUX_LEFT_SSH=root@lt49
export LINUX_RIGHT_SSH=root@lt59

export REGRESS_FAIL_EARLY=no
export TEST_SSH_UNSAFE_PERMISSIONS=yes

LOCAL_IF=vio1
LOCAL_MAC=52:54:00:00:9c:58

export LOCAL_IF LOCAL_MAC

# proxy for building ports localy

ftp_proxy=http://10.0.1.3:8000/
http_proxy=http://10.0.1.3:8000/
https_proxy=http://10.0.1.3:8000/
export ftp_proxy http_proxy https_proxy
