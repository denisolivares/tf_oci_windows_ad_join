provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

variable "userdata" {
  default = "userdata"
}

variable "cloudinit_ps1" {
  default = "cloudinit.ps1"
}

variable "cloudinit_config" {
  default = "cloudinit.yml"
}

variable "setup_ps1" {
  default = "setup.ps1"
}

variable "size_in_gbs" {
  default = "256"
}

variable "instance_name" {
  default = "ad-server"
}

variable "instance_image_ocid" {
  type = map(string)

  default = {
    # Images released in and after July 2018 have cloudbase-init and winrm enabled by default, refer to the release notes - https://docs.cloud.oracle.com/iaas/images/
    # Image OCIDs for Windows-Server-2012-R2-Standard-Edition-VM-Gen2-2018.10.12-0 - https://docs.cloud.oracle.com/iaas/images/image/80b70ffd-5efc-479e-872c-d1bf6bcbefbd/
    eu-frankfurt-1 = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaat5km25plmetj6gtnhrr5xprmv7boe25q2vrzwhbgno5yh2owybja"
    us-ashburn-1   = "ocid1.image.oc1.iad.aaaaaaaaxgzzrdoge7zxrjtmjqjhicaxsujljvaju3mbwryo5x5k5axlmsza"
    uk-london-1    = "ocid1.image.oc1.uk-london-1.aaaaaaaaedntd3p6jed5d2p7gsohfu6x3k67s364amtzb5vwfzrvfzt2rrlq"
    us-phoenix-1   = "ocid1.image.oc1.phx.aaaaaaaaskz7sq3mlmiwazehuqzoxdq4xz7sinrwn5m6kedxz3td2c7it2vq"
    # Windows-Server-2019-Standard-Edition-VM-E3-2020.10.20-0
    # https://docs.oracle.com/en-us/iaas/images/image/d8f0601f-8d32-4283-8ab7-80466de63ed5/
    sa-saopaulo-1  = "ocid1.image.oc1.sa-saopaulo-1.aaaaaaaackqe7r4zy7wurd54p52y5dtw4yx77rzdtujoy43hgrx45m5xjxva"
  }
}

# Cloudinit
# Generate a new strong password for your instance
resource "random_string" "instance_password" {
  length  = 16
  special = true
}

# Use the cloudinit.ps1 as a template and pass the instance name, user and password as variables to same
data "template_file" "cloudinit_ps1" {
  vars = {
    instance_user     = "opc"
    instance_password = random_string.instance_password.result
    instance_name     = var.instance_name
  }

  template = file("${var.userdata}/${var.cloudinit_ps1}")
}

data "template_cloudinit_config" "cloudinit_config" {
  gzip          = false
  base64_encode = true

  # The cloudinit.ps1 uses the #ps1_sysnative to update the instance password and configure winrm for https traffic
  part {
    filename     = "cloudinit.ps1"
    content_type = "text/x-shellscript"
    content      = data.template_file.cloudinit_ps1.rendered
  }

  # The cloudinit.yml uses the #cloud-config to write files remotely into the instance, this is executed as part of instance setup
  part {
    filename     = "cloudinit.yml"
    content_type = "text/cloud-config"
    content      = file("${var.userdata}/${var.cloudinit_config}")
  }
}

# Network
data "oci_identity_availability_domain" "ad" {
  compartment_id = var.tenancy_ocid
  ad_number      = 1
}

resource "oci_core_vcn" "test_vcn" {
  cidr_block     = "10.1.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "TestVcn"
  dns_label      = "testvcn"
}

resource "oci_core_internet_gateway" "test_internet_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = "TestInternetGateway"
  vcn_id         = oci_core_vcn.test_vcn.id
}

resource "oci_core_route_table" "test_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.test_vcn.id
  display_name   = "TestRouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.test_internet_gateway.id
  }
}

# https://docs.cloud.oracle.com/iaas/Content/Compute/Tasks/accessinginstance.htm#one
resource "oci_core_security_list" "ad_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.test_vcn.id
  display_name   = "TestSecurityList"

  # allow inbound remote desktop traffic
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 3389
      max = 3389
    }
  }

  # allow inbound winrm traffic
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 5985
      max = 5986
    }
  }

  # allow inbound RPC endpoint mapper
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "10.1.20.0/24"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 135
      max = 135
    }
  }

  # allow inbound NetBIOS name service
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "10.1.20.0/24"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 137
      max = 137
    }
  }

  # allow inbound WINS replication
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "10.1.20.0/24"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 42
      max = 42
    }
  }

  # allow inbound DNS
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "10.1.20.0/24"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 53
      max = 53
    }
  }

  # allow inbound http
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 80
      max = 80
    }
  }

  # allow inbound Kerberos
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "10.1.20.0/24"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 88
      max = 88
    }
  }

  # allow inbound NetBIOS datagram service
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "10.1.20.0/24"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 138
      max = 138
    }
  }

  # allow inbound NetBIOS session service
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "10.1.20.0/24"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 139
      max = 139
    }
  }

  # allow inbound LDAP
  ingress_security_rules {
    protocol  = "17" # udp
    source    = "10.1.20.0/24"
    stateless = false

    udp_options {
      # These values correspond to the destination port range.
      min = 389
      max = 389
    }
  }

  # allow inbound SMB over IP (Microsoft-DS)
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "10.1.20.0/24"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 445
      max = 445
    }
  }

  # allow inbound LDAP over SSL
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "10.1.20.0/24"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 636
      max = 636
    }
  }

  # allow inbound WINS resolution
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "10.1.20.0/24"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 1512
      max = 1512
    }
  }

  # allow inbound Global catalog LDAP
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "10.1.20.0/24"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 3268
      max = 3268
    }
  }

  # allow inbound Global catalog LDAP over SSL
  ingress_security_rules {
    protocol  = "6" # tcp
    source    = "10.1.20.0/24"
    stateless = false

    tcp_options {
      # These values correspond to the destination port range.
      min = 3269
      max = 3269
    }
  }

  # allow inbound RPC
  ingress_security_rules {
    protocol  = "17" # udp
    source    = "10.1.20.0/24"
    stateless = false

    udp_options {
      # These values correspond to the destination port range.
      min = 49152
      max = 65535
    }
  }

  # allow all outbound traffic
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }
}

resource "oci_core_subnet" "test_subnet" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  cidr_block          = "10.1.20.0/24"
  display_name        = "TestSubnet"
  dns_label           = "testsubnet"
  security_list_ids   = [oci_core_security_list.ad_security_list.id]
  compartment_id      = var.compartment_ocid
  vcn_id              = oci_core_vcn.test_vcn.id
  route_table_id      = oci_core_route_table.test_route_table.id
  dhcp_options_id     = oci_core_vcn.test_vcn.default_dhcp_options_id
}

# Compute

resource "oci_core_instance" "ad_server" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = var.instance_name
  shape               = "VM.Standard.E3.Flex"

    shape_config {
    ocpus = 2
    memory_in_gbs = 16
  }

  # Refer cloud-init in https://docs.cloud.oracle.com/iaas/api/#/en/iaas/20160918/datatypes/LaunchInstanceDetails
  metadata = {
    # Base64 encoded YAML based user_data to be passed to cloud-init
    user_data = data.template_cloudinit_config.cloudinit_config.rendered
  }

  create_vnic_details {
    subnet_id      = oci_core_subnet.test_subnet.id
    hostname_label = "ad-server"
  }

  source_details {
    boot_volume_size_in_gbs = var.size_in_gbs
    source_id               = var.instance_image_ocid[var.region]
    source_type             = "image"
  } 
}

data "oci_core_instance_credentials" "instance_credentials" {
  instance_id = oci_core_instance.ad_server.id
}

/* 
resource "oci_core_volume" "test_volume" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = "TestVolume"
  size_in_gbs         = var.size_in_gbs
}

resource "oci_core_volume_attachment" "test_volume_attachment" {
  attachment_type = "iscsi"
  instance_id     = oci_core_instance.ad_server.id
  volume_id       = oci_core_volume.test_volume.id
}
 */

# Outputs

output "username" {
  value = [data.oci_core_instance_credentials.instance_credentials.username]
}

output "password" {
  value = [random_string.instance_password.result]
}

output "instance_public_ip" {
  value = [oci_core_instance.ad_server.public_ip]
}

output "instance_private_ip" {
  value = [oci_core_instance.ad_server.private_ip]
}