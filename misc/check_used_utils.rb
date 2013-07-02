#!/usr/bin/ruby
ENV['PATH'] = "#{ENV['PATH']}:/sbin:/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin"
conserve_root = '/data/documents/development/conserve'
Dir.chdir(conserve_root)
i = 0
puts "N\tAlert\tComment\tTime(s)\tUtil Name\tPackage"
packages = Array.new
IO.read("./misc/used_utils.txt").each_line{|util|
	i += 1
	util.chomp!
	matches = Array.new
	`grep -r #{util} ./ |grep -v git |grep -v .swp |grep -v history.txt |grep -v used_utils.txt`.each_line{|line|
		matches.push(line.chomp.strip)
	}
	if matches.empty?
		puts "#{i}:\t!!!\tNotUsed\t0\t#{util}"
	else
		util_path = `which #{util}`.chomp
		package = `dpkg -S #{util_path} 2>/dev/null`.chomp.split(":")[0]
		packages.push(package)
		#package = `apt-file -F search #{util_path} 2>/dev/null`.chomp.split(":")[0]
		puts "#{i}:\t\t\t#{matches.length}\t#{util}\t#{"\t" if util.length < 8}#{package}"
	end
}
packages.uniq!.compact!
puts "Used packages: "
File.open("./misc/used_packages.txt", 'w'){|file|
	packages.each{|package|
		puts "\t" + package
		file.puts(package)
	}
}
#tasks = Array.new
#packages.each{|package|
#	task = `apt-cache show #{package} |grep -m 1 Task`.chomp.split(":")[1]
#	tasks.push(task)
#}
#tasks.uniq!
#puts "Used tasks: #{tasks}."
