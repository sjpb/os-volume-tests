Test volume attachment for different images.

# Usage

    ansible-playbook test.yml

The playbook `compare.yml` can also be used to diff arbitrary commands on 2x hosts, e.g.:

    ansible-playbook compare.yml -e 'cmd="systemctl show exports-home.mount"'
    code --diff test-RL89.tmp test-RL93.tmp

Note quoting as per above is important if `cmd` contains spaces.

# Status

After reboot, RL83 has both volumes RL93 only has
    
        vdb    252:16   0   10G  0 disk /var/lib/state
