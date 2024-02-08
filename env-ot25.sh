# em0 is management
# em0, em1, em2, em3 are onboard
# em10 is tripple port
# em6, em7 are quad port
export MANAGEMENT_IF=em0
# em4, em5, ix0, ix1 have no carrier
# em8, em9, em10 are identical to em2
export SKIP_IF=em0,em1,em4,em5,em8,em9,em10,em11,em12,ix0,ix1
export NETLINK_LINE=4
# currently there is no distinct linux interface for link 4, share with 3
export LINUX_IF=enp6s0

# allow to manually run perform tests frag and splice on netlink hosts

export REGRESS_FAIL_EARLY=no
export TEST_SSH_UNSAFE_PERMISSIONS=yes

LOCAL_IF=em1
LOCAL_MAC=00:21:28:13:9c:0d

LOCAL_ADDR=10.188.25.45
LOCAL_NET=10.188.25.45/24
FAKE_ADDR=10.188.25.188

LOCAL_ADDR6=fdd7:e83e:66bc:25::45
LOCAL_NET6=fdd7:e83e:66bc:25::45/64
FAKE_ADDR6=fdd7:e83e:66bc:25::188

export LOCAL_IF LOCAL_MAC
export LOCAL_ADDR LOCAL_NET FAKE_ADDR
export LOCAL_ADDR6 LOCAL_NET6 FAKE_ADDR6

ftp_proxy=http://10.0.1.3:8000/
http_proxy=http://10.0.1.3:8000/
https_proxy=http://10.0.1.3:8000/
export ftp_proxy http_proxy https_proxy

# allow to manually run perform tests frag and splice on netlink hosts

LOCAL_ADDR_RANGE=10.10.41.20
LOCAL_ADDR6_RANGE=fdd7:e83e:66bd:1041::20
LINUX_ADDR_RANGE=10.10.42.40
LINUX_ADDR6_RANGE=fdd7:e83e:66bd:1042::40
LINUX_SSH=root@lt40
LINUX_OTHER_SSH=root@lt43
export LOCAL_ADDR_RANGE LOCAL_ADDR6_RANGE LINUX_ADDR_RANGE LINUX_ADDR6_RANGE
export LINUX_SSH LINUX_OTHER_SSH
