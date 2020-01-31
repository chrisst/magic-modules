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
################
# Discovery Doc Builder
#
# This script takes in a yaml file with a Docs object that
# describes which Discovery APIs are being taken in.
#
# The script will then build api.yaml files using
# the Discovery API

# Load everything from MM root.
$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '../../')
Dir.chdir(File.join(File.dirname(__FILE__), '../../'))

require 'tools/generator/builder/discovery'
# require 'tools/generator/builder/docs'
# require 'tools/generator/builder/override'

require 'optparse'

module Api
  class Object
    # Create a setter if the setter doesn't exist
    # Yes, this isn't pretty and I apologize
    def method_missing(method_name, *args)
      matches = /([a-z_]*)=/.match(method_name)
      super unless matches
      create_setter(matches[1])
      method(method_name.to_sym).call(*args)
    end

    def create_setter(variable)
      self.class.define_method("#{variable}=") { |val| instance_variable_set("@#{variable}", val) }
    end

    def validate
    end
  end
end

# doc_file = 'tools/linter/docs.yaml'
targets = []
doc_url = 'http://localhost:8080/gameservices_service.json'
doc_url = nil
resource_path = ''

OptionParser.new do |opts|
  opts.banner = 'Discovery doc runner. Usage: run.rb [docs.yaml]'
  opts.on('-u', '--url URL', 'Required. Url of the discovery doc.') { |url| doc_url = url }
  opts.on('-t', '--targets [target1,target2]',
          'Required. Comma separated list of targets. eg: Disk,RegionDisk') do |arg|
    targets = arg.split(',')
  end
  opts.on('-p', '--path [path.to.results]',
          'JSON path to traverse to the results. eg: resources.projects.resources') do |path|
    resource_path = path
  end
end.parse!

raise 'Targets required. Use --help to see usage.' if targets.empty?
raise 'URL required. Use --help to see usage.' if doc_url.nil?

dp = DiscoveryProduct.new(doc_url)
# dp.filter_results('derivedData.discovery.0.content')
dp.build_resources
api = dp.build_api_product(targets, resource_path)
# TODO - loop through targets and call build Resource
# require 'pry'; binding.pry
puts api.to_yaml

