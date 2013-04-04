class Backup
	attr_accessor :source, :destination, :share_type, :use_lvm, :mount_point, :credential_file, :archive, :mbr
	
	def initialize(source, destination)
		@destination = destination
		@source = source
		@share_type = 'smb'
		@mounted = []
		@use_lvm = true
		@mount_point = '/mnt'
		@credential_file = '/root/credential'
		@log = $log
		@mount_dir = []
		@archive = false
		@lvm = nil
		@source_is_blockdev = false
		@mbr = nil
	end
	
	def ensure
		@mounted.each{|share|
			`umount #{share}`
			@log.write("\tUnmounting #{share}. - [ #{green('OK')} ]")
		}
		@mount_dir.each{|directory|
			Dir.unlink(directory)
		}
		@lvm.ensure if @lvm
	end

	def create
		begin
			@log.write("")
			@log.write("Backup started - #{Time.now.asctime}")
			destination_parse = parse_and_mount(@destination)
			@source_is_blockdev = true if File.blockdev?(@source)
			source_parse = parse_and_mount(@source)
			destination_parse[0] == 0 ? destination_file = destination_parse[2] : (raise "\"parse_and_mount\" destination error: #{destination_parse[1]}")
			source_parse[0] == 0 ? source_file = source_parse[2] : (raise "\"parse_and_mount\" source error: #{source_parse[1]}")
			
			if File.blockdev?(source_file)
				if @mbr == true
					@log.write(yellow("\tBackup MBR from #{source_file} selected."))
					backup_mbr(source_file, destination_file)
				else
				# делаем образ со снепшота или просто с раздела
					@log.write("\tSource (#{source_file}) is a block device.")
					if @use_lvm == true
					# делаем снепшот
						@log.write(yellow("\tUse LVM selected by default."))
						@lvm = LVM_operate.new
						create_snapshot_result = @lvm.create_snapshot(source_file)
						if create_snapshot_result[0] == 0
							@log.write("\t\tSnapshot of #{source_file} created. - [ #{green('OK')} ]")
							source_file = create_snapshot_result[2]
						else
							raise "Snapshot creation failed with: #{create_snapshot_result[1]}"
						end
					end
					make_image(source_file, destination_file)
				end					
			else
			# бэкап копированием
				@log.write("\tSource (#{source_file}) isn't a block device.")
				if @use_lvm == true
				# делаем снепшот lvm
					@log.write(yellow("\tUse LVM selected by default.")) 
					volume = guess_file_volume(source_file)
					if volume[0] == 0
						@log.write("\t\tFound block device \"#{volume[2]}\" for source file(s): #{source_file}.")
						@lvm = LVM_operate.new
						create_snapshot_result = @lvm.create_snapshot(volume[2])
						if create_snapshot_result[0] == 0
							@log.write("\t\tSnapshot of #{volume[2]} created. - [ #{green('OK')} ]")
							source_vol = create_snapshot_result[2]
							mount_result = parse_and_mount(source_vol)
							if mount_result[0] = 0
								@log.write_noel("\t\t\tTrying to find #{source_file} on #{mount_result[2]}... - ")
								$stdout.flush								
								source_file = mount_result[2] + source_file.gsub(where_mounted?(volume[2]), '')
								if File.exist?(source_file)
									@log.write("[ #{green('OK')} ]")
								else
									@log.write("[ #{red('FAILED')} ]")
									raise "Can't find #{source_file}"
								end
							else
								raise "Can't mount #{source_vol}: #{mount_result[1]}"
							end
						else
							raise "Snapshot creation failed with: #{create_snapshot_result[1]}"
						end
					else
						raise "Can't find block device for file #{source_file}."
					end		
				end	
				# тарим и сжимаем если требуется
				@log.write_noel("\tRunning tar of #{source_file} to #{destination_file}, please wait... - ")
				tar_result = tar_create(source_file,destination_file)
				if tar_result[0] == 0
					@log.write("[ #{green('OK')} ]")
				else
					@log.write("[ #{red('FAILED')} ]")
					raise tar_result[1]
				end
			end
		rescue
			raise (red("\t*** ") + yellow(error = $!) + red(' ***'))
		end
	end

###########
	private
###########
	def get_partition_size(device)
		size = nil
		info = `fdisk -l #{device} 2>/dev/null`
		info.each_line{|line|
			if line.index(device)
				line = line.split(' ')
				size = line[line.length - 2]
			end
		}
		size.to_i
	end

	def backup_mbr(source_device, destination_file)
		if File.blockdev?(source_device)
			@log.write_noel("\tRunning MBR backup of #{source_device} to #{destination_file}, please wait... - ")
			`dd if=#{source_device} of=#{destination_file} bs=512 count=1 1>/dev/null 2>/dev/null`
			if File.exist?(destination_file)
				@log.write("[ #{green('OK')} ]")
			else
				@log.write("[ #{red('FAILED')} ]")
				raise "MBR backup destination file \"#{destination_file}\" not found"
			end
		else
			raise "Can't backup MBR: #{source_device} isn't a block device"
		end
	end

	def parse_and_mount(path)
		begin
			status = 0
			error = nil
			path = parse_path(path)
			raise "Path error: #{path[1]}" if path[0] == false
			if path[2] # есть в пути имя сервера
				path_new = "//#{path[2]}#{path[3]}"
				mount_result = mount(path_new, @mount_point, 'smb')
				file = "#{mount_result[2]}/#{path[4]}"
				raise "#{file} is a directory. You need to point destination file (-d) not a directory" if File.directory?(file)
			elsif File.blockdev?("#{path[3]}/#{path[4]}") && check_mounted("#{path[3]}/#{path[4]}")[0] == 1 && @source_is_blockdev == false
			# блоковое устройство и не примаунчено + изначально как --source выбиралось не блоковое устройство
				path_new = "#{path[3]}/#{path[4]}"
				mount_result = mount(path_new, @mount_point, 'local')
				file = mount_result[2]
			else # нет в пути имени сервера
				mount_result = [0,nil]
				file = "#{path[3]}/#{path[4]}"
			end
			# Тут бы нужно проверять наличие файла или папки...
			# raise "Can't find file \"#{file}\"" if File.exist?(file) == false
			raise "Can't mount device or network share: #{mount_result[1]}" if mount_result[0] != 0
			rescue
			status = 1
			error = $!
		end
		@source_is_blockdev = false
		result = [status, error, file]
	end

	def get_image_file_size(file)
		begin
			image_size = nil
			if File.extname(file) == '.gz'
				#puts "\t\tDetermining the size of image file archived in #{file},\n\t\tit can take anywhere from 5 minutes to an hour, depending on the size of the original image."
				zcat_log = '/tmp/zcat.log'
				image_size = `zcat #{file} 2>#{zcat_log} |wc -c`
				raise "\"#{file}\" archive was corrupted" if !IO.read(zcat_log).empty?
				image_size = image_size.chomp.to_i
			else
				image_size = File.size?(file)
			end
			image_size # size in bytes
		ensure
			File.unlink(zcat_log)
		end
	end
	
	def make_image(partition, path)
		begin
			@log.write_noel("\tRunning image creation of #{partition}, please wait... - ")
			size = nil
			@lvm ? (block_size = @lvm.lvm_block_size) : (block_size = 4)
			dd_log = '/tmp/dd.log'
			if archive == false
				`dd if=#{partition} of=#{path} bs=#{block_size}M 2>#{dd_log}`
			else
				path = "#{path}.gz"
				`dd if=#{partition} bs=#{block_size}M 2>#{dd_log} | gzip > #{path}`
			end
			info = IO.read(dd_log)
			if info.index("copied")
				partition_size = get_partition_size(partition)
				image_size = get_image_file_size(path)
				if partition_size == image_size
					@log.write("[ #{green('OK')} ]")
					@log.write_noel("\t\tSource size: #{yellow(format_size(partition_size))}; Image size: #{yellow(format_size(image_size))}")
					archive == true ? (@log.write("; Archived image size: #{yellow(format_size(File.size?(path)))}.")) : @log.write(".")
				else
					@log.write("[ #{red('FAILED')} ]")
					raise "image file size not equal to partition size: #{image_size} != #{partition_size}"
				end
			else
				raise info
			end
		ensure
			File.unlink(dd_log)
		end
	end
	
	def guess_file_volume(file)
		begin
			status = 0
			volume = nil
			file_path = parse_path(file)
			if file_path[0] == 0
				mount_list = IO.read('/etc/mtab')
				mount_list.each_line{|line|
					line = line.split(' ')
					#puts "#{line[0]} - #{line[1]}"
					#puts file_path[3].index(line[1])
					if file_path[3].index(line[1]) && line[1] != '/'
						volume = line[0]
					elsif file_path[3].index(line[1]) && line[1] == '/' && volume == nil

						volume = line[0]
					end
				}
				if volume.index('/dev/mapper/')
					group_volume = (volume.split('/')).last
					volume = group_volume[group_volume.index(/[^-]-[^-]/)+2..group_volume.length]
					group = group_volume[0..group_volume.index(/[^-]-[^-]/)].gsub('--','-')
					volume = "/dev/#{group}/#{volume}"
				end
			else
				raise file_path[1]
			end
		rescue
			status = 1
			error = $!
		end
		result = [status, error, volume]
	end
	
	def create_random_dir(where)
		# создаёт директорию куда монтировать в той что указана в where (т.е. корневая)
		# удаляется в функции ensure
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
		begin
			status = 0
			path = nil
			if File.directory?(where)
				if type == 'smb'
					path = mount_smb(what, where, type)
				elsif type == 'local'
					psth = mount_local(what, where, type)
				else
					raise "Can't work with that mount type: #{type}"
				end
			else
				raise "root mount directory \"#{where}\" not found or not a directory"
			end
		rescue
			status = 1
			error = $!
		end
		result = [status, error, path]
	end	

	def mount_smb(what, where, type)
		raise "You need to install \"mount.cifs\" (\"cifs-utils\" package on Ubuntu, \"cifs-mount\" on SLES) to mount SMB shares" if File.exist?(`which 'mount.cifs'`.chomp) == false
		@log.write("\tMounting SMB share...")
		server = (what.split("/"))[2]
		if check_online(server)[0] == 0
			random_dir = create_random_dir(where)
			random_dir[0] == 0 ? mount_dir = random_dir[2] : (raise "Can't create random directory: #{random_dir[1]}")
			create_cred_file if File.exist?(@credential_file) == false
			#credential_file = create_cred_file[2] if (credential_file = @credential_file) == nil
#				puts "mount -t cifs #{what} #{mount_dir} -o credential=#{@credential_file}"
			mount_stat = $operate.cmd_output("mount -t cifs #{what} #{mount_dir} -o credential=#{@credential_file}")
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
		@log.write("\tMounting local disk...")
		random_dir = create_random_dir(where)
		random_dir[0] == 0 ? mount_dir = random_dir[2] : (raise "Can't create random directory: #{random_dir[1]}")
		mount_stat = $operate.cmd_output("mount #{what} #{mount_dir}")
		mount_check = check_mount_stat(mount_stat, what, mount_dir)
		mount_check[0] == 0 ? (path = mount_dir) : (raise mount_check[1])
		path
	end
	
	def check_mount_stat(mount_stat, what, mount_dir)
		begin
			status = 0
			if mount_stat[3] != ''
				@log.write("\t\t#{what} NOT mounted to #{mount_dir}. - [ #{red('FAILED')} ]")
				raise mount_stat[3]
			elsif mount_stat[2] != '' && mount_stat[3] == ''
				@mounted.push(mount_dir)
				@log.write("\t\t#{what} mounted to #{mount_dir} with warnings: #{mount_stat[2]}. - [ #{green('OK')} ]")
			else
				@mounted.push(mount_dir)
				@log.write("\t\t#{what} mounted to #{mount_dir}. - [ #{green('OK')} ]")
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
			raise "#{device} not mounted" if mounted != true
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
			@log.write(yellow("\t\tCredential file \"#{@credential_file}\" not found. Let's create it..."))
			status = 0
			error = nil
			print sky_blue("\t\t\tEnter username to access shared resource: ")
			username = $stdin.gets.chomp
			print sky_blue("\t\t\tEnter password: ")
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

	def tar_create(what, where)
		begin
			tar_log = '/tmp/tar.log'
			tar_error_log = '/tmp/tar_err.log'
			if @archive == true
				`tar -czf #{where}.tar.gz #{what} 1>#{tar_log} 2>#{tar_error_log}`
				ext = '.tar.gz'
			else
				`tar -cf #{where}.tar #{what} 1>#{tar_log} 2>#{tar_error_log}`
				ext = '.tar'
			end
			info = IO.read(tar_log)
			error_s = IO.read(tar_error_log)
			error_a = []
			error_s.each_line{|line|
				line.chomp!
				if line.index("tar: Removing leading `/\' from") == nil
					error_a.push(line)
				end
			}
			if error_a != [] && File.exist?("#{where}#{ext}")
			# тут бы конечно покрасивее сделать, а то по ошибке не будет ничего понятно толком
				raise "tar error: #{error_a}"
			else
				status = 0
				error = nil
			end
		rescue
			status = 1
			error = $!
		ensure
			File.unlink(tar_log, tar_error_log)
		end
		result = [status, error, info]
	end

end
