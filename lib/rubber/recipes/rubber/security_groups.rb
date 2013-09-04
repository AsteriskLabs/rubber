namespace :rubber do

  desc <<-DESC
    Sets up the network security groups
    All defined groups will be created, and any not defined will be removed.
    Likewise, rules within a group will get created, and those not will be removed
  DESC
  required_task :setup_security_groups do
    servers = find_servers_for_task(current_task)

    cloud.setup_security_groups(servers.collect(&:host))
  end

  desc <<-DESC
    Describes the network security groups
  DESC
  required_task :describe_security_groups do
    groups = cloud.describe_security_groups()
    groups.each do |group|
      puts "#{group[:name]}, #{group[:description]}"
      group[:permissions].each do |perm|
        puts "  protocol: #{perm[:protocol]}"
        puts "  from_port: #{perm[:from_port]}"
        puts "  to_port: #{perm[:to_port]}"
        puts "  source_groups: #{perm[:source_groups].collect {|g| g[:name]}.join(", ") }" if perm[:source_groups]
        puts "  source_ips: #{perm[:source_ips].join(", ") }" if perm[:source_ips]
        puts "\n"
      end if group[:permissions]
      puts "\n"
    end
  end

  desc <<-DESC
    Removes external SSH rules from the network security groups
  DESC
  required_task :security_group_lockdown do
    groups = cloud.describe_security_groups()
    groups.each do |group|
      group[:permissions].each do |perm|
         # skip those groups that don't belong to this project/env
         envv = rubber_cfg.environment.bind([],nil)
         next if envv.isolate_security_groups && group[:name] !~ /^#{envv.app_name}_#{Rubber.env}_/
         if perm[:protocol] == "tcp" and perm[:from_port] == 22 and perm[:to_port] == 22 then
          from = ""
          from = "source_groups: #{perm[:source_groups].collect {|g| g[:name]}.join(", ") }" if perm[:source_groups]
          from += "source_ips: #{perm[:source_ips].join(", ") }" if perm[:source_ips]
          answer = Capistrano::CLI.ui.ask("#{group[:name]}, #{group[:description]} includes SSH from\n#{from}\n..remove from cloud? [y/N]: ")

          if answer =~ /^y/
            if perm[:source_groups]
            elsif perm[:source_ips]
              perm[:source_ips].each do |source_ip|
                cloud.remove_security_group_rule(group[:name], perm[:protocol], perm[:from_port], perm[:to_port], source_ip)
              end
            end
          end
        end
      end if group[:permissions]
    end
  end


  def get_assigned_security_groups(host=nil, roles=[])
    env = rubber_cfg.environment.bind(roles, host)
    security_groups = env.assigned_security_groups
    if env.auto_security_groups
      security_groups << host
      security_groups += roles
    end
    security_groups = security_groups.uniq.compact.reject {|x| x.empty? }
    security_groups = security_groups.collect {|x| cloud.isolate_group_name(x) }
    return security_groups
  end
end