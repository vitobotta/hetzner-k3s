require "../../models/addons_config/local_path_storage_class"

class Configuration::Validators::AddonsConfig::LocalPathStorageClass
  getter errors : Array(String)
  getter local_path_storage_class : Configuration::Models::AddonsConfig::LocalPathStorageClass

  def initialize(@errors, @local_path_storage_class)
  end

  def validate
    return if local_path_storage_class.enabled?
    return if local_path_storage_class.default?

    errors << "addons.local_path_storage_class.default is false but the addon is disabled, so there is no storage class to keep non-default. Set enabled to true or drop the default key."
  end
end
