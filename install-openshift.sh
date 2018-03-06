#!/bin/bash

## see: https://www.youtube.com/watch?v=-OOnGK-XeVY

echo "------------>1.process export variable------------>"
export DOMAIN=${DOMAIN:="192.168.106.2"}
export USERNAME=${USERNAME:="voleak"}
export PASSWORD=${PASSWORD:=voleak}
export VERSION=${VERSION:="v3.7.1"}

export SCRIPT_REPO=${SCRIPT_REPO:="https://raw.githubusercontent.com/thol-voleak/installcentos/master"}

export IP="$(ip route get 8.8.8.8 | awk '{print $NF; exit}')"

echo "******"
echo "* Your domain is $DOMAIN "
echo "* Your username is $USERNAME "
echo "* Your password is $PASSWORD "
echo "* OpenShift version: $VERSION "
echo "******"

echo "------------>2.process install applications dependency------------>"
yum install -y epel-release
yum install -y git wget zile nano net-tools docker \
python-cryptography pyOpenSSL.x86_64 python2-pip \
openssl-devel python-devel httpd-tools NetworkManager python-passlib \
java-1.8.0-openjdk-headless "@Development Tools"

echo "------------>3.process check/restart/enable network manager------------>"
systemctl | grep "NetworkManager.*running" 
if [ $? -eq 1 ]; then
	systemctl start NetworkManager
	systemctl enable NetworkManager
fi

echo "------------>4.process clone & install ansible------------>"
which ansible || pip install -Iv ansible

[ ! -d openshift-ansible ] && git clone https://github.com/openshift/openshift-ansible.git

cd openshift-ansible && git fetch && git checkout release-3.7 && cd ..

echo "------------>5.process set /etc/hosts------------>"
cat <<EOD > /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4 
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
${IP}		$(hostname) console console.${DOMAIN} 
EOD
echo "------------>6.process check/setup docker storage------------>"
if [ -z $DISK ]; then 
	export DISK="/dev/sda"
	cp /etc/sysconfig/docker-storage-setup /etc/sysconfig/docker-storage-setup.bk
	echo DEVS=$DISK > /etc/sysconfig/docker-storage-setup
	echo VG=DOCKER >> /etc/sysconfig/docker-storage-setup
	echo SETUP_LVM_THIN_POOL=yes >> /etc/sysconfig/docker-storage-setup
	echo DATA_SIZE="100%FREE" >> /etc/sysconfig/docker-storage-setup

	systemctl stop docker

	rm -rf /var/lib/docker
	wipefs --force $DISK
	docker-storage-setup
fi
echo "------------>7.process restart/enable docker------------>"
systemctl restart docker
systemctl enable docker
 echo "------------>8.process check ssh key------------>"
if [ ! -f ~/.ssh/id_rsa ]; then
        echo "------------>8.1.process generate ssh key------------>"
	ssh-keygen -q -f ~/.ssh/id_rsa -N ""
	cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
	ssh -o StrictHostKeyChecking=no -p 7735 root@$IP "pwd" < /dev/null
fi


echo "------------>9.process enable/disable METRICS/LOGGING------------>"
export METRICS="True"
export LOGGING="True"
memory=$(cat /proc/meminfo | grep MemTotal | sed "s/MemTotal:[ ]*\([0-9]*\) kB/\1/")
if [ "$memory" -lt "4194304" ]; then
	export METRICS="False"
fi
if [ "$memory" -lt "8388608" ]; then
	export LOGGING="False"
fi

echo "------------>10.process ansible playbook------------>"
curl -o inventory.download $SCRIPT_REPO/inventory.ini
envsubst < inventory.download > inventory.ini
ansible-playbook -i inventory.ini openshift-ansible/playbooks/byo/config.yml

echo "------------>11.process htpasswd and set cluster role------------>"
htpasswd -b /etc/origin/master/htpasswd ${USERNAME} ${PASSWORD}
oc adm policy add-cluster-role-to-user cluster-admin ${USERNAME}

echo "------------>12.process restart origin-master-api------------>"
systemctl restart origin-master-api

echo "******"
echo "* Your conosle is https://console.$DOMAIN:8443"
echo "* Your username is $USERNAME "
echo "* Your password is $PASSWORD "
echo "*"
echo "* Login using:"
echo "*"
echo "$ oc login -u ${USERNAME} -p ${PASSWORD} https://console.$DOMAIN:8443/"
echo "******"
echo "------------>12.process oc login------------>"
oc login -u ${USERNAME} -p ${PASSWORD} https://console.$DOMAIN:8443/
