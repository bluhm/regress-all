export REGRESS_FAIL_EARLY=no
export TEST_SSH_UNSAFE_PERMISSIONS=yes

LOCAL_IF=mcx1
LOCAL_MAC=98:03:9b:82:ed:f7

REMOTE_SSH=ot11
REMOTE_IF=mcx1
REMOTE_MAC=b8:59:9f:0e:57:55
FAKE_MAC=12:34:56:78:9a:bc
OTHER_IF=em0

LOCAL_ADDR=10.188.31.30
LOCAL_NET=10.188.31.30/24
REMOTE_ADDR=10.188.31.31
FAKE_ADDR=10.188.31.188
OTHER_ADDR=10.188.32.31
OTHER_FAKE_ADDR=10.188.32.188
FAKE_NET=10.188.30.0/24
FAKE_NET_ADDR=10.188.30.188

LOCAL_ADDR6=fdd7:e83e:66bc:31::30
LOCAL_NET6=fdd7:e83e:66bc:31::30/64
REMOTE_ADDR6=fdd7:e83e:66bc:31::31
FAKE_ADDR6=fdd7:e83e:66bc:31::188
OTHER_ADDR6=fdd7:e83e:66bc:32::31
OTHER_FAKE1_ADDR6=fdd7:e83e:66bc:32::dead
OTHER_FAKE2_ADDR6=fdd7:e83e:66bc:32::beef
FAKE_NET6=fdd7:e83e:66bc:30::/64
FAKE_NET_ADDR6=fdd7:e83e:66bc:30::188

export LOCAL_IF LOCAL_MAC
export REMOTE_SSH REMOTE_IF REMOTE_MAC FAKE_MAC OTHER_IF
export LOCAL_ADDR LOCAL_NET REMOTE_ADDR FAKE_ADDR
export OTHER_ADDR OTHER_FAKE_ADDR
export LOCAL_ADDR6 LOCAL_NET6 REMOTE_ADDR6 FAKE_ADDR6
export OTHER_ADDR6 OTHER_FAKE1_ADDR6 OTHER_FAKE2_ADDR6
export FAKE_NET FAKE_NET_ADDR
export FAKE_NET6 FAKE_NET_ADDR6
