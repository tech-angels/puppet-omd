# (private) defines an exported hosts for inclusion in omd checks
define omd::host::export (
  $folder,
  $tags,
  $cluster_member = false,
) {
  validate_re($folder, '^\w+$')
  validate_bool($cluster_member)
  # no $tag validation, can be array or string

  $splitted_name = split($name, ' - ')

  $site   = $splitted_name[0]
  $fqdn   = $splitted_name[1]

  validate_re($site, '^\w+$')
  validate_re($fqdn, '^([a-zA-Z0-9-]+\.)+[a-zA-Z0-9-]+$')

  $wato_dir   = "/omd/sites/${site}/etc/check_mk/conf.d/wato"
  $hosts_file = "${wato_dir}/${folder}/hosts.mk"

  $content_str = join( flatten([$fqdn, 'puppet_generated', $folder, $tags]), '|')

  puppetlab-concat::fragment { "${site} site's ${folder}/hosts.mk entry for ${fqdn} (all_hosts)":
    target  => $hosts_file,
    content => "  \"${content_str}\",\n",
    order   => '05',
    notify  => Exec["check_mk inventorize ${fqdn} for site ${site}"],
  }

  if $cluster_member {
    puppetlab-concat::fragment { "${site} site's ${folder}/hosts.mk entry for ${fqdn} (clusters)":
      target  => $hosts_file,
      content => " \"${fqdn}\",\n",
      order   => '15',
      notify  => Exec["check_mk inventorize ${fqdn} for site ${site}"],
    }
  }

  # Build a list of host -> number of services
  if ! defined(Exec['count services per host']) {
    exec { "count services per host":
      command => "grep host_name /omd/sites/default/etc/nagios/conf.d/check_mk_objects.cfg|awk '{print $2}'|sort|uniq -c|awk '{print $2\" \"$1}'>/tmp/serviceperhost",
    }
  }
  Exec['count services per host'] ->
  exec { "check_mk inventorize ${fqdn} for site ${site}":
    command     => "su - ${site} -c 'check_mk -I ${fqdn}'",
    path        => [ '/bin' ],
    require     => Puppetlab-Concat[$hosts_file],
    unless      => "grep '${fqdn} ..' /tmp/serviceperhost>/dev/null",
    #unless      => "grep ${fqdn} /omd/sites/${site}/etc/nagios/conf.d/check_mk_objects.cfg|wc -l|grep ..>/dev/null", # Inventorise is less than 10 services

  }

  # add the orderings and reinventorize trigger to the file trigger of the collected
  # checks (actual collecting see server config)
  File <| tag == "omd_client_check_${fqdn}" |> {
    require => Concat[$hosts_file],
    notify  +> Exec["check_mk inventorize ${fqdn} for site ${site}"],
  }

}
