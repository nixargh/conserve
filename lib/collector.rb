#Conserve - linux backup tool.
#Copyright (C) 2013  nixargh <nixargh@gmail.com>
#
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see http://www.gnu.org/licenses/gpl.html.
class Collector
	include Add_functions

	def initialize
		# creatures list
		hdd, md, partition, lvm, mount, boot = Hash.new, Hash.new, Hash.new, Hash.new, Hash.new, Hash.new

		# Hash of creatures information hashes
		@creatures = { 'hdd' => hdd, 'md' => md, 'partition' => partition, 'lvm' => lvm, 'mount' => mount}
	end

	def collect # collect iformation about creatures
		list_disks!
		@creatures.sort.each{|creature, value|
			@creatures[creature] = eval("get_#{creature}_info")
		}
		@creatures['boot'] = [get_boot_info]
		@creatures
	end

	private

	def get_hdd_info # collect information about phisical disk devices
		hdd_list = Array.new
		@disk_list.each{|disk, size|
			if disk =~ /\A\/dev\/[hs]d[a-z]{1,2}\z/
				hdd = Hash.new
				hdd['name'] = disk
				hdd['size'] = size 
				hdd['blocksize'] = get_device_blocksize(disk)
				hdd['uuid'], hdd['type'] = get_uuid_and_type(disk)
				hdd['has_grub_mbr'] = find_grub_mbr(disk)
				hdd_list.push(hdd)
			end
		}
		hdd_list
	end

	def get_md_info # collect information about software RAID devices
		md_list = Array.new
		@disk_list.each{|disk, size|
			if disk =~ /\A\/dev\/md\d{1,3}\z/
				raid = Hash.new
				raid['name'] = disk
				`cat /proc/mdstat`.each_line{|line|
					if line.index(File.basename(disk))
						line.scan(/raid\d{1,2}/){|raid_lvl| 
							raid['raid_lvl'] = raid_lvl.match(/\d{1,2}/)[0].to_i
						}
						raid['members'] = Array.new
						line.scan(/[hs]d[a-z]{1,2}\d/){|disk|
							raid['members'].push("/dev/#{disk}")
						}
					end
				}
				md_list.push(raid)
			end	
		}
		md_list
	end

	def get_partition_info # collect information about partition tables
		partition_list = Array.new
		@creatures['hdd'].each{|hdd|
			if hdd['type'] == nil
				partitions = Hash.new
				partitions['disk'] = hdd['name']
				partitions['partitions'] = read_partitions(hdd['name'])
				partitions['partitions'].each{|partition|
					partition['uuid'], partition['type'] = get_uuid_and_type(partition['name'])
				}
				partition_list.push(partitions)
			end
		}
		partition_list
	end

	def get_lvm_info # collect information about LVM
		begin
			vg_list = Array.new
			backup_dir = "/tmp/vgcfgbackup"
			backup_files = Array.new
			Dir.mkdir(backup_dir) if !File.directory?(backup_dir)
			dir = Dir.open(backup_dir)
			`vgcfgbackup -f #{backup_dir}/%s 2>1 1>/dev/null`
			dir.each{|file|
				if file != '.' && file !='..'
					vg = Hash.new
					vg['name'] = file
					backup_file = "#{backup_dir}/#{file}"
					backup_files.push(backup_file)
					vg['config'] = IO.read(backup_file)
					vg_list.push(vg)
				end
			}
			vg_list
		ensure
			backup_files.each{|file|
				File.unlink(file) if File.exist?(file)
			}
			Dir.unlink(backup_dir) if File.directory?(backup_dir)
		end
	end

	def get_mount_info # collect information about how to mount partitions
		mounts = Array.new
		IO.read('/etc/fstab').each_line{|line|
			mounts.push(line.split(' ')) if line.index('#') != 0
		}
		mounts
	end

	def get_boot_info # find where GRUB installed
		bootloader = Hash.new
		boot_folder_hdd = find_where_boot_folder
		@creatures['hdd'].each{|hdd|
			if hdd['has_grub_mbr']
				bootloader['hdd'] = hdd['name'] if hdd['name'] == boot_folder_hdd
				bootloader['type'] = File.exist?('/boot/grub/menu.lst') ? 'grub' : 'grub2'
			end
		}
		bootloader
	end

	def find_where_boot_folder # detect on which device "/boot" folder is
		boot, root = nil, nil
		@creatures['mount'].each{|line|
			boot = line[0] if line[1] == '/boot'
			root = line[0] if line[1] == '/'
		}
		device = boot ? boot : root
		if device.upcase.index('UUID')
			uuid = device.split('=')[1]
			device = find_by_uuid(uuid)
		end
		device.chop
	end

	def find_by_uuid(uuid) # find hdd or partition by it's UUID
		@creatures['hdd'].each{|hdd|
			return hdd['name'] if uuid == hdd['uuid']
		}
		@creatures['partition'].each{|hdd|
			hdd['partitions'].each{|partition|
				return partition['name'] if uuid == partition['uuid']
			}
		}
		nil
	end

	def find_grub_mbr(device) # detect if there is GRUB's info at hdd mbr
		info, error = runcmd("dd bs=512 count=1 if=#{device} 2>/dev/null | strings")
		if info
		info.each_line{|line|
			line.chomp!.strip!	
			return true if line == 'GRUB'
		}
		end
		false
	end

	def list_disks! # create list with sizes of different disk devices on current machine
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

	def get_device_size # size in bytes
		`blockdev --getsize64 #{dev}`.chomp.to_i
	end

	def get_device_blocksize(dev) # get blocksize of device in bytes
		`blockdev --getbsz #{dev}`.chomp.to_i
	end

	def get_uuid_and_type(device) # get uuid and type of block device
		uuid, type = nil, nil
		info = `blkid #{device}`.split(' ')
		info.each{|arg|
			uuid = arg.split('=')[1].delete('"') if arg.index('UUID')
			type = arg.split('=')[1].delete('"') if arg.index('TYPE')
		}
		return uuid, type
	end

	def read_partitions(disk) # read partitions table of disk + some of partition attributes
		partitions = Array.new
		info, error = runcmd("sfdisk -l #{disk} -d -x 2>1")
		if !error
			info.each_line{|line|
				if line.index('/dev/') == 0
					partition = Hash.new
					spl_line = line.split(',')
					size = 0
					spl_line.each{|arg|
						partition['size'] = arg.split('=')[1].strip.to_i if arg.index('size=')
						partition['id'] = arg.split('=')[1].strip if arg.index('Id=')
						partition['name'] = name = arg.split(':')[0].strip if arg.index('/dev/')
					}
					if partition['size'] > 0
						partitions.push(partition)
					end
				end
			}
		elsif error.index('GPT')
			# stub. need to write alternative detection method for GPT partition table
		end
		partitions
	end
end
