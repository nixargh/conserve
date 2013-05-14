class Backup
	attr_accessor :log, :source, :destination, :share_type, :use_lvm, :mount_point, :credential_file, :archive, :mbr
	include Add_functions
	
	def initialize(source, destination)
		@destination = destination
		@source = source
		@share_type = 'smb'
		@mounted = []
		@use_lvm = true
		@mount_point = '/mnt'
		@credential_file = '/root/credential'
		@mount_dir = []
		@archive = false
		@lvm = nil
		@source_is_blockdev = false
		@mbr = nil
	end
	
	def clean!
		@log.write("\tCleaning after Backup:", 'yellow')
		@mounted.each{|share|
			umount!(share)
		}
		@mount_dir.each{|directory|
			Dir.unlink(directory)
		}
		@lvm.clean! if @lvm
	end

	def create!
		begin
			@log.write("Backup started - #{Time.now.asctime}")
			destination_parse = parse_and_mount(@destination)
			@source_is_blockdev = true if File.blockdev?(@source)
			source_parse = parse_and_mount(@source)
			destination_parse[0] == 0 ? destination_file = destination_parse[2] : (raise "\"parse_and_mount\" destination error: #{destination_parse[1]}")
			source_parse[0] == 0 ? source_file = source_parse[2] : (raise "\"parse_and_mount\" source error: #{source_parse[1]}")
			
			if File.blockdev?(source_file)
			# do block device backup
				if @mbr == true
					@log.write("\tBackup MBR from #{source_file} selected.", 'yellow')
					backup_mbr(source_file, destination_file)
				else
				# do image of snapshot or raw partition
					@log.write("\tSource (#{source_file}) is a block device.")
					if @use_lvm == true
						# do snapshot
						source_file = do_snapshot(source_file)
					end
					make_image!(source_file, destination_file)
				end					
			else
			# do files backup copy
				@log.write("\tSource (#{source_file}) isn't a block device.")
				if @use_lvm == true
					device, mount_point = guess_file_volume(source_file)
					@log.write("\t\tFound block device \"#{device}\" for source file(s): #{source_file}.")
					device = do_snapshot(device)
					new_mount_point = parse_and_mount(device)[2]
					if (new_source_file = find_symlink(source_file))
						source_file = new_source_file
					end
					if mount_point == '/'
						source_file = "#{new_mount_point}#{source_file}"
					else
						source_file.gsub!(/\A#{mount_point}/, new_mount_point)
					end
				end	
				create_archive!(source_file, destination_file)
			end
		rescue
			raise $!
		ensure
			clean!
		end
	end

###########
	private
###########
	def find_symlink(file)
		path = String.new
		symlink = nil
		file.split('/').each{|part|
			if !part.empty?
				path = "#{path}/#{part}"
				symlink = "#{symlink}/#{part}" if symlink
				symlink = File.readlink(path) if File.symlink?(path)
			end
		}
		symlink
	end

	def umount!(mount_point) # unmounting mount point in verbose mode
		@log.write_noel("\t\tUnmounting #{mount_point}. - ")
		info, error = runcmd("umount -v #{mount_point}")
		if info && !error
			@log.write('[OK]', 'green')
		else
			@log.write('[FAILED}', 'red')
			@log.write("\t\t\t#{error}", 'yellow')
		end
	end

	def do_snapshot(lvm_lv) # do snapshot of LVM Logical Volume
		lvm_lv_snapshot = nil
		@log.write("\tUsing LVM (by default):", 'yellow')
		@lvm = LVM_operate.new
		@lvm.log = @log
		@log.write_noel("\t\tCreating snapshot of #{lvm_lv} - ") 
		create_snapshot_result = @lvm.create_snapshot(lvm_lv)
		if create_snapshot_result[0] == 0
			@log.write('[OK]', 'green')
			lvm_lv_snapshot = create_snapshot_result[2]
		else
			@log.write('[FAILED]', 'red')
			raise "Snapshot creation failed with: #{create_snapshot_result[1]}"
		end
		lvm_lv_snapshot
	end
	
	def get_device_size(device) # get size of block device
		size = `blockdev --getsize64 #{device}`.strip.to_i
	end

	def backup_mbr(source_device, destination_file) # backups Master Boot Record of block device
		if File.blockdev?(source_device)
			@log.write_noel("\tRunning MBR backup of #{source_device} to #{destination_file}, please wait... - ")
			`dd if=#{source_device} of=#{destination_file} bs=512 count=1 1>/dev/null 2>/dev/null`
			if File.exist?(destination_file)
				@log.write('[OK]', 'green')
			else
				@log.write('[FAILED]', 'red')
				raise "MBR backup destination file \"#{destination_file}\" not found"
			end
		else
			raise "Can't backup MBR: #{source_device} isn't a block device"
		end
	end

	def parse_and_mount(path) # return right file path
		begin
			raise "path is \"nil\"" if !path
			status = 0
			error = nil
			server, directory, file = parse_path(path)
			if server
			# server name or ip found on path argument
				remote_directory = "//#{server}#{directory}"
				mount_point = mount(remote_directory, @mount_point, 'smb')
				new_file = "#{mount_point}/#{file}"
				raise "#{new_file} is a directory. You need to point destination file (-d) not a directory" if File.directory?(new_file)
			else
				if File.blockdev?("#{directory}/#{file}") && check_mounted("#{directory}/#{file}")[0] == 1 && !@source_is_blockdev
						# block device not mounted and --source wasn't block device
						device = "#{directory}/#{file}"
						new_file = mount(device, @mount_point, 'local')
				else
					mount_result = [0, nil]
					new_file = "#{directory}/#{file}"
				end
			end
			#raise "Can't mount device or network share: #{mount_result[1]}" if mount_result[0] != 0
		rescue
			status = 1
			error = $!
		end
		@source_is_blockdev = false
		result = [status, error, new_file]
	end

	def parse_path(path) # divide path to file on server part and path part etc
		server, directory, file = nil, nil, nil
		path.gsub!('\\', '/')
		if path.index('|')
			path = path.split('|')
			server = path[0]
			file = File.basename(path[1])
			directory = File.dirname(path[1])
		else
			if File.directory?(path)
				directory = path
			elsif File.directory?(File.dirname(path))
				directory = File.dirname(path)
				file = File.basename(path)
			else
				raise "path \"#{path}\" not found."
			end
		end
		return server, directory, file
	end

	def get_image_file_size(file) # get size of created image file (and inside gzip archive)
		image_size = nil
		if File.extname(file) == '.gz'
			begin
				#puts "\t\tDetermining the size of image file archived in #{file},\n\t\tit can take anywhere from 5 minutes to an hour, depending on the size of the original image."
				zcat_log = "/tmp/zcat_#{rand(100)}.log"
				image_size = `zcat #{file} 2>#{zcat_log} |wc -c`
				zcat_error = IO.read(zcat_log)
				if !zcat_error.empty?
					@log.write(zcat_error)
					raise "\"#{file}\" archive was corrupted"
				end
				image_size = image_size.chomp.to_i
			ensure
				File.unlink(zcat_log)
			end
		else
			image_size = File.size?(file)
		end
		image_size # size in bytes
	end
	
	def make_image!(partition, path) # creates and checks image of some partition or HDD
		begin
			@log.write("\tImage creation:", 'yellow')
			info = create_image(partition, path)
			if info && info.index("copied")
				@log.write('[OK]', 'green')
				check_image!(partition, path)
			else
				info ? (raise info) : (raise "No image creation info was returned.")
			end
		rescue
			#@log.write("[FAILED]", 'red')
			raise "Image creation failed: #{$!}."
		end
	end

	def create_image(partition, path) # creates image of partition or HDD
		begin
			@log.write_noel("\t\tCreating image of #{partition} - ")
			block_size = @lvm ? @lvm.lvm_block_size : 4
			dd_log = "/tmp/dd_#{rand(100)}.log"
			if @archive
				path = "#{path}.gz"
				`dd if=#{partition} bs=#{block_size}M 2>#{dd_log} | gzip > #{path}`
			else
				`dd if=#{partition} of=#{path} bs=#{block_size}M 2>#{dd_log}`
			end
			return IO.read(dd_log)
		rescue
			return nil
		ensure
			File.unlink(dd_log)
		end
	end

	def check_image!(partition, path) # checks that image was create successfully
		begin
			path = "#{path}.gz" if @archive
			@log.write_noel("\t\tChecking image (#{path}) of #{partition} - ")
			size = nil
			partition_size = get_device_size(partition)
			image_size = get_image_file_size(path)
			if partition_size == image_size
				@log.write('[OK]', 'green')
				@log.write_noel("\t\tSource size: #{format_size(partition_size)}; Image size: #{format_size(image_size)}")
				@archive ? (@log.write("; Archived image size: #{format_size(File.size?(path))}.")) : @log.write(".")
			else
				raise "image file size not equal to partition size: #{image_size} != #{partition_size}"
			end
		rescue
			@log.write("[FAILED]", 'red')
			raise "Image check failed: #{$!.backtrace}."
		end
	end
	
	def guess_file_volume(file) # detect partition where file stored
		raise "file #{file} not found" if !File.exist?(file)
		info, error = runcmd("df -T \"#{file}\"")
		raise error if error
		info = s_to_a(info)
		raise "more than 1 file found: #{info}" if info.length > 2
		device, a, b, c, d, e, mount_point = info[1].split(' ')
		return device, mount_point
	end
	
	def create_random_dir(where) # creates random directories inside directory specified at --where argument
		begin
			status = 0
			mount_dir = "#{where}/bak#{rand(1000000)}"
			raise "Can't create directory #{mount_dir}." if Dir.mkdir(mount_dir) != 0
			@mount_dir.push(mount_dir)
		rescue
			status = 1
			error = $!
		end
		result = [status, error, mount_dir]
	end
	
	def mount(what, where, type)
		if File.directory?(where)
			if type == 'smb'
				path = mount_smb(what, where, type)
			elsif type == 'local'
				path = mount_local(what, where, type)
			else
				raise "Can't work with that mount type: #{type}"
			end
		else
			raise "root mount directory \"#{where}\" not found or not a directory"
		end
		path
	end	

	def mount_smb(what, where, type) # mounts smb or cifs share
		raise "You need to install \"mount.cifs\" (\"cifs-utils\" package on Ubuntu, \"cifs-mount\" on SLES) to mount SMB shares" if !File.exist?(`which 'mount.cifs'`.chomp)
		@log.write_noel("\tMounting SMB share: ")
		server = (what.split("/"))[2]
		if check_online(server)[0] == 0
			random_dir = create_random_dir(where)
			random_dir[0] == 0 ? mount_dir = random_dir[2] : (raise "Can't create random directory: #{random_dir[1]}")
			create_cred_file if File.exist?(@credential_file) == false
			mount_stat = runcmd("mount -t cifs #{what} #{mount_dir} -o credentials=#{@credential_file}")
			mount_check = check_mount_stat(mount_stat, what, mount_dir)
			mount_check[0] == 0 ? (path = mount_dir) : (raise mount_check[1])
			test_file = "#{path}/test_file"
			begin
				File.open(test_file, 'w'){|file|
					file.puts('test')
				}
				File.unlink(test_file)
			rescue
				raise "Can't create file at mounted share \"#{what}\". Perhaps \"#{File.basename(what)}\" directory doesn't exist."
			end
		else
			raise "#{what[0]} isn't online."
		end
		path
	end

	def mount_local(what, where, type)
		@log.write_noel("\tMounting local disk: ")
		random_dir = create_random_dir(where)
		random_dir[0] == 0 ? mount_dir = random_dir[2] : (raise "Can't create random directory: #{random_dir[1]}")
		mount_stat = runcmd("mount #{what} #{mount_dir}")
		mount_check = check_mount_stat(mount_stat, what, mount_dir)
		mount_check[0] == 0 ? (path = mount_dir) : (raise mount_check[1])
		path
	end
	
	def check_mount_stat(mount_stat, what, mount_dir)
		begin
			info, error = mount_stat
			status = 0
			if error
				@log.write("#{what} NOT mounted to #{mount_dir} - ")
				@log.write("[FAILED]", 'red')
				raise error
			elsif info && !error
				@mounted.push(mount_dir)
				@log.write_noel("#{what} mounted to #{mount_dir} with warnings: #{info}. - ")
				@log.write("[OK]", 'green')
			else
				@mounted.push(mount_dir)
				@log.write_noel("#{what} mounted to #{mount_dir}. - ")
				@log.write("[OK]", 'green')
			end
		rescue
			status = 1
			error = $!
		end
		result = [status, error]
	end

	def check_online(server)
		begin
			if server == nil
				raise 'Nothing to check, because "server" is nil.'
			end
			response = `ping -c 1 #{server} 2>/dev/null`
			online = response.split('packets transmitted, ')[1].split(' received')[0].to_i
			if online == 1
				status = 0
				error = nil
			elsif online ==0 
				status = 1
				error = "Ping of #{server} failed."
			else
				status = 2
				error = 'Undefined number of pings...'
			end
		rescue
			status = 1
			error = $!
		end
		result = [status, error]
	end
	
	def check_mounted(device)
		begin
			status = 0
			mounted = false
			mtab_list = `cat /etc/mtab`
			mtab_list.each_line{|line|
				mounted_device = line.split(" ")[0]
				if mounted_device.index(device)
					mounted = true
				else
					if mounted_device.index("mapper")
						splited_volume = mounted_device.split("/")
						volume_length = splited_volume.length
						lvm_data = splited_volume[volume_length - 1].split("-")
						volume = "/dev/#{lvm_data[0]}/#{lvm_data[1]}"
						mounted = true if volume.index(device)
					end
				end	
			}
			raise "#{device} not mounted" if !mounted
		rescue
			status = 1
			error = $!
		end
		result = [status, error]
	end
	
	def where_mounted?(partition)
		partition = File.readlink(partition) if File.symlink?(partition)
		partition = partition.gsub('..','/dev')
		root = nil
		IO.read('/etc/mtab').each_line{|line|
			line.chomp!
			line = line.split(" ")
			root = line[1] if line[0] == partition
			#puts "partition = #{partition}\t\tline[0] = #{line[0]}\t\tline[1] = #{line[1]}\t\troot = #{root}\n"
		}
		root ? root : (raise "Can't find where #{partition} mounted")
	end
	
	def create_cred_file
		begin
			@log.write("\t\tCredential file \"#{@credential_file}\" not found. Let's create it...", 'yellow', true)
			status = 0
			error = nil
			@log.write("\t\t\tEnter username to access shared resource: ", 'sky_blue', true)
			username = $stdin.gets.chomp
			@log.write("\t\t\tEnter password: ", 'sky_blue', true)
			system "stty -echo"
			password = $stdin.gets.chomp
			system "stty echo"
			if File.directory?(File.dirname(@credential_file))
				File.open(@credential_file, "w"){ |openfile|
					openfile.puts "username=#{username}"
					openfile.puts "password=#{password}"
				}
			else
				raise "Can't access #{File.dirname(@credential_file)} directory"
			end
		rescue
			status = 1
			error = $!
		ensure
			system "stty echo"
		end
		result = [status, error]
	end

	def create_archive!(source_file, destination_file) # do tar and gzip if needed
		begin
			if @archive
				destination_file = "#{destination_file}.tar.gz"
				arc_arg = 'z'
			else
				destination_file = "#{destination_file}.tar"
				arc_arg = nil
			end
			@log.write_noel("\tRunning tar#{ arc_arg ? ' and gzip' : ''} of #{source_file} to #{destination_file} - ")
			cmd = "tar -c#{arc_arg}f \"#{destination_file}\" \"#{source_file}\""
			info, error = runcmd(cmd)
			
			error_a = Array.new
			error.each_line{|line|
				line.chomp!
				if !line.index("tar: Removing leading `/\' from")
					error_a.push(line)
				end
			}
			raise "tar created with error(s): #{error_a}" if !error_a.empty? && File.exist?(destination_file)
			@log.write('[OK]', 'green')
		rescue
			@log.write('[FAILED]', 'red')
			raise "tar creation failed: #{$!}."
		end
	end
end
