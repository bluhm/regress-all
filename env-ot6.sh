export REGRESS_FAIL_EARLY=no
export TEST_SSH_UNSAFE_PERMISSIONS=yes

LOCAL_IF=em1
LOCAL_MAC=00:04:23:d8:a7:59

LOCAL_ADDR=10.188.61.26
LOCAL_NET=10.188.61.26/24
FAKE_ADDR=10.188.61.188

LOCAL_ADDR6=fdd7:e83e:66bc:61::26
LOCAL_NET6=fdd7:e83e:66bc:61::26/64
FAKE_ADDR6=fdd7:e83e:66bc:61::188

export LOCAL_IF LOCAL_MAC
export LOCAL_ADDR LOCAL_NET FAKE_ADDR
export LOCAL_ADDR6 LOCAL_NET6 FAKE_ADDR6
