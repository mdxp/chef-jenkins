name "vagrant"
description "Vagrant role"
run_list(
    "recipe[test::apt_update]"
)

default_attributes(
  :active_sudo_users =>  ["vagrant"]
)
