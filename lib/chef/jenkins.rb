#
# Author:: Adam Jacob (<adam@opscode.com>)
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
#

require 'rubygems'
require 'chef/jenkins/config'
require 'chef/config'
require 'chef/log'
require 'chef/knife'
require 'chef/knife/core/object_loader'
require 'chef/knife/cookbook_upload'
require 'chef/knife/role_from_file'
require 'chef/knife/data_bag_from_file'
require 'chef/knife/cookbook_test'
require 'chef/environment'
require 'chef/exceptions'
require 'chef/cookbook_loader'
require 'chef/cookbook_uploader'
require 'chef/cookbook_version'
require 'git'

class Chef
  class Jenkins
    VERSION = "0.1.0"

    attr_accessor :git

    def initialize
      @git = Git.open(Chef::Config[:jenkins][:repo_dir])
      @git.config("user.name", Chef::Config[:jenkins][:git_user])
      @git.config("user.email", Chef::Config[:jenkins][:git_email])
    end

    # Automatically bump patch level if this is not done by any user.
    # New added cookbook will not trigger auto bump.
    def bump_patch_level(metadatarb, cookbook_name)
      File.open(metadatarb, 'r+') do |f|
        lines = f.readlines
        lines.each do |line|
          if line =~ /^version\s+["'](\d+)\.(\d+)\.(\d+)["'].*$/
            major = $1
            minor = $2
            patch = $3
            current_version = "#{major}.#{minor}.#{patch}"
            available_versions = Chef::CookbookVersion.available_versions(cookbook_name)
            if available_versions.nil? 
              Chef::Log.info("User added a new cookbook: #{cookbook_name}") 
            elsif available_versions.include?(current_version)
              new_patch = patch.to_i + 1
              Chef::Log.info("Auto incrementing #{metadatarb} version from #{major}.#{minor}.#{patch} to #{major}.#{minor}.#{new_patch}") 
              line.replace("version '#{major}.#{minor}.#{new_patch}'\n")
            else
              Chef::Log.info("User already incremented #{metadatarb} version to #{current_version}") 
            end
          end
        end
        f.pos = 0
        lines.each do |line|
          f.print line
        end
        f.truncate(f.pos)
      end
    end

    # Find all cookbooks from cookbook_path that configure by user
    def find_all_cookbooks(cookbook_path=Chef::Config[:cookbook_path])
      changed_cookbooks = []
      cookbook_path.each do |path|
        Dir[File.join(File.expand_path(path), '*')].each do |cookbook_dir|
          if File.directory?(cookbook_dir)
            if cookbook_dir =~ /#{File.expand_path(path)}\/(.+)/
              changed_cookbooks << $1
            end
          end
        end
      end
      changed_cookbooks.uniq
    end

    # Find changed cookbooks between two versions 
    # Will return cookbook name, not a path
    def find_changed_cookbooks(sha1, sha2, cookbook_path=Chef::Config[:cookbook_path], repo_path=Chef::Config[:jenkins][:repo_dir])
      changed_cookbooks = []
      @git.diff(sha1, sha2).each do |diff_file|
        cookbook_path.each do |path|
          full_path_to_file = File.expand_path(File.join(repo_path, diff_file.path))
          if full_path_to_file =~ /^#{File.expand_path(path)}\/(.+?)\/.+/
            changed_cookbooks << $1
          end
        end
      end
      changed_cookbooks.uniq
    end

    # Find all roles from configured role_path
    # Will return full path
    def find_all_roles(role_path=Chef::Config[:role_path])
      changed_roles = []
      role_path.each do |path|
        Dir[File.join(File.expand_path(path), '*')].each do |role|
          if File.file?(role)
            if role =~ /(#{File.expand_path(path)}\/.+\.(json|rb))/
              changed_roles << $1
            end
          end
        end
      end
      changed_roles.uniq
    end

    # Find changed roles between two versions 
    # Will return full path
    def find_changed_roles(sha1, sha2, role_path=Chef::Config[:role_path], repo_path=Chef::Config[:jenkins][:repo_dir])
      changed_roles = []
      @git.diff(sha1, sha2).each do |diff_file|
        role_path.each do |path|
          full_path_to_file = File.expand_path(File.join(repo_path, diff_file.path))
          if full_path_to_file =~ /(^#{File.expand_path(path)}\/.+\.(json|rb))/
            changed_roles << $1
          end
        end
      end
      changed_roles.uniq
    end

    # Find all data_bag items between two versions 
    # Will return full path
    def find_all_data_bags(data_bag_path=Chef::Config[:data_bag_path])
      changed_data_bags = []
      Dir[File.join(File.expand_path(data_bag_path[0]), '*')].each do |path|
        if File.directory?(path)
          Dir[File.join(File.expand_path(path), '*')].each do |data|
            if File.file?(data)
              if data =~ /(#{File.expand_path(path)}\/.+\.(json|rb))/
                changed_data_bags << $1
              end
            end
          end
        end
      end
      changed_data_bags.uniq
    end

    # Find changed data_bag items between two versions 
    # Will return full path
    def find_changed_data_bags(sha1, sha2, data_bag_path=Chef::Config[:data_bag_path], repo_path=Chef::Config[:jenkins][:repo_dir])
      changed_data_bags = []
      @git.diff(sha1, sha2).each do |diff_file|
        data_bag_path.each do |path|
          full_path_to_file = File.expand_path(File.join(repo_path, diff_file.path))
          if full_path_to_file =~ /(^#{File.expand_path(path)}\/.+\.(json|))/
            changed_data_bags << $1
          end
        end
      end
      changed_data_bags.uniq
    end

    def current_commit
      @git.log(1)
    end

    # Write current commit (made by chef-jenkins) into a file, which will read by next build
    def write_current_commit(path=Chef::Config[:jenkins][:repo_dir])
      File.open(File.join(path, ".chef_jenkins_last_commit"), "w") do |f|
        f.print(current_commit)
      end
      @git.add(File.join(path, ".chef_jenkins_last_commit"))
      @git.commit("Updating the last auto-commit marker for Chef Jenkins")
      true
    end

    # Read the last commit made by chef-jenkins
    def read_last_commit(path=Chef::Config[:jenkins][:repo_dir])
      if File.exists?(File.join(path, ".chef_jenkins_last_commit"))
        IO.read(File.join(path, ".chef_jenkins_last_commit"))
      else
        nil
      end
    end

    # If automatically bumped patch level, commit those changes
    # Commit changed env.json file(s) 
    def commit_cookbook_changes(cookbook_list=[])
      begin
        @git.commit("#{cookbook_list.length} cookbooks patch levels updated by Chef Jenkins\n\n" + cookbook_list.join("\n"), :add_all => true)
      rescue Git::GitExecuteError => e
        Chef::Log.debug("No thing to commit")
      end
    end

    def integration_branch_name
      if ENV.has_key?('BUILD_TAG')
        ENV['BUILD_TAG']
      else
        "chef-jenkins-manual-#{Time.new.to_i}"
      end
    end

    def git_branch(branch_name)
      @git.branch(branch_name).checkout
    end

    # Make sure using the right upstream from config file
    def add_upstream(upstream_url=Chef::Config[:jenkins][:repo_url])
      begin
        @git.add_remote("upstream", upstream_url)
      rescue Git::GitExecuteError => e
        Chef::Log.debug("We already added the upstream - skipping")
      end
    end

    # Push the changes back to upstream, after chef-jenkins job made changes
    # like bump version or updated env.json
    def push_to_upstream(branch=Chef::Config[:jenkins][:branch])
      @git.push("upstream", "HEAD:#{branch}")
    end

    # Upload cookbooks to chef server
    def upload_cookbooks(cookbooks=[])
      unless cookbooks.empty?
        cu = Chef::Knife::CookbookUpload.new
        cu.name_args = cookbooks 
        cu.config[:environment] = Chef::Config[:jenkins][:env_to]
        cu.config[:freeze] = Chef::Config[:cookbook_freeze] ? true : false
        cu.run
        save_environment_file
      end
    end

    # Upload roles to chef server
    # Input roles expecting full path to the role
    def upload_roles(roles=[])
      unless roles.empty?
        cu = Chef::Knife::RoleFromFile.new
        cu.name_args = roles 
        cu.run
      end
    end

    # Upload data_bags to chef server
    # Input data_bags expecting full path to the data_bag 
    def upload_data_bags(data_bags=[])
      unless data_bags.empty?
        data_bags.each do |data_bag_full_path|
          file_name = File.basename(data_bag_full_path)
          folder_name = File.basename(File.dirname(data_bag_full_path)) 
          cu = Chef::Knife::DataBagFromFile.new
          cu.config[:all] = false
          cu.name_args = ["#{folder_name}", "#{file_name}"] 
          cu.run
        end
      end
    end

    # * After a cookbook's version has been bumped, update that version to env.json too.
    # * When propagating env, write the env_to.json with content of env_from.json. 
    def save_environment_file(env_to=Chef::Config[:jenkins][:env_to])
      Chef::Log.info("Saving environmnent #{env_to} to #{env_to}.json")
      dir = Chef::Config[:jenkins][:repo_dir]
      
      envto = Chef::Environment.load(env_to).to_hash
      File.open(File.join(dir, "environments/#{env_to}.json"), "w") do |env_file|
        envto['cookbook_versions'] = Hash[envto['cookbook_versions'].sort]
        env_file.print(JSON.pretty_generate(envto))
      end

      @git.add("#{dir}/environments/#{env_to}.json")
      @git.commit("Updating #{env_to} with the latest cookbook versions", :allow_empty => true)
    end
  
    # Use the knife cookbook_test function provided by chef gem, 
    # result will be printed to STDOUT
    # Expecting input,cookbooks, as a list of names, not paths
    def knife_cookbook_test(cookbooks=[], cookbook_path=Chef::Config[:cookbook_path]) 
      puts "-------------------"
      puts "knife cookbook test"
      puts "-------------------"
      cookbook_test = Chef::Knife::CookbookTest.new
      cookbook_test.config[:cookbook_path] = cookbook_path 
      cookbook_test.config[:all] = false
      cookbook_test.name_args = cookbooks
      cookbook_test.run
      puts "--------------------------"
      puts "Knife cookbook test passed"
      puts "--------------------------"
    end

    # Run foodcritic test 
    # Expecting input,cookbooks, as a list of names, not paths
    def foodcritic_test(cookbooks=[], cookbook_path=Chef::Config[:cookbook_path]) 

      # Convert names into full_paths, as foodcritic is expecting full_paths 
      full_path_cookbooks = []
      cookbook_path.each do |path|
        cookbooks.each do |cookbook|
          full_path = File.join(File.expand_path(path), cookbook)
          full_path_cookbooks << full_path if File.exists?(full_path) 
        end
      end

      puts "---------------"
      puts "foodcritic test"
      puts "---------------"
      options = {}
      options[:fail_tags] = Chef::Config[:jenkins][:foodcritic][:fail_tags]
      options[:tags] = Chef::Config[:jenkins][:foodcritic][:tags]
      options[:include_rules] = Chef::Config[:jenkins][:foodcritic][:include_rules]
      puts "foodcritic options: #{options}"
      review = FoodCritic::Linter.new.check(full_path_cookbooks, options)
      FoodCritic::SummaryOutput.new.output(review)

      if review.failed?
        puts "----------------------"
        puts "Foodcritic test failed"
        puts "----------------------"
        exit 1
      end
      puts "----------------------"
      puts "Foodcritic test passed"
      puts "----------------------"
    end

    # Propagate cookbook version(s) from one environment to another
    def prop(env_from=Chef::Config[:jenkins][:env_from], env_to=Chef::Config[:jenkins][:env_to])
      add_upstream
      
      from = Chef::Environment.load(env_from)  
      to = Chef::Environment.load(env_to)

      if from.cookbook_versions.eql? to.cookbook_versions
        Chef::Log.info("#{env_from} and #{env_to} are already in sync")
        exit 0
      end

      to.cookbook_versions(from.cookbook_versions)
      to.save
      save_environment_file(env_to)
      push_to_upstream
    end

    # Sync cookbooks, roles, and data_bags to chef_server while pushing changes to git repo
    def sync(cookbook_path=Chef::Config[:cookbook_path], role_path=Chef::Config[:role_path], repo_dir=Chef::Config[:jenkins][:repo_dir])
      add_upstream

      git_branch(integration_branch_name)

      cookbooks_to_change = []
      roles_to_change = []
      data_bags_to_change = []

      last_commit = read_last_commit
      if last_commit
        cookbooks_to_change = find_changed_cookbooks(last_commit, 'HEAD')
        roles_to_change = find_changed_roles(last_commit, 'HEAD')
        data_bags_to_change = find_changed_data_bags(last_commit, 'HEAD')
      else
        cookbooks_to_change = find_all_cookbooks
        roles_to_change = find_all_roles
        data_bags_to_change = find_all_data_bags
      end

      puts "==============================="
      puts "Chef Jenkins output starts here"
      puts "==============================="
      if cookbooks_to_change.length == 0 || cookbooks_to_change.nil?
        puts "* No cookbooks have changed"
        no_cookbook_change = true
      end

      if roles_to_change.length == 0 || roles_to_change.nil?
        puts "* No roles have changed"
        no_role_change = true
      end
    
      if data_bags_to_change.length == 0 || data_bags_to_change.nil?
        puts "* No data_bags have changed"
        no_data_bag_change = true
      end

      if no_cookbook_change and no_role_change and no_data_bag_change
        puts "* Nothing to do, exit"
        exit 0
      end

      unless no_cookbook_change
        # Run tests
        tests = Chef::Config[:test]
        if tests 
          require 'foodcritic'
          require 'foodcritic/linter'
          require 'foodcritic/output'
          puts "## Testing Start"
          knife_cookbook_test(cookbooks_to_change) if tests.include?("ruby")
          foodcritic_test(cookbooks_to_change) if tests.include?("foodcritic")
          puts "## Testing End"
        end

        # Bump cookbook patch version
        cookbooks_to_change.each do |cookbook|
          cookbook_path.each do |path|
            metadata_file = File.join(path, cookbook, "metadata.rb")
            bump_patch_level(metadata_file, cookbook) if File.exists?(metadata_file)
          end
        end

        commit_cookbook_changes(cookbooks_to_change)
        Chef::Log.info("Cookbook versions updated")
      end

      upload_data_bags(data_bags_to_change)
      upload_roles(roles_to_change)
      upload_cookbooks(cookbooks_to_change)

      write_current_commit(repo_dir)
      push_to_upstream
    ensure
      @git.branch("master").checkout
    end

  end
end
