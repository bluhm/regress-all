LOCAL_IF=ix0
LOCAL_ADDR=10.3.45.34
LOCAL_ADDR6=fdd7:e83e:66bc:0345::34

REMOTE_IF=ix1
REMOTE_ADDR=10.3.45.35
REMOTE_ADDR6=fdd7:e83e:66bc:0345::35
REMOTE_SSH=ot15

LINUX_ADDR=10.3.46.36
LINUX_ADDR6=fdd7:e83e:66bc:0346::36
LINUX_FORWARD_ADDR=10.3.46.36
LINUX_FORWARD_ADDR6=fdd7:e83e:66bc:0346::36
LINUX_RELAY_ADDR=10.3.34.34
LINUX_RELAY_ADDR6=fdd7:e83e:66bc:0334::34
LINUX_SSH=perform@lt13

LINUX_RELAY_LOCAL_ADDR=10.3.56.35
LINUX_RELAY_LOCAL_ADDR6=fdd7:e83e:66bc:0356::35
LINUX_RELAY_REMOTE_ADDR=10.3.46.34
LINUX_RELAY_REMOTE_ADDR6=fdd7:e83e:66bc:0346::34
LINUX_OTHER_SSH=perform@lt16

LOCAL_IPSEC_ADDR=10.4.34.34
LOCAL_IPSEC_ADDR6=fdd7:e83e:66bc:0434::34
REMOTE_IPSEC_ADDR=10.4.56.35
REMOTE_IPSEC_ADDR6=fdd7:e83e:66bc:0456::35
LINUX_IPSEC_ADDR=10.4.56.36
LINUX_IPSEC_ADDR6=fdd7:e83e:66bc:0456::36

export LOCAL_IF LOCAL_ADDR LOCAL_ADDR6
export REMOTE_IF REMOTE_ADDR REMOTE_ADDR6
export REMOTE_SSH
export LINUX_ADDR LINUX_ADDR6 LINUX_FORWARD_ADDR LINUX_FORWARD_ADDR6
export LINUX_RELAY_ADDR LINUX_RELAY_ADDR6
export LINUX_SSH
export LINUX_RELAY_LOCAL_ADDR LINUX_RELAY_LOCAL_ADDR6
export LINUX_RELAY_REMOTE_ADDR LINUX_RELAY_REMOTE_ADDR6
export LINUX_OTHER_SSH
export LOCAL_IPSEC_ADDR REMOTE_IPSEC_ADDR LINUX_IPSEC_ADDR
export LOCAL_IPSEC_ADDR6 REMOTE_IPSEC_ADDR6 LINUX_IPSEC_ADDR6
