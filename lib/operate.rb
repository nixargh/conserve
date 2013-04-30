class Operate
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
				params['debug'] = true
			else
				raise "Bad parametr #{arg}. Use \"--help\" or \"-h\" for full list of parametrs."
			end
		}
		params
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
