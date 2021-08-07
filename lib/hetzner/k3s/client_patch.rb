module K8s
  class ResourceClient
    def initialize(transport, api_client, api_resource, namespace: nil, resource_class: K8s::Resource)
      @transport = transport
      @api_client = api_client
      @api_resource = api_resource
      @namespace = namespace
      @resource_class = resource_class

      if @api_resource.name.include? '/'
        @resource, @subresource = @api_resource.name.split('/', 2)
      else
        @resource = @api_resource.name
        @subresource = nil
      end

      # fail "Resource #{api_resource.name} is not namespaced" unless api_resource.namespaced || !namespace
    end

    def path(name = nil, subresource: @subresource, namespace: @namespace)
      namespace_part = namespace ? ['namespaces', namespace] : []

      if namespaced?
        if name && subresource
          @api_client.path(*namespace_part, @resource, name, subresource)
        elsif name
          @api_client.path(*namespace_part, @resource, name)
        else namespaced?
          @api_client.path(*namespace_part, @resource)
        end
      elsif name
        @api_client.path(@resource, name)
      else
        @api_client.path(@resource)
      end
    end
  end
end
