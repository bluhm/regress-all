export REGRESS_FAIL_EARLY=no
export TEST_SSH_UNSAFE_PERMISSIONS=yes

ftp_proxy=http://10.0.1.3:8000/
http_proxy=http://10.0.1.3:8000/
https_proxy=http://10.0.1.3:8000/
export ftp_proxy http_proxy https_proxy

LOCAL_IF=cas1
LOCAL_MAC=00:03:ba:ac:b9:b4

LOCAL_ADDR=10.188.21.41
FAKE_ADDR=10.188.21.188

LOCAL_ADDR6=fdd7:e83e:66bc:21::41
FAKE_ADDR6=fdd7:e83e:66bc:21::188

export LOCAL_IF LOCAL_MAC
export LOCAL_ADDR FAKE_ADDR
export LOCAL_ADDR6 FAKE_ADDR6
