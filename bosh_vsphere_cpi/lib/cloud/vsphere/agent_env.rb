module VSphereCloud
  class AgentEnv
    include VimSdk
    include RetryBlock

    def initialize(client, file_provider, cloud_searcher)
      @client = client
      @file_provider = file_provider
      @cloud_searcher = cloud_searcher
    end

    def get_current_env(vm, datacenter_name)
      cdrom = @client.get_cdrom_device(vm)
      env_iso_folder = env_iso_folder(cdrom)
      return unless env_iso_folder

      datastore_name = cdrom.backing.datastore.name
      datastore_pattern = Regexp.escape(datastore_name)
      result = env_iso_folder.match(/\[#{datastore_pattern}\] (.*)/)
      raise Bosh::Clouds::CloudError.new('Could not find matching datastore name') unless result
      env_path = result[1]

      contents = @file_provider.fetch_file(datacenter_name, datastore_name, "#{env_path}/env.json")
      raise Bosh::Clouds::CloudError.new('Unable to load env.json') unless contents

      JSON.load(contents)
    end

    def set_env(vm, location, env)
      env_json = JSON.dump(env)

      disconnect_cdrom(vm)
      clean_env(vm)
      @file_provider.upload_file(location[:datacenter], location[:datastore], "#{location[:vm]}/env.json", env_json)
      @file_provider.upload_file(location[:datacenter], location[:datastore], "#{location[:vm]}/env.iso", generate_env_iso(env_json))

      datastore = @cloud_searcher.get_managed_object(Vim::Datastore, name: location[:datastore])
      file_name = "[#{location[:datastore]}] #{location[:vm]}/env.iso"

      update_cdrom_env(vm, datastore, file_name)
    end

    def env_iso_folder(cdrom_device)
      return unless cdrom_device && cdrom_device.backing.respond_to?(:file_name)
      File.dirname(cdrom_device.backing.file_name)
    end

    def clean_env(vm)
      cdrom = @client.get_cdrom_device(vm)
      env_iso_folder = env_iso_folder(cdrom)
      return unless env_iso_folder

      datacenter = @client.find_parent(vm, Vim::Datacenter)

      @client.delete_path(datacenter, File.join(env_iso_folder, 'env.json'))
      @client.delete_path(datacenter, File.join(env_iso_folder, 'env.iso'))
    end

    private

    def update_cdrom_env(vm, datastore, file_name)
      backing_info = Vim::Vm::Device::VirtualCdrom::IsoBackingInfo.new
      backing_info.datastore = datastore
      backing_info.file_name = file_name

      connect_info = Vim::Vm::Device::VirtualDevice::ConnectInfo.new
      connect_info.allow_guest_control = false
      connect_info.start_connected = true
      connect_info.connected = true

      cdrom = @client.get_cdrom_device(vm)
      cdrom.connectable = connect_info
      cdrom.backing = backing_info

      config = Vim::Vm::ConfigSpec.new
      config.device_change = [create_edit_device_spec(cdrom)]
      @client.reconfig_vm(vm, config)
    end

    def disconnect_cdrom(vm)
      cdrom = @client.get_cdrom_device(vm)
      if cdrom.connectable.connected
        cdrom.connectable.connected = false
        config = Vim::Vm::ConfigSpec.new
        config.device_change = [create_edit_device_spec(cdrom)]
        @client.reconfig_vm(vm, config)
      end
    end

    def generate_env_iso(env)
      Dir.mktmpdir do |path|
        env_path = File.join(path, 'env')
        iso_path = File.join(path, 'env.iso')
        File.open(env_path, 'w') { |f| f.write(env) }
        output = `#{genisoimage} -o #{iso_path} #{env_path} 2>&1`
        raise "#{$?.exitstatus} -#{output}" if $?.exitstatus != 0
        File.open(iso_path, 'r') { |f| f.read }
      end
    end

    def which(programs)
      ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
        programs.each do |bin|
          exe = File.join(path, bin)
          return exe if File.exists?(exe)
        end
      end
      programs.first
    end

    def genisoimage
      @genisoimage ||= which(%w{genisoimage mkisofs})
    end

    def create_edit_device_spec(device)
      device_config_spec = Vim::Vm::Device::VirtualDeviceSpec.new
      device_config_spec.device = device
      device_config_spec.operation = Vim::Vm::Device::VirtualDeviceSpec::Operation::EDIT
      device_config_spec
    end
  end
end
