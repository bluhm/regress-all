export REGRESS_FAIL_EARLY=no
export TEST_SSH_UNSAFE_PERMISSIONS=yes

export MANAGEMENT_IF=em0
export SKIP_IF=em0,em1
export NETLINK_LINE=6
export LINUX_IF=ens10f0np0
export LINUX_DIRECT_IF=ens10f1np1
export LINUX_LEFT_SSH=root@lt40
export LINUX_RIGHT_SSH=root@lt43

ftp_proxy=http://10.0.1.3:8000/
http_proxy=http://10.0.1.3:8000/
https_proxy=http://10.0.1.3:8000/
export ftp_proxy http_proxy https_proxy
