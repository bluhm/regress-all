export REGRESS_FAIL_EARLY=no
export TEST_SSH_UNSAFE_PERMISSIONS=yes

ftp_proxy=http://10.0.1.3:8000/
http_proxy=http://10.0.1.3:8000/
https_proxy=http://10.0.1.3:8000/
export ftp_proxy http_proxy https_proxy

LOCAL_IF=em0
LOCAL_MAC=90:e2:ba:7e:e8:10

LOCAL_ADDR=10.188.51.25
FAKE_ADDR=10.188.51.188

LOCAL_ADDR6=fdd7:e83e:66bc:51::25
FAKE_ADDR6=fdd7:e83e:66bc:51::188

export LOCAL_IF LOCAL_MAC
export LOCAL_ADDR FAKE_ADDR
export LOCAL_ADDR6 FAKE_ADDR6
