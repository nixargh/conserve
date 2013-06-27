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
class Backup
	attr_accessor :log, :mount_point, :credential_file, :archive, :mbr, :plain, :lvm, :sysinfo, :job_name, :rsync_options
	include Add_functions
	
	def initialize(source, destination, dest_target_type)
		@destination = destination
		@dest_target_type = dest_target_type
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
		@sysinfo = nil
		@job_name = destination
		@rsync = false
		@rsync_options = nil
	end
	
	def clean! # cleans after backups
		@log.write("\t\tCleaning after Backup:", 'yellow')
		@mounted.each_value{|directory|
			umount!(directory)
		}
		@mount_dir.each{|directory|
			Dir.unlink(directory)
		}
		@lvm.clean! if @lvm
	end

	def create! # creates backups
		begin
			@log.write("Backup job \"#{@job_name}\" started - #{Time.now.asctime}")

			dest_path = prepaire_destination(@destination)

			save_sysinfo!(dest_path) if @sysinfo

			source_files = prepaire_source(@source)

			raise "Can't backup multiple sources to one destination file. Not ready yet." if source_files.length > 1 && @dest_target_type == 'file'

			source_files.each{|source_file|
				@log.write("\tBackup of #{source_file}:", 'yellow')
				destination_file = create_destination(dest_path, source_file)
				puts destination_file

				if File.blockdev?(source_file)
				# do block device backup
					raise "can't backup block device with rsync." if @rsync
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
					if @rsync
						rsync_copy!(source_file, destination_file)
					elsif @plain
						create_file_copy!(source_file, destination_file)
					else
						create_tar!(source_file, destination_file)
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

	def prepaire_destination(destination) # detects what is destination, mounts it etc.
		destination.chop! if destination[-1] == '/'
		dest_type, dest_path = parse_destination(destination)
		if dest_type == 'local'
			if @dest_target_type == 'dir'
				if !File.directory?(dest_path)
					begin
						Dir.mkdir(dest_path)
					rescue
						raise "Distination directory not found and can't be created: #{dest_path}."
					end
				end
			end
		else
			if @dest_target_type == 'file'
				dest_file = File.basename(dest_path)
				dest_path = "/#{File.dirname(dest_path)}"
			end
			if dest_type == 'smb' || dest_type == 'nfs'
				dest_path = mount(dest_path, dest_type)
			elsif dest_type == 'rsync'
				#raise "rsync backup is under construction."
				@rsync = true
				dest_path = destination
			else
				raise "Unknown type of destination: #{dest_type}."
			end
			dest_path = "#{dest_path}/#{dest_file}" if @dest_target_type == 'file'
		end
		dest_path
	end

	def parse_destination(destination) # split destination to protocol and path
		raise "Destination isn't specified." if !destination || destination.empty?
		destination.gsub!('\\', '/')
		if destination.index('://')
			type, path = destination.split(':', 2)
		else
			type = 'local'
			path = destination
		end
		return type, path
	end

	def create_destination(dest_path, source_path) # creates destination path; depends on source name in case of directory
		destination_file = nil
		if @dest_target_type == 'file'
			destination_file = dest_path
		elsif @dest_target_type == 'dir'
			destination_file = "#{dest_path}/#{File.basename(source_path)}"
		end
		destination_file
	end

	def prepaire_source(source) # return array of sources path
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
							source_files.push(file)
						end
					}
				else
					source_files.push(source)
				end
			end
		}
		source_files
	end

	def mount(what, type, where = @mount_point) # mount destinations of different types
		if @mounted[what]
			path = @mounted[what]
			@log.write("\t\tDevice #{what} already mounted at #{path}.")
		else
			if File.directory?(where)
				if type == 'smb'
					path = mount_smb(what, where)
				elsif type == 'nfs'
					path = mount_nfs(what, where)
				elsif type == 'local'
					path = mount_local(what, where)
				else
					raise "Can't work with that mount type: #{type}"
				end
			else
				raise "root mount directory \"#{where}\" not found or not a directory"
			end
		end
		path
	end	

	def mount_smb(what, where) # mounts smb or share
		raise "You need to install \"mount.cifs\" (\"cifs-utils\" package on Ubuntu, \"cifs-mount\" on SLES) to mount SMB shares" if !File.exist?(`which 'mount.cifs'`.chomp)
		@log.write("\t\tMounting SMB share: ", 'yellow')
		server, path = what[2..what.length].split('/',2)
		if check_online(server)
			random_dir = create_random_dir(where)
			random_dir[0] == 0 ? mount_dir = random_dir[2] : (raise "Can't create random directory: #{random_dir[1]}")
			create_cred_file if File.exist?(@credential_file) == false
			mount_stat = runcmd("mount -t cifs #{what} #{mount_dir} -o credentials=#{@credential_file}")
			mount_check = check_mount_stat(mount_stat, what, mount_dir)
			mount_check[0] == 0 ? (path = mount_dir) : (raise mount_check[1])
			@log.write_noel("\t\t\tTesting share is writable - ")
			test_file = "#{path}/test_file"
			begin
				File.open(test_file, 'w'){|file|
					file.puts('test')
				}
				File.unlink(test_file)
				@log.write('[OK]', 'green')
			rescue
				@log.write('[FAILED}', 'red')
				raise "File creation test on share #{what} failed: #{$!}."
			end
		else
			raise "#{server} isn't online."
		end
		path
	end

	def mount_nfs(what, where) # mounts nfs share
		raise "You need to install \"mount.nfs\" (\"nfs-common\" package on Ubuntu) to mount SMB shares" if !File.exist?(`which 'mount.nfs'`.chomp)
		@log.write("\t\tMounting NFS share: ", 'yellow')
		server, path = what[2..what.length].split('/',2)
		what = "#{server}:/#{path}"
		if check_online(server)
			random_dir = create_random_dir(where)
			random_dir[0] == 0 ? mount_dir = random_dir[2] : (raise "Can't create random directory: #{random_dir[1]}")
			mount_bin = File.exist?(`which 'mount.nfs4'`.chomp) ? "mount.nfs4" : "mount.nfs"
			mount_stat = runcmd("#{mount_bin} -w #{what} #{mount_dir}")
			mount_check = check_mount_stat(mount_stat, what, mount_dir)
			mount_check[0] == 0 ? (path = mount_dir) : (raise mount_check[1])
			@log.write_noel("\t\t\tTesting share is writable - ")
			test_file = "#{path}/test_file"
			begin
				File.open(test_file, 'w'){|file|
					file.puts('test')
				}
				File.unlink(test_file)
				@log.write('[OK]', 'green')
			rescue
				@log.write('[FAILED}', 'red')
				raise "File creation test on share #{what} failed: #{$!}."
			end
		else
			raise "#{server} isn't online."
		end
		path
	end

	def mount_local(what, where) # mounts local device
		@log.write("\t\tMounting local disk: ", 'yellow')
		random_dir = create_random_dir(where)
		random_dir[0] == 0 ? mount_dir = random_dir[2] : (raise "Can't create random directory: #{random_dir[1]}")
		mount_stat = runcmd("mount #{what} #{mount_dir}")
		mount_check = check_mount_stat(mount_stat, what, mount_dir)
		mount_check[0] == 0 ? (path = mount_dir) : (raise mount_check[1])
		path
	end
	
	def check_mount_stat(mount_stat, what, mount_dir) # analize mount feedback information
		begin
			info, error = mount_stat
			status = 0
			@mounted[what] = mount_dir
			if error
				@log.write("\t\t\t#{what} NOT mounted to #{mount_dir} - ")
				@log.write("[FAILED]", 'red')
				raise error
			elsif info && !error
				@log.write_noel("\t\t\t#{what} mounted to #{mount_dir} with warnings: #{info}. - ")
				@log.write("[OK]", 'green')
			else
				@log.write_noel("\t\t\t#{what} mounted to #{mount_dir}. - ")
				@log.write("[OK]", 'green')
			end
		rescue
			status = 1
			error = $!
		end
		result = [status, error]
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

		# skip warning from verbose umount
		error = nil if error && error.chomp.strip == 'NFSv4 mount point detected'

		if info && !error
			@log.write('[OK]', 'green')
		else
			@log.write('[FAILED}', 'red')
			@log.write("\t\t\t\tUnmount error: #{error}", 'yellow')
		end
	end

	def do_snapshot(lvm_lv) # do snapshot of LVM Logical Volume
		lvm_lv_snapshot = nil
		@log.write("\t\tUsing LVM (by default):", 'yellow')
		@log.write_noel("\t\t\tCreating snapshot of #{lvm_lv} - ") 
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
	

	def check_online(server) # ping the server to check if it is online
		online = false
		raise 'Nothing to check, because "server" is nil.' if !server
		response = `ping -c 1 #{server} 2>/dev/null`
		ping_recieved = response.split('packets transmitted, ')[1].split(' received')[0].to_i
		if ping_recieved == 1
			online = true
		elsif ping_recieved == 0 
			raise "Ping of #{server} failed."
		else
			raise "Undefined number of pings: #{ping_recieved}"
		end
		online
	end
	
	def create_cred_file # ask to enter credentials for remote destination
		begin
			@log.write("\t\t\tCredential file \"#{@credential_file}\" not found. Let's create it...", 'yellow', true)
			status = 0
			error = nil
			@log.write_noel("\t\t\t\tEnter username to access shared resource: ", 'sky_blue', true)
			username = $stdin.gets.chomp
			@log.write_noel("\t\t\t\tEnter password: ", 'sky_blue', true)
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

	def rsync_copy!(source, destination) # copy files using rsync
		rsync_options = @rsync_options ? @rsync_options : "-hru#{'z' if @archive}"
		@log.write_noel("\t\tRunning rsync (-v #{rsync_options}) of #{source} to #{destination} - ")
		info, error = runcmd("rsync -v #{rsync_options} #{source} #{destination}")
		if error
			@log.write('[FAILED]', 'red')
			raise "rsync failed: #{error}."
		else
			@log.write('[OK]', 'green')
			puts info
		end
	end

	def create_file_copy!(source_file, destination_file) # copy file from to
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

	def create_tar!(source_file, destination_file) # do tar and gzip if needed
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

	def save_sysinfo!(dest_path) # saves system information if it can't be saved early
		if @dest_target_type == 'dir'
			file = "#{dest_path}/#{hostname}.info"
		elsif @dest_target_type == 'file'
			file = "#{File.dirname(dest_path)}/#{hostname}.info"
		else
			raise "Can't save sysinfo: unknown destination type."
		end
		require 'yaml'
		File.open(file, 'w'){|file|
			file.write(@sysinfo.to_yaml)	
		}
		@log.write("SysInfo saved.", 'yellow') if @debug
	end
end
