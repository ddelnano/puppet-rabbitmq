Puppet::Type.type(:rabbitmq_policy).provide(:rabbitmqctl) do
  if Puppet::PUPPETVERSION.to_f < 3
    commands :rabbitmqctl => 'rabbitmqctl'
  else
     has_command(:rabbitmqctl, 'rabbitmqctl') do
       environment :HOME => "/tmp"
     end
  end

  mk_resource_methods
  defaultfor :feature => :posix

  def self.instances
    rabbitmqctl('-q', 'list_vhosts').split(/\n/).collect do |vhost|
      rabbitmqctl('-q', 'list_policies', '-p', vhost).split(/\n/).collect do |line|
        # /   federate mcollective exchanges  exchanges   ^(mcollective_|amq\\.)  {"federation-upstream-set":"all"}   0
        if line =~ /^(\S+)\s+(.+)\s+(\S+)\s+(\S+)\s(\S+)\s+(\S+)$/
          new(:name => $2, :ensure => :present, :vhost => $1, :apply_to => $3, :pattern => $4, :definition => JSON.parse($5), :priority => $6)
        else
          raise Puppet::Error, "Cannot parse invalid policy line: #{line}"
        end
      end
    end.flatten
  end
  def self.prefetch(resources)
    instances.each do |provider|
      if resource = resources[provider.name] then
        resource.provider = provider
      end
    end
  end

  def create
    rabbitmqctl('set_policy', '-p', resource[:vhost], '--apply-to', resource[:apply_to], resource[:name], resource[:pattern], resource[:definition].to_json, '--priority', resource[:priority])
  end

  def destroy
    rabbitmqctl('clear_policy', '-p', @property_hash[:vhost], resource[:name])
    @property_hash = {}  # used in conjunction with flush to avoid calling non-indempotent destroy twice
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def flush
    # flush is used purely in an update capacity
    # @property_hash is tested to avoid calling non-indempotent destroy twice
    if @property_hash == {}
      Puppet.debug 'hash empty - instance does not exist on system'
    elsif self.exists?
      self.create
    else
      self.destroy
    end
  end
end
