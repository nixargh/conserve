#!/usr/bin/ruby -w
##### INFO #####################################################################
# script to restore linux
# tested at: 
# 	1. SLES11 x86 on Hyper-V
#	2. SLES11 sp.1 x86 at HP DL160 G5
# (*w)
$version = '0.9.2'
#### SETTINGS ##################################################################
$net_mount_dir = '/mnt/net'
$backup_files = {'mbr' => 'mbr.img', 'boot' => 'boot.img', 'root' => 'root.img'}
$last_error = nil
$boot_dev = nil
#### REQUIRE ###################################################################
require 'fileutils'
#### CLASES ####################################################################
#### FUNCTIONS #################################################################
def print_f(string)
	print string
	$stdin.flush
end

def menu
	begin
		status = 0
		system("/usr/bin/clear")
		puts "##### Metrex Restore v.#{$version} #####"
		puts "\n Last run error: #{$last_error}\n\t" if $last_error != nil
		puts "Menu:"
		puts "\t1. Restore from smb share.\n\t\troot and swap at LVM + grub bootloader"
		puts "\t2. Print information about existing HDD."
		puts "\t3. Print $backup_files hash."
		puts "\n\tr. Reboot"
		puts "\ts. Shutdown"
		puts "\n\tq. Quit to shell"
		print "i choose: "
		answer = $stdin.gets.chomp
	rescue
		status = 1
		error = $!
	end
	result = [status, error, answer]
end

def do_action(action)
	begin
		status = 0
		if action == "s"
			`/sbin/poweroff`
		elsif action == "r"
			`/sbin/reboot`
		elsif action == "q"
			exit 0
		elsif action == "1"
			if make_dir($net_mount_dir)
				mount_smb_result = mount_smb($net_mount_dir)
				if mount_smb_result[0] == 0
					check_backup_files($net_mount_dir) ? (puts "\tBackup files found.") : (raise "Can't find some of backup files")
					find_mbr_dev_result = find_mbr_dev
					if find_mbr_dev_result[0] == 0
						target_hdd = find_mbr_dev_result[2]
						restore_mbr_result = restore_mbr("#{$net_mount_dir}/#{$backup_files['mbr']}",target_hdd)
						if restore_mbr_result[0] == 0
							`/usr/sbin/sfdisk -R #{target_hdd}`
							find_boot_dev_result = find_boot_dev(target_hdd)
							if find_boot_dev_result[0] == 0
								# restoring /boot
								$boot_partition = find_boot_dev_result[2]
								restore_boot_result = restore_boot("#{$net_mount_dir}/#{$backup_files['boot']}",$boot_partition)
								if restore_boot_result[0] = 0
									# restoring other partitions
									restoring_nonboot_partitions_result = restoring_nonboot_partitions(target_hdd)
									if 	restoring_nonboot_partitions_result[0] == 0
										puts "\t*** System restored successfully. ***"
										puts "\tJust NOTE: If this is virtual machine, give old mac adress to its network interface."
										puts "\nPress ENTER to reboot or m to go to Menu..."
										 if (ch = $stdin.gets.chomp) == ''
											`/sbin/reboot`
										 elsif ch == 'm'
											raise "Menu sir!"
										 else
											raise "I think you miss the right button, so look at menu now :)"
										 end
									else
										raise "Can't restore other partitions: #{restoring_nonboot_partitions_result[1]}"
									end
								else 
									raise "Can't restore boot device: #{restore_boot_result[1]}"
								end
							else
								raise "Can't find device to restore \"/boot\": #{find_boot_dev_result[1]}"
							end
						else
							raise "Failed to restore MBR: #{restore_mbr_result[1]}"
						end
					else
						raise "Can't find HDD to restore mbr: #{find_mbr_dev_result[1]}"
					end
				else
					raise "Can't mount smb share: #{mount_smb_result[1]}"
				end
			else
				raise "Can't create directory: #{$!}"
			end
		elsif action == "2"
			build_table_of_all_hdd
			puts "\nPress ENTER to continue..."
			if $stdin.gets.chomp
				raise "Menu sir!"
			end
		elsif action == '3'
			puts $backup_files
			puts "\nPress ENTER to continue..."
			if $stdin.gets.chomp
				raise "Menu sir!"
			end
		else
			raise "Unknown action"
		end
	rescue
		status = 1
		error = $!
	end
	result = [status, error]
end

def check_backup_files(dir)
	puts "\tChecking backup files: "
	$backup_files.each{|partition, file|
		print_f "\t\t#{partition} backup file \"#{file}\" - "
		if File.exist?("#{dir}/#{file}")
			puts "Found."
		elsif File.exist?("#{dir}/#{file}.gz")
			puts "Found archived."
			$backup_files[partition] = "#{file}.gz"
		else
			puts "Not found."
			file = manual_file_select(dir, file)
			$backup_files[partition] = file
			return false if File.exist?("#{dir}/#{file}") == false
		end
	}
end

def manual_file_select(dir, file)
	build_dir_files_table(dir)
	print_f "\t\tCan't find #{file}, enter correct name of file to restore \"#{(file.split('.'))[0]}\": "
	file = $stdin.gets.chomp
end

def build_dir_files_table(dir)
	dir_files = Dir.entries(dir)
	puts "\n\t\tName\t\t\tSize\t\tModify Date"
	puts "\t\t---------------------------------------------"
	dir_files.each{|file|
		if File.directory?(file) == false
			full_file = "#{dir}/#{file}"
			file_obj = File.new(full_file)
			file.length < 8 ? (file_name = "#{file}\t") : (file_name = file)
			puts "\t\t#{file_name}\t\t#{format_size(File.size(full_file))}\t\t#{file_obj.mtime.asctime}\n"
		end
	}
end

def check_smb_online(server)
	raise 'Nothing to check, because "server" is nil.' if server == nil
	`quit 2>/dev/null |/bin/telnet #{server} 445 2>/dev/null`.index("Connected to #{server}.") ? true : false
end

def make_dir(dir)
	Dir.mkdir(dir) if Dir.exist?(dir) == false
	Dir.exist?(dir) ? true : false
end

def mount_smb(mount_dir)
	begin
		status = 0
		if Dir.exist?(mount_dir)
			print "Enter UNC path to backup files: "
			backup_path = read_unc_path
			server = (backup_path.split('/'))[2]
			if check_smb_online(server) 
				puts "\tSMB at \"#{server}\" - OK."
			else
				puts "\tSMB at \"#{server}\" - not answering."
				print "Enter correct UNC path to backup files: "
				backup_path = read_unc_path
				server = (backup_path.split('/'))[2]
				if check_smb_online(server)
					puts "\tSMB at \"#{server}\" - OK."
				else
					raise "SMB didn't answer at server \"#{server}\": #{$!}"
				end
			end
			print "Enter usename: "
			username = $stdin.gets.chomp
			if username.length > 0
				print "Enter password: "
				password = read_password
			else
				password = ''
			end
			print_f "\n\tMounting #{backup_path} to #{mount_dir} - "
			`mount.cifs #{backup_path} #{mount_dir} -o username=#{username},password=#{password}`
			# проверка не очень, так как не видно конечную папку, только шару
			where_mounted?(File.dirname(backup_path)) ? (puts 'OK.') : (puts 'Failed.')
		else
			raise "directory \"#{mount_dir}\" not found"
		end
	rescue
		status = 1
		error = $!
	end
	result = [status, error]
end

def read_unc_path
	unc_path = $stdin.gets.chomp
	unc_path = unc_path.gsub('\\', '/')
end

def read_password
	system "stty -echo"
	password = $stdin.gets.chomp
	system "stty echo"
	password
end

def mount_local(partition)
	mount_dir = where_mounted?(partition)
	if where_mounted?(partition) == nil
		mount_dir = "/mnt/#{(partition.split("/"))[2]}"
		make_dir(mount_dir) if Dir.exist?(mount_dir) == false
		`/sbin/mount #{partition} #{mount_dir}`
		puts "\tPartition #{partition} mounted to #{mount_dir}."
	end
	mount_dir
end

def where_mounted?(partition)
	partition = File.readlink(partition) if File.symlink?(partition)
	root = nil
	IO.read('/etc/mtab').each_line{|line|
		root = (line.split(" "))[1] if line.index(partition)
	}
	root
end

def find_mbr_dev
	begin
		status = 0
		mbr_device = []
		Dir.foreach("/dev"){|device|
			if device.index(/\A(s|h)d.\Z/)
				is_mbr_device = true
				device = "/dev/#{device}"
				mtab = IO.read('/etc/mtab')
				mtab.each_line{|line|
					is_mbr_device = false if line.index("#{device} ")
				}
				mbr_device.push(device) if is_mbr_device && File.blockdev?(device)
			end
		}
		if mbr_device.length == 0
			raise "No HDD device found"
		elsif mbr_device.length == 1
			mbr_device = mbr_device[0]
		elsif mbr_device.length >= 2
			build_table_of_all_hdd
		    print "\t\tFound #{mbr_device.length} HDD, enter correct one to restore MBR: "
			mbr_device = $stdin.gets.chomp
		end
		puts "\tFound HDD: #{mbr_device}."
	rescue
		status = 1
		error = $!
	end
	$boot_dev = mbr_device
	result = [status, error, mbr_device]
end

def find_boot_dev(hdd)
	begin
		status = 0
		partition = nil
		partition_list = `/sbin/fdisk -l #{hdd}`
		partition_list.each_line{|line|
			if line.index("*") && line.index(hdd) == 0
				partition = line[0, hdd.length + 1]
			end
		}
		if partition == nil
			print "\t\tCan't find boot partition on \"#{hdd}\". Type it manually: "
			partition = $stdin.gets.chomp
		end
		#if File.exist?(partition)
			puts "\tFound boot partition: #{partition}."
		#else
		#	raise "Founded boot partition \"#{partition}\" doesn't exist"
		#end
	rescue
		status = 1
		error = $!
	end
	result = [status, error, partition]
end

def restore_mbr(input_file, output_device)
	begin
		status = 0
		raise "#{output_device} isn't block device" if File.blockdev?(output_device) != true
		print_f "\tMBR restoring to HDD: #{output_device} - "
		puts "OK." if dd_with_status("dd if=#{input_file} of=#{output_device} bs=512 count=1")
	rescue
		status = 1
		error = $!
	end
	result = [status, error]
end

def dd_with_status(dd_cmd)
	begin
		dd_error_log='/tmp/dd_error.log'
		`#{dd_cmd} 1>#{dd_error_log} 2>#{dd_error_log}`
		info = IO.read(dd_error_log)	
		if info.index("copied")
			info = info.split("\n")
	#puts "#{info[0].split('+')[0]} == #{info[1].split('+')[0]}"
			if info[0].split('+')[0] == info[1].split('+')[0]
				return true
			else
				#raise "\"records out\" not equal \"records in\", case: #{info[0]}."
				raise "dd failed: #{info[0]}"
			end
		else
			raise info
		end
	ensure
		File.unlink(dd_error_log)
	end
end

def restore_boot(input_file, output_device)
	begin
		status = 0
		rest_dev = restore_device(input_file, output_device)
	#rest_dev = [0, nil]
		if rest_dev[0] == 0
			fix_devicemap(output_device, ($boot_dev != nil ? $boot_dev : find_mbr_dev[2]))
		else
			raise rest_dev[2]
		end
	rescue
		status = 1
		error = $!
	end
	result = [status, error]
end

def restore_device(input_file, output_device)
	begin
		status = 0
		splited_input_file= input_file.split('.')
		input_file_ext = splited_input_file[splited_input_file.length - 1]
		print_f "\tRestoring \"#{output_device}\" partition restore from image file \"#{input_file}\" "
		# не понятно почему, но без паузы команда выполняется "как-то не так". вроде статистика копирования информации таже,
		# но реально раздел не меняется, как буд-то информация уходит мимо
		sleep(1)
		if input_file_ext == 'gz'
			print_f "archive "
			puts "- OK." if dd_with_status("/usr/bin/gzip -dc #{input_file} | dd of=#{output_device} bs=4M")
		else
			puts "- OK." if dd_with_status("/usr/bin/dd if=#{input_file} of=#{output_device} bs=4M")
		end
		fscheck_result = fscheck(output_device)
		if fscheck_result[0] == 0
			puts "\tDevice restored from image file \"#{input_file}\" to partition \"#{output_device}\"."
		else
			raise "Restore of \"#{input_file}\" to \"#{output_device}\" failed: #{fscheck_result[1]}"
		end
	rescue
		status = 1
		error = $!
	end
	result = [status, error]
end

def fscheck(partition)
	begin
		status = 0
		first_check = fsck(partition)
		if first_check == 0
			puts "\t\tPartition checked - OK"
		elsif first_check == 1
			puts "\t\tPartition wasn't clean, check passed, recheck."
			if fsck(partition) == 0
				puts "\t\tPartition rechecked - OK"
			else
				puts "\t\tSecond \"fsck\" failed, you have to fix it manually."
			end
		else
			raise "Partition check failed, maybe partition isn't restored"
		end
	rescue
		status = 1
		error = $!
	end
	result = [status, error]
end

def fsck(partition)
	status = nil
	fsck = `/sbin/fsck -T -y #{partition} 2>/dev/null`
	fsck.each_line{|line|
		if line.index(partition) == 0 && line.index(" not cleanly ")
			status = 1
		elsif line.index(partition) == 0 && line.index(" clean,")
			status = 0
		end
	}
	status = 2 if status != 0 && status != 1
	status
end

def restoring_nonboot_partitions(hdd)
	begin
		status = 0
		lvm_partitions = []
		puts "\tStarting restore of non-boot partitions."
		part_list = list_other_partitions(hdd)
		build_table_of_partitions(part_list).each{|key, value|
			if value == 'LVM'
				lvm_partitions.push(key)
			elsif value == 'Linux'
				raise "Don't know what to do with Linux type of partitions, yet..."
			end
		}
		mount_dir = mount_local($boot_partition)
		root, swap = parse_grub_menu(mount_dir)
		# lvm partitions restore
		lvm_operates(lvm_partitions, root, swap)
		# add here non-lvm partitions restore
		# restoring swap
		make_swap(swap)
		# restoring /root
		res_dev_res = restore_device("#{$net_mount_dir}/#{$backup_files['root']}", root)
		#res_dev_res = [0, nil]
		if res_dev_res[0] == 0
			fix_fstab(root, find_boot_dev(hdd)[2])
		else
			raise "root restore failed: #{res_dev_res[1]}"
		end
	rescue
		status = 1
		error = $!
	end
	result = [status, error]
end

def make_swap(swap)
	if check_swap(swap) == false
		print_f "\tCreating swap on #{swap} - "
		`/sbin/mkswap -c #{swap}; /sbin/swapon #{swap}`
		if check_swap(swap)
			puts "OK."
		else
			puts "Failed."
			raise "swap creation on #{swap} failed. Restore without swap will call \'BUS ERROR\'. Try to create swap manually."
		end
	end
end

def check_swap(swap)
	active_swaps = IO.read('/proc/swaps')
	swap = File.readlink(swap) if File.symlink?(swap)
	active_swaps.index(swap) ? (return true) : (return false)
end

def lvm_operates(lvm_partitions, root, swap)
	lvm_part_length = lvm_partitions.length
	if lvm_part_length > 0
	puts "\tStarting LVM operations:"
		root = parse_lvm(root)
		swap = parse_lvm(swap)		
		if lvm_part_length == 1
			root_lvm_partition = swap_lvm_partition = lvm_partitions
			#swap_lvm_partition = lvm_partitions
		elsif lvm_part_length > 1
			puts "\t\tFound more than one partition with LVM type."
			print "\t\t\tPlease, choose partition(s) for LVM volume group \"#{root[0]}\": "
			root_lvm_partition = $stdin.gets.chomp
			if root[0] == swap[0]
				root_lvm_partition = swap_lvm_partition
			else
				print "\t\t\tPlease, choose partition(s) for LVM volume group \"#{swap[0]}\": "
				swap_lvm_partition = $stdin.gets.chomp
			end
		end
		lvm_create(swap_lvm_partition, swap)
		lvm_create(root_lvm_partition, root)
	end
end

def lvm_create(partitions, vg_lv)
	vg = vg_lv[0]
	lv = vg_lv[1]
	partitions_list = nil
	partitions.each{ |partition|
			partitions_list = "#{partitions_list} #{partition}"
		}
	partitions_list.slice!(0)
	if check_pv(partitions_list) == false
		pvcreate(partitions_list)
	else
		puts "\t\tpv found, no need to create."
		if check_vg(vg)
			vgactivate(vg)
		else
			raise "Can't understand situation: pv found without creating, but vg \"#{vg}\" not found"
		end
	end
	if check_vg(vg) == false
		vgcreate(vg, partitions_list)
	end
	if check_lv(vg, lv) == false
		lvcreate(vg, lv)
	end
end

def pvcreate(partitions_list)
	pv_error = `/sbin/pvcreate #{partitions_list}`
	if check_pv(partitions_list)
		puts "\t\tpvcreate - OK."
	else
		raise "pvcreate failed: #{pv_error}"
	end
end

def vgcreate(vg, partitions_list)
	puts "\t\tCreating LVM vg \"#{vg}\" at #{partitions_list}..."
	vg_error = `/sbin/vgcreate #{vg} #{partitions_list}`
	if check_vg(vg)
		puts "\t\t\tLVM vg \"#{vg}\" at #{partitions_list} created - OK."
		vgactivate(vg)
	else
		raise "Can't create vg \"#{vg}\" at #{partitions_list}: #{vg_error}"
	end
end

def vgactivate(vg)
	puts "\t\t\tActivating LVM vg \"#{vg}\"."
	`/sbin/vgchange -a y #{vg}`
end

def lvcreate(vg, lv)
	puts "\t\tCreating LVM lv \"#{lv}\" at #{vg}..."
	if lv == 'swap'
		lv_error = `/sbin/lvcreate -L #{guess_swap_size/1024}k -n #{lv} #{vg}`
	else
		lv_error = `/sbin/lvcreate -L #{guess_lv_size(lv)/1024}k -n #{lv} #{vg}`
	end
	if check_lv(vg, lv)
		puts "\t\t\tLVM lv #{lv} created at #{vg} - OK."
	else
		raise "Can't create lv \"#{lv}\" at #{vg}: #{lv_error}"
	end
end

def check_pv(partitions_list)
	pv = false
	partition = (partitions_list.split(' '))[0]
	`/sbin/pvdisplay`.each_line{|line|
		if line.index('PV Name') && line.index(partition)
			pv = true
		end
	}
	pv
end

def check_vg(vg)
	vg_s = false
	`/sbin/vgdisplay`.each_line{|line|
		if line.index('VG Name') && line.index(vg)
			vg_s = true
		end
	}
	vg_s
end

def check_lv(vg, lv)
	lv_s = false
	`/sbin/lvdisplay #{vg}`.each_line{|line|
		if line.index('LV Name') && line.index(lv)
			lv_s = true
		end
	}
	lv_s
end

def guess_lv_size(lv)
	lv_img_file = "#{$net_mount_dir}/#{$backup_files[lv]}"
	if File.extname(lv_img_file) == '.gz'
		puts "\t\t\tDetermining the size of image file archived in #{lv_img_file},\n\t\t\tit can take anywhere from 5 minutes to an hour, depending on the size of the original image."
		lv_size = `/usr/bin/zcat #{lv_img_file} |/usr/bin/wc -c`
	else
		lv_size = File.size?(lv_img_file)
	end
	raise "Can't get file #{lv_img_file} size" if lv_size == nil
	lv_size.to_i
end

def guess_swap_size
	swap = nil
	IO.read('/proc/meminfo').each_line{|line|
		if line.index('MemTotal:')
			swap = ((line.split(' '))[1]).to_i*512
		end
	}
	if swap == nil
		print "Can't guess swap size. Enter it manually in Mb: "
		swap = $stdin.gets.chomp
		swap = swap.to_i*1024*1024
	end
	swap
end

def parse_lvm(path)
	puts "\t\tGetting LVM structure for #{path}..."
	splited_path = path.split('/')
	vg = splited_path[2]
	lv = splited_path[3]
	puts "\t\t\tvg = #{vg}; lv = #{lv}."
	return vg, lv
end

def partition_size?(partition)
	size = nil
	partition_info = `/sbin/fdisk -l #{partition} 2>/dev/null`
	partition_info.each_line{|line|
		if line.index("#{partition}:")
			line_splitted = line.split(" ")
			size = "#{line_splitted[2]} #{line_splitted[3].delete!(",")}"
		end
	}
	size
end

def build_table_of_partitions(part_list)
	table = get_name_and_type(part_list)
		puts "\tNon-boot partitions list:"
	puts "\t\tPartition\tType\tSize\n\t\t--------------------------------------"
	table.each{|key, value|
		puts "\t\t#{key}\t#{value}\t#{partition_size?(key)}"
	}
	puts
	table
end

def parse_grub_menu(fs_root)
	root = nil
	swap = nil
	grub_menu = "#{fs_root}/grub/menu.lst"
	puts "\tGetting information from #{grub_menu}..."
	if File.exist?(grub_menu)
		IO.read(grub_menu).each_line{|line|
			if line.index('kernel')
				(line.split(" ")).each{|param|
					if param.index('root=')
						root = (param.split('='))[1]
					elsif param.index('resume=')
						swap = (param.split('='))[1]
					end
				}
			end
		}
	else
		raise "Can't find #{grub_menu}"
	end
	puts "\t\t\Found: \"root\" is #{root}."
	puts "\t\tFound: \"swap\" is #{swap}."
	return root, swap
end

def get_name_and_type(part_list)
	part_types = Hash.new
	part_list.each{|partition|
		part_info = partition.split(" ")
		part_types[part_info[0]] = part_info[part_info.length - 1]
	}
	part_types
end

def list_other_partitions(hdd)
	rested_part_list = []
	partition_list = `/sbin/fdisk -l #{hdd}`
	partition_list.each_line{|line|
		if line.index(/#{hdd}[0-9]/) && line.index($boot_partition) == nil
			rested_part_list.push(line)
		end
	}
	rested_part_list
end

def fix_devicemap(partition, hdd)
	check_dev_res  = check_devicemap(partition, hdd)
	if check_dev_res[0]
		puts "\t\"device.map\" file - OK."
	else
		devicemap_file = check_dev_res[1]
		print_f "\tFixing \"device.map\" file - "
		begin
			info = IO.read(devicemap_file)
			File.open(devicemap_file, 'w'){|file|
				info.each_line{|line|
					line = "#{line[0..line.index('/dev') - 1]}#{hdd}" if line.index('hd0')
					file.puts(line)
				}
			}
		rescue
			puts "\t\t#{devicemap_file} file open error: #{$!}"
		end
		check_devicemap(partition, hdd)[0] ? (puts 'OK') : (puts 'Failed')
	end
end

def fix_fstab(partition, boot_part)
	check_fstab_res = check_fstab(partition, boot_part)
	if check_fstab_res[0]
		puts "\t\"fstab\" file - OK."
	else
		fstab_file = check_fstab_res[1]
		print_f "\tFixing \"fstab\" file - "
		begin
			found = false
			info = IO.read(fstab_file)
			new_info = Array.new
			info.each_line{|line|
				if line.index('/boot')
					line = line.split(' ')
					line[0] = boot_part
					line = line.join("\t")
					found = true
				end
				new_info.push(line)
			}
			if found == false
				info = []
				print_f " Can't find \"/boot\" record at fstab. Setup booting from \"/\" partition. - "
				new_info.each{|line|
					sp_line = line.split(' ')
					if sp_line[1] == '/'
						sp_line[0] = boot_part
						line = sp_line.join("\t")
					end
					info.push(line)
				}
			else
				info = new_info
			end
			File.open(fstab_file, 'w'){|file|
				file.puts(info)
			}
		rescue
			puts "\t\t#{fstab_file} file open error: #{$!}"
		end
		check_fstab(partition, boot_part)[0] ? (puts 'OK') : (puts 'Failed')
	end
end

def check_devicemap(partition, hdd)
	result = false
	root_dir = mount_local(partition)
	device_map = "#{root_dir}/grub/device.map"
	result = true if (IO.read(device_map)).index(hdd)
	return result, device_map
end

def check_fstab(partition, boot_part)
	result = false
	root_dir = mount_local(partition)
	fstab_file = "#{root_dir}/etc/fstab"
	result = true if (IO.read(fstab_file)).index(boot_part)
	return result, fstab_file
end

def build_table_of_all_hdd
	proc_partitions = IO.read('/proc/partitions')
	proc_devices = IO.read('/proc/devices')
	table = Array.new
	proc_partitions.each_line{|partition|
		row = Hash.new
		partition = partition.split(' ')
		if partition[3] && partition[3].index(/\A(s|h)d[a-z]\z/)
			row['name'] = partition[3]
			dev_num = partition[0]
			proc_devices = proc_devices[proc_devices.index('Block devices:')..proc_devices.length]
			proc_devices.each_line{|device|
				device = device.split(' ')
				if device[0] == dev_num
					row['controller'] = device[1]
				end
			}
			size_file = "/sys/block/#{row['name']}/size"
			block_size_file = "/sys/block/#{row['name']}/queue/hw_sector_size"
			model_file = "/sys/block/#{row['name']}/device/model"
			serial_file = "/sys/block/#{row['name']}/device/serial"
			#firmware_file = "/sys/block/#{row['name']}/device/firmware"
			File.exist?(block_size_file) ? (block_size = (IO.read(block_size_file).chomp).to_f) : (block_size = 512)
			row['size'] = (IO.read(size_file).chomp).to_f * block_size if File.exist?(size_file)
			row['model'] = IO.read(model_file).chomp if File.exist?(model_file)
			row['serial'] = IO.read(serial_file).chomp if File.exist?(serial_file)
			#row['firmware'] = IO.read(firmware_file).chomp if File.exist?(firmware_file)
		end
		table.push(row) if row.length != 0
	}
	# too long string for screen resolution with Firmware
	puts "\tDevice\t\tSize\tController\tModel\t\tSerial"#\t\tFirmware"
	puts "\t-------------------------------------------------------------------------"
	table.each{|row|
		puts "\t/dev/#{row['name']}\t#{format_size(row['size'])}\t#{row['controller']}\t\t#{row['model']}\t#{row['serial']}"#\t\t#{row['firmware']}"
	}
end

def format_size(bytes_size)
	fromated_size = nil
	if bytes_size != nil
		units = ['b', 'Kb', 'Mb', 'Gb', 'Tb']
		index = 0
		size = bytes_size
		until (size / 1024) <= 1
			index += 1
			size = size / 1024
		end
		fromated_size = "#{size.round} #{units[index]}"
	end
	fromated_size
end
#### PROGRAM ###################################################################
begin
	menu_return = menu
	answer = menu_return[2]
	do_action_result = do_action(answer)
	raise do_action_result[1] if do_action_result[0] != 0
rescue
	$last_error = $!
	retry
end