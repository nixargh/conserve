class Backup
	attr_accessor :log, :mount_point, :credential_file, :archive, :mbr, :plain, :lvm
	include Add_functions
	
	def initialize(source, destination)
		@destination = destination
		@source = source
		@share_type = 'smb'
		@mounted = Hash.new
		@mount_point = '/mnt'
		@credential_file = '/root/credential'
		@mount_dir = []
		@archive = false
		@lvm = nil
		@source_is_blockdev = false
		@mbr = nil
		@plain = false
	end
	
	def clean!
		@log.write("\t\tCleaning after Backup:", 'yellow')
		@mounted.each_value{|directory|
			umount!(directory)
		}
		@mount_dir.each{|directory|
			Dir.unlink(directory)
		}
		@lvm.clean! if @lvm
	end

	def create!
		begin
			@log.write("Backup started - #{Time.now.asctime}")

			dest_path, dest_type = parse_and_mount(@destination)
			source_files = parse_source(@source)

			raise "Can't backup multiple sources to one destination file." if source_files.length > 1 && dest_type == 'file'

			source_files.each{|source_file|
				@log.write("\tBackup of #{source_file}:", 'yellow')
				destination_file = create_destination(dest_path, dest_type, source_file)

				if File.blockdev?(source_file)
				# do block device backup
					@log.write("\t\tSource (#{source_file}) is a block device.", 'yellow')
					if @mbr == true
						@log.write("\t\tBackup MBR from #{source_file} selected.", 'yellow')
						backup_mbr(source_file, destination_file)
					else
					# do image of snapshot or raw partition
						if @lvm
							# do snapshot
							source_file = do_snapshot(source_file)
						end
						make_image!(source_file, destination_file)
					end					
				else
				# do files backup copy
					if @lvm
						device, mount_point = guess_file_volume(source_file)
						@log.write("\t\tFound block device \"#{device}\" for source file(s): #{source_file}.")
						device = do_snapshot(device)
						new_mount_point = mount(device, 'local')
						if (new_source_file = find_symlink(source_file))
							source_file = new_source_file
						end
						if mount_point == '/'
							source_file = "#{new_mount_point}#{source_file}"
						else
							source_file.gsub!(/\A#{mount_point}/, new_mount_point)
						end
					end	
					if @plain
						create_file_copy!(source_file, destination_file)
					else
						create_archive!(source_file, destination_file)
					end
				end
			}
			
		rescue
			raise $!
		ensure
			clean!
		end
	end

###########
	private
###########

	def parse_source(source)
		source_files = Array.new
		source.split(',').each{|source|
			source.strip!
			if source
				if source[-1, 1] == '*'
					top_dir = File.dirname(source)
					raise "Uncorrect path #{source}, #{top_dir} isn't a directory." if !File.directory?(top_dir)
					Dir.entries(top_dir).each{|file|
						if file != '.' && file !='..'
							file = "#{top_dir}/#{file}"
							source_files.push(get_source(file))
						end
					}
				else
					source_files.push(get_source(source))
				end
			end
		}
		source_files
	end

	def get_source(source)
		if File.blockdev?(source)
			source_file = source
		else
			src_path, src_type = parse_and_mount(source)
			source_file = src_path
		end
		source_file
	end

	def create_destination(dest_path, dest_type, source_path)
		destination_file = nil
		if dest_type == 'file'
			destination_file = dest_path
		elsif dest_type == 'dir'
			destination_file = "#{dest_path}/#{File.basename(source_path)}"
		end
		destination_file
	end

	def parse_and_mount(path) # parse path, convert to usefull format and return new path + type of destination: file or directory
		begin
			raise "path is \"nil\"" if !path
			server, directory, file = parse_path(path)
			if server
				remote_directory = "//#{server}#{directory}"
				mount_point = mount(remote_directory, 'smb')
				path  = "#{mount_point}/#{file}"
				type = File.directory?(path) ? 'dir' : 'file'
			else
				if file
					path = "#{directory}/#{file}"
					type = 'file'
				else
					path = directory
					type = 'dir'
				end
			end
			path.chop! if path[-1] == '/'
			return path, type
		rescue
			raise "parse_and_mount error: #{$!}"
		end
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
		@log.write_noel("\t\t\tUnmounting #{mount_point}. - ")
		info, error = runcmd("umount -v #{mount_point}")
		if info && !error
			@log.write('[OK]', 'green')
		else
			@log.write('[FAILED}', 'red')
			@log.write("\t\t\t\t#{error}", 'yellow')
		end
	end

	def do_snapshot(lvm_lv) # do snapshot of LVM Logical Volume
		lvm_lv_snapshot = nil
		@log.write("\t\tUsing LVM (by default):", 'yellow')
		#lvm_lv_snapshot = "#{lvm_lv}_backup"
		#if @lvm.snapshots_created.index(lvm_lv_snapshot) && File.exist?(lvm_lv_snapshot)
		#	@log.write("\t\tSnapshot of #{lvm_lv} named #{lvm_lv_snapshot} exist.")
		#else
			@log.write_noel("\t\t\tCreating snapshot of #{lvm_lv} - ") 
			create_snapshot_result = @lvm.create_snapshot(lvm_lv)
			if create_snapshot_result[0] == 0
				@log.write('[OK]', 'green')
				lvm_lv_snapshot = create_snapshot_result[2]
			else
				@log.write('[FAILED]', 'red')
				raise "Snapshot creation failed with: #{create_snapshot_result[1]}"
			end
		#end
		lvm_lv_snapshot
	end
	
	def get_device_size(device) # get size of block device
		size = `blockdev --getsize64 #{device}`.strip.to_i
	end

	def backup_mbr(source_device, destination_file) # backups Master Boot Record of block device
		if File.blockdev?(source_device)
			@log.write_noel("\t\tRunning MBR backup of #{source_device} to #{destination_file}, please wait... - ")
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


	def get_image_file_size(file) # get size of created image file (and inside gzip archive)
		image_size = nil
		if File.extname(file) == '.gz'
			begin
				#puts "\t\tDetermining the size of image file archived in #{file},\n\t\tit can take anywhere from 5 minutes to an hour, depending on the size of the original image."
				zcat_log = "/tmp/zcat_#{rand(100)}.log"
				image_size = `zcat #{file} 2>#{zcat_log} |wc -c`
				zcat_error = IO.read(zcat_log)
				if !zcat_error.empty?
				puts zcat_error
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
			@log.write("\t\tImage creation:", 'yellow')
			info = create_image(partition, path)
			if info && info.index("copied")
				@log.write('[OK]', 'green')
				check_image!(partition, path)
			else
				info ? (raise info) : (raise "No image creation info was returned.")
			end
		rescue
			@log.write("[FAILED]", 'red')
			raise "Image creation failed: #{$!}."
		end
	end

	def create_image(partition, path) # creates image of partition or HDD
		begin
			block_size = @lvm ? @lvm.lvm_block_size : 4
			dd_log = "/tmp/dd_#{rand(100)}.log"
			if @archive
				path = "#{path}.gz"
				@log.write_noel("\t\t\tCreating gziped image of #{partition} to #{path} - ")
				`dd if=#{partition} bs=#{block_size}M 2>#{dd_log} | gzip > #{path}`
			else
				@log.write_noel("\t\t\tCreating image of #{partition} to #{path} - ")
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
			@log.write_noel("\t\t\tChecking image (#{path}) of #{partition} - ")
			size = nil
			partition_size = get_device_size(partition)
			image_size = get_image_file_size(path)
			if partition_size == image_size
				@log.write('[OK]', 'green')
				@log.write_noel("\t\t\tSource size: #{format_size(partition_size)}; Image size: #{format_size(image_size)}")
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
	
	def mount(what, type, where = @mount_point)
		if @mounted[what]
			path = @mounted[what]
			@log.write("\t\t\tDevice #{what} already mounted at #{path}.")
		else
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
		end
		path
	end	

	def mount_smb(what, where, type) # mounts smb or cifs share
		raise "You need to install \"mount.cifs\" (\"cifs-utils\" package on Ubuntu, \"cifs-mount\" on SLES) to mount SMB shares" if !File.exist?(`which 'mount.cifs'`.chomp)
		@log.write_noel("\t\t\tMounting SMB share: ")
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
		@log.write_noel("\t\t\tMounting local disk: ")
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
			@mounted[what] = mount_dir
			if error
				@log.write("#{what} NOT mounted to #{mount_dir} - ")
				@log.write("[FAILED]", 'red')
				raise error
			elsif info && !error
				@log.write_noel("#{what} mounted to #{mount_dir} with warnings: #{info}. - ")
				@log.write("[OK]", 'green')
			else
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
			@log.write("\t\t\tCredential file \"#{@credential_file}\" not found. Let's create it...", 'yellow', true)
			status = 0
			error = nil
			@log.write("\t\t\t\tEnter username to access shared resource: ", 'sky_blue', true)
			username = $stdin.gets.chomp
			@log.write("\t\t\t\tEnter password: ", 'sky_blue', true)
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

	def create_file_copy!(source_file, destination_file)
		@log.write_noel("\t\tRunning copy of #{source_file} to #{destination_file} - ")
		begin
			FileUtils.copy_entry(source_file, destination_file, preserve = true, remove_destination = true)
# It's coreutils variation of the same copy
#		info, error = runcmd("cp -rf #{source_file} #{destination_file}")
#		if !error
#			@log.write('[OK]', 'green')
#		else	
#			@log.write('[FAILED]', 'red')
#			raise "Files copy failed: #{error}."
#		end
			if File.exist?(destination_file)
				@log.write('[OK]', 'green')
			else	
				raise "Destination file #{destination_file} not found."
			end
		rescue
			@log.write('[FAILED]', 'red')
			raise "Files copy failed: #{$!}."
		end
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
			@log.write_noel("\t\tRunning tar#{ arc_arg ? ' and gzip' : ''} of #{source_file} to #{destination_file} - ")
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
