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

require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Chef::Jenkins" do
  before(:each) do
    AH.reset!
    Chef::Config.from_file(AH.file("config.rb"))
    @cj = Chef::Jenkins.new
  end

  describe "initialize" do
    it "returns a Chef::Jenkins object" do
      @cj.should be_a_kind_of(Chef::Jenkins)
    end

    it "sets the user.name git config variable" do
      @cj.git.config["user.name"].should == Chef::Config[:jenkins][:git_user]
    end

    it "sets the user.email git config variable" do
      @cj.git.config["user.email"].should == Chef::Config[:jenkins][:git_email]
    end
  end

  describe "bump_patch_level" do
    it "updates metadata.rb to have an incremented patch version" do
      @cj.bump_patch_level(AH.file("metadata.rb"), "ntp")
      has_correct_version = false
      IO.foreach(AH.file("metadata.rb")) do |line|
        if line =~ /^version '0\.99\.5'$/
          has_correct_version = true
          break
        end
      end
      has_correct_version.should == true
    end
  end

  describe "write_current_commit" do
    it "writes the current commit out to a file" do
      @cj.write_current_commit(AH::INFLIGHT)
      cfile = File.join(AH::INFLIGHT, ".chef_jenkins_last_commit") 
      File.exists?(cfile).should == true
      # The length of a shasum
      IO.read(cfile).length.should == 40
    end
  end

  describe "commit_cookbook_changes" do
    it "commits changes to git, with the number and list of cookbooks" do
      cookbook_list = [ "ntp" ]
      cr = "\n"
      @cj.git.stub!(:commit).and_return(true)
      @cj.git.should_receive(:commit).with("1 cookbooks patch levels updated by Chef Jenkins\n\n#{cookbook_list.join(cr)}", :add_all => true)
      @cj.commit_cookbook_changes(cookbook_list)
    end
  end

  describe "read_last_commit" do
    it "returns the last commit" do
      @cj.write_current_commit(AH::INFLIGHT)
      @cj.read_last_commit(AH::INFLIGHT).length.should == 40
    end
  end

  describe "integration_branch_name" do
    it "uses the BUILD_TAG environment variable if it is set" do
      ENV['BUILD_TAG'] = "snoopy"
      @cj.integration_branch_name.should == "snoopy"
    end

    it "sets a manual build tag with the number of seconds since the epoch if no environment value is set" do
      ENV.delete('BUILD_TAG')
      @cj.integration_branch_name.should =~ /^chef-jenkins-manual-\d+$/
    end
  end

  describe "find_changed_cookbooks" do
    it "prints a list of cookbooks changed since last commit" do
      system("echo '#test' >> #{AH::INFLIGHT}/cookbooks/ntp/metadata.rb")
      system("cd #{AH::INFLIGHT}; git commit -am 'changed cookbook ntp';")
      cblist = @cj.find_changed_cookbooks('HEAD^', 'HEAD', ["#{AH::INFLIGHT}/cookbooks"]) 
      cblist.include?("ntp").should == true 
    end
  end

  describe "find_changed_roles" do
    it "prints a list of roles changed since last commit" do
      system("echo '#test' >> #{AH::INFLIGHT}/roles/apache2.rb")
      system("echo '#test' >> #{AH::INFLIGHT}/roles/vagrant.rb")
      system("cd #{AH::INFLIGHT}; git commit -am 'changed 2 roles';")
      role_list = @cj.find_changed_roles('HEAD^', 'HEAD', ["#{AH::INFLIGHT}/roles"]) 
      role_list = role_list.map {|i| File.basename(i)}
      role_list.include?("apache2.rb").should == true
      role_list.include?("vagrant.rb").should == true
    end
  end

  describe "find_changed_data_bags" do
    it "prints a list of data_bags changed since last commit" do
      system("echo '#test' >> #{AH::INFLIGHT}/data_bags/users/foobar.json")
      system("echo '#test' >> #{AH::INFLIGHT}/data_bags/groups/ops.json")
      system("cd #{AH::INFLIGHT}; git commit -am 'changed 2 databags';")
      data_bag_list = @cj.find_changed_data_bags('HEAD^', 'HEAD', ["#{AH::INFLIGHT}/data_bags"]) 
      data_bag_list = data_bag_list.map {|i| File.basename(i)}
      data_bag_list.include?("foobar.json").should == true
      data_bag_list.include?("ops.json").should == true
    end
  end

  describe "knife cookbook test" do
    it "test cookbook(s) with knife cookbook test" do
      @cj.knife_cookbook_test(["ntp"])
    end   
  end

  describe "foodcritic test" do
    require "foodcritic"
    it "test cookbook(s) with foodcritic" do
      @cj.foodcritic_test(["ntp"])
    end   
  end
end
