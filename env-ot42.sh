# igc2 is management, igc3 is left over
export MANAGEMENT_IF=igc2
export SKIP_IF=em0,em1,igc2,igc3,ice0,ice1
export NETLINK_LINE=2
export LINUX_IF=ens2f0
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

LOCAL_ADDR_RANGE=10.10.21.20
LOCAL_ADDR6_RANGE=fdd7:e83e:66bd:1021::20
LINUX_ADDR_RANGE=10.10.22.40
LINUX_ADDR6_RANGE=fdd7:e83e:66bd:1022::40
export LOCAL_ADDR_RANGE LOCAL_ADDR6_RANGE LINUX_ADDR_RANGE LINUX_ADDR6_RANGE
