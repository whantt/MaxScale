#!/bin/bash

export dir=`pwd`

ulimit -n

# read the name of build scripts directory
export script_dir="$(dirname $(readlink -f $0))"

rm -rf LOGS

export mdbci_config_name=`echo ${mdbci_config_name} | sed "s/?//g"`



# prepare separate dir for MDBCI vms
rm -rf $HOME/${mdbci_config_name}_vms
mkdir -p $HOME/${mdbci_config_name}_vms

export MDBCI_VM_PATH=$HOME/${mdbci_config_name}_vms
export PATH=$PATH:$HOME/mdbci

export provider=`mdbci show provider $box --silent 2> /dev/null`
export backend_box=${backend_box:-"centos_7_"$provider}

mdbci destroy test_vm

cp ${script_dir}/test_vm.json $HOME/${mdbci_config_name}_vms/
test_vm_box="ubuntu_bionc_"$provider
me=`whoami`
sed -i $HOME/${mdbci_config_name}_vms/test_vm.json "s/###test_vm_box###/${test_vm_box}/"
sed -i $HOME/${mdbci_config_name}_vms/test_vm.json "s/###test_vm_user###/${me}/"

mdbci generate test_vm --template test_vm.json --override
mdbci up test_vm

ip=`mdbci show network --silent ub`
key=`mdbci show keyfile --silent ub`
sshopt="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=120  "


ssh -i $key $sshopt $me@$ip "mkdir -p .ssh; mkdir -p ${MDBCI_VM_PATH}; mkdir mdbci"
scp -i $key $sshopt -r ${script_dir}/../../* $me@$ip:~/MaxScale/

scp -i $key $sshopt $HOME/.config/mdbci/max-tst.key $me@$ip:~/.ssh/id_rsa
ssh -i $key $sshopt $me@$ip "chmod 400 .ssh/id_rsa"
scp -i $key $sshopt ${script_dir}/mdbci_wrapper $me@$ip:~/mdbci/mdbci
ssh -i $key $sshopt $me@$ip "chmod +x mdbci/mdbci"

ssh -i $key $sshopt $me@$ip "echo export MDBCI_VM_PATH=${MDBCI_VM_PATH} > test_env"
ssh -i $key $sshopt $me@$ip "echo export PATH=\$PATH:\$HOME/mdbci >> test_env"

test_env_list = (
    "WORKSPACE"
    "JOB_NAME"
    "BUILD_NUMBER"
    "BUILD_TIMESTAMP"
    "name"
    "target"
    "box"
    "product"
    "version"
    "do_not_destroy_vm"
    "test_set"
    "ci_url"
    "smoke"
    "big"
    "backend_ssl"
    "use_snapshots"
    "no_vm_revert"
    "template"
    "config_to_clone"
    "test_branch"
    "use_valgrind"
    "use_callgrind"
    "mdbci_config_name"
)

for s in ${test_env_list[@]} ; do
   eval "v=\$$s"
   echo "export $s=$v" >> test_env
done

scp -i $key $sshopt test_env $me@$ip:~/

ssh -i $key $sshopt $me@$ip ". ./test_env; ./MaxScale/maxscale-system-test/mdbci/run_test.sh"

. ${script_dir}/configure_log_dir.sh

ulimit -c unlimited



cp core.* ${logs_publish_dir}
${script_dir}/copy_logs.sh
cd $dir

if [ "${do_not_destroy_vm}" != "yes" ] ; then
	mdbci destroy ${mdbci_config_name}
	echo "clean up done!"
fi
