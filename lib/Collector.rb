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

		# Hash of creatures information hashes
		@creatures = { 'hdd' => hdd, 'md' => md, 'partition' => partition, 'lvm' => lvm, 'mount' => mount }
	end

	def collect # collect iformation about creatures
		list_disks!
		@creatures.each_key{|creature|
			@creatures[creature]['info'] = eval("get_#{creature}_info")
		}
	end

	def save # save information about creatures
		@creatures.each{|key, value|
			puts "#{key} = #{value}"
		}
	end

	private

	def get_hdd_info # collect information about phisical disk devices
		hdd_list = Array.new
		@disk_list.each{|disk, size|
			if disk =~ /\A\/dev\/[sh]d[a-z]\z/
				hdd = Hash.new
				hdd['name'] = disk
				hdd['size'] = size 
				hdd['blocksize'] = get_device_blocksize(disk)
				hdd_list.push(hdd)
			end
		}
		hdd_list
	end

	def get_md_info # collect information about software RAID devices
		md_list = Hash.new
		@disk_list.each{|disk, size|
			if disk =~ /\A\/dev\/md\d{1,3}\z/
				md_list['name'] = disk
				`cat /proc/mdstat`.each_line{|line|
					if line.index(File.basename(disk))
						line.scan(/raid\d{1,2}/){|raid_lvl| 
							md_list['raid_lvl'] = raid_lvl.match(/\d{1,2}/)[0].to_i
						}
						md_list['members'] = Array.new
						line.scan(/[hs]d[a-z]{1,2}\d/){|disk|
							md_list['members'].push("/dev/#{disk}")
						}
					end
				}
			end	
		}
		md_list
	end

	def get_partition_info # collect information about partition tables
	end

	def get_lvm_info # collect information about LVM
	end

	def get_mount_info # collect information about how to mount partitions
	end

	def list_disks! # create list of disk devices on current machine
		@disk_list = Hash.new
		`fdisk -l 2>/dev/null`.each_line{|line|
			if line.index('Disk /')
				dev, size = line.split(':')
				dev = dev.split(' ')[1]			# device name
				size = size.split(' ')[-2] 		# size in bytes
				@disk_list[dev] = size.to_i
			end
		}
	end

	def get_device_blocksize(dev) # get blocksize of device in bytes
		`blockdev --getbsz #{dev}`.chomp.to_i
	end
end

# Test section
collector = Collector.new
collector.collect
collector.save
