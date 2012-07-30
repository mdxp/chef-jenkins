name "apache2"
description "Apache2/PHP role"
run_list(
    "recipe[apache2]",
    "recipe[apache2::mod_php5]",
    "recipe[apache2::mod_rewrite]",
    "recipe[apache2::mod_expires]",
)
default_attributes(
)
