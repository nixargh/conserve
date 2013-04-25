class Operate
	def initialize
	end
	
	def ensure
		@backup.ensure if @backup != nil
		if @inform != nil
			inform = Inform.new
			inform.config_file = @inform
			inform.run
		end
	end

	def read_arguments
		raise "Nothing will happens without parametres. Use \"--help\" or \"-h\" for full list." if ARGV == []
		params = Hash.new
		ARGV.each{|arg|
			if arg == '-h' || arg == '--help'
				help
				exit 0
			elsif arg == '--no_lvm'
				params['use_lvm'] = false
			elsif arg == '--gzip' || arg == '-z'
				params['archive'] = true
			elsif arg.index('--log') == 0 || arg.index('-l') == 0
				params['log_enabled'] = true
				raise "You need to enter full log path." if !(params['log_file'] = arg.split('=')[1])
			elsif arg.index('--mbr') == 0
				params['mbr'] = true
			elsif arg.index('--source') == 0 || arg.index('-s') == 0
				raise "You must enter source path." if (params['source'] = arg.split('=')[1]) == nil
			elsif arg.index('--destination') == 0 || arg.index('-d') == 0
				raise "You must enter destination path." if (params['destination'] = arg.split('=')[1]) == nil
			elsif arg.index('--mountdir') == 0 || arg.index('-m') == 0
				raise "You must enter root mount directory." if (params['mountdir'] = arg.split('=')[1]) == nil
			elsif arg.index('--credential') == 0 || arg.index('-c') == 0
				raise "You must enter full path to credential file." if (params['cred_file'] = arg.split('=')[1]) == nil
			elsif arg.index('--inform') == 0 || arg.index('-i') == 0
				raise "You must enter full path to config file." if (params['inform'] = arg.split('=')[1]) == nil
			elsif arg.index('--job_name') == 0 || arg.index('-n') == 0
				raise "You must enter backup job name." if (params['job_name'] = arg.split('=')[1]) == nil
			elsif arg == '-v' || arg == '--version'
				puts "Conserve - backup tool v.#{$version} (*w)"
				exit 0
			elsif arg == '--debug'
				params['debug'] == true
			else
				raise "Bad parametr #{arg}. Use \"--help\" or \"-h\" for full list of parametrs."
			end
		}
		params
	end
	
	def action()
		begin
			status = 0
			error = nil
			$job_name = 'Default Backup Job Name' if $job_name == nil
			if @log_enabled == true
				$log.log_enabled = true
				$log.log_file = @log_file
			end
			@backup = Backup.new(@source,@destination)
			@backup.mbr = true if @mbr == true
			@backup.use_lvm = false if @use_lvm == false
			@backup.mount_point = @mountdir if @mountdir != nil
			@backup.credential_file = @cred_file if @cred_file != nil
			@backup.archive = true if @archive == true
			@backup.create
		rescue
			status = 1
			error = $!
		end
		result = [status, error]
	end

	def cmd_output(cmd)
		begin
			status = 0
			error = nil
			temp_log_err = '/tmp/conseve_cmd_err.log'
			temp_log = '/tmp/conseve_cmd.log'
			`#{cmd} 2>#{temp_log_err} 1>#{temp_log}`
			cmd_error = IO.read(temp_log_err)
			cmd_info = IO.read(temp_log)
		rescue
			status = 1
			error = $!
		ensure
			File.unlink(temp_log_err, temp_log)
		end
		result = [status, error, cmd_info, cmd_error] 
	end

	private

	def help()
		puts "Conserve v.#{$version}
- is a backup tool, which can do:
	1. Backup block devices with LVM and dd.
	2. Backup MBR.
	3. Backup files from lvm snapshot or from \"live\" fs.
	4. Backup from and to smb shares.

Options:
	-l=	--log='file'\t\t\t\tfull path to logfile. Show info to console by default.
	-s=	--source='server|/dev/dev0'\t\tfull path to block device or files to backup
	-d=	--destination='server|/dir/file'\tfull path where to store backup
	\t\t\t\t\t\tif path isn't smb share then you just use local path to files;
	\t\t\t\t\t\tserver - server name where share is, /dir/file - files path on the share
		--no_lvm\t\t\t\tdo not use LVM snapshot
	-m=	--mountdir='/dir'\t\t\troot directory to mount network shares (\"/mnt\" by default)
	-c=	--credential='file'\t\t\tfull path to file with smb credentials. File format as for cifs mount.
	-z	--gzip\t\t\t\t\tarchive block device image by gzip or tar and gzip files when backuping non block device
	\t--mbr\t\t\t\t\tbackup MBR from device pointed like source
	-i=	--inform='/dir/inform.conf'\t\tinform about backup status as described at config file
	\t\t\t\t\t\tif no config file found it will be created
	-n=	--job_name='Daily MBR Backup'\t\tset display name for backup job (equal to given conserve parametrs by default)
		
	-h	--help\t\t\t\t\tto show this help
	-v	--version\t\t\t\tto show Conserve version
		--debug\t\t\t\t\tshow more information about code errors 
"
	end
end	
