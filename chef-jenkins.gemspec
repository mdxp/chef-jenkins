# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "chef/jenkins/version"

Gem::Specification.new do |s|
  s.name        = "chef-jenkins"
  s.version     = Chef::Jenkins::VERSION
  s.authors     = ["Adam Jacob", "Marius Ducea"]
  s.email       = ["adam@opscode.com", "marius.ducea@gmail.com"]
  s.homepage    = "https://github.com/mdxp/chef-jenkins"
  s.summary     = %q{Chef+Jenkins}
  s.description = %q{Keep your chef server in sync with jenkins}

  s.rubyforge_project = "chef-jenkins"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.extra_rdoc_files = [
    "LICENSE",
    "README.rdoc"
  ]

  s.add_dependency "chef", ">= 0.10.10"
  s.add_dependency "git", ">= 1.2.5"

end
