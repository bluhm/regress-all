export REGRESS_FAIL_EARLY=no
export TEST_SSH_UNSAFE_PERMISSIONS=yes

LOCAL_IF=em1
LOCAL_MAC=00:1b:21:30:3c:51

LOCAL_ADDR=10.188.51.46
LOCAL_NET=10.188.51.46/24
FAKE_ADDR=10.188.51.188

LOCAL_ADDR6=fdd7:e83e:66bc:51::46
LOCAL_NET6=fdd7:e83e:66bc:51::46/64
FAKE_ADDR6=fdd7:e83e:66bc:51::188

export LOCAL_IF LOCAL_MAC
export LOCAL_ADDR LOCAL_NET FAKE_ADDR
export LOCAL_ADDR6 LOCAL_NET6 FAKE_ADDR6

ftp_proxy=http://10.0.1.3:8000/
http_proxy=http://10.0.1.3:8000/
https_proxy=http://10.0.1.3:8000/
export ftp_proxy http_proxy https_proxy
