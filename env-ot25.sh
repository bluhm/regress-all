# em0 is management
# em0, em1, em2, em3 are onboard
# em6, em7 belong to quad port
export MANAGEMENT_IF=em0
export SKIP_IF=em0,em1,em6,em7
export NETLINK_LINE=4
export LINUX_IF=ens10f0np0
export LINUX_LEFT_SSH=root@lt40
export LINUX_RIGHT_SSH=root@lt43

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
export LOCAL_ADDR_RANGE LOCAL_ADDR6_RANGE LINUX_ADDR_RANGE LINUX_ADDR6_RANGE
