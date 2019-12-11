# Copyright 2018 Google Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'net/http'
require 'json'
require 'active_support/inflector'
require 'api/product'
require 'api/resource'
require 'api/type'
require 'api/compiler'
require 'api/async'

TYPES = {
  'string': 'String',
  'boolean': 'Boolean',
  'object': 'KeyValuePairs',
  'integer': 'Integer',
  'number': 'Double',
  'array': 'Array'
}

class DiscoveryProperty
  attr_reader :schema
  attr_reader :name

  attr_reader :__product

  def initialize(name, schema, product)
    @name = name
    @schema = schema

    @__product = product
  end

  def get_property
    prop = Module.const_get("Api::Type::#{type}").new
    prop.name = @name
    prop.description = @schema.dig('description')
    if deprecated?
      puts "WARN rejecting #{prop.name}"
      return nil
    end
    prop.output = output?
    prop.values = enum if @schema.dig('enum')
    prop.properties = nested if prop.is_a?(Api::Type::NestedObject)
    prop.item_type = array if prop.is_a?(Api::Type::Array)
    prop
  end

  private

  def type
    return "NestedObject" if @schema.dig('$ref')
    return "NestedObject" if @schema.dig('type') == 'object' && @schema.dig('properties')
    return "Enum" if @schema.dig('enum')
    TYPES[@schema.dig('type').to_sym]
  end

  def output?
    description = (@schema.dig('description') || '').downcase
    description.include?('output only') || description.include?('read-only')
  end

  def deprecated?
    description = (@schema.dig('description') || '').downcase
    if description.include?('not currently supported by cloud run') ||
      description.include?('not supported by cloud run') ||
      description.include?('not currently populated by cloud run')
      return true
    end
    if description.downcase.include?('supported') || description.downcase.include?('deprecated')
      # puts "\n**#{@name}**\n#{description}\n"
      return true
    end
    false
  end

  def enum
    @schema.dig('enum').map { |val| val.to_sym }
  end

  def nested
    if @schema.dig('$ref')
      @__product.get_resource(@schema.dig('$ref')).properties
    else
      DiscoveryResource.new(@schema, @__product).properties
    end
  end

  def array
    schema_type = @schema.dig('items', 'type')
    if (!schema_type && @schema.dig('items', '$ref')) || @schema.dig('items', 'properties')
      prop = Api::Type::NestedObject.new
      if @schema.dig('items', '$ref')
        prop.properties = @__product.get_resource(@schema.dig('items', '$ref')).properties
      else
        prop.properties = DiscoveryResource.new(@schema.dig('items'), @__product).properties
      end
      return prop
    end
    return "Api::Type::#{TYPES[schema_type.to_sym]}" if schema_type != 'object'
  end
end

# Holds information about discovery objects
# Two sections: schema (properties) and methods
class DiscoveryResource
  attr_reader :schema

  attr_reader :__product

  def initialize(schema, product)
    @schema = schema
    @__product = product

  end

  def exists?
    !@schema.nil?
  end

  def resource
    @methods = @__product.get_methods_for_resource(@schema.dig('id'), @__product.doc.resource_path)

    res = Api::Resource.new
    res.name = @schema.dig('id')
    res.kind = @schema.dig('properties', 'kind', 'default')
    res.base_url = base_url_format(@methods['list']['path'])
    res.description = @schema.dig('description')
    res.properties = properties
    res
  end

  def properties
    @schema.dig('properties')
           .reject { |k, _| k == 'kind' }
           .map { |k, v| DiscoveryProperty.new(k, v, @__product).get_property }
  end

  private

  def base_url_format(url)
    "projects/#{url.gsub('{', '{{').gsub('}', '}}')}"
  end
end

# Responsible for grabbing Discovery Docs and getting resources from it
class DiscoveryProduct
  attr_reader :results
  attr_reader :doc

  def initialize(doc)
    @doc = doc
    @results = send_request(@doc.url)
    if doc.name == 'Google Game Services'
      @results = @results['derivedData']['discovery'][0]['content']
    end
  end

  def get_resources
    @results['schemas'].map do |name, _|
      # require 'pry'; binding.pry
      next unless @doc.objects.include?(name)
      get_resource(name).resource
    end.compact
  end

  def get_resource(resource)
    DiscoveryResource.new(@results['schemas'][resource], self)
  end

  def get_methods_for_resource(resource, resource_path = nil)
    resource_path = 'resources' if resource_path.nil?
    # Discovery docs aren't created equal and some define resources at different nesting levels.
    @resources = @results
    resource_path.split('.').each{|k| @resources = @resources[k]}

    resource_name = resource.pluralize[0].downcase

    raise "Cannot find #{resource} at api path: root.#{resource_path}" unless @resources[resource.pluralize.camelize]
    return unless @resources[resource.pluralize.camelize]

    @resources[resource.pluralize.camelize]['methods']
  end

  def get_product
    product = Api::Product.new
    product.name = @doc.name
    product.prefix = @doc.prefix
    product.scopes = @doc.scopes
    product.versions = [version]
    product.objects = get_resources
    product
  end

  private

  def send_request(url)
    JSON.parse(Net::HTTP.get(URI(url)))
  end

  def version
    version = Api::Product::Version.new
    version.name = 'ga'
    version.base_url = base_url_format(@results['baseUrl'])
    version.default = true
    version
  end

  def base_url_format(url)
    return if url.nil?
    url.gsub('projects/', '').gsub('{', '{{').gsub('}', '}}')
  end
end

