require 'spec_helper_acceptance'

describe 'basic neutron' do

  context 'default parameters' do

    it 'should work with no errors' do
      pp= <<-EOS
      Exec { logoutput => 'on_failure' }

      # Common resources
      case $::osfamily {
        'Debian': {
          include ::apt
          class { '::openstack_extras::repo::debian::ubuntu':
            release         => 'liberty',
            repo            => 'proposed',
            package_require => true,
          }
          $package_provider = 'apt'
        }
        'RedHat': {
          class { '::openstack_extras::repo::redhat::redhat':
            manage_rdo => false,
            repo_hash => {
              'openstack-common-testing' => {
                'baseurl'  => 'http://cbs.centos.org/repos/cloud7-openstack-common-testing/x86_64/os/',
                'descr'    => 'openstack-common-testing',
                'gpgcheck' => 'no',
              },
              'openstack-liberty-testing' => {
                'baseurl'  => 'http://cbs.centos.org/repos/cloud7-openstack-liberty-testing/x86_64/os/',
                'descr'    => 'openstack-liberty-testing',
                'gpgcheck' => 'no',
              },
              'openstack-liberty-trunk' => {
                'baseurl'  => 'http://trunk.rdoproject.org/centos7-liberty/current-passed-ci/',
                'descr'    => 'openstack-liberty-trunk',
                'gpgcheck' => 'no',
              },
            },
          }
          package { 'openstack-selinux': ensure => 'latest' }
          $package_provider = 'yum'
        }
        default: {
          fail("Unsupported osfamily (${::osfamily})")
        }
      }

      class { '::mysql::server': }

      class { '::rabbitmq':
        delete_guest_user => true,
        package_provider  => $package_provider,
      }

      rabbitmq_vhost { '/':
        provider => 'rabbitmqctl',
        require  => Class['rabbitmq'],
      }

      rabbitmq_user { 'neutron':
        admin    => true,
        password => 'an_even_bigger_secret',
        provider => 'rabbitmqctl',
        require  => Class['rabbitmq'],
      }

      rabbitmq_user_permissions { 'neutron@/':
        configure_permission => '.*',
        write_permission     => '.*',
        read_permission      => '.*',
        provider             => 'rabbitmqctl',
        require              => Class['rabbitmq'],
      }

      # Keystone resources, needed by Neutron to run
      class { '::keystone::db::mysql':
        password => 'keystone',
      }
      class { '::keystone':
        verbose             => true,
        debug               => true,
        database_connection => 'mysql://keystone:keystone@127.0.0.1/keystone',
        admin_token         => 'admin_token',
        enabled             => true,
      }
      class { '::keystone::roles::admin':
        email    => 'test@example.tld',
        password => 'a_big_secret',
      }
      class { '::keystone::endpoint':
        public_url => "https://${::fqdn}:5000/",
        admin_url  => "https://${::fqdn}:35357/",
      }

      # Neutron resources
      class { '::neutron':
        rabbit_user           => 'neutron',
        rabbit_password       => 'an_even_bigger_secret',
        rabbit_host           => '127.0.0.1',
        allow_overlapping_ips => true,
        core_plugin           => 'ml2',
        debug                 => true,
        verbose               => true,
        service_plugins => [
          'neutron.services.l3_router.l3_router_plugin.L3RouterPlugin',
          'neutron_lbaas.services.loadbalancer.plugin.LoadBalancerPlugin',
          'neutron.services.metering.metering_plugin.MeteringPlugin',
        ],
      }
      class { '::neutron::db::mysql':
        password => 'a_big_secret',
      }
      class { '::neutron::keystone::auth':
        password => 'a_big_secret',
      }
      class { '::neutron::server':
        database_connection => 'mysql://neutron:a_big_secret@127.0.0.1/neutron?charset=utf8',
        auth_password       => 'a_big_secret',
        identity_uri        => 'http://127.0.0.1:35357/',
        sync_db             => true,
      }
      class { '::neutron::client': }
      class { '::neutron::quota': }
      class { '::neutron::agents::dhcp': debug => true }
      class { '::neutron::agents::l3': debug => true }
      class { '::neutron::agents::lbaas':
        debug => true,
      }
      class { '::neutron::agents::metering': debug => true }
      class { '::neutron::agents::ml2::ovs':
        enable_tunneling => true,
        local_ip         => '127.0.0.1',
        tunnel_types => ['vxlan'],
      }
      class { '::neutron::plugins::ml2':
        type_drivers         => ['vxlan'],
        tenant_network_types => ['vxlan'],
        mechanism_drivers    => ['openvswitch']
      }
      EOS


      # Run it twice and test for idempotency
      apply_manifest(pp, :catch_failures => true)
      apply_manifest(pp, :catch_changes => true)
    end

    describe 'test Neutron OVS agent bridges' do
      it 'should list OVS bridges' do
        shell("ovs-vsctl show") do |r|
          expect(r.stdout).to match(/br-int/)
          expect(r.stdout).to match(/br-tun/)
        end
      end
    end

  end
end
