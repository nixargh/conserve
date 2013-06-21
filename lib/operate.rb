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
class Operate
	def read_arguments
		raise "Nothing will happens without parametres. Use \"--help\" or \"-h\" for full list." if ARGV == []
		params = Hash.new
		params['use_lvm'] = true
		ARGV.each{|arg|
			parameter, value = arg.split('=')
			if parameter == '-h' || parameter == '--help'
				help
				exit 0
			elsif parameter == '--baremetal' || parameter == '-b'
				params['baremetal'] = true
			elsif parameter == '--exclude' || parameter == '-e'
				raise "You must enter device name (at \"normal device name\" format) to exclude." if !(params['exclude'] = value)
			elsif parameter == '--no_lvm'
				params['use_lvm'] = false
			elsif parameter == '--gzip' || parameter == '-z'
				params['archive'] = true
			elsif parameter == '--log' || parameter == '-l'
				params['log_enabled'] = true
				raise "You need to enter full log path." if !(params['log_file'] = value)
			elsif parameter == '--mbr'
				params['mbr'] = true
			elsif parameter == '--plain' || parameter == '-p'
				params['plain_files_tree'] = true
			elsif parameter == '--source' || parameter == '-s'
				raise "You must enter source path." if !(params['source'] = value)
			elsif parameter == '--dest_file' || parameter == '-d'
				raise "You must enter destination path." if !(params['destination'] = value)
				params['dest_target_type'] = 'file'
			elsif parameter == '--dest_dir' || parameter == '-D'
				raise "You must enter destination path." if !(params['destination'] = value)
				params['dest_target_type'] = 'dir'
			elsif parameter == '--mountdir' || parameter == '-m'
				raise "You must enter root mount directory." if !(params['mountdir'] = value)
			elsif parameter == '--credential' || parameter == '-c'
				raise "You must enter full path to credential file." if !(params['cred_file'] = value)
			elsif parameter == '--collect' || parameter == '-cl'
				params['collect'] = true
				params['collect_dir'] = value
			elsif parameter == '--inform' || parameter == '-i'
				raise "You must enter full path to config file." if !(params['inform'] = value)
			elsif parameter == '--job_name' || parameter == '-n'
				raise "You must enter backup job name." if !(params['job_name'] = value) 
			elsif parameter == '-v' || parameter == '--version'
				puts "Conserve - backup tool v.#{$version} (*w)"
				exit 0
			elsif parameter == '--debug'
				params['debug'] = true
			else
				raise "Bad parametr #{arg}. Use \"--help\" or \"-h\" for full list of parametrs."
			end
		}
		params
	end
	
	private

	def help()
		puts "Conserve  Copyright (C) 2013  nixargh <nixargh@gmail.com>
This program comes with ABSOLUTELY NO WARRANTY.
This is free software, and you are welcome to redistribute it
under certain conditions.\n
Conserve v.#{$version}
- is a backup tool, which can do:
\t1. Backup block devices with LVM snapshots and dd.
\t2. Backup MBR.
\t3. Backup files from LVM snapshot or from \"live\" fs.
\t4. Backup to SMB or NFS share.
\t5. Collect information useful on restore.
\t6. Find out what to backup for bare metal restore.
\t7. Send report by email.

Options:
\t-b\t--baremetal\t\t\t\tdetect what to backup automatically;
\t\t\t\t\t\t\tbackups only devices from fstab;
\t\t\t\t\t\t\tyou have to point destination folder to store backup files;
\t\t\t\t\t\t\t--collect used automatically.
\t-e=\t--exclude='device1,device2'\t\texclude devices from baremetal backup;
\t\t\t\t\t\t\tdevice name must be at \"normal device name\" format, for example \"/dev/vg/lv\".
\t-s=\t--source='path'\t\t\t\tfull path to block device, file or directory to backup;
\t\t\t\t\t\t\t'/dir/file, /dir, /dev/blockdev' - you can specify source as comma-separated list;
\t\t\t\t\t\t\t'/dir/*' can be used to backup all directory entries as individual sources. 
\t-d=\t--dest_file='[type://server]/file'\tfull file path where to store backup;
\t\t\t\t\t\t\ttypes: smb, nfs (rsync under development)
\t\t\t\t\t\t\tif file exist it is going to be overwrited;
\t\t\t\t\t\t\tif source is number of files than all backup files will be added to \"destination.tar\" file.
\t-D=\t--dest_dir='[type://server]/directory'\tfull directory path where to store backup;
\t\t\t\t\t\t\ttypes: smb, nfs (rsync under development)
\t\t\t\t\t\t\ttarget directory must exist;
\t\t\t\t\t\t\tbackup files names will be constructed from sources names.
\t-l=\t--log='file'\t\t\t\tfull path to logfile. Show info to console by default.
\t\t--no_lvm\t\t\t\tdo not use LVM snapshot.
\t-p\t--plain\t\t\t\t\tbackup files without tar as plain tree.
\t-m=\t--mountdir='/dir'\t\t\troot for temporary directories used to mount network shares or LVM snapshots (\"/mnt\" by default).
\t-c=\t--credential='file'\t\t\tfull path to file with smb credentials. File format as for cifs mount.
\t-z\t--gzip\t\t\t\t\tarchive block device image by gzip or tar and gzip files when backuping non block device.
\t\t--mbr\t\t\t\t\tbackup MBR from device pointed like source.
\t-cl\t--collect\t\t\t\tstore information about system;
\t\t\t\t\t\t\tby default path to the file will be \"/destination_dir/fqdn.info\".
\t\t\t\t\t\t\tif you want to save information to other file you can use it like -cl='dir'.
\t-i=\t--inform='/dir/inform.conf'\t\tinform about backup status as described at config file;
\t\t\t\t\t\t\tif no config file found it will be created.
\t-n=\t--job_name='Daily MBR Backup'\t\tset display name for backup job.
		
\t-h\t--help\t\t\t\t\tto show this help.
\t-v\t--version\t\t\t\tto show Conserve version.
\t\t--debug\t\t\t\t\tshow more information about code errors.
\n
"
	end
end	
