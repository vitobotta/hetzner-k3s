require "./routing_spec_helper"
require "../src/configuration/validators/node_pool_config/pool_name"
require "../src/configuration/validators/cluster_name"

private def pool_name_errors(name : String?, pool_type : Symbol = :workers)
  errors = [] of String
  Configuration::Validators::NodePoolConfig::PoolName.new(errors, pool_type, name).validate
  errors
end

private def workers_errors_for(pool : Configuration::Models::WorkerNodePool)
  errors = [] of String
  Configuration::Validators::WorkerNodePools.new(
    errors: errors,
    worker_node_pools: [pool],
    schedule_workloads_on_masters: false,
    masters_pool: Configuration::Models::MasterNodePool.from_yaml({"instance_type" => "cpx22"}.to_yaml),
    instance_types: [Hetzner::InstanceType.from_json({"id" => 1, "name" => "cpx22"}.to_json)],
    all_locations: [Hetzner::Location.from_json({"id" => 1, "name" => "fsn1", "network_zone" => "eu-central"}.to_json)],
    datastore: Configuration::Models::Datastore.from_yaml({"mode" => "etcd"}.to_yaml),
    private_network_enabled: true,
    settings: Configuration::Main.from_yaml(RoutingSpec.config)
  ).validate
  errors
end

private def worker_pool(name : String?)
  yaml = {"instance_type" => "cpx22"}.to_yaml
  yaml = yaml.sub("instance_type: cpx22", "instance_type: cpx22\nname: #{name}") unless name.nil?
  Configuration::Models::WorkerNodePool.from_yaml(yaml)
end

describe Configuration::Validators::NodePoolConfig::PoolName do
  # Leading digits worked before pool names were validated (`<cluster>-pool-8gb-worker1` is a valid
  # server name), so they have to keep working.
  ["web", "workers", "worker-pool-1", "pool2", "a", "a1", "node-pool-01", "8gb", "2xl-fsn", "1"].each do |name|
    it "accepts the valid name #{name.inspect}" do
      pool_name_errors(name).should be_empty
    end
  end

  ["-web", "web-", "web--"].each do |name|
    it "rejects #{name.inspect}, which starts or ends with a dash" do
      pool_name_errors(name).should_not be_empty
    end
  end

  it "rejects underscores, which the Hetzner API refuses in server names" do
    pool_name_errors("web_pool").join.should contain("Worker node pool 'web_pool' has an invalid name")
  end

  it "rejects uppercase, dots and spaces" do
    ["Web-Pool", "web.pool", "web pool"].each do |name|
      pool_name_errors(name).join.should contain("invalid name")
    end
  end

  it "states the allowed characters" do
    pool_name_errors("web_pool").join.should contain("only lowercase letters, digits and dashes are allowed")
  end

  it "requires the name to start with a letter and end with a letter or a digit" do
    pool_name_errors("-web").join.should contain("must start with a lowercase letter")
    pool_name_errors("web-").join.should contain("must start with a lowercase letter")
  end

  it "requires a name" do
    pool_name_errors(nil).join.should contain("has no name")
    pool_name_errors("").join.should contain("has no name")
  end

  it "ignores the masters pool, whose name is not part of any server name" do
    pool_name_errors(nil, :masters).should be_empty
    pool_name_errors("Master_Pool", :masters).should be_empty
  end

  it "keeps the shared NameFormat predicate in sync with the validator" do
    ["web", "worker-pool-1", "a", "web_pool", "Web-Pool", "web-", "-web", "web.pool"].each do |name|
      Configuration::Validators::NameFormat.valid?(name).should eq(pool_name_errors(name).empty?)
    end
  end
end

describe Configuration::Validators::WorkerNodePools do
  it "reports an invalid worker node pool name before any server is created" do
    workers_errors_for(worker_pool("web_pool")).join.should contain("Worker node pool 'web_pool' has an invalid name")
  end

  it "accepts a valid worker node pool name" do
    workers_errors_for(worker_pool("web-pool")).should be_empty
  end
end

describe Configuration::Validators::ClusterName do
  it "keeps the shared rules and its own messages" do
    errors = [] of String
    Configuration::Validators::ClusterName.new(errors, "cluster_name").validate
    errors.join.should contain("cluster_name is an invalid format (only lowercase letters, digits and dashes are allowed)")

    errors = [] of String
    Configuration::Validators::ClusterName.new(errors, "-cluster").validate
    errors.join.should contain("Ensure that cluster_name starts and ends with a normal letter")

    errors = [] of String
    Configuration::Validators::ClusterName.new(errors, "cluster-1").validate
    errors.should be_empty
  end
end
