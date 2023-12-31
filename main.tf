terraform {
  required_version = ">= 0.14"
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}

variable "instances" {
    default = {
        # RL88: "Rocky-8-GenericCloud-Base-8.8-20230518.0.x86_64.qcow2" # scsi, sdX, scsi-0QEMU_QEMU_HARDDISK_58370aeb-77f8-4e0e-976d-95f1634fa4bd
        RL89: "Rocky-8-GenericCloud-Base-8.9-20231119.0.x86_64.qcow2" # no scsi, vdX, virtio-5e4eb5e8-c001-4e16-a
        RL93: "Rocky-9-GenericCloud-Base-9.3-20231113.0.x86_64.qcow2" # no scsi, vdX, virtio-d4c01616-fe98-4a1e-b
        # RL93-systemd254: "Rocky-9-GenericCloud-Base-9.3-20231113-systemd254.qcow2" # systemd v254
        default: "openhpc-231027-0916-893570de" # https://github.com/stackhpc/ansible-slurm-appliance/pull/324, # RL8 w/ scsi, sdX, scsi-0QEMU_QEMU_HARDDISK_44495415-cced-4275-b856-a45e5c0d7f51
    }
}

data "openstack_images_image_v2" "rl" {
    for_each = var.instances
    
    name = each.value
}

resource "openstack_blockstorage_volume_v3" "state" {
    
    for_each = var.instances

    name = "${each.key}-state"
    description = "State for control node"
    size = 10
}

resource "openstack_blockstorage_volume_v3" "home" {
    
    for_each = var.instances

    name = "${each.key}-home"
    description = "Home for control node"
    size = 20
}


resource "openstack_compute_instance_v2" "rl" {
  
  for_each = var.instances
  
  name = "test-${each.key}"
  image_name = each.value
  flavor_name = "vm.ska.cpu.general.small"
  key_pair = "slurm-app-ci"
  
  # root device:
  block_device {
      uuid = data.openstack_images_image_v2.rl[each.key].id
      source_type  = "image"
      destination_type = "local" # TODO: try "volume"
      #volume_size = var.volume_backed_instances ? var.root_volume_size : null
      boot_index = 0
      delete_on_termination = true
  }

  block_device {
      destination_type = "volume"
      source_type  = "volume"
      boot_index = -1
      uuid = openstack_blockstorage_volume_v3.state[each.key].id
  }

  block_device {
      destination_type = "volume"
      source_type  = "volume"
      boot_index = -1
      uuid = openstack_blockstorage_volume_v3.home[each.key].id
  }

  network {
    name = "portal-internal"
    access_network = true
  }

  
  user_data = <<-EOF
    #cloud-config
    
    bootcmd:
      %{for volume in [openstack_blockstorage_volume_v3.state[each.key], openstack_blockstorage_volume_v3.home[each.key]]}
      - BLKDEV=$(readlink -f $(ls /dev/disk/by-id/*${substr(volume.id, 0, 20)}* | head -n1 )); blkid -o value -s TYPE $BLKDEV ||  mke2fs -t ext4 -L ${lower(split(" ", volume.description)[0])} $BLKDEV
      %{endfor}

    mounts:
      - [LABEL=state, /var/lib/state, auto, "defaults,x-systemd.requires=cloud-init.service,_netdev,comment=cloudconfig"]
      - [LABEL=home, /exports/home, auto, "defaults,x-systemd.requires=cloud-init.service,_netdev,comment=cloudconfig,x-systemd.required-by=nfs-server.service,x-systemd.before=nfs-server.service,x-systemd.required-by=remote-fs.target,x-systemd.before=remote-fs.target"]


    # this is for debugging purposes, and is obviously insecure!
    chpasswd:
      expire: false
      users:
        - name: root
          password: GX67A
          type: text
  EOF

}


output "ip" {
    description = "ips"
    value = {for instance in openstack_compute_instance_v2.rl: instance.name => instance.access_ip_v4}
    sensitive = true
}

resource local_file "inventory" {
    content = <<-EOF
        [all]
        %{ for instance in openstack_compute_instance_v2.rl}
        ${instance.name} ansible_host=${instance.access_ip_v4 ~}
        %{ endfor }
    EOF
    filename = "inventory.ini"
}
