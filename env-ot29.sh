export REGRESS_FAIL_EARLY=no
export TEST_SSH_UNSAFE_PERMISSIONS=yes

LOCAL_IF=em1
LOCAL_MAC=d0:50:99:f9:d7:0c

export LOCAL_IF LOCAL_MAC

ftp_proxy=http://10.0.1.3:8000/
http_proxy=http://10.0.1.3:8000/

export ftp_proxy http_proxy
