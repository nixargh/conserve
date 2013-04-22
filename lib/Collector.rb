class Collector
	def initialize
		# creatures list
		hdd, md, partition, lvm, mount = Hash.new, Hash.new, Hash.new, Hash.new, Hash.new

		# directory to store creatures files 
		@info_dir = 'info'

		# files to store creatures information 
		hdd['info_file'] = "#{@info_dir}/hdd"
		md['info_file'] = "#{@info_dir}/md"
		partition['info_file'] = "#{@info_dir}/partition"
		lvm['info_file'] = "#{@info_dir}/lvm"
		mount['info_file'] = "#{@info_dir}/mount"

		@creatures = { 'hdd' => hdd, 'md' => md, 'partition' => partition, 'lvm' => lvm, 'mount' => mount }
	end

	def collect
		list_disks!
		@creatures.each_key{|creature|
			@creatures[creature]['info'] = eval("get_#{creature}_info")
		}
	end

	def save
		@creatures.each{|key, value|
			puts "#{key} = #{value}"
		}
	end

	private

	def get_hdd_info
		hdd_list = Array.new
		@disk_list.each{|disk, size|
			if disk =~ /\A\/dev\/(s|h)d[a-z]\z/
				hdd = Hash.new
				hdd['name'] = disk
				disk['size'] = size
				hdd_list.push(hdd)
			end
		}
		hdd_list
	end

	def get_md_info
		'md'
	end

	def get_partition_info
	end

	def get_lvm_info
	end

	def get_mount_info
	end

	def list_disks!
		@disk_list = Hash.new
		`fdisk -l 2>/dev/null`.each_line{|line|
			if line.index('Disk /')
				dev, size = line.split(':')
				dev = dev.split(' ')[1]
				size = size.split(' ')[-2]
				@disk_list[dev] = size
			end
		}
	end
end

collector = Collector.new
collector.collect
collector.save
