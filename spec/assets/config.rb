current_dir = File.dirname(__FILE__)
log_level                :info
log_location             STDOUT
node_name                "jenkins"
client_key               "#{ENV['HOME']}/.chef/jenkins.pem"
chef_server_url          "https://testing.chef-jenkins.org"
cache_type               'BasicFile'
cache_options( :path => "#{ENV['HOME']}/.chef/checksums" )
cookbook_path            ["#{current_dir}/cookbooks", "#{current_dir}/site-cookbooks"]
role_path                ["#{current_dir}/roles"]
data_bag_path            ["#{current_dir}/data_bags"]
jenkins[:repo_path] = File.expand_path("#{current_dir}/../../")

jenkins({
  :repo_dir => current_dir,
  :repo_url => 'ssh://git@git.promethost.com/chef',
  :git_user => "Jenkins CI",
  :git_email => "jenkins@promethost.com",
  :env_to => "ops",
  :branch => "master",
  :foodcritic => {
    :fail_tags => ["correctness"],
    :tags => [],
    :include_rules => []
  }
})

