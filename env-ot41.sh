# em4 is management, not enough switch ports for em2 and em3
export MANAGEMENT_IF=em4
export SKIP_IF=em4,em2,em3
export NETLINK_LINE=1
export LINUX_IF=ens2f1
export LINUX_LEFT_SSH=root@lt40
export LINUX_RIGHT_SSH=root@lt43

# allow to manually run perform tests frag and splice on netlink hosts

LOCAL_ADDR=undef
LOCAL_NET=undef
LOCAL_ADDR6=undef
LOCAL_NET6=undef
REMOTE_ADDR=undef
REMOTE_ADDR6=undef
REMOTE_SSH=undef
export LOCAL_ADDR LOCAL_NET LOCAL_ADDR6 LOCAL_NET6
export REMOTE_ADDR REMOTE_ADDR6 REMOTE_SSH

LOCAL_ADDR_RANGE=10.10.11.20
LOCAL_ADDR6_RANGE=fdd7:e83e:66bd:1011::20
LINUX_ADDR_RANGE=10.10.12.40
LINUX_ADDR6_RANGE=fdd7:e83e:66bd:1012::40
export LOCAL_ADDR_RANGE LOCAL_ADDR6_RANGE LINUX_ADDR_RANGE LINUX_ADDR6_RANGE
