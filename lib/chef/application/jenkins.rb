#
# Author:: Marius Ducea (<marius.ducea@gmail.com>)
# Author:: Adam Jacob (<adam@opscode.com)
# Copyright:: Copyright (c) 2011 Opscode, Inc.
# License:: Apache License, Version 2.0
#
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

require 'chef/application'
require 'chef/jenkins'
require 'mixlib/log'

class Chef::Application::Jenkins < Chef::Application

  banner "Usage: jenkins (sync|prop|save|load) (options)"

  NO_COMMAND_GIVEN = "You need to pass sync|prop|save|load as the first argument\n"

  option :config_file,
    :short => "-c CONFIG",
    :long  => "--config CONFIG",
    :description => "The configuration file to use",
    :proc => lambda { |path| File.expand_path(path, Dir.pwd) }

  option :env,
    :short        => "-e ENVIRONMENT",
    :long         => "--env ENVIRONMENT",
    :description  => "The environment to save/load"

  option :backup,
    :short        => "-b BACKUP",
    :long         => "--backup BACKUP",
    :description  => "The backup to save/load"

  option :env_to,
    :short        => "-t ENVIRONMENT",
    :long         => "--env-to ENVIRONMENT",
    :description  => "Set the Chef environment to sync/prop to"

  option :env_from,
    :short        => "-f ENVIRONMENT",
    :long         => "--env-from ENVIRONMENT",
    :description  => "Set the Chef environment to prop from"

  option :help,
    :short        => "-h",
    :long         => "--help",
    :description  => "Show this message",
    :on           => :tail,
    :boolean      => true

  option :node_name,
    :short => "-u USER",
    :long => "--user USER",
    :description => "API Client Username"

  option :test,
    :short => "-T TESTS",
    :long => "--test TESTS",
    :description => "Add test(s) before uploading to chef server; -T ruby,foodcritic"

  option :cookbook_freeze,
    :short => "-F",
    :long => "--freeze",
    :description => "Freeze cookbook(s) while uploading"

  option :client_key,
    :short => "-k KEY",
    :long => "--key KEY",
    :description => "API Client Key",
    :proc => lambda { |path| File.expand_path(path, Dir.pwd) }

  option :chef_server_url,
    :short => "-s URL",
    :long => "--server-url URL",
    :description => "Chef Server URL"

  option :version,
    :short        => "-v",
    :long         => "--version",
    :description  => "Show chef version",
    :boolean      => true,
    :proc         => lambda {|v| puts "chef-jenkins: #{::Chef::Jenkins::VERSION}"},
    :exit         => 0

  # Run knife
  def run_application
    Mixlib::Log::Formatter.show_time = false
    jenkins = Chef::Jenkins.new
    if ARGV[0] == "sync"
      jenkins.sync
    elsif ARGV[0] == "prop"
      jenkins.prop(config[:env_from], config[:env_to])
    elsif ARGV[0] == "save"
      jenkins.save(config[:env], config[:backup])
    elsif ARGV[0] == "load"
      jenkins.load(config[:env], config[:backup])
    else
      Chef::Application.fatal!("You must provide sync or prop as the first argument")
    end
    exit 0
  end

  def configure_chef
    begin
      self.parse_options
    rescue OptionParser::InvalidOption => e
        puts "#{e}\n"
        puts self.opt_parser
        exit 0
    rescue OptionParser::MissingArgument => e
        puts "#{e}\n"
        puts self.opt_parser
        exit 0
    end

    if config[:help]
      puts self.opt_parser
      exit 0
    end

    begin
      case config[:config_file]
      when /^(http|https):\/\//
        Chef::REST.new("", nil, nil).fetch(config[:config_file]) { |f| apply_config(f.path) }
      else
	load_config_file
      end
    rescue Errno::ENOENT => error
      Chef::Log.warn("*****************************************")
      Chef::Log.warn("Did not find config file: #{config[:config_file]}, using command line options.")
      Chef::Log.warn("*****************************************")

      Chef::Config.merge!(config)
    rescue SocketError => error
      Chef::Application.fatal!("Error getting config file #{Chef::Config[:config_file]}", 2)
    rescue Chef::Exceptions::ConfigurationError => error
      Chef::Application.fatal!("Error processing config file #{Chef::Config[:config_file]} with error #{error.message}", 2)
    rescue Exception => error
      Chef::Application.fatal!("Unknown error processing config file #{Chef::Config[:config_file]} with error #{error.message}", 2)
    end
  end
 
  def setup_application
  end

end

