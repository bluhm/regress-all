# em18 is management, em18 is tripple port
# em8 and em9 are onboard
# em4, em5 and em12, em13 belong to quad port
export MANAGEMENT_IF=em18
export SKIP_IF=em18
export NETLINK_LINE=3
# currently there is no distinct linux interface for link 4, share with 3
export LINUX_IF=enp6s0

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

LOCAL_ADDR_RANGE=10.10.31.20
LOCAL_ADDR6_RANGE=fdd7:e83e:66bd:1031::20
LINUX_ADDR_RANGE=10.10.32.40
LINUX_ADDR6_RANGE=fdd7:e83e:66bd:1032::40
LINUX_SSH=root@lt40
LINUX_OTHER_SSH=root@lt43
export LOCAL_ADDR_RANGE LOCAL_ADDR6_RANGE LINUX_ADDR_RANGE LINUX_ADDR6_RANGE
export LINUX_SSH LINUX_OTHER_SSH
