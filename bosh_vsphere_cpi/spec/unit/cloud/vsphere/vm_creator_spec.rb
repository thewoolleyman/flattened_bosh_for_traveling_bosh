require 'cloud/vsphere/vm_creator'

describe VSphereCloud::VmCreator do
  describe '#create' do
    subject(:creator) do
      described_class.new(1024, 1024, 3, placer, vsphere_client, cloud_searcher, logger, cpi, agent_env, file_provider)
    end

    let(:placer) { instance_double('VSphereCloud::FixedClusterPlacer', drs_rules: []) }
    let(:vsphere_client) { instance_double('VSphereCloud::Client') }
    let(:logger) { double('logger', debug: nil) }
    let(:cpi) { instance_double('VSphereCloud::Cloud') }
    let(:agent_env) { instance_double('VSphereCloud::AgentEnv') }
    let(:file_provider) { instance_double('VSphereCloud::FileProvider') }
    let(:cloud_searcher) { instance_double('VSphereCloud::CloudSearcher') }

    let(:networks) do
      {
        'network_name' => {
          'cloud_properties' => {
            'name' => 'network_name',
          },
        },
      }
    end

    let(:disk_locality) { ['disk1_cid'] }
    let(:disk_spec) { double('disk spec') }
    let(:folder_mob) { double('folder managed object') }
    let(:datacenter_mob) { double('datacenter mob') }
    let(:resource_pool_mob) { double('resource pool managed object') }
    let(:cluster_mob) { double(:cluster_mob) }

    let(:cluster) do
      datacenter = double('datacenter', :name => 'datacenter name', :vm_folder => double('vm_folder', :mob => folder_mob), mob: datacenter_mob)

      double('cluster', :datacenter => datacenter, :resource_pool => double('resource pool', :mob => resource_pool_mob), mob: cluster_mob)
    end

    let(:datastore) { double('datastore') }

    let(:vm_double) { double('cloned vm') }

    let(:ephemeral_disk) { instance_double('VSphereCloud::EphemeralDisk') }

    before do
      stemcell_vm = double('stemcell vm')
      allow(cpi).to receive(:stemcell_vm).with('stemcell_cid').and_return(stemcell_vm)

      current_snapshot = double('current snapshot')
      snapshot = double('snapshot', :current_snapshot => current_snapshot)

      vdisk_controller_key = double('virtual disk controller key')
      system_disk = VimSdk::Vim::Vm::Device::VirtualDisk.new(controller_key: vdisk_controller_key)
      virtual_nic = VimSdk::Vim::Vm::Device::VirtualEthernetCard.new
      pci_controller_key = double('virtual pci controller key')
      pci_controller = VimSdk::Vim::Vm::Device::VirtualPCIController.new(key: pci_controller_key)
      devices = [ system_disk, virtual_nic, pci_controller ]
      stemcell_properties = {
        'config.hardware.device' => devices,
        'snapshot' => snapshot,
      }

      delete_nic_spec = double('nic config')
      allow(cpi).to receive(:create_delete_device_spec).with(virtual_nic).and_return(delete_nic_spec)

      network_env = double('network env rv')
      allow(cpi).to receive(:generate_network_env).with(devices, networks, {}).and_return(network_env)
      allow(cpi).to receive(:disk_spec).with(disk_locality).and_return(disk_spec)
      allow(file_provider).to receive(:upload_file).with('datacenter name', 'datastore name', 'vm-vm_unique_name/env.iso', '')

      allow(cloud_searcher).to receive(:get_property).with(stemcell_vm, anything, anything, anything).and_return(1024*1024)

      allow(placer).to receive(:place).and_return([cluster, datastore])

      replicated_stemcell_vm = double('replicated vm')
      allow(cloud_searcher).to receive(:get_properties).with(replicated_stemcell_vm, VimSdk::Vim::VirtualMachine, ['config.hardware.device', 'snapshot'], ensure_all: true).and_return(stemcell_properties)

      allow(datastore).to receive(:name).with(no_args).and_return("datastore name")

      allow(cpi).to receive(:generate_unique_name).with(no_args).and_return("vm_unique_name")
      allow(cpi).to receive(:replicate_stemcell).with(cluster, datastore, "stemcell_cid").and_return(replicated_stemcell_vm)

      network_mob = double('standard network managed object')
      allow(vsphere_client).to receive(:find_by_inventory_path).
        with(['datacenter name', 'network', 'network_name']).
        and_return(network_mob)
      add_nic_spec = double('add virtual nic spec')
      allow(cpi).to receive(:create_nic_config_spec).with(
        'network_name',
        network_mob,
        pci_controller_key,
        {},
      ).and_return(add_nic_spec)

      disk_device = double('disk device')
      ephemeral_disk_config = double('ephemeral disk config', :device => disk_device)
      allow(cpi).to receive(:fix_device_unit_numbers).with(devices, [ephemeral_disk_config, add_nic_spec, delete_nic_spec])
      disk_env = double('disk env')
      allow(cpi).to receive(:generate_disk_env).with(system_disk, disk_device).and_return(disk_env)
      datastore_mob = double('datastore mob')
      allow(datastore).to receive(:mob).with(no_args).and_return(datastore_mob)
      allow(VSphereCloud::EphemeralDisk).to receive(:new).with(
        1024,
        'vm-vm_unique_name',
        datastore,
      ).and_return(ephemeral_disk)
      allow(ephemeral_disk).to receive(:create_spec).with(vdisk_controller_key).and_return(ephemeral_disk_config)
      allow(logger).to receive(:info)

      clone_vm_task = double('cloned vm task')
      allow(cpi).to receive(:clone_vm).with(
        replicated_stemcell_vm,
        'vm-vm_unique_name',
        folder_mob,
        resource_pool_mob,
        {
          datastore: datastore_mob,
          linked: true,
          snapshot: current_snapshot,
          config: match_attributes(
            memory_mb: 1024,
            num_cpus: 3,
            device_change: [ephemeral_disk_config, add_nic_spec, delete_nic_spec],
          ),
        },
      ).and_return(clone_vm_task)
      allow(vsphere_client).to receive(:wait_for_task).with(clone_vm_task).and_return(vm_double)
      allow(cloud_searcher).to receive(:get_properties).with(vm_double, VimSdk::Vim::VirtualMachine, ['config.hardware.device'], ensure_all: true).and_return(stemcell_properties)
      allow(cpi).to receive(:generate_agent_env).with("vm-vm_unique_name", vm_double, 'agent_id', network_env, disk_env).and_return({})

      vm_location = double('vm location')
      allow(cpi).to receive(:get_vm_location).with(
        vm_double,
        datacenter: 'datacenter name',
        datastore: 'datastore name',
        vm: 'vm-vm_unique_name',
      ).and_return(vm_location)
      allow(agent_env).to receive(:set_env).with(vm_double, vm_location, {'env' => {}})

      allow(vsphere_client).to receive(:power_on_vm).with(datacenter_mob, vm_double)
    end

    context 'when the stemcell vm does not exist' do
      before do
        allow(cpi).to receive(:stemcell_vm).with('sc-beef').and_return(nil)
      end

      it 'raises an error' do
        expect {
          creator.create(nil, 'sc-beef', nil, [], {})
        }.to raise_error('Could not find stemcell: sc-beef')
      end
    end

    it 'chooses the placement based on memory, ephemeral and persistent disks' do
      expect(placer).to receive(:place).with(1024, 2049, disk_spec).
                          and_return([cluster, datastore])
      creator.create('agent_id', 'stemcell_cid', networks, disk_locality, {})
    end

    describe 'DRS rules' do
      context 'when several DRS rules are specified in cloud properties' do
        before do
          allow(placer).to receive(:drs_rules).and_return(
            [
              { 'name' => 'fake-drs-rule-1', 'type' => 'separate_vms' },
              { 'name' => 'fake-drs-rule-2', 'type' => 'separate_vms' },
            ]
          )
        end

        it 'raises an error' do
          expect(cpi).to receive(:delete_vm)
          expect {
            creator.create('agent_id', 'stemcell_cid', networks, disk_locality, {})
          }.to raise_error /vSphere CPI supports only one DRS rule per resource pool/
        end
      end

      context 'when one DRS rule is specified' do
        before do
          allow(placer).to receive(:drs_rules).and_return(
            [
              { 'name' => 'fake-drs-rule-1', 'type' => drs_rule_type },
            ]
          )
        end
        let(:drs_rule_type) { 'separate_vms' }

        context 'when DRS rule type is separate_vms' do
          it 'adds VM to specified drs rules' do
            drs_rule_1 = instance_double('VSphereCloud::DrsRule')
            expect(VSphereCloud::DrsRule).to receive(:new).
              with('fake-drs-rule-1', vsphere_client, cloud_searcher, cluster_mob, logger).
              and_return(drs_rule_1)
            expect(drs_rule_1).to receive(:add_vm).with(vm_double)

            creator.create('agent_id', 'stemcell_cid', networks, disk_locality, {})
          end
        end

        context 'when DRS rule type is not separate_vms' do
          let(:drs_rule_type) { 'bad_type' }

          it 'raises an error' do
            expect(cpi).to receive(:delete_vm)
            expect {
              creator.create('agent_id', 'stemcell_cid', networks, disk_locality, {})
            }.to raise_error /vSphere CPI only supports DRS rule of 'separate_vms' type/
          end
        end
      end
    end
  end

  RSpec::Matchers.define :match_attributes do |expected|
    match do |actual|
      expected.all? do |attr_name, attr_value|
        attr_value == actual.public_send(attr_name)
      end
    end
    # rspec-mocks usually expects == and chokes on rspec-expectation's 'matches'
    alias_method(:==, :matches?)
  end
end
