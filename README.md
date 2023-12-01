Test volume attachment for different images.

# Problem
- The prefix of the block devices in `/dev` depends on the image properties of
  the root disk, being either `vdX` if scsi properties are applied, else `vdX`.
- More problematically, the ordering of the block devices in `/dev` is not reliable.
  With a RockyLinux GenericCloud 8.8 image (and, anecdotally, 8.6), the ordering in
  `/dev` matched the order of the `block_device` blocks within an
  `openstack_compute_instance_v2` resource. However for an 8.9 this ordering did not
  survive a reboot.

# Solution

Use cloud-init userdata to:
- Identify the device path using the partial openstack ID present in `/dev/disk-by-id`
  - note what's present here depends on scsi tags.
- Run `mke2fs` to create the filesystem, with a label derived from the openstack
  volume description, with a check to avoid re-formatting existing filesystems. This
  check is necessary to avoid problems after e.g. reimaging or deleting/recreating
  instances when cloud-init will run again.
- Use cloud-init's `mount` module to mount the filesystem by label.

# Usage

    ansible-playbook test.yml

This will:
    - Delete (if necessary, for a clean start) and create instances with 2x attached
      volumes, formatting and mounting them via cloud-init bootcmds
    - Check the volumes are attached
    - Reboot the instances
    - Check volumes are still attached (this failed with a previous approach, not
      implmented here, which depended on the order in `/dev/disk`)
    - Write some test data to each volume
    - Reimage the instances
    - Check test data survived (i.e. didn't re-format the volumes)

The playbook `compare.yml` can also be used to diff arbitrary commands on 2x hosts, e.g.:

    ansible-playbook compare.yml -e 'cmd="systemctl show exports-home.mount"'
    code --diff test-RL89.tmp test-RL93.tmp

Note quoting as per above is important if `cmd` contains spaces.

# Status

After reboot, RL83 has both volumes RL93 only has
    
        vdb    252:16   0   10G  0 disk /var/lib/state
