# Test Suite : Ansible Role 

A shell based test library for [my Ansible roles](https://galaxy.ansible.com/yabhinav/) that works both locally and over Travis-CI.


## Introduction

This test suite helps seggregate my role tests from fillingup the master/release branch of ansible role repository with unnecessary commits to make travis build work

You can use these tests as a guide for both writing tests for your roles and as documentation on how to use a specific role.


## Comparing real examples

The snippets below come from testing a ipaserver deployment role.

### The old typical Travis way

```
---
services: docker

env:
  - distribution: centos  # Linux distribution
    version: 6            # Distribution version
    init: /sbin/init      # Path to init executable (differs for SysVInit/Systemd)
    run_opts: ""          # Additional options for running the Docker container
    playbook: test.yml    # Test playbook for the distribution
  - distribution: centos
    version: 7
    init: /usr/lib/systemd/systemd
    run_opts: "--privileged --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro"
    playbook: test.yml
  - distribution: fedora
    version: 25
    init: /usr/lib/systemd/systemd
    run_opts: "--privileged --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro"
    playbook: test.yml

before_install:
  # Pull container.
  - 'docker pull yabhinav/ansible:${distribution}-${version}'


script:
  - container_id=$(mktemp)
  # Run container in detached state.
  - 'docker run --detach -h testlab.example.com --volume="${PWD}":/etc/ansible/roles/role_under_test:ro ${run_opts} yabhinav/ansible:${distribution}-${version} "${init}" > "${container_id}"'

  # Ansible version check.
  - 'docker exec --tty "$(cat ${container_id})" env TERM=xterm ansible --version'

  # Hostname checks.
  - 'docker exec --tty "$(cat ${container_id})" env TERM=xterm cat /etc/hosts'
  - 'docker exec --tty "$(cat ${container_id})" env TERM=xterm hostname'

  # - 'docker exec --tty "$(cat ${container_id})" env TERM=xterm ansible all -m setup'

  # Ansible syntax check.
  - 'docker exec --tty "$(cat ${container_id})" env TERM=xterm ansible-playbook /etc/ansible/roles/role_under_test/tests/${playbook} --syntax-check'

  # Test role.
  - testrun=$(mktemp)
  - docker exec "$(cat ${container_id})" env TERM=xterm ansible-playbook /etc/ansible/roles/role_under_test/tests/${playbook} | tee -a ${testrun}
  - >
    tail ${testrun}
    | grep -q 'changed=.*failed=0'
    && (echo 'Role test: pass' && exit 0)
    || (echo 'Role test: fail' && exit 1)

  # Test role idempotence.
  - idempotence=$(mktemp)
  - docker exec "$(cat ${container_id})" env TERM=xterm ansible-playbook /etc/ansible/roles/role_under_test/tests/${playbook} | tee -a ${idempotence}
  - >
    tail ${idempotence}
    | grep -q 'changed=0.*failed=0'
    && (echo 'Idempotence test: pass' && exit 0)
    || (echo 'Idempotence test: fail' && exit 1)

  # Check if IPA Server is running
  - 'docker exec "$(cat ${container_id})" ipactl status'

  # Check klist
  - 'docker exec "$(cat ${container_id})" klist'

  # Check IPA user command
  - 'docker exec "$(cat ${container_id})" ipa user-find admin'


notifications:
  webhooks: https://galaxy.ansible.com/api/v1/notifications/


```

### The same test case using this test-suite


```
---

sudo: required

# Set the Environment Variables
env:
  global: 
    - rolename : ansible-role-ipaserver
  matrix:
    - distribution: centos       # Linux distribution
      version: 6                 # Distribution version
    - distribution: centos
      version: 7
    - distribution: fedora
      version: 25
    -  distribution: ubuntu
      version: 14.04
    - distribution: ubuntu
      version: 12.04

# Donot change anything below. Test controls are given to test-suite
services: docker

before_install:
  # Install latest Git
  - sudo apt-get install --only-upgrade git 


before_script:
  # Fetch the latest test code for the role
  - 'git clone --depth 1 https://github.com/yabhinav/ansible-test-suite'
  - mv ansible-test-suite/$rolename/* . &&  rm -rf ansible-test-suite

script:
  # Create container and load the role as a volume
  - ./docker-tests.sh


notifications:
  webhooks: https://galaxy.ansible.com/api/v1/notifications/


```

It minimizes the script in travis configuration file (only env variables need to set which can be set even in travis project page) and most of the roles pluggable. It also helps in testing multiple/stable ansible version on same docker image.

Giving control to travis doesn't exit the build after a command failure , but with the custom script we can display custom messages/logs.


## Installation


### Docker 

#### Travis

If you're using it on Travis then you don't need to download anything.

Use this [.travis.yml](#the-same-test-case-using-this-test-suite) as a guide, it would go in each of your role's repositories:

#### Locally

1. Set the environmental variables for docker test on centOS6 and ansible-role-ipaserver
  `export distribution=centos; export version=6;`

2. Link your role as role_under_test 
  `ln -s ~/code/MyProjects/ansible-galaxy-roles/ansible-role-ipaserver  /etc/ansible/roles/role_under_test`

3. Execute the test script on the container 
  `docker exec -d ansible_bash ./test.sh`

### Vagrant

Similar to docker but we will use docker images and ansible instead of test scripts. The boxes are provided by [geerlingguy](https://vagrantcloud.com/geerlingguy). I have lost interest in vagrant since docker seems to be better alternative and hence not maintaining the boxes myself

1. Link your role as role_under_test 
  `ln -s ~/code/MyProjects/ansible-galaxy-roles/ansible-role-ipaserver  /etc/ansible/roles/role_under_test`

2. Run the following command from the [ansible-test-suite](https://github.com/yabhinav/ansible-test-suite) :
  ` vagrant --rolename ansible-role-ipaserver --hostname testlab.example.com up `


## License

MIT / BSD


## Author Information

Created by [Abhinav Yalamanchili](https://yabhinav.github.com)


