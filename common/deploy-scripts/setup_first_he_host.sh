#!/bin/bash -x
HOSTEDENGINE="$1"
shift
HE_MAC_ADDRESS="$1"
shift
HEADDR="$1"
shift

DOMAIN=$(dnsdomainname)
MYHOSTNAME="$(hostname | sed s/_/-/g)"
HE_SETUP_HOOKS_DIR="/usr/share/ansible/collections/ansible_collections/ovirt/ovirt/roles/hosted_engine_setup/hooks"

# This is needed in case we're using prebuilt ost-images.
# In this scenario ssh keys are baked in to the qcows (so lago
# doesn't inject its own ssh keys), but HE VM is built from scratch.
copy_ssh_key() {
    cat << EOF > ${HE_SETUP_HOOKS_DIR}/enginevm_before_engine_setup/copy_ssh_key.yml
---
- name: Copy ssh key for root to HE VM
  authorized_key:
    user: root
    key: "{{ lookup('file', '/root/.ssh/authorized_keys') }}"
EOF

}

# Use repositories from the host-0 so that we can actually update HE to the same custom repos
dnf_update() {
        cat << EOF > ${HE_SETUP_HOOKS_DIR}/enginevm_before_engine_setup/replace_repos.yml
---
- name: Remove all repositories
  file:
    path: /etc/yum.repos.d
    state: absent
- name: Copy host-0 repositories
  copy:
    src: /etc/yum.repos.d
    dest: /etc
- name: DNF update the system
  dnf:
    name:  "*"
    state: latest
    exclude: ovirt-release-master
EOF

}

copy_dependencies() {
    cat << EOF > ${HE_SETUP_HOOKS_DIR}/enginevm_before_engine_setup/copy_dependencies.yml
---
- name: Copy cirros image to HE VM
  copy:
    src: /var/tmp/cirros.img
    dest: /var/tmp/cirros.img
- name: Copy sysstat rpm package to HE VM
  copy:
    src: "{{ item }}"
    dest: /var/tmp/sysstat.rpm
  with_fileglob:
    - "/var/tmp/sysstat-*"
- name: Copy sysstat dependencies to HE VM
  copy:
    src: "{{ item }}"
    dest: /var/tmp/lm_sensors.rpm
  with_fileglob:
    - "/var/tmp/lm_sensors-*"
EOF

}

add_he_to_hosts() {
    echo "${HEADDR} ${HOSTEDENGINE}.${DOMAIN} ${HOSTEDENGINE}" >> /etc/hosts
}

copy_ssh_key

dnf_update

copy_dependencies

add_he_to_hosts

fstrim -va
rm -rf /var/cache/yum/*
# TODO currently we only pass IPv4 for HE and that breaks on dual stack since host-0 resolves to IPv6 and the setup code gets confused
hosted-engine --deploy --config-append=/root/hosted-engine-deploy-answers-file.conf
RET_CODE=$?
if [ ${RET_CODE} -ne 0 ]; then
    echo "hosted-engine deploy on ${MYHOSTNAME} failed with status ${RET_CODE}."
    exit ${RET_CODE}
fi
rm -rf /var/cache/yum/*
fstrim -va
