#! /usr/bin/env bash
#
# Credits : Bert Van Vreckem <bert.vanvreckem@gmail.com>
# Author : Abhinav Y <https:yabhinav-github.com>
#
# Runs tests for this Ansible role on a Docker container
# Environment variables distribution and version must be set
# See usage() for details.

#{{{ Bash settings
# abort on nonzero exitstatus
set -o errexit
# abort on unbound variable
set -o nounset
# don't hide errors within pipes
set -o pipefail
#}}}
#{{{ Variables
readonly script_name=$(basename "${0}")
readonly script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
IFS=$'\t\n'   # Split on newlines and tabs (but not on spaces)

readonly container_id="$(mktemp)"
readonly role_dir='/etc/ansible/roles/role_under_test'
readonly test_playbook="${role_dir}/playbooks/test.yml"

readonly docker_image="yabhinav/ansible"

# Distribution specific settings
init="/sbin/init"
run_opts=("--privileged")

# Supported versions of ansible stable releases
readonly ansible_versions=(latest 2.6.0.0 2.5.0.0 2.4.0.0 2.3.0.0 2.2.0.0 2.1.0.0 2.0.0.0)
ansible_version=latest

#}}}



main() {
  configure_env

  start_container

  # debug_facts
  run_freeipa_installer #for Debian

  run_syntax_check

  run_playbook

  # Running Playbook on older stable ansible versions
  for ansible_version in "${ansible_versions[@]}"
  do
    run_idempotence_test
  done

  run_functional_test

}

#{{{ Helper functions

configure_env() {

  case "${distribution}${version}" in
    'centos7')
      init=/usr/lib/systemd/systemd
      run_opts+=('--volume=/sys/fs/cgroup:/sys/fs/cgroup:ro')
      ;;
    'fedora25')
      init=/usr/lib/systemd/systemd
      run_opts+=('--volume=/sys/fs/cgroup:/sys/fs/cgroup:ro')
      ;;
    'ubuntu14.04')
      # Workaround for issue when the host operating system has SELinux
      if [ -x '/usr/sbin/getenforce' ]; then
        run_opts+=('--volume=/sys/fs/selinux:/sys/fs/selinux:ro')
      fi
      ;;
    'ubuntu16.04')
      run_opts=('--volume=/run' '--volume=/run/lock' '--volume=/tmp' '--volume=/sys/fs/cgroup:/sys/fs/cgroup:ro' '--cap-add=SYS_ADMIN' '--cap-add=SYS_RESOURCE')

      if [ -x '/usr/sbin/getenforce' ]; then
        run_opts+=('--volume=/sys/fs/selinux:/sys/fs/selinux:ro')
      fi
      ;;
  esac
}

# Usage: build_container
build_container() {
  docker build --tag="${docker_image}:${distribution}${version}"
}

start_container() {
  log "Starting container on image : ${docker_image}:${distribution}${version}"
  set -x
  docker run --detach  \
    -h "testlab.example.com" \
    --volume="${PWD}:${role_dir}:ro" \
    "${run_opts[@]}" \
    "${docker_image}:${distribution}${version}" \
    "${init}"  \
    > "${container_id}"
  set +x
}

debug_facts(){
  log "Debugging System and Ansible facts"
  set -x
  exec_container "hostname -f"
  exec_container "hostname -d"
  exec_container "hostname -s"
  exec_container "cat /etc/hosts"
  exec_container "source ~/.bashrc && workon ansible_${ansible_version} && ansible all -m setup && deactivate"
  exec_container "cat /etc/sysconfig/network"
  set +x
}

get_container_id() {
  cat "${container_id}"
}

# Usage: get_container_ip CONTAINER_ID
get_container_ip() {
  local container_id="${1}"

  docker inspect \
    --format '{{ .NetworkSettings.IPAddress }}' \
    "${container_id}"
}

exec_container() {
  id="$(get_container_id)"
  set -x
  docker exec \
    "${id}" \
    bash -c "${@}"
  set +x
}

# FreeIPA has issue executing install over virtualenvwrapper
# due to debian is non-interactive but still --configure is triggered for freeipa as if in interactive mode
run_freeipa_installer(){
  if [ "${distribution}" == "ubuntu" ] || [ "${distribution}" == "debian" ]; then
        exec_container "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y install freeipa-server" >> /dev/null
  fi
}

run_syntax_check() {
  log "Running syntax check on playbook"
  log "Working on ansible version : ${ansible_version}"
  exec_container "source ~/.bashrc && workon ansible_${ansible_version} && ansible --version"
  exec_container "source ~/.bashrc &&  workon ansible_${ansible_version} && ansible-playbook ${test_playbook} --syntax-check && deactivate ; (exit \$?)"
}

run_playbook() {
  log "Running playbook"
  log "Working on ansible version : ${ansible_version}"
  exec_container "source ~/.bashrc && workon ansible_${ansible_version} && ansible --version"
  local output
  output="$(mktemp)"

  exec_container "source ~/.bashrc && workon ansible_${ansible_version} && ansible-playbook ${test_playbook} && deactivate ; (exit \$?)" 2>&1 | tee "${output}"

  if grep -q 'changed=.*unreachable=0.*failed=1' "${output}"; then
    result='pass'
    return_status=0
  else
    result='fail'
    return_status=1
  fi
  rm "${output}"

  log "Result: ${result}"
  return "${return_status}"
}

run_idempotence_test() {
  log "Running idempotence test"
  log "Working on ansible version : ${ansible_version}"
  exec_container "source ~/.bashrc && workon ansible_${ansible_version} && ansible --version"
  local output
  output="$(mktemp)"

  exec_container "source ~/.bashrc && workon ansible_${ansible_version} && ansible-playbook ${test_playbook} && deactivate ; (exit \$?)" 2>&1 | tee "${output}"

  if grep -q 'changed=0.*unreachable=0.*failed=0' "${output}"; then
    result='pass'
    return_status=0
  else
    result='fail'
    return_status=1
  fi
  rm "${output}"

  log "Result: ${result}"
  return "${return_status}"
}

run_functional_test() {
  log "Running IPA server functional tests"
  exec_container "ipa user-find admin"
  exec_container "ipa user-add testlab --first=testlab --last=user "
  exec_container "ipa user-show testlab"
  exec_container "getent passwd testlab"
  exec_container "getent group testlab"
  exec_container "ipa user-del testlab"
  log "Functional Tests successfull"
}

cleanup() {
  log "Cleaning up"
  id="$(get_container_id)"

  docker stop "${id}"
  docker rm "${id}"
  rm "${container_id}"
}
trap cleanup EXIT INT ERR HUP TERM


log() {
  local yellow='\e[0;33m'
  local reset='\e[0m'

  printf "${yellow}>>> %s${reset}\n" "${*}"
}

#}}}

main
